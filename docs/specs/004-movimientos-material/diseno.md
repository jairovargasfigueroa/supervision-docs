# 004 · Diseño

## Materiales

- `POST /movimientos` (rol `almacenero` asignado a la obra). El `id` lo genera la app (UUID v4).
- Pasos, en una transacción de MongoDB:
  1. Si ya existe un movimiento con ese `id` → devolver `200` con el existente (idempotencia).
  2. Validar acceso por `obra_acceso` (almacenero asignado; si no ve la obra → `404 OBRA_NO_ENCONTRADA`; otro rol → `403 SIN_PERMISO`), material activo, `SALIDA` con `partidaId`.
  3. `periodo` = mes de `registradoEn` en `America/La_Paz`. Si existe `cierre_periodo` `CERRADO` para obra y periodo → `409 PERIODO_CERRADO`.
  4. Insertar `movimiento`; actualizar `stock_obra.cantidad` (± cantidad) con `version` (reintento si choca).
  5. Si es `SALIDA` y la cantidad previa era menor que la salida → `superaStock = true` en la respuesta y en el movimiento.
  6. Si el stock quedó `BAJO` y antes no lo estaba → outbox `StockBajo`.
  7. Outbox `MovimientoRegistrado` (para reportes en la capa 4).
- `GET /obras/{obraId}/movimientos?periodo=` para consultas.
- Agregar al modelo `movimiento.supera_stock: bool`.

## Obras (lectura para la app)

- La app necesita las partidas de la obra: usa `GET /obras/{id}` de Obras, que devuelve las partidas. Roles con acceso: los asignados a la obra.

## App

- Pantallas (Expo Router, grupo del rol `almacenero`): `obras` (lista), `obras/[id]/ingreso`, `obras/[id]/salida`, `obras/[id]/stock`.
- Cliente REST con `fetch`, token del `expo-secure-store`, URLs base desde `app.json` → `extra` (`obrasUrl`, `materialesUrl`).
- Genera el UUID con `expo-crypto` (`randomUUID`) al abrir el formulario y lo reutiliza en los reintentos de ese mismo registro.
- Reintento automático 3 veces con espera 1 s, 2 s, 4 s ante error de red o `503`.
- Muestra los avisos de los criterios 5 y 7.

## Pruebas

- Materiales: ingreso suma, salida resta, salida sin partida (400), periodo cerrado (409), mismo `id` dos veces no duplica ni suma dos veces, `superaStock`, `StockBajo` solo al cruzar el mínimo, obra no asignada → `404 OBRA_NO_ENCONTRADA` (no se revela que existe), rol distinto de `almacenero` → `403 SIN_PERMISO`.
- App: prueba del cliente con reintentos y reutilización del UUID.
