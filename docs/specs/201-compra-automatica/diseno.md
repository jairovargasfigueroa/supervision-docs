# 201 · Diseño

## Flujo

```
Materiales (003 o 004): el stock cruza por debajo del mínimo → outbox evento.materiales.StockBajo (datos ampliados)
RabbitMQ (cola n8n.stock-bajo) → n8n flujo «Compra por stock bajo»
   → Finanzas POST /ordenes-compra (token de servicio de n8n)
        201 { nueva: true, orden }  →  Finanzas: outbox evento.finanzas.OrdenCompraCreada
        200 { nueva: false, orden } →  fin (evento repetido u orden abierta)
   → si nueva: correo SMTP al proveedor (Mailpit en desarrollo)
   → Finanzas POST /ordenes-compra/{id}/enviada  (orden ENVIADA)

Materiales escucha OrdenCompraCreada → guarda la copia orden_compra_obra (PENDIENTE)
App: GET /paquete-datos (Sincronización) trae las órdenes pendientes de cada obra
App → Sincronización → Materiales POST /movimientos { tipo: INGRESO, ordenCompraId }
   Materiales (misma transacción): valida la copia, la marca RECIBIDA, outbox evento.materiales.CompraRecibida

RabbitMQ (cola n8n.compra-recibida) → n8n flujo «Cuenta por pagar al recibir compra»
   → Finanzas POST /cuentas-por-pagar → 201 (o 200 si el ingreso ya tenía cuenta) → orden RECIBIDA
```

- Las reglas (cantidad a pedir, una orden abierta por obra y material, montos, vencimiento) viven en Finanzas; n8n solo traslada datos, envía el correo y llama a las APIs (decisión del equipo).
- n8n no guarda los mensajes procesados: la idempotencia la garantiza Finanzas (`evento_origen_id` en la orden, `ingreso_id` en la cuenta por pagar).

## Eventos

| Clave | Publica | Escuchan | `datos` |
|---|---|---|---|
| `evento.materiales.StockBajo` (se amplía) | Materiales | n8n | `obraId, obraNombre, materialId, cantidad, minimo, material{codigo, nombre, unidad, unidadPlural, precioReferencial, proveedorHabitualId}` |
| `evento.finanzas.OrdenCompraCreada` (nuevo) | Finanzas | Materiales | `ordenCompraId, numero, obraId, materialId, cantidad, proveedorNombre, creadaEn` |
| `evento.materiales.CompraRecibida` (nuevo) | Materiales | n8n | `ingresoId, ordenCompraId, obraId, materialId, cantidad, registradoEn` |

- `StockBajo` agrega campos sin quitar ninguno: sigue en `version: 1` (decisión del equipo). `proveedorHabitualId` puede ser `null`. `obraNombre` sale de `obra_acceso.nombre`.
- Los tres usan el sobre común, outbox e inbox de las convenciones.

## Keycloak (infra)

- Rol de realm nuevo `automatizacion`.
- Cliente confidencial `n8n` con *service account*, rol `automatizacion` y el mapper de audiencia `plataforma-api`. El secreto va en el `.env` de infra.
- n8n obtiene el token con el flujo *client credentials* (credencial OAuth2 de n8n).

## Finanzas

### Datos (cambios)

- `orden_compra`: agregar `creada_en timestamptz`; `estado` pasa a `CREADA`, `ENVIADA`, `RECIBIDA`; `numero` único; índice único parcial sobre (`obra_id`, `material_id`) donde `estado IN ('CREADA','ENVIADA')` (garantiza una sola orden abierta por obra y material); `evento_origen_id` único (ya estaba).
- `cuenta_por_pagar`: agregar `cantidad_recibida numeric(14,3)`; `orden_compra_id` e `ingreso_id` únicos (ya estaban).
- Seeder `ProveedorSeeder` con tres proveedores de prueba e ids fijos (decisión del equipo):

| id | nombre | correo | teléfono |
|---|---|---|---|
| `7b1e5c1a-0001-4c3e-9a10-000000000001` | Ferretería El Constructor | ventas@elconstructor.test | 3-3456789 |
| `7b1e5c1a-0002-4c3e-9a10-000000000002` | Aceros del Oriente | pedidos@acerosoriente.test | 3-3567890 |
| `7b1e5c1a-0003-4c3e-9a10-000000000003` | Agregados Santa Cruz | ventas@agregadosscz.test | 3-3678901 |

- Middleware `rol:automatizacion` para las rutas que llama n8n.

### GET /proveedores · 201

Roles: `admin`, `gerente`. `[{ "id", "nombre", "correo", "telefono" }]`, ordenados por nombre.

### POST /ordenes-compra · 201

Roles: `automatizacion`. Quién llama: n8n.

```json
{
  "eventoOrigenId": "uuid (id del mensaje StockBajo)",
  "obraId": "uuid", "materialId": "id",
  "proveedorId": "uuid | null",
  "cantidadActual": 40.0, "minimo": 100.0, "precioUnitario": 62.00
}
```

En una transacción:

1. Si existe una orden con ese `evento_origen_id` → `200 { "nueva": false, "orden": … }`.
2. `proveedorId` nulo → `422 MATERIAL_SIN_PROVEEDOR`; proveedor inexistente → `422 PROVEEDOR_NO_ENCONTRADO`; `precioUnitario ≤ 0` → `422 PRECIO_INVALIDO`.
3. Si hay una orden `CREADA` o `ENVIADA` para la misma obra y material → `200 { "nueva": false, "orden": <la existente> }`.
4. `cantidad = ceil(2 × minimo − cantidadActual)` (mínimo 1); `monto = cantidad × precioUnitario` redondeado a 2 decimales.
5. `numero` = `OC-<año en La Paz>-<correlativo de 4 dígitos>` (mismo mecanismo de correlativo que el número de cobro).
6. Inserta con `estado = CREADA`, `creada_en = ahora`; outbox `OrdenCompraCreada`.
7. Si la inserción choca con el índice único parcial o con `evento_origen_id` (dos mensajes a la vez), relee y responde `200 { "nueva": false, … }`.

Devuelve `201`:

```json
{
  "nueva": true,
  "orden": {
    "id": "uuid", "numero": "OC-2026-0012", "obraId": "uuid", "materialId": "id",
    "cantidad": 160, "precioUnitario": 62.00, "monto": 9920.00,
    "estado": "CREADA", "creadaEn": "2026-11-15T14:00:05Z", "enviadaEn": null,
    "proveedor": { "id": "uuid", "nombre": "Ferretería El Constructor", "correo": "ventas@elconstructor.test", "telefono": "3-3456789" },
    "cuentaPorPagar": null
  }
}
```

Errores: `400` · `401` · `403` · `422 MATERIAL_SIN_PROVEEDOR` · `422 PROVEEDOR_NO_ENCONTRADO` · `422 PRECIO_INVALIDO`.

### POST /ordenes-compra/{id}/enviada · 201

Roles: `automatizacion`. Sin cuerpo. `CREADA` → `ENVIADA` con `enviada_en = ahora`; si ya está `ENVIADA` o `RECIBIDA`, devuelve `200` sin cambios. Devuelve la orden. Errores: `404 ORDEN_COMPRA_NO_ENCONTRADA`.

### GET /ordenes-compra?obraId=&estado= · 201

Roles: `admin`, `gerente`. Lista de órdenes (mismo objeto `orden`, sin `nueva`), de la más reciente a la más antigua. `cuentaPorPagar` = `{ "id", "monto", "emitidaEn", "venceEn" }` o `null`.

### POST /cuentas-por-pagar · 201

Roles: `automatizacion`. Quién llama: n8n.

```json
{ "ingresoId": "uuid", "ordenCompraId": "uuid", "cantidadRecibida": 150.0, "recibidaEn": "2026-11-20T15:00:00Z" }
```

1. Si existe una cuenta con ese `ingreso_id` → `200` con ella.
2. Orden inexistente → `404 ORDEN_COMPRA_NO_ENCONTRADA`; la orden ya tiene cuenta de otro ingreso → `409 ORDEN_YA_RECIBIDA`; `cantidadRecibida ≤ 0` → `400`.
3. `monto = cantidadRecibida × orden.precio_unitario` (2 decimales); `emitida_en` = fecha de `recibidaEn` en `America/La_Paz`; `vence_en = emitida_en + 30 días`.
4. Inserta la cuenta y pasa la orden a `RECIBIDA` en la misma transacción.

Devuelve `201 { "id", "ordenCompraId", "proveedorId", "ingresoId", "cantidadRecibida", "monto", "emitidaEn", "venceEn" }`.

## Materiales

### Catálogo

- `material.proveedor_habitual_id` (ya previsto) entra en `POST /materiales` y `PUT /materiales/{id}` como `proveedorHabitualId` (UUID opcional, `null` para quitarlo) y sale en `GET /materiales`. Materiales no valida que exista (es de Finanzas); solo el formato.

### `StockBajo` ampliado

- En los dos lugares donde se publica (fijar mínimo, 003; movimiento, 004) se agregan `obraNombre` y `material{…}` con los datos del catálogo en ese momento.

### Copia de órdenes: colección `orden_compra_obra`

| Campo | Tipo | Notas |
|---|---|---|
| _id | string (uuid) | `ordenCompraId` (ref Finanzas) |
| numero | string | |
| obra_id | string | ref Obras |
| material_id | string | FK material |
| cantidad | decimal | cantidad pedida |
| proveedor_nombre | string | |
| estado | string | `PENDIENTE`, `RECIBIDA` |
| ingreso_id | string | movimiento que la recibió |
| creada_en | date | |
| recibida_en | date | |

Índice (`obra_id`, `estado`).

- Consumidor de `evento.finanzas.OrdenCompraCreada` (inbox `mensaje_procesado`): crea la copia en `PENDIENTE` si no existe. La cola `materiales` agrega la clave `evento.finanzas.OrdenCompraCreada`.

### GET /obras/{obraId}/ordenes-compra?estado= · 201

Roles: internos que pueden ver la obra (`obra_acceso`). Quién llama: Sincronización (paquete de datos).

`[{ "ordenCompraId", "numero", "materialId", "cantidad", "proveedorNombre", "estado", "creadaEn" }]`. Errores: `404 OBRA_NO_ENCONTRADA`.

### POST /movimientos (cambio)

- Acepta `ordenCompraId` (UUID, opcional, solo en `INGRESO`; en `SALIDA` → `400`).
- En la misma transacción, después de la comprobación de idempotencia: la copia debe existir, ser de la misma obra y material y estar `PENDIENTE`; si no → `422 ORDEN_COMPRA_NO_PENDIENTE`. Si es válida: guarda `movimiento.orden_compra_id`, marca la copia `RECIBIDA` con `ingreso_id` y `recibida_en`, y agrega al outbox `CompraRecibida`.
- Un ingreso repetido (mismo `id`) devuelve `200` con el existente y no vuelve a publicar `CompraRecibida`.

## Sincronización

- `GET /paquete-datos`: agrega a cada obra `"ordenesCompra": [{ "ordenCompraId", "numero", "materialId", "cantidad", "proveedorNombre" }]` con Materiales `GET /obras/{id}/ordenes-compra?estado=PENDIENTE`.
- `MOVIMIENTO_MATERIAL` ya reenvía el cuerpo completo: no cambia.

## App de obra

- Formulario de ingreso: al elegir el material, si hay órdenes pendientes de ese material en el paquete, aparece «Orden de compra (opcional)» con «OC-2026-0012 · Ferretería El Constructor · 160 bolsas». Se excluyen las órdenes ya usadas por ingresos de la cola que no estén `RECHAZADO`.
- `datos.ordenCompraId` en la operación `MOVIMIENTO_MATERIAL`.
- Rechazo `ORDEN_COMPRA_NO_PENDIENTE` → «La orden de compra no está pendiente para este material» (criterio 16); el almacenero vuelve a registrar el ingreso sin orden.

## Gateway

```graphql
enum EstadoOrdenCompra { CREADA ENVIADA RECIBIDA }
type Proveedor { id: ID! nombre: String! correo: String telefono: String }
type CuentaPorPagar { id: ID! monto: Float! emitidaEn: String! venceEn: String! }
type OrdenCompra {
  id: ID! numero: String! obraId: ID! obraNombre: String       # Obras (GET /obras); null si no se encuentra
  materialId: ID! material: Material                          # Materiales (GET /materiales)
  cantidad: Float! precioUnitario: Float! monto: Float! estado: EstadoOrdenCompra!
  proveedor: Proveedor! creadaEn: String! enviadaEn: String
  cuentaPorPagar: CuentaPorPagar
}

extend type Material {
  proveedorHabitualId: ID
  proveedorHabitual: Proveedor        # Finanzas; null sin error si el rol no es admin ni gerente
}
# MaterialEntrada agrega: proveedorHabitualId: ID

extend type Query {
  proveedores: [Proveedor!]!                                              # 201 · admin, gerente
  ordenesCompra(obraId: ID, estado: EstadoOrdenCompra): [OrdenCompra!]!   # 201 · admin, gerente
}
```

- `ordenesCompra` → Finanzas `GET /ordenes-compra`; `obraNombre` y `material` con *DataLoader* (una llamada a Obras y una a Materiales por petición).
- `proveedorHabitual` → Finanzas `GET /proveedores` (una llamada por petición); `null` con `SERVICIO_NO_DISPONIBLE` si Finanzas no responde.

## mf-materiales

- Ruta interna `/materiales/ordenes-compra`, en el menú interno solo para `admin` y `gerente`.
- Tabla: número, fecha (`creadaEn`), obra, material, cantidad con unidad plural, proveedor, monto, estado y cuenta por pagar (monto y vencimiento). Estados con color: `CREADA` «Correo no enviado» (ámbar), `ENVIADA` (azul), `RECIBIDA` (verde). Filtros por obra (consulta `obras`) y estado. Estado vacío: «Todavía no hay órdenes de compra».
- Catálogo (003): selector «Proveedor habitual» (consulta `proveedores`) en el formulario; en la tabla, etiqueta «Sin proveedor habitual» con la ayuda del criterio 3.
- Si la 104 está hecha, la lista usa `useConsultaConRespaldo`.

## n8n y correo (infra)

- Contenedor n8n (imagen oficial `docker.n8n.io/n8nio/n8n` con versión fija), puerto `5678`, volumen de datos, `GENERIC_TIMEZONE=America/La_Paz`, `N8N_ENCRYPTION_KEY` en `.env`.
- Contenedor Mailpit (`axllent/mailpit` con versión fija): SMTP `1025`, interfaz y API `8025`.
- RabbitMQ: colas durables `n8n.stock-bajo` (clave `evento.materiales.StockBajo`) y `n8n.compra-recibida` (clave `evento.materiales.CompraRecibida`) sobre el exchange `plataforma`, declaradas en el archivo de definiciones de RabbitMQ de infra.
- Credenciales de n8n (se crean siguiendo el README; nunca se suben): RabbitMQ, OAuth2 *client credentials* (URL de token `…/realms/supervision/protocol/openid-connect/token`, cliente `n8n`) y SMTP (Mailpit, sin autenticación en desarrollo).
- Variables usadas por los flujos: `FINANZAS_URL`, `COMPRAS_CORREO_REMITENTE` (por ejemplo `compras@constructora-andina.test`), `EMPRESA_NOMBRE` («Constructora Andina»).

### Flujo «Compra por stock bajo»

1. **RabbitMQ Trigger** sobre `n8n.stock-bajo`, contenido como JSON.
2. **HTTP Request** `POST {FINANZAS_URL}/ordenes-compra` con `eventoOrigenId = id`, `obraId`, `materialId`, `proveedorId = material.proveedorHabitualId`, `cantidadActual = cantidad`, `minimo`, `precioUnitario = material.precioReferencial`; *Retry On Fail* 3 veces cada 5 s; tiempo máximo 10 s. Un `422` termina la ejecución como fallida con el `detail` (criterio 9).
3. **IF** `nueva = true`.
4. **Send Email** (SMTP) a `orden.proveedor.correo`, desde `COMPRAS_CORREO_REMITENTE`; *Retry On Fail* 3 veces cada 10 s.
   - Asunto: `Orden de compra {numero} · {EMPRESA_NOMBRE}`.
   - Cuerpo: «Estimados {proveedor.nombre}: {EMPRESA_NOMBRE} solicita el siguiente material para la obra {obraNombre}. Orden: {numero}. Material: {material.codigo} · {material.nombre}. Cantidad: {cantidad} {material.unidadPlural}. Precio unitario: Bs {precioUnitario}. Monto: Bs {monto}. Por favor, confirme la entrega respondiendo a este correo.»
5. **HTTP Request** `POST {FINANZAS_URL}/ordenes-compra/{orden.id}/enviada`.

### Flujo «Cuenta por pagar al recibir compra»

1. **RabbitMQ Trigger** sobre `n8n.compra-recibida`.
2. **HTTP Request** `POST {FINANZAS_URL}/cuentas-por-pagar` con `ingresoId`, `ordenCompraId`, `cantidadRecibida = cantidad`, `recibidaEn = registradoEn`; *Retry On Fail* 3 veces cada 5 s.

- Los dos flujos se exportan en JSON a `infra/n8n/flujos/` y se importan al iniciar con la CLI de n8n (`n8n import:workflow`). Verificar en la documentación de la versión fijada las opciones de importación y la de confirmación del mensaje del *RabbitMQ Trigger* (confirmar al terminar la ejecución, para no perder mensajes si n8n se cae a mitad de un flujo).
- Si una ejecución falla, queda en la lista de ejecuciones de n8n y se puede reintentar desde su panel; por la idempotencia de Finanzas, reintentar no duplica nada.

## Pruebas

- Finanzas: cantidad y monto (por ejemplo mínimo 100 y stock 40 → 160; stock 40,5 → 160 por redondeo hacia arriba), número correlativo por año, mismo `eventoOrigenId` dos veces → una orden, orden abierta existente → `nueva: false`, sin proveedor → `422`, `enviada` idempotente, cuenta por pagar con monto, emisión en fecha de La Paz (ingreso a las 03:30Z del 21 = 23:30 del 20 en La Paz → emitida el 20) y vencimiento a 30 días, mismo ingreso dos veces → una cuenta, otro ingreso para la misma orden → `409`, rol distinto de `automatizacion` → `403`, `GET /ordenes-compra` y `GET /proveedores` por rol, seeder.
- Materiales: `StockBajo` con los datos ampliados desde 003 y 004; copia por `OrdenCompraCreada` (repetida → una sola); ingreso con orden válida → copia `RECIBIDA` y `CompraRecibida` en el outbox en la misma transacción; orden de otra obra, de otro material o ya recibida → `422`; salida con `ordenCompraId` → `400`; ingreso repetido no vuelve a publicar; `proveedorHabitualId` en el catálogo.
- Sincronización: `ordenesCompra` en el paquete.
- Gateway: `ordenesCompra` con `obraNombre` y `material` en una llamada por servicio; `proveedorHabitual` nulo si Finanzas no responde.
- mf-materiales: tabla con los tres estados, filtros, selector de proveedor, etiqueta «Sin proveedor habitual», menú oculto para otros roles.
- App: selector filtrado por material y sin órdenes ya usadas en la cola; mensaje de rechazo.
- Integración (infra, con Docker Compose): fijar un mínimo por encima del stock → orden `ENVIADA` y correo visible en Mailpit (API `GET http://localhost:8025/api/v1/messages`) → registrar el ingreso con la orden → cuenta por pagar creada y orden `RECIBIDA`; volver a publicar los mismos mensajes → sin duplicados.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/contratos/eventos.md`

Nueva sección «Capa 2» con las tres filas de la tabla «Eventos» de arriba (y en la fila de `StockBajo` del sistema base, los `datos` ampliados y «Escuchan: n8n»).

### `docs/contratos/rest.md`

- Finanzas: reemplazar «Capa 2 · Crear orden de compra y cuenta por pagar (las llama n8n). Se especifican en la capa 2» por `GET /proveedores`, `POST /ordenes-compra`, `POST /ordenes-compra/{id}/enviada`, `GET /ordenes-compra`, `POST /cuentas-por-pagar` (códigos `MATERIAL_SIN_PROVEEDOR`, `PROVEEDOR_NO_ENCONTRADO`, `PRECIO_INVALIDO`, `ORDEN_COMPRA_NO_ENCONTRADA`, `ORDEN_YA_RECIBIDA`).
- Materiales: `proveedorHabitualId` en `GET/POST/PUT /materiales`; `ordenCompraId` en `POST /movimientos` (código `ORDEN_COMPRA_NO_PENDIENTE`); nuevo `GET /obras/{obraId}/ordenes-compra`.
- Sincronización: `ordenesCompra` por obra en `GET /paquete-datos`.

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

El SDL de arriba (`EstadoOrdenCompra`, `Proveedor`, `CuentaPorPagar`, `OrdenCompra`, campos nuevos de `Material` y `MaterialEntrada`, consultas `proveedores` y `ordenesCompra`). En «Consume (REST)», Finanzas agrega `GET /proveedores` y `GET /ordenes-compra`.

### `services/finanzas/docs/datos.md`

`orden_compra`: `creada_en`, estado `CREADA`, `numero` único, índice único parcial (`obra_id`, `material_id`) para estados `CREADA` y `ENVIADA`. `cuenta_por_pagar`: `cantidad_recibida`. Proveedores de prueba del seeder.

### `services/finanzas/docs/contratos.md`

Los cinco endpoints; publica `evento.finanzas.OrdenCompraCreada`.

### `services/materiales/docs/datos.md`

Colección `orden_compra_obra`; en `movimiento.orden_compra_id`, «validado contra `orden_compra_obra`».

### `services/materiales/docs/contratos.md`

Cambios REST de arriba; escucha `evento.finanzas.OrdenCompraCreada`; publica `evento.materiales.CompraRecibida`; `StockBajo` ampliado.

### `docs/convenciones.md`

- «Puertos en desarrollo»: **n8n · 5678** y **Mailpit (SMTP / interfaz) · 1025 / 8025**.
- «Autenticación y permisos»: rol de realm `automatizacion` y cliente confidencial `n8n` con *service account* (lo usa n8n para llamar a Finanzas).
- «Eventos y comandos»: n8n tiene sus colas `n8n.stock-bajo` y `n8n.compra-recibida`.

### `docs/reglas-negocio.md`

Nueva sección «Compras automáticas (capa 2)»:

- Cuando el stock de un material en una obra baja del mínimo, se crea una orden de compra al proveedor habitual del material, si tiene.
- Cantidad a pedir = 2 × mínimo − cantidad actual, redondeada hacia arriba al entero (**decisión del equipo**). Precio unitario = precio referencial del material.
- Una sola orden sin recibir por obra y material.
- Número de orden: `OC-<año>-<correlativo de 4 dígitos>`, correlativo global por año (**decisión del equipo**).
- Estados de la orden: `CREADA` → `ENVIADA` (correo enviado) → `RECIBIDA` (ingreso registrado).
- Una orden se recibe en un solo ingreso (**decisión del equipo**). Cuenta por pagar = cantidad recibida × precio unitario de la orden; vence a los 30 días calendario desde la fecha del ingreso en La Paz (**decisión del equipo**).

### `docs/arquitectura.md`

Tabla «Conexiones»: agregar Finanzas → RabbitMQ → Materiales (`OrdenCompraCreada`) y n8n → Finanzas con token de *service account*.

### `frontend/mf-materiales/docs/contratos.md`

Consume `ordenesCompra` y `proveedores`; `proveedorHabitualId` en `crearMaterial` / `actualizarMaterial`.

### `docs/plan.md`

Agregar la fila de la funcionalidad 201 (infra, finanzas, materiales, sincronizacion, gateway, mf-materiales, app-obra).
