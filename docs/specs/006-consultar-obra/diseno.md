# 006 · Diseño

## Obras

- `GET /obras?estado=&busqueda=`: lista visible para el usuario con `avancePct`, `plazoPct`, `enRiesgo` calculados al leer (reglas «Avance y plazo»).
- `GET /obras/{id}`: detalle con partidas (`ejecutadaAcumulada`, `avancePct`), copia del contrato, asignaciones (ids) y los indicadores.
- `GET /obras/{id}/material-previsto?periodo=AAAA-MM` (roles `admin`, `gerente` y `residente` asignado; si no ve la obra, `404 OBRA_NO_ENCONTRADA`): `[{ partidaId, materialId, cantidadPrevista }]` a partir de la planilla del periodo (en cualquier estado) y los insumos previstos. Respuesta `{ periodo, hayPlanilla, items }`.
- Cálculos en el dominio (`Obra.avance()`, `Obra.plazoTranscurrido(hoy)`), probados con fechas fijas.

## Materiales

- `GET /obras/{obraId}/consumos?periodo=AAAA-MM` (roles `admin`, `gerente` y `residente` asignado, según `obra_acceso`; si no ve la obra, `404 OBRA_NO_ENCONTRADA`): suma de salidas por `partidaId` y `materialId` → `[{ partidaId, materialId, cantidad }]`.

## Finanzas

- `GET /contratos?obraId=` (roles `admin`, `gerente`): `{ id, obraId, monto, saldoDisponible, totalCobrado, totalReservado }`.
- `GET /cobros?obraId=&estado=` (roles `admin`, `gerente`).

## Gateway

- `obras(estado, busqueda): [ObraResumen!]!` y `obra(id: ID!): Obra`.
- Campos de `Obra` resueltos por separado (respuesta parcial):
  - `usuarios` asignados → nombres desde Keycloak (cliente `gateway`), con caché en memoria de 5 minutos.
  - `finanzas: FinanzasObra` → Finanzas; `null` con error `SERVICIO_NO_DISPONIBLE` si no responde; `null` sin error si el rol no es `admin` ni `gerente`.
  - `materialComparado(periodo: String!): ComparacionMaterial` → une `material-previsto` (Obras) + `consumos` (Materiales) + nombres de materiales (Materiales `GET /materiales`), calcula `diferencia` y `excedido` (usado > 1,20 × previsto).
  - `planillas` → Obras (007). `cobros` → Finanzas.
- *DataLoader* por petición para no repetir llamadas al mismo servicio.

## mf-obras

- `/obras`: lista con filtros y etiqueta «En riesgo».
- `/obras/:id`: encabezado, indicadores, tabla de partidas y pestañas Material, Fotos, Planillas y Cobros. Cada pestaña maneja su propio error («No disponible por el momento»).
- Consulta GraphQL única para el encabezado y partidas; cada pestaña pide sus campos al abrirse.

## Pruebas

- Obras: avance con planillas aprobadas y no aprobadas (solo cuentan aprobadas), plazo en los bordes (antes de iniciar = 0, después del plazo = 100), `enRiesgo` en el borde de 10 puntos, material previsto con y sin planilla, visibilidad por rol.
- Materiales: agregación de consumos solo con salidas del periodo.
- Gateway: respuesta parcial cuando Finanzas no responde (prueba con un servidor simulado que tarda más de 3 s), cálculo de `excedido`.
