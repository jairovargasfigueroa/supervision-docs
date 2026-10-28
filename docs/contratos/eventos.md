# Contrato de eventos y comandos (RabbitMQ)

Sobre común, exchange `plataforma` (topic), colas por servicio, outbox, inbox y cola de fallidos: `docs/convenciones.md`. Cada proyecto copia en su `docs/contratos.md` las filas que le tocan.

## Sistema base

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.ObraRegistrada` | Obras | Finanzas, Materiales | `obraId, nombre, fechaInicio, asignaciones{residenteId, maestroId, almaceneroId, clienteId}, contrato{monto, plazoDias, anticipoPct, retencionPct, firmadoEn}` | 002 |
| `evento.finanzas.ContratoRegistrado` | Finanzas | Obras | `obraId, contratoId` | 002 |
| `evento.finanzas.ContratoRechazado` | Finanzas | Obras | `obraId, motivo` | 002 |
| `evento.materiales.StockBajo` | Materiales | (n8n en la capa 2) | `obraId, materialId, cantidad, minimo` | 003, 004 |
| `evento.materiales.MovimientoRegistrado` | Materiales | (IA en la capa 4) | `movimientoId, obraId, materialId, tipo, cantidad, partidaId, periodo, superaStock, registradoEn` | 004 |
| `comando.finanzas.ReservarSaldo` | Obras | Finanzas | `planillaId, obraId, monto` | 008 |
| `evento.finanzas.SaldoReservado` | Finanzas | Obras | `planillaId, reservaId` | 008 |
| `evento.finanzas.SaldoInsuficiente` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.materiales.CerrarConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosCerrados` | Materiales | Obras | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.CierreFallido` | Materiales | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.EmitirCobro` | Obras | Finanzas | `planillaId, reservaId, monto` | 008 |
| `evento.finanzas.CobroEmitido` | Finanzas | Obras (y IA en la capa 4) | `planillaId, cobroId, numero, venceEn` | 008 |
| `evento.finanzas.CobroFallido` | Finanzas | Obras | `planillaId, motivo` | 008 |
| `comando.finanzas.LiberarReserva` | Obras | Finanzas | `planillaId, reservaId` | 008 |
| `evento.finanzas.ReservaLiberada` | Finanzas | (nadie; queda en el log) | `planillaId, reservaId` | 008 |
| `comando.materiales.ReabrirConsumos` | Obras | Materiales | `planillaId, obraId, periodo` | 008 |
| `evento.materiales.ConsumosReabiertos` | Materiales | (nadie; queda en el log) | `planillaId, obraId, periodo` | 008 |
| `evento.obras.PlanillaAprobada` | Obras | (IA en la capa 4) | `planillaId, obraId, periodo, neto, cobroId, lineas[{partidaId, cantidadPeriodo, monto}]` | 008 |
| `evento.obras.PlanillaObservada` | Obras | (IA en la capa 4) | `planillaId, obraId, motivo, origen` | 008 |

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
