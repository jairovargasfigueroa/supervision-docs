# 008 · Diseño

## Saga orquestada por Obras

Estado guardado en `saga_aprobacion` (`paso_actual`, `estado`, `detalle` con `reservaId`, `cobroId`, motivo, y `vence_en` del paso actual). `correlacionId` de todos los mensajes = `saga_aprobacion.id`.

| Paso | Obras envía | Respuesta OK | Respuesta fallo | Compensación si falla un paso posterior |
|---|---|---|---|---|
| 1 | — (planilla → `APROBANDO`, crea saga) | — | — | planilla → `OBSERVADA` |
| 2 | `comando.finanzas.ReservarSaldo` | `SaldoReservado {reservaId}` | `SaldoInsuficiente {motivo}` | `comando.finanzas.LiberarReserva {reservaId}` |
| 3 | `comando.materiales.CerrarConsumos` | `ConsumosCerrados` | `CierreFallido {motivo}` | `comando.materiales.ReabrirConsumos` |
| 4 | `comando.finanzas.EmitirCobro {reservaId}` | `CobroEmitido {cobroId, numero, venceEn}` | `CobroFallido {motivo}` | — |
| 5 | planilla → `APROBADA`, `cobro_id` y `cobro_numero` (el `numero` de `CobroEmitido`); publica `evento.obras.PlanillaAprobada` | — | — | — |

- Al fallar: se envían las compensaciones de los pasos ya hechos en orden inverso, sin esperar respuesta para cerrar la planilla (las compensaciones son idempotentes y se reintentan desde el outbox); la planilla pasa a `OBSERVADA` con el motivo; la saga queda `COMPENSADA`; se publica `evento.obras.PlanillaObservada`.
- Vencimiento: una tarea programada cada 10 s busca sagas `EN_CURSO` con `vence_en` pasado y las trata como fallo con el motivo «El paso X no respondió a tiempo» (X = número del paso: 2, 3 o 4).
- Respuestas tardías de una saga ya `COMPENSADA`: si es `SaldoReservado`, se envía `LiberarReserva`; si es `ConsumosCerrados`, se envía `ReabrirConsumos`; si es `CobroEmitido`, se registra en el log como incidente (no debería pasar porque el paso 4 solo se envía tras el 3).
- Idempotencia: `mensaje_procesado` en los tres servicios; además, en Finanzas una sola reserva vigente por `planilla_id` y un solo cobro por `planilla_id` (único), y en Materiales un solo `cierre_periodo` por obra y periodo.

## Obras: endpoints del portal

- `POST /planillas/{id}/aprobar` (rol `cliente`, dueño de la obra): solo si `PRESENTADA` → 202 `{ estado: "APROBANDO" }`. `409 PLANILLA_NO_PRESENTADA`.
- `POST /planillas/{id}/observar` `{ motivo }` (rol `cliente`): solo si `PRESENTADA` → 200. `422 MOTIVO_INVALIDO`.
- El cliente usa además `GET /obras`, `GET /obras/{id}`, `GET /obras/{id}/fotos` (solo publicadas), `GET /obras/{id}/planillas` y `GET /planillas/{id}`, que para el rol `cliente` excluyen `BORRADOR`.

## Finanzas

- `ReservarSaldo {planillaId, obraId, monto}`: busca el contrato por `obraId`; si `saldoDisponible ≥ monto` crea `reserva_saldo RESERVADA`, descuenta del saldo y responde `SaldoReservado`; si no, `SaldoInsuficiente` con `motivo` «Saldo del contrato insuficiente». Si ya hay una reserva vigente para esa planilla, responde de nuevo `SaldoReservado` con la misma.
- `EmitirCobro {planillaId, reservaId, monto}`: si la reserva está `RESERVADA`, crea el `cobro` (`numero` correlativo, `vence_en = emitido_en + 30 días`, `PENDIENTE`), marca la reserva `CONSUMIDA` y responde `CobroEmitido`. Si ya existe cobro para la planilla, responde con el existente. Si la reserva no está `RESERVADA` (por ejemplo, ya se liberó), responde `CobroFallido` con `motivo` «No se pudo emitir el cobro: la reserva de saldo ya no está vigente»; ante cualquier otro error al emitir, `CobroFallido` con «No se pudo emitir el cobro por un error en Finanzas».
- `LiberarReserva {reservaId}`: si está `RESERVADA`, la marca `LIBERADA` y devuelve el monto al saldo. Idempotente.
- Tarea diaria (`schedule`) a las 00:10 hora de La Paz: cobros `PENDIENTE` con `vence_en < hoy` → `VENCIDO`.

## Materiales

- `CerrarConsumos {planillaId, obraId, periodo}`: crea o actualiza `cierre_periodo` a `CERRADO` y marca `cerrado = true` en los movimientos del periodo; responde `ConsumosCerrados`. Si ya está `CERRADO` por la misma planilla, responde igual; por otra planilla, `CierreFallido` con `motivo` «Los consumos del periodo AAAA-MM ya fueron cerrados por otra planilla» (con el periodo real).
- `ReabrirConsumos {planillaId, obraId, periodo}`: pasa a `REABIERTO` y `cerrado = false`. Idempotente.

## Portal

- Rutas: `/` (mis obras), `/obras/:id`, `/planillas/:id`.
- Cliente REST hacia Obras (`VITE_OBRAS_URL`) con el token de `react-oidc-context`.
- Diálogo de confirmación para aprobar; diálogo con contador de caracteres para observar; consulta cada 2 s durante `APROBANDO`, hasta 4 minutos, con el aviso de los 90 s (criterio 5). Textos en `docs/mensajes.md`.

## Gateway y mf-obras

- `Planilla` expone `estado`, `observacion` y `cobro: CobroPlanilla`. `cobro.id` y `cobro.numero` salen de Obras (`cobroId`, `cobroNumero`) para todos los roles que ven la planilla. `montoNeto`, `emitidoEn`, `venceEn` y `estado` se piden a Finanzas (`GET /cobros/{id}`) **solo** para `admin` y `gerente`; para el `residente` llegan en `null` sin error (Finanzas no tiene la regla de obras asignadas). El editor de mf-obras refresca el estado al abrirse.

## Pruebas

- Obras: máquina de estados de la saga con un bus simulado: camino feliz, fallo en cada paso con sus compensaciones, vencimiento por tiempo, respuesta repetida, respuesta tardía tras compensar.
- Finanzas: reserva con saldo justo y sin saldo, reserva repetida, cobro repetido, liberación repetida, número correlativo, vencimiento diario.
- Materiales: cierre y reapertura idempotentes, cierre por otra planilla falla, movimientos marcados.
- Prueba de integración (en `infra`, con Docker Compose): aprobar una planilla de punta a punta y comprobar cobro, reserva consumida y periodo cerrado.
