# 009 · Diseño

## Servicios (endpoints de resumen)

- Obras: `GET /obras?estado=EN_EJECUCION` ya devuelve avance, plazo y riesgo (006). Se agrega a cada elemento `ultimaPlanilla { periodo, estado }`.
- Materiales: `GET /stock/resumen?obraIds=a,b,c` → `[{ obraId, materialesBajos }]`, solo de las obras pedidas que el usuario puede ver.
- Finanzas: `GET /cobros/resumen` (roles `admin`, `gerente`) → `{ vencidos: { cantidad, monto }, porVencer30Dias: { cantidad, monto } }`.

## Gateway

- `tablero: Tablero!` con campos resueltos por separado:
  - `obras: [FilaTablero!]` (Obras) y, por cada fila, `materialesBajos` (Materiales, una sola llamada en lote con DataLoader).
  - `indicadores: IndicadoresTablero` → `obrasEnEjecucion`, `obrasEnRiesgo` (Obras), `materialesBajos` (Materiales), `cobrosVencidos` (Finanzas; `null` sin error para roles sin acceso).
- Cada parte que falle devuelve `null` con `SERVICIO_NO_DISPONIBLE`.

## mf-supervision

- Ruta interna `/supervision` (pantalla inicial del microfrontend).
- Apollo Client 4 con el token de `window.plataforma.sesion`.
- Cuatro tarjetas de indicadores y una tabla ordenable; navegación al detalle con `window.history.pushState` + evento `popstate` hacia `/obras/:id` (el shell escucha el cambio de ruta).
- Estilos dentro del Shadow DOM.

## Pruebas

- Gateway: armado del tablero con un servicio caído; lote de Materiales en una sola llamada.
- Materiales y Finanzas: resúmenes con datos de prueba.
- mf-supervision: orden por diferencia y renderizado con datos parciales.
