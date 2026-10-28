# 007 · Diseño

## Obras

- Agregado `Planilla` con `LineaPlanilla`; toda regla de cálculo y de estado vive en el dominio:
  - `Planilla.crear(obra, periodo, numero, hoy)` valida periodo y que no haya otra abierta (lo comprueba el caso de uso con el repositorio).
  - `Planilla.actualizarLineas(cantidades, acumuladosAnteriores, contratadas)` valida `acumulado + cantidad ≤ contratada` y recalcula montos y totales.
  - `Planilla.presentar()` exige subtotal > 0 y estado `BORRADOR` u `OBSERVADA`.
- Cálculo (2 decimales, mitad hacia arriba al final de cada monto): `monto = cantidad × precio`; `subtotal = Σ montos`; `descuentoAnticipo = subtotal × anticipoPct / 100`; `retencion = subtotal × retencionPct / 100`; `neto = subtotal − descuentoAnticipo − retencion`.
- Endpoints (detalle en `docs/contratos.md` de Obras):
  - `POST /obras/{obraId}/planillas` `{ periodo }` → 201.
  - `GET /obras/{obraId}/planillas` → lista.
  - `GET /planillas/{id}` → detalle con líneas, totales, fotos y `version`.
  - `PUT /planillas/{id}` `{ version, lineas: [{ partidaId, cantidadPeriodo }], fotoIds: [] }` → 200 con el detalle.
  - `POST /planillas/{id}/presentar` `{ version }` → 200; marca `publicada_cliente = true` en las fotos adjuntas.
- Errores: `409 PLANILLA_ABIERTA_EXISTE`, `422 PERIODO_NO_POSTERIOR` (el periodo no es posterior al de la última planilla), `422 PERIODO_FUTURO` (mes futuro), `422 SUPERA_CANTIDAD_CONTRATADA` (con `errores[]` por partida), `409 VERSION_DESACTUALIZADA`, `409 PLANILLA_NO_EDITABLE`, `422 SUBTOTAL_CERO`, `422 FOTO_FUERA_DEL_PERIODO`, `403`.
- Bloqueo optimista con `@Version` sobre `planilla.version`.

## Gateway

- `Obra.planillas: [PlanillaResumen!]!`, `planilla(id: ID!): Planilla`.
- Mutaciones: `crearPlanilla(obraId, periodo)`, `guardarPlanilla(id, entrada: GuardarPlanillaEntrada!)`, `presentarPlanilla(id, version)`.

## mf-obras

- `/obras/:id/planillas/nueva` (selector de mes) y `/planillas/:id` (editor).
- Editor: tabla con cantidades editables, totales en vivo (mismo cálculo que el dominio, solo como ayuda visual; manda lo que devuelve el servicio), galería de fotos del periodo para adjuntar, botones «Guardar» y «Presentar».
- Muestra la observación cuando el estado es `OBSERVADA`.

## Pruebas

- Obras (dominio): cálculo con anticipo 10 % y retención 7 % sobre un caso fijo, redondeo, límite contra lo contratado en el borde exacto, transiciones válidas e inválidas, subtotal 0.
- Obras (API): planilla abierta existente (409), periodo futuro (`422 PERIODO_FUTURO`) y no posterior (`422 PERIODO_NO_POSTERIOR`), versión desactualizada (409), fotos publicadas al presentar.
- mf-obras: cálculo visual y bloqueo de «Guardar» con filas inválidas.
