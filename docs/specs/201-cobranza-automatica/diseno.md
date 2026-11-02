# 201 · Diseño

## Flujo

```
Cliente aprueba la planilla (portal) → saga 008 → Finanzas emite el cobro → outbox evento.finanzas.CobroEmitido
RabbitMQ (cola n8n.cobro-emitido) → n8n «Enviar nota de cobro»
   → Finanzas  GET /cobros/{cobroId}            ¿ya tiene envío NOTA_COBRO? → fin
   → Obras     GET /planillas/{planillaId}      líneas, totales, periodo
   → Obras     GET /obras/{obraId}              nombre y clienteId
   → Keycloak  GET /admin/realms/supervision/users/{clienteId}   nombre y correo
   → Finanzas  POST /cobros/{cobroId}/nota-cobro   (datos de la planilla) → PDF
   → SMTP      correo al cliente con el PDF, copia oculta a cobranzas (Mailpit en desarrollo)
   → Finanzas  POST /cobros/{cobroId}/envios { tipo: NOTA_COBRO }

Todos los días 08:00 La Paz → n8n «Recordar cobros»
   → Finanzas  GET /cobros/recordatorios         { porVencer[], vencidos[] }
   → por cada cobro: Obras GET /obras/{obraId} → Keycloak (cliente) → correo → Finanzas POST /cobros/{id}/envios
   → si hubo alguno: correo con el resumen del día a cobranzas

ERP (admin) «Registrar pago» → gateway registrarPagoCobro → Finanzas POST /cobros/{id}/pago
   → cobro PAGADO + outbox evento.finanzas.CobroPagado
RabbitMQ (cola n8n.cobro-pagado) → n8n «Enviar constancia de pago»
   → Finanzas GET /cobros/{id} (¿ya tiene CONSTANCIA_PAGO? → fin) → Obras GET /obras/{obraId} → Keycloak → correo
   → Finanzas POST /cobros/{id}/envios { tipo: CONSTANCIA_PAGO }
RabbitMQ (cola ia) → IA: rpt_cobro PAGADO
```

- **Reparto (decisión del equipo):** Finanzas decide qué cobros necesitan recordatorio, arma la nota de cobro y guarda lo que se envió; Obras y Keycloak dan los datos que ya tienen; n8n une los datos, envía los correos y anota cada envío. n8n no guarda estado propio: la idempotencia la da Finanzas (`envio_cobro`, único por cobro y tipo).
- **Por qué n8n le pasa la planilla a Finanzas** (y Finanzas no la pide a Obras): así cada servicio solo expone lo suyo y el flujo encadena los pasos, como pide el punto 13. Finanzas no confía a ciegas: comprueba que la planilla es la del cobro y que su neto es el del cobro.
- **Orden «enviar y después anotar»:** si n8n se cae justo entre el correo y la anotación, el reintento puede repetir ese correo una vez. Se acepta (decisión del equipo): anotar antes del envío haría que un correo que falló figure como enviado.

## Eventos

| Clave | Publica | Escuchan | `datos` |
|---|---|---|---|
| `evento.finanzas.CobroEmitido` (sin cambios; suma un consumidor) | Finanzas | Obras, IA, **n8n** | `planillaId, cobroId, numero, venceEn` |
| `evento.finanzas.CobroPagado` (nuevo) | Finanzas | n8n, IA | `cobroId, planillaId, obraId, numero, montoNeto, pagadoEn, comprobante` |

- `CobroPagado` usa el sobre común, outbox e inbox de las convenciones (`version: 1`).
- `StockBajo` se queda sin consumidor hasta la 010 (ya no lo escucha n8n).

## Keycloak (infra)

- Rol de realm `automatizacion` (técnico, ninguna persona lo tiene).
- Cliente confidencial `n8n`, solo *client credentials*, con *service account* que tiene:
  - `automatizacion`: solo las rutas nuevas de Finanzas que llama n8n;
  - `gerente`: para leer con los endpoints que ya existen (`GET /obras/{id}`, `GET /planillas/{id}`, `GET /cobros/{id}`), igual que `ia-reportes` en la 401, sin cambiar guardias ni visibilidad de Obras y Finanzas;
  - `view-users` de `realm-management`: para leer el nombre y el correo del cliente (`GET /admin/realms/supervision/users/{id}`), como el gateway. Es la segunda excepción a «ningún otro proyecto llama a la API de administración de Keycloak».
  - mapper de audiencia `plataforma-api`.
- El `azp` del token es `n8n`: los servicios usan los roles del token tal cual (convenciones, «Usuario con varios roles»).
- El secreto va en el `.env` de infra (`N8N_KEYCLOAK_SECRETO`); nunca en el repo.

## Finanzas

### Datos (cambios)

`cobro` agrega:

| Campo | Tipo | Notas |
|---|---|---|
| estado | varchar(20) | se suma `PAGADO` |
| pagado_en | date | fecha de pago (La Paz); null si no está pagado |
| comprobante | varchar(50) | opcional |
| pago_registrado_por | uuid | ref Keycloak (`sub` de quien registró) |
| pago_registrado_en | timestamptz | |

Tabla nueva `envio_cobro`:

| Campo | Tipo | Notas |
|---|---|---|
| id | uuid | PK |
| cobro_id | uuid | FK cobro |
| tipo | varchar(30) | `NOTA_COBRO`, `RECORDATORIO_POR_VENCER`, `RECORDATORIO_VENCIDO`, `CONSTANCIA_PAGO` |
| destinatario | varchar(254) | correo del cliente al que se envió |
| enviado_en | timestamptz | |
| ejecucion_n8n | varchar(64) | id de la ejecución de n8n, para buscarla en su panel; opcional |

Único (`cobro_id`, `tipo`).

- `totalCobrado` del contrato (006) suma los cobros `PENDIENTE`, `VENCIDO` **y `PAGADO`**: el saldo disponible se calcula con los cobros emitidos y no cambia al pagar.
- La tarea `cobros:marcar-vencidos` solo toca los `PENDIENTE` (ya era así): un `PAGADO` no se vence.
- `GET /cobros/resumen` (009) y la herramienta MCP `cobros_por_vencer` (501) ya filtran por `PENDIENTE` y `VENCIDO`: no cuentan los `PAGADO` (se agregan pruebas).

### POST /cobros/{id}/pago · 201

Roles: `admin`. Quién llama: el gateway, con el token del usuario.

```json
{ "pagadoEn": "2027-04-28", "comprobante": "TRF-883412" }
```

1. `pagadoEn` obligatorio (`AAAA-MM-DD`); `comprobante` opcional, de 1 a 50 caracteres (vacío se guarda como null).
2. En una transacción, bloquea la fila del cobro (`FOR UPDATE`). Si no existe → `404 COBRO_NO_ENCONTRADO`; si está `PAGADO` → `409 COBRO_YA_PAGADO`.
3. `pagadoEn` posterior a hoy (La Paz) o anterior a `emitido_en` → `422 FECHA_PAGO_INVALIDA`.
4. Guarda `PAGADO`, `pagado_en`, `comprobante`, `pago_registrado_por` (`sub`) y `pago_registrado_en`; agrega al outbox `CobroPagado`.

Devuelve `200` con el cobro (mismo objeto que `GET /cobros/{id}`). Errores: `400 DATOS_INVALIDOS` · `401` · `403` · `404 COBRO_NO_ENCONTRADO` · `409 COBRO_YA_PAGADO` · `422 FECHA_PAGO_INVALIDA`.

### GET /cobros y GET /cobros/{id} (cambio)

- `estado` admite `PAGADO` (también como filtro).
- Cada cobro agrega `"pagadoEn": "2027-04-28" | null`, `"comprobante": "…" | null` y `"envios": [{ "tipo": "NOTA_COBRO", "destinatario": "cliente1@correo.test", "enviadoEn": "2027-04-02T12:00:41Z" }]` (ordenados por `enviadoEn`).
- Roles sin cambios (`admin`, `gerente`; n8n entra con su `gerente`).

### GET /cobros/recordatorios · 201

Roles: `automatizacion`. Quién llama: n8n («Recordar cobros»). «Hoy» = fecha actual en `America/La_Paz`.

```json
{
  "hoy": "2027-04-29",
  "porVencer": [{ "id", "numero", "obraId", "planillaId", "montoNeto", "emitidoEn", "venceEn", "estado", "diasParaVencer": 3 }],
  "vencidos":  [{ "id", "numero", "obraId", "planillaId", "montoNeto", "emitidoEn", "venceEn", "estado", "diasVencido": 1 }]
}
```

- `porVencer`: `PENDIENTE` con `vence_en` entre hoy y hoy + 3 (ambos incluidos) y sin envío `RECORDATORIO_POR_VENCER`.
- `vencidos`: `VENCIDO`, o `PENDIENTE` con `vence_en` anterior a hoy, sin envío `RECORDATORIO_VENCIDO`.
- Un cobro aparece en un solo grupo. Orden por `vence_en` y `numero`. Sin paginar (pocos por día).

### POST /cobros/{id}/envios · 201

Roles: `automatizacion`. `{ "tipo": "NOTA_COBRO", "destinatario": "cliente1@correo.test", "ejecucionN8n": "1532" }`.

- Si ya existe un envío de ese `tipo` para el cobro → `200` con el existente (no lo cambia). Si no → lo crea con `enviado_en = ahora` → `201`.
- Errores: `400 DATOS_INVALIDOS` (tipo desconocido, destinatario vacío) · `404 COBRO_NO_ENCONTRADO`.

### POST /cobros/{id}/nota-cobro · 201

Roles: `automatizacion`. Devuelve el PDF de la nota de cobro (`application/pdf`, `Content-Disposition: attachment; filename="nota-cobro-COB-2027-0003.pdf"`). No se guarda: se genera en cada llamada.

```json
{
  "cliente": { "nombre": "Roberto Justiniano Paz" },
  "obra": { "id": "uuid", "nombre": "Edificio Residencial Las Palmeras" },
  "planilla": {
    "id": "uuid", "numero": 3, "periodo": "2026-09",
    "lineas": [{ "codigo": "P-03", "nombre": "Hormigón armado en columnas", "unidad": "m3", "cantidadPeriodo": 40, "precioUnitario": 3365.00, "monto": 134600.00 }],
    "subtotal": 397770.00, "descuentoAnticipo": 39777.00, "retencion": 27843.90, "neto": 330149.10,
    "anticipoPct": 10, "retencionPct": 7
  }
}
```

1. Cobro inexistente → `404 COBRO_NO_ENCONTRADO`.
2. Comprobación de coherencia → `422 NOTA_COBRO_INCONSISTENTE` si `planilla.id` no es la del cobro, si `obra.id` no es la del contrato, si `neto` difiere de `monto_neto` (más de 0,005) o si los totales no cuadran (suma de líneas = subtotal; subtotal − anticipo − retención = neto).
3. Contenido (criterio 8): empresa (`EMPRESA_NOMBRE`, «Constructora Andina»), cliente, obra, planilla N.º y periodo («septiembre 2026»), líneas con `cantidadPeriodo` > 0, totales, número de cobro, emisión, vencimiento y la leyenda «Este documento no es una factura». Montos como `Bs 330.149,10` y fechas `dd/mm/aaaa` (convenciones).
- Librería: **`barryvdh/laravel-dompdf` 3.1.2** (admite Laravel 13; PHP puro, sin navegador). Vista Blade `resources/views/pdf/nota-cobro.blade.php` maquetada con tablas (dompdf no admite flexbox ni grid).

### Middleware y rutas

- Middleware `rol:automatizacion` en `GET /cobros/recordatorios`, `POST /cobros/{id}/envios` y `POST /cobros/{id}/nota-cobro`. `automatizacion` no entra en ninguna otra ruta.
- `GET /cobros/recordatorios` se registra antes de `GET /cobros/{id}` (como `resumen`).

### Semilla (011)

Los 3 cobros cargados tienen su envío `NOTA_COBRO` a su cliente (enviado el día de emisión a las 08:05 de La Paz). Sin recordatorios ni pagos: en la demostración, «Recordar cobros» envía el recordatorio del cobro vencido de la obra 1 y el pago se registra en vivo.

## Obras

Sin cambios de código: n8n lee `GET /obras/{id}` y `GET /planillas/{id}` con su rol `gerente`.

## IA (401, 503)

- Cola `ia`: suma el enlace `evento.finanzas.CobroPagado`. Consumidor nuevo: `rpt_cobro.estado = PAGADO`, `pagado_en` (inbox, reintentos y fallidos como los demás). Si el cobro todavía no está en `rpt_cobro` (llegó antes que `CobroEmitido`), falla y se reintenta.
- `rpt_cobro` agrega `pagado_en date null`. La tarea diaria de vencidos (00:20) solo pasa a `VENCIDO` los `PENDIENTE`.
- Carga inicial: lee `estado` y `pagadoEn` de `GET /cobros`.
- Catálogo de reportes (503): en el conjunto de cobros, el filtro de estado admite `PAGADO` y se agrega la columna «Fecha de pago» (`pagado_en`). «Cobrado» sigue siendo «cobros emitidos» (reglas del negocio).

## Gateway

```graphql
enum EstadoCobro { PENDIENTE VENCIDO PAGADO }
enum TipoEnvioCobro { NOTA_COBRO RECORDATORIO_POR_VENCER RECORDATORIO_VENCIDO CONSTANCIA_PAGO }
type EnvioCobro { tipo: TipoEnvioCobro! destinatario: String! enviadoEn: String! }
extend type Cobro { pagadoEn: String comprobante: String envios: [EnvioCobro!]! }

extend type Mutation {
  registrarPagoCobro(cobroId: ID!, pagadoEn: String!, comprobante: String): Cobro!   # 201 · admin
}
```

- `registrarPagoCobro` → Finanzas `POST /cobros/{id}/pago` con el token del usuario; los errores pasan con su `codigo` (`COBRO_NO_ENCONTRADO`, `COBRO_YA_PAGADO`, `FECHA_PAGO_INVALIDA`, `DATOS_INVALIDOS`).
- `CobroPlanilla.estado` admite `PAGADO` (mismo enum).

## mf-obras

Pestaña «Cobros» del detalle de obra (006; `admin` y `gerente`):

- Estado con color: `PENDIENTE` (neutro), `VENCIDO` (rojo), `PAGADO` (verde, «Pagado el 28/04/2027» y el comprobante debajo, si lo hay).
- Columna «Correos»: una etiqueta por envío con su fecha y hora al pasar el cursor («Nota enviada», «Recordatorio por vencer», «Recordatorio de vencido», «Constancia enviada»); «Nota sin enviar» en ámbar si no hay `NOTA_COBRO`.
- Botón «Registrar pago» (solo `admin`, cobros `PENDIENTE` o `VENCIDO`) → diálogo con «Fecha de pago» (selector de fecha, por defecto hoy, mínimo la emisión, máximo hoy) y «N.º de comprobante (opcional)»; «Registrar» llama a `registrarPagoCobro`; al terminar, aviso «Pago registrado» y la tabla se actualiza. Errores con los textos de `docs/mensajes.md`.
- Sin conexión (104): el botón queda desactivado como las demás acciones que guardan.

## n8n y correo (infra)

### Contenedores (perfil `automatizacion` del Docker Compose)

- **`n8n`**: imagen `n8nio/n8n:2.43.7` (estable, publicada el 16/10/2026), puerto `5678`, volumen de datos, `GENERIC_TIMEZONE=America/La_Paz` y `TZ=America/La_Paz`, `N8N_ENCRYPTION_KEY` (en `.env`), `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (desde n8n 2.0 viene en `true` y los flujos leen sus URLs de `$env`).
  - Cuenta del propietario por variables (sin paso manual): `N8N_INSTANCE_OWNER_MANAGED_BY_ENV=true`, `N8N_INSTANCE_OWNER_EMAIL`, `N8N_INSTANCE_OWNER_PASSWORD_HASH` (hash **bcrypt** en `.env`; el README dice cómo generarlo) y nombre. Están en el código de 2.43.7, no en la documentación pública: comprobar al implementar; si no funcionan, el README explica crear la cuenta la primera vez.
  - Obras y Finanzas se alcanzan en `host.docker.internal` (8081 y 8083), como el perfil `ia`. **Keycloak se alcanza como `localhost:8080`** dentro de la red de n8n (un contenedor de reenvío con `network_mode: service:n8n`), para que el emisor del token sea el mismo que validan los servicios (mismo motivo que `ia/reenviar-keycloak.py`).
- **`mailpit`**: imagen `axllent/mailpit:v1.31.6` (15/10/2026), SMTP `1025` e interfaz y API `8025`. La API sirve para las pruebas: `GET /api/v1/messages`, `GET /api/v1/message/{ID}` y `GET /api/v1/message/{ID}/part/{PartID}` (adjunto).
- Licencia de n8n: *Sustainable Use License*; el uso interno y no comercial es gratuito.

### Variables de los flujos (`.env` de infra)

`FINANZAS_URL`, `OBRAS_URL`, `KEYCLOAK_URL` (`http://localhost:8080`), `EMPRESA_NOMBRE` («Constructora Andina»), `COBRANZA_REMITENTE` (`cobranzas@constructora-andina.test`), `COBRANZA_CORREO` (copia oculta y resumen; el mismo en desarrollo).

### Credenciales de n8n

Se importan desde `n8n/credenciales/` **sin secretos** y los secretos se inyectan con `CREDENTIALS_OVERWRITE_DATA` desde el `.env` (nunca en el repo):

- **OAuth2 API** con *Grant Type* «Client Credentials» (URL de token `…/realms/supervision/protocol/openid-connect/token`, cliente `n8n`). n8n pide el token y lo vuelve a pedir cuando un servicio responde `401`. La usan todos los nodos HTTP (Finanzas, Obras y la API de administración de Keycloak).
- **RabbitMQ** (usuario del `.env`).
- **SMTP** (Mailpit, sin autenticación en desarrollo).

### Colas (definiciones de RabbitMQ de infra)

Durables, sobre el exchange `plataforma`: `n8n.cobro-emitido` (clave `evento.finanzas.CobroEmitido`) y `n8n.cobro-pagado` (clave `evento.finanzas.CobroPagado`). Los nodos *RabbitMQ Trigger* las usan con «Assert Queue» desactivado (ya existen) y «Delete From Queue When» = «Execution Finishes»: el mensaje se confirma al terminar la ejecución, haya salido bien o mal. Si n8n se cae a mitad, el mensaje vuelve a la cola; si la ejecución falla, queda en el panel para reintentarla (sin bucles de reentrega).

### Flujo «Enviar nota de cobro»

1. **RabbitMQ Trigger** (`n8n.cobro-emitido`, JSON).
2. **HTTP Request** `GET {FINANZAS_URL}/cobros/{datos.cobroId}`. **IF** ya hay envío `NOTA_COBRO` → fin.
3. **HTTP Request** `GET {OBRAS_URL}/planillas/{datos.planillaId}` y `GET {OBRAS_URL}/obras/{obraId}`.
4. **HTTP Request** `GET {KEYCLOAK_URL}/admin/realms/supervision/users/{asignaciones.clienteId}`. **IF** sin `email` → **Stop and Error** «El cliente no tiene correo registrado» (criterio 20).
5. **HTTP Request** `POST {FINANZAS_URL}/cobros/{cobroId}/nota-cobro` con *Response Format* «File» (PDF binario).
6. **Send Email** (SMTP, HTML) al cliente, copia oculta a `COBRANZA_CORREO`, adjunto el PDF. Asunto: `Nota de cobro {numero} · {obra} · {periodo}`. Cuerpo: «Estimado/a {nombre}: le enviamos la nota de cobro {numero} por la planilla N.º {n} de {periodo} de la obra {obra}. Neto a cobrar: Bs {neto}. Vence el {venceEn}. {EMPRESA_NOMBRE}».
7. **HTTP Request** `POST {FINANZAS_URL}/cobros/{cobroId}/envios` (`NOTA_COBRO`, destinatario, id de la ejecución).

### Flujo «Recordar cobros»

1. **Schedule Trigger** todos los días a las 08:00 (zona del flujo `America/La_Paz`).
2. `GET {FINANZAS_URL}/cobros/recordatorios`; une `porVencer` (tipo `RECORDATORIO_POR_VENCER`) y `vencidos` (`RECORDATORIO_VENCIDO`) en una lista.
3. Por cada cobro: `GET` obra → Keycloak (cliente) → **Send Email** con el texto del criterio 12 → `POST …/envios`. Un cliente sin correo deja ese cobro como error y sigue con los demás («Continue On Fail» en ese tramo; la ejecución queda con error visible).
4. Si la lista no estaba vacía: **Send Email** a `COBRANZA_CORREO` «Resumen de cobranza del {fecha}» con una tabla (número, obra, monto, vencimiento, tipo).

### Flujo «Enviar constancia de pago»

1. **RabbitMQ Trigger** (`n8n.cobro-pagado`).
2. `GET {FINANZAS_URL}/cobros/{cobroId}`; **IF** ya hay `CONSTANCIA_PAGO` → fin.
3. `GET` obra → Keycloak (cliente) → **Send Email** «Constancia de pago {numero} · {obra}»: «Registramos el pago del cobro {numero} de la obra {obra} por Bs {monto}, pagado el {pagadoEn}{, comprobante {comprobante}}. Gracias. {EMPRESA_NOMBRE}», copia oculta a cobranzas.
4. `POST …/envios` (`CONSTANCIA_PAGO`).

### Comunes a los tres

- Nodos HTTP y de correo con *Retry On Fail*: 3 intentos cada 10 s; tiempo máximo de 10 s por llamada (criterio 19).
- Los flujos se guardan en JSON en `infra/n8n/flujos/` con su `id` fijo y se importan al iniciar (`n8n import:workflow --separate --input=…`; se importan desactivados) y se activan con `n8n publish:workflow --id=…` (en 2.x; `update:workflow --active` está obsoleto). Comprobar al implementar el orden de arranque y si la activación necesita reiniciar.
- Cambiar un texto o un horario se hace en el editor de n8n y se vuelve a exportar el JSON al repo.

## Pruebas

- Finanzas: pago (fechas límite, `409` repetido, `404`, rol distinto de `admin` → `403`, outbox `CobroPagado` en la misma transacción), `PAGADO` no se vence, `totalCobrado` con pagados, resumen y MCP sin pagados, `recordatorios` (bordes: vence hoy, hoy + 3, hoy + 4, vencido ayer, pendiente con vencimiento pasado, ya recordado, pagado), `envios` idempotente, `nota-cobro` (PDF válido que contiene número, neto y la leyenda; cada caso de `422`; rol distinto de `automatizacion` → `403`), semilla.
- IA: consumidor de `CobroPagado` (repetido, sin `CobroEmitido` previo), tarea de vencidos con pagados, carga inicial, catálogo y seguridad del reporte con `PAGADO`.
- Gateway: campos nuevos, mutación por rol y errores.
- mf-obras: estados, etiquetas de correos, «Nota sin enviar», diálogo (solo `admin`, validaciones, errores), sin conexión.
- Integración (infra, con Docker Compose y la API de Mailpit): aprobar una planilla en el portal → en menos de 1 minuto un correo al cliente con el PDF y el envío anotado; volver a publicar el mismo `CobroEmitido` → sin segundo correo; ejecutar «Recordar cobros» → recordatorio del cobro vencido de la semilla y resumen a cobranzas; ejecutarlo otra vez → nada; registrar un pago → constancia; cliente sin correo → ejecución fallida y «Nota sin enviar».
- Manual (Jairo, en la demostración): aprobar una planilla en el portal, abrir Mailpit (`http://localhost:8025`) y el PDF, ver «Nota enviada» en el ERP, registrar el pago y ver la constancia; abrir el panel de n8n (`http://localhost:5678`) y mostrar las ejecuciones.

## Cambios a contratos y datos

Para integrar en los documentos compartidos al implementar (primera tarea de cada proyecto).

### `docs/contratos/eventos.md`

- Fila de `CobroEmitido`: «Escuchan: Obras, IA, n8n (201)».
- Fila nueva `evento.finanzas.CobroPagado` (tabla «Eventos» de arriba), en una sección «Capa 2».
- Fila de `StockBajo`: «Escuchan: (Notificaciones en la 010)»; ya no n8n.

### `docs/contratos/rest.md`

- Finanzas: reemplazar «Capa 2 · Crear orden de compra y cuenta por pagar…» por `POST /cobros/{id}/pago`, `GET /cobros/recordatorios`, `POST /cobros/{id}/envios`, `POST /cobros/{id}/nota-cobro`; en `GET /cobros` y `GET /cobros/{id}`, `PAGADO`, `pagadoEn`, `comprobante` y `envios`; en `GET /contratos`, que `totalCobrado` incluye los `PAGADO`.

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

El SDL de arriba; en «Consume (REST)», Finanzas agrega `POST /cobros/{id}/pago`.

### `services/finanzas/docs/datos.md`, `contratos.md` y `servicio.md`

- Datos: cambios de `cobro`, tabla `envio_cobro`; se quitan `proveedor`, `orden_compra` y `cuenta_por_pagar` (eran de la compra automática).
- Contratos: los cuatro endpoints, `CobroPagado` publicado.
- Servicio: «Registrar pago de un cobro» (admin) y «Atender a la automatización de cobranza» (n8n).

### `services/ia/docs/datos.md` y `contratos.md`

`rpt_cobro.pagado_en` y el estado `PAGADO`; escucha `CobroPagado`; catálogo de reportes con el valor y la columna nuevos.

### `services/materiales/docs/`

`servicio.md` («Avisar stock bajo para la automatización de compras») y `datos.md` (`proveedor_habitual_id`): la automatización de compras ya no existe; el aviso queda para la 010 y el campo queda sin uso (no se borra para no tocar la semilla).

### `frontend/mf-obras/docs/contratos.md` y `app.md`

`registrarPagoCobro`, `Cobro.pagadoEn`, `comprobante` y `envios`; la pestaña «Cobros» con el diálogo.

### `docs/reglas-negocio.md`

- Sección «Planilla de avance» (saga): el cobro tiene los estados `PENDIENTE` → `VENCIDO` y `PENDIENTE` o `VENCIDO` → `PAGADO`; un `PAGADO` no cambia más.
- Sección nueva «Cobranza (capa 2)»: pago completo registrado por administración (fecha entre la emisión y hoy); nota de cobro al emitirse; recordatorios por vencer (hasta 3 días antes) y vencido, uno de cada tipo; constancia al pagar; los `PAGADO` no reciben recordatorios (**decisiones del equipo**).
- «Material y stock»: el evento «stock bajo» ya no lo usa la capa 2.

### `docs/permisos.md`

- `automatizacion`: «Rutas de Finanzas que llama n8n (recordatorios, envíos y nota de cobro)»; el cliente `n8n` tiene además `gerente` (lectura) y `view-users`.
- Filas: «Registrar pago de un cobro» (`admin`); `POST /cobros/{id}/pago` (`admin`); `GET /cobros/recordatorios`, `POST /cobros/{id}/envios`, `POST /cobros/{id}/nota-cobro` (`automatizacion`); quitar las filas de órdenes de compra y cuentas por pagar.

### `docs/mensajes.md`

- Reemplazar los cinco códigos de la capa 2 por `COBRO_NO_ENCONTRADO` (404, «No se encontró el cobro.»), `COBRO_YA_PAGADO` (409, «El cobro ya está pagado.»), `FECHA_PAGO_INVALIDA` (422, «La fecha de pago no puede ser futura ni anterior a la emisión del cobro.») y `NOTA_COBRO_INCONSISTENTE` (422, solo n8n, «Los datos de la planilla no coinciden con el cobro.»).
- Textos de la pestaña «Cobros» («Registrar pago», «Pago registrado», «Pagado el…», etiquetas de correos, «Nota sin enviar») y de los correos (asuntos y cuerpos de arriba).

### `docs/convenciones.md`

- Roles técnicos: `automatizacion` en las rutas de Finanzas de la 201; el cliente `n8n` con `gerente` y `view-users` (segunda excepción a la API de administración de Keycloak, junto al gateway).
- «Puertos en desarrollo»: n8n `5678`, Mailpit `1025` / `8025` (si no figuran).
- «Eventos y comandos»: colas `n8n.cobro-emitido` y `n8n.cobro-pagado`.

### `docs/arquitectura.md`

Filas de n8n en «Conexiones»: RabbitMQ → n8n (`CobroEmitido`, `CobroPagado`); n8n → Finanzas, Obras y Keycloak (REST con token de *service account*); n8n → correo (SMTP).

### `docs/entorno-local.md` y `docs/stack.md`

- Imágenes: `n8nio/n8n:2.43.7` y `axllent/mailpit:v1.31.6` (la tabla decía `v1.32`, que no tenía dos semanas al especificar).
- Finanzas: `barryvdh/laravel-dompdf` 3.1.2 para la nota de cobro.

### `docs/datos-prueba.md`

- Sección 8: envío `NOTA_COBRO` de los 3 cobros; sin pagos.
- Sección 4 (proveedores) y la columna «Proveedor habitual» del catálogo: sin uso desde que la 201 dejó de ser la compra automática.

### `docs/producto.md` y `CLAUDE.md`

«Fuera del alcance»: «Registro de pagos de clientes y a proveedores» pasa a «Pagos parciales de clientes y pagos a proveedores»; en el `CLAUDE.md`, «registro de pagos» pasa a «pagos parciales y a proveedores».

### Repos con tareas de la compra automática

Borrar `docs/specs/201-compra-automatica/` en `services/materiales`, `services/finanzas`, `gateway`, `frontend/mf-materiales`, `mobile/app-obra` e `infra` (cada uno en su rama `feat/201-cobranza-automatica`).

### `docs/plan.md`

Fila 201 con los proyectos infra, finanzas, ia, gateway y mf-obras.
