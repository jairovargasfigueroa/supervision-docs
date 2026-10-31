# Contrato de eventos y comandos (RabbitMQ)

Sobre común, exchange `plataforma` (topic), colas por servicio, outbox, inbox y cola de fallidos: `docs/convenciones.md`. Cada proyecto copia en su `docs/contratos.md` las filas que le tocan.

## Sistema base

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.ObraRegistrada` | Obras | Finanzas, Materiales, IA | `obraId, nombre, ubicacion, zona, fechaInicio, asignaciones{residenteId, maestroId, almaceneroId, clienteId}, contrato{monto, plazoDias, anticipoPct, retencionPct, firmadoEn}` (`ubicacion` y `zona` desde la 401; `zona` es `null` sin zona) | 002, 401 |
| `evento.finanzas.ContratoRegistrado` | Finanzas | Obras, IA | `obraId, contratoId` | 002, 401 |
| `evento.finanzas.ContratoRechazado` | Finanzas | Obras | `obraId, motivo` | 002 |
| `evento.materiales.StockBajo` | Materiales | (n8n en la capa 2) | `obraId, materialId, cantidad, minimo` | 003, 004 |
| `evento.materiales.MovimientoRegistrado` | Materiales | IA | `movimientoId, obraId, materialId, tipo, cantidad, precioReferencial, partidaId, periodo, superaStock, registradoEn` (`precioReferencial` desde la 401: el precio del material al registrar el movimiento) | 004, 401, 403 |
| `comando.finanzas.ReservarSaldo` | Obras | Finanzas | `planillaId, obraId, monto` | 008 |
| `evento.finanzas.SaldoReservado` | Finanzas | Obras | `planillaId, reservaId` | 008 |
| `evento.finanzas.SaldoInsuficiente` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.materiales.CerrarConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosCerrados` | Materiales | Obras | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.CierreFallido` | Materiales | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.EmitirCobro` | Obras | Finanzas | `planillaId, reservaId, monto` | 008 |
| `evento.finanzas.CobroEmitido` | Finanzas | Obras, IA | `planillaId, cobroId, numero, venceEn` | 008, 401 |
| `evento.finanzas.CobroFallido` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.LiberarReserva` | Obras | Finanzas | `planillaId, reservaId` | 008 |
| `evento.finanzas.ReservaLiberada` | Finanzas | (nadie; queda en el log) | `planillaId, reservaId` | 008 |
| `comando.materiales.ReabrirConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosReabiertos` | Materiales | (nadie; queda en el log) | `planillaId, obraId, periodo` | 008 |
| `evento.obras.PlanillaAprobada` | Obras | IA | `planillaId, obraId, periodo, neto, cobroId, lineas[{partidaId, cantidadPeriodo, monto}]` | 008, 401 |
| `evento.obras.PlanillaObservada` | Obras | IA | `planillaId, obraId, motivo, origen` | 008, 401 |

## Saga «aprobar planilla»: secuencia

```
Portal → Obras: POST /planillas/{id}/aprobar   (planilla APROBANDO, saga EN_CURSO, correlacionId = saga.id)
Obras → Finanzas:   ReservarSaldo          → SaldoReservado | SaldoInsuficiente
Obras → Materiales: CerrarConsumos         → ConsumosCerrados | CierreFallido
Obras → Finanzas:   EmitirCobro            → CobroEmitido | CobroFallido
Obras: planilla APROBADA, saga COMPLETADA, publica PlanillaAprobada

Fallo en el paso 3: LiberarReserva → planilla OBSERVADA, saga COMPENSADA
Fallo en el paso 4: ReabrirConsumos, LiberarReserva → planilla OBSERVADA, saga COMPENSADA
Sin respuesta en 60 s: igual que un fallo en ese paso
```

## Capas

Los eventos de las capas (sincronización, automatización, reportes, agentes) se agregan en sus especificaciones.

### Capa 4: el servicio de IA como consumidor (401, 402, 403)

La capa 4 no agrega eventos nuevos: el servicio de IA escucha seis de los del sistema base en su cola durable `ia` y arma con ellos el modelo de lectura `reportes_db` (CQRS, 401). Los dos campos nuevos (`ubicacion` y `zona` en `ObraRegistrada`, `precioReferencial` en `MovimientoRegistrado`) no cambian la `version` del sobre (sigue en 1); Finanzas y Materiales ignoran los que no usan.

| Clave de enrutamiento | Proyección en IA | Además |
|---|---|---|
| `evento.obras.ObraRegistrada` | `rpt_obra_resumen` (alta) | — |
| `evento.finanzas.ContratoRegistrado` | `rpt_obra_resumen.estado = EN_EJECUCION` (sin la obra todavía: falla y se reintenta) | Recalcula el riesgo de retraso (402) |
| `evento.obras.PlanillaAprobada` | `rpt_planilla`, avance de `rpt_obra_resumen`, `rpt_cobro` (`ocurridoEn` = `aprobada_en`) | Recalcula el riesgo de retraso (402) |
| `evento.obras.PlanillaObservada` | `rpt_planilla` (veces observada, último motivo y origen) | Recalcula el riesgo de retraso (402) |
| `evento.finanzas.CobroEmitido` | `rpt_cobro` (número, emisión = fecha de `ocurridoEn` en La Paz, vencimiento) | — |
| `evento.materiales.MovimientoRegistrado` | `rpt_movimiento` y, si es `SALIDA`, `rpt_consumo_material` | Una `SALIDA` se evalúa antes como posible consumo atípico (403); si lo es, recalcula el riesgo de la obra (402) |

- La cola `ia` y sus 6 enlaces están en las definiciones de RabbitMQ de `infra` desde la fase 1, así existen (y guardan los eventos) aunque el servicio no esté corriendo; el worker (`ia-worker`) también los declara al conectarse.
- Lector tolerante: los campos desconocidos se ignoran, y `ubicacion`, `zona` y `precioReferencial` pueden faltar (eventos anteriores al cambio; sin precio, el monto del consumo suma 0).
- Inbox (`evento_aplicado`), reintentos con `x-intentos` y `plataforma.fallidos` como en `docs/convenciones.md`. El servicio de IA no publica eventos en la capa 4.
- Lo que ya existía antes de la cola (o después de vaciarla con `recargar`) lo trae la carga inicial por REST (`docs/contratos/rest.md`, «IA»).
