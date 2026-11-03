# Contrato de eventos y comandos (RabbitMQ)

Sobre común, exchange `plataforma` (topic), colas por servicio, outbox, inbox y cola de fallidos: `docs/convenciones.md`. Cada proyecto copia en su `docs/contratos.md` las filas que le tocan.

## Sistema base

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.ObraRegistrada` | Obras | Finanzas, Materiales, IA | `obraId, nombre, ubicacion, zona, fechaInicio, asignaciones{residenteId, maestroId, almaceneroId, clienteId}, contrato{monto, plazoDias, anticipoPct, retencionPct, firmadoEn}` (`ubicacion` y `zona` desde la 401; `zona` es `null` sin zona) | 002, 401 |
| `evento.finanzas.ContratoRegistrado` | Finanzas | Obras, IA | `obraId, contratoId` | 002, 401 |
| `evento.finanzas.ContratoRechazado` | Finanzas | Obras | `obraId, motivo` | 002 |
| `evento.materiales.StockBajo` | Materiales | n8n (010) | `obraId, materialId, cantidad, minimo` | 003, 004, 010 |
| `evento.materiales.MovimientoRegistrado` | Materiales | IA | `movimientoId, obraId, materialId, tipo, cantidad, precioReferencial, partidaId, periodo, superaStock, registradoEn` (`precioReferencial` desde la 401: el precio del material al registrar el movimiento) | 004, 401, 403 |
| `comando.finanzas.ReservarSaldo` | Obras | Finanzas | `planillaId, obraId, monto` | 008 |
| `evento.finanzas.SaldoReservado` | Finanzas | Obras | `planillaId, reservaId` | 008 |
| `evento.finanzas.SaldoInsuficiente` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.materiales.CerrarConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosCerrados` | Materiales | Obras | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.CierreFallido` | Materiales | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.EmitirCobro` | Obras | Finanzas | `planillaId, reservaId, monto` | 008 |
| `evento.finanzas.CobroEmitido` | Finanzas | Obras, IA, n8n (201) | `planillaId, cobroId, numero, venceEn` | 008, 401, 201 |
| `evento.finanzas.CobroFallido` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.LiberarReserva` | Obras | Finanzas | `planillaId, reservaId` | 008 |
| `evento.finanzas.ReservaLiberada` | Finanzas | (nadie; queda en el log) | `planillaId, reservaId` | 008 |
| `comando.materiales.ReabrirConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosReabiertos` | Materiales | (nadie; queda en el log) | `planillaId, obraId, periodo` | 008 |
| `evento.obras.PlanillaAprobada` | Obras | IA | `planillaId, obraId, periodo, neto, cobroId, lineas[{partidaId, cantidadPeriodo, monto}]` | 008, 401 |
| `evento.obras.PlanillaObservada` | Obras | IA | `planillaId, obraId, motivo, origen` | 008, 401 |
| `evento.obras.PlanillaPresentada` | Obras | n8n (010) | `planillaId, obraId, numero, periodo ("2026-10"), neto, reenvio (true si venía de OBSERVADA), presentadaEn` | 010 |

### Avisos (010)

- `PlanillaPresentada` usa el sobre común y el outbox de las convenciones (`version: 1`); Obras lo agrega al outbox en la misma transacción que el cambio a `PRESENTADA` (`POST /planillas/{id}/presentar`), con `reenvio` según el estado anterior. Es lo único que cambia en Obras; `StockBajo` sigue igual (Materiales lo publica cada vez que el material cruza el mínimo).
- n8n escucha en dos colas durables propias más (definiciones de RabbitMQ de infra, con el usuario `n8n` de solo lectura de la 201): `n8n.stock-bajo` (`evento.materiales.StockBajo`, flujo «Avisar stock bajo»: *push* al tema `obra-{obraId}-almacenero`) y `n8n.planilla-presentada` (`evento.obras.PlanillaPresentada`, flujo «Avisar planilla para revisar»: correo al cliente). Confirma al terminar y de a uno, como en la 201; los repetidos los descarta el propio flujo (guarda el `id` del sobre en sus datos estáticos, los últimos 500), porque estos avisos no anotan nada en otro servicio. No publica eventos.
- El recordatorio del diario no usa eventos: lo dispara la hora (18:00 de La Paz) en n8n.

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

### Capa 2: cobranza automática (201)

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.finanzas.CobroPagado` | Finanzas | n8n, IA | `cobroId, planillaId, obraId, numero, montoNeto, pagadoEn, comprobante` | 201 |

- `CobroPagado` usa el sobre común, outbox e inbox de las convenciones (`version: 1`); Finanzas lo agrega al outbox en la misma transacción que registra el pago (`POST /cobros/{id}/pago`).
- n8n escucha en dos colas durables propias sobre el exchange `plataforma` (definiciones de RabbitMQ de infra): `n8n.cobro-emitido` (`evento.finanzas.CobroEmitido`, flujo «Enviar nota de cobro») y `n8n.cobro-pagado` (`evento.finanzas.CobroPagado`, flujo «Enviar constancia de pago»). El mensaje se confirma al terminar la ejecución, haya salido bien o mal; no publica eventos. La idempotencia la da Finanzas (`envio_cobro`, único por cobro y tipo): un aviso repetido no envía un segundo correo.
- IA suma a su cola `ia` el enlace `evento.finanzas.CobroPagado`: `rpt_cobro.estado = PAGADO` y `pagado_en` (si el cobro todavía no está en `rpt_cobro`, falla y se reintenta).
- La 201 ya no escucha `StockBajo` (dejó de ser la compra automática); desde la 010 lo escucha n8n para el aviso de stock bajo al almacenero (cola `n8n.stock-bajo`, «Avisos (010)» arriba).

### Capa 4: el servicio de IA como consumidor (401, 402, 403)

La capa 4 no agrega eventos nuevos: el servicio de IA escucha seis de los del sistema base en su cola durable `ia` (desde la 201, también `CobroPagado`; arriba) y arma con ellos el modelo de lectura `reportes_db` (CQRS, 401). Los dos campos nuevos (`ubicacion` y `zona` en `ObraRegistrada`, `precioReferencial` en `MovimientoRegistrado`) no cambian la `version` del sobre (sigue en 1); Finanzas y Materiales ignoran los que no usan.

| Clave de enrutamiento | Proyección en IA | Además |
|---|---|---|
| `evento.obras.ObraRegistrada` | `rpt_obra_resumen` (alta) | — |
| `evento.finanzas.ContratoRegistrado` | `rpt_obra_resumen.estado = EN_EJECUCION` (sin la obra todavía: falla y se reintenta) | Recalcula el riesgo de retraso (402) |
| `evento.obras.PlanillaAprobada` | `rpt_planilla`, avance de `rpt_obra_resumen`, `rpt_cobro` (`ocurridoEn` = `aprobada_en`) | Recalcula el riesgo de retraso (402) |
| `evento.obras.PlanillaObservada` | `rpt_planilla` (veces observada, último motivo y origen) | Recalcula el riesgo de retraso (402) |
| `evento.finanzas.CobroEmitido` | `rpt_cobro` (número, emisión = fecha de `ocurridoEn` en La Paz, vencimiento) | — |
| `evento.materiales.MovimientoRegistrado` | `rpt_movimiento` y, si es `SALIDA`, `rpt_consumo_material` | Una `SALIDA` se evalúa antes como posible consumo atípico (403); si lo es, recalcula el riesgo de la obra (402) |

- La cola `ia` y sus 6 enlaces están en las definiciones de RabbitMQ de `infra` desde la fase 1 (el séptimo, `CobroPagado`, se agrega con la 201), así existen (y guardan los eventos) aunque el servicio no esté corriendo; el worker (`ia-worker`) también los declara al conectarse.
- Lector tolerante: los campos desconocidos se ignoran, y `ubicacion`, `zona` y `precioReferencial` pueden faltar (eventos anteriores al cambio; sin precio, el monto del consumo suma 0).
- Inbox (`evento_aplicado`), reintentos con `x-intentos` y `plataforma.fallidos` como en `docs/convenciones.md`. El servicio de IA no publica eventos en la capa 4.
- Lo que ya existía antes de la cola (o después de vaciarla con `recargar`) lo trae la carga inicial por REST (`docs/contratos/rest.md`, «IA»).

### Capa 5: sin eventos nuevos (302, 501, 502, 503, 504)

La capa 5 no publica ni escucha eventos nuevos. Los agentes (502) leen el dato al instante por las herramientas MCP de cada servicio (`docs/contratos/rest.md`, «Herramientas MCP»), y aprobar o rechazar una sugerencia solo registra la decisión en `ia_db` (no publica nada). Los reportes (503) leen el modelo de lectura de la capa 4. El servicio de IA sigue sin publicar eventos.
