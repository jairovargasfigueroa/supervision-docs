# 003 · Diseño

## Materiales

- Endpoints (detalle en `docs/contratos.md` de Materiales): `GET /materiales`, `POST /materiales`, `PUT /materiales/{id}`, `GET /obras/{obraId}/stock`, `PUT /obras/{obraId}/stock/{materialId}/minimo`.
- Roles: lectura `admin`, `residente`, `gerente`, `almacenero`, `maestro`; escritura solo `admin`.
- Visibilidad de `GET /obras/{obraId}/stock`: según `obra_acceso` (convenciones). Si la obra no está en `obra_acceso` → `404 OBRA_NO_ENCONTRADA`.
- Estado del stock calculado al leer (reglas del negocio), no guardado.
- `PUT .../minimo` hace *upsert* de `stock_obra` (crea con cantidad 0 si no existe) y, si el nuevo mínimo deja el stock en `BAJO`, publica `StockBajo` (lo usa la capa 2; en el sistema base nadie lo escucha).
- Índice único en `material.codigo`. El código se normaliza a mayúsculas sin espacios a los costados.
- Errores: `409 CODIGO_MATERIAL_REPETIDO`, `404 MATERIAL_NO_ENCONTRADO`, `422 MATERIAL_INACTIVO` (al fijar mínimo de un material inactivo).

## Gateway

- Consultas: `materiales(busqueda: String, soloActivos: Boolean, pagina: Int = 1, tamano: Int = 20): MaterialesPagina!` (paginada, como dice `docs/contratos/graphql-erp.md`), `stockObra(obraId: ID!): [StockMaterial!]!`.
- Mutaciones: `crearMaterial`, `actualizarMaterial`, `definirStockMinimo`.
- `obras` (de la 006) alimenta el selector de obra; si la 006 no está, usa `obras` básico de la 002.

## mf-materiales

- Rutas internas: `/materiales/catalogo` y `/materiales/stock`.
- Catálogo: tabla con búsqueda, formulario en panel lateral para crear y editar (atributos como filas dinámicas).
- Stock: selector de obra, tabla con estado coloreado, acción «Fijar mínimo» por fila y «Agregar material» (solo `admin`).
- Los botones de escritura se ocultan según los roles de `window.plataforma.sesion.usuario.roles`.

## Pruebas

- Materiales: crear con código repetido (409), normalización del código, desactivar, mínimo con upsert, cálculo de estados en los bordes (igual al mínimo → `JUSTO`, 1,25 × mínimo → `JUSTO`, por encima → `OK`), visibilidad por `obra_acceso`, 403 para no admin.
- mf-materiales: renderizado de estados y ocultamiento de botones por rol.
