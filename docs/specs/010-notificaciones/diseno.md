# 010 · Diseño

## Flujo

```
Obras      ──PlanillaPresentada (nuevo), PlanillaAprobada, PlanillaObservada, ObraRegistrada──┐
Finanzas   ──CobroVencido (nuevo), ContratoRechazado─────────────────────────────────────────┼─> exchange plataforma ─> cola «notificaciones»
Materiales ──StockBajo──────────────────────────────────────────────────────────────────────┘
                                                                                                │
Notificaciones (NestJS · MongoDB notificaciones_db · 8086)  <───────────────────────────────────┘
  ObraRegistrada → guarda obra_acceso (copia de asignaciones, igual que Materiales)
  otro evento    → decide destinatarios (obra_acceso, usuario_conocido por rol)
                 → en una transacción: inbox + una notificación por destinatario (historial)
                 → después de confirmar: push por FCM a los dispositivos de cada destinatario
                      (si Firebase no está configurado: no envía, deja el aviso en el log)

ERP (shell) ──GraphQL──> gateway ──REST──> Notificaciones   (bandeja, contador, registrar dispositivo)
Portal      ──REST──────────────────────> Notificaciones
App de obra ──REST──────────────────────> Notificaciones
Firebase Cloud Messaging ──push──> navegador (service worker firebase-messaging-sw.js) · Android (expo-notifications)
```

Cualquier llamada con token al servicio (desde el gateway, el portal o la app) actualiza `usuario_conocido` con el `sub`, el nombre y los roles del token: así el servicio sabe quiénes son los `admin` y `gerente` sin llamar a Keycloak.

## Decisiones generales

- **Servicio propio** `services/notificaciones` (repositorio `supervision-ms-notificaciones`): ningún servicio del negocio conoce dispositivos ni Firebase; solo publican hechos. Los servicios no cambian si mañana se agrega correo u otro canal.
- **Historial siempre, *push* cuando se puede:** la notificación se guarda primero (es la fuente de verdad de la bandeja); el *push* es un aviso adicional que puede fallar sin perder nada.
- **Destinatarios por rol (decisión del equipo):** el servicio guarda `usuario_conocido` con los roles que trae el token en cada llamada. Se descartó consultar la API de administración de Keycloak con un cliente propio porque `docs/convenciones.md` reserva ese acceso al gateway y obligaría a crear otro cliente confidencial con su secreto. Consecuencia (criterio 26): un `admin` o `gerente` que nunca entró desde que existe el servicio no recibe los avisos «para todos los `admin`/`gerente`». Los usuarios que no se ven hace más de 90 días no se cuentan, para no avisar a cuentas que ya no se usan.
- **Un aviso por hecho y destinatario:** índice único (`evento_id`, `usuario_id`) en `notificacion` además del inbox `mensaje_procesado`.
- **Enlaces sin acoplar rutas:** la notificación guarda una `referencia` (`tipo` + ids). Cada aplicación traduce la referencia a su propia ruta con una función pura `rutaDeNotificacion` (con pruebas). El servicio no conoce rutas de pantallas.
- **Web con mensajes solo de datos y Android con mensajes de notificación (decisión del equipo):** en la web, el service worker arma la notificación del sistema y controla el clic; en Android, el sistema la muestra aunque la app esté cerrada.
- **Solo Android en la app (decisión del equipo):** iOS necesita cuenta de desarrollador de Apple y certificado APNs; queda fuera del alcance.
- **Sin suscripciones GraphQL:** el contador se actualiza con el *push* en primer plano y con una consulta cada 60 s (decisión del equipo); funciona igual sin Firebase.

## Servicio Notificaciones (`services/notificaciones`, nuevo)

- NestJS 12 · TypeScript con módulos ES · Vitest · oxlint · Prettier, **misma base y estructura Clean que Materiales** (decisión del equipo). Puerto `8086`. Base MongoDB `notificaciones_db` en la misma instancia (*replica set* de la fase 1, por las transacciones del inbox).
- Librerías: las de Materiales (`@nestjs/config`, `@nestjs/mongoose` + `mongoose` 9, `class-validator` + `class-transformer`, `@nestjs/swagger` 12, `amqplib`, `jose` 6; Vitest, `supertest`, `mongodb-memory-server` 11 con *replica set*) y además **`firebase-admin` 14** (SDK oficial; versión mayor verificada con `npm view firebase-admin version` → 14.5.0 el 28/10/2026; pide Node ≥ 22). Sin `@nestjs/schedule`: el reintento de *push* usa un intervalo, como el publicador del outbox de Materiales.
- No publica eventos (no tiene outbox). Escucha eventos con inbox.
- Token: valida firma (JWKS), emisor, vencimiento y audiencia `plataforma-api` con `jose`, igual que Materiales. No tiene cliente propio en Keycloak.
- CORS: solo para el portal (`CORS_ORIGENES`); el ERP entra por el gateway y la app no usa CORS.
- `X-Request-Id`: lo lee (o lo crea) y lo incluye en cada registro; en los eventos se registra `correlacionId`.

### Estructura

```
src/
  main.ts                          # ValidationPipe, filtro de errores, CORS, Swagger (dev), puerto
  app.module.ts
  compartido/
    dominio/        regla-negocio.error.ts, formato.ts (montos es-BO, fechas y periodos en America/La_Paz)
    infraestructura/
      auth/         jwt.guard.ts, roles.guard.ts, usuario-actual.decorator.ts (como Materiales)
      http/         problem-details.filter.ts, request-id.middleware.ts
      mensajeria/   rabbit.cliente.ts, sobre.ts, inbox.schema.ts, consumidor.ts (cola, enlaces, reintentos x-intentos, plataforma.fallidos)
      mongo/        transaccion.ts
  acceso-obra/                     # obra_acceso (consumidor de ObraRegistrada)
  usuarios/                        # usuario_conocido + usuario-conocido.interceptor.ts
  dispositivos/
    dominio/        dispositivo.ts, plataforma.ts
    aplicacion/     puertos/dispositivo.repositorio.ts, casos-uso/registrar-dispositivo, dar-de-baja-dispositivo
    infraestructura/ dispositivo.schema.ts, dispositivo.repositorio.mongo.ts
    presentacion/   dispositivos.controller.ts, dto/
  notificaciones/
    dominio/        notificacion.ts, tipo-notificacion.ts, referencia.ts,
                    destinatarios.ts (regla: tipo → destinatarios), redaccion.ts (título y mensaje por tipo; puras)
    aplicacion/
      puertos/      notificacion.repositorio.ts, enviador-push.ts (interfaz), directorio.ts (obra_acceso + usuario_conocido)
      casos-uso/    notificar-evento.caso-uso.ts, listar-notificaciones, contar-no-leidas, marcar-leida, marcar-todas-leidas, reintentar-push
    infraestructura/
      notificacion.schema.ts, notificacion.repositorio.mongo.ts
      consumidores/ manejadores por clave de enrutamiento (traducen datos del evento → entrada del caso de uso)
      push/         firebase.proveedor.ts (inicializa o no), enviador-push.firebase.ts, enviador-push.desactivado.ts, reintentador-push.ts
    presentacion/   notificaciones.controller.ts, dto/, notificacion.respuesta.ts
test/
  notificaciones.e2e-spec.ts       # API y consumidores con mongodb-memory-server y FCM simulado
```

### Variables de entorno (`.env.example`)

```
PORT=8086
MONGODB_URI=mongodb://localhost:27017/notificaciones_db
KEYCLOAK_URL=http://localhost:8080
KEYCLOAK_REALM=supervision
AUDIENCIA=plataforma-api
RABBITMQ_URL=amqp://notificaciones:<RABBITMQ_NOTIFICACIONES_CLAVE de infra/.env>@localhost:5672
CORS_ORIGENES=http://localhost:4300
# Vacío = sin push (las notificaciones se guardan igual). Ver «Configuración de Firebase».
FIREBASE_CUENTA_SERVICIO_RUTA=
```

### Firebase opcional

- `firebase.proveedor.ts` al iniciar:
  - `FIREBASE_CUENTA_SERVICIO_RUTA` vacía → registra **una vez** el aviso `Firebase no configurado: las notificaciones se guardan sin envío push` (nivel `warn`) y usa `EnviadorPushDesactivado`.
  - Ruta con archivo inexistente o JSON inválido → registra el error (sin el contenido del archivo) y usa `EnviadorPushDesactivado`. El servicio **no se detiene** (decisión del equipo: el historial no depende de Firebase).
  - Archivo válido → `initializeApp({ credential: cert(json) }, 'notificaciones')` de `firebase-admin/app` y `getMessaging(app)` de `firebase-admin/messaging`; registra `Firebase configurado (proyecto <project_id>)`.
- `EnviadorPushDesactivado` no envía nada y deja `push.estado = DESACTIVADO`.
- Los nombres exactos de la API (`initializeApp`, `cert`, `getMessaging`, `sendEach`) y de los códigos de error se confirman en la documentación de `firebase-admin` 14 al implementar.

### Datos (MongoDB `notificaciones_db`)

**`notificacion`**

| Campo | Tipo | Notas |
|---|---|---|
| _id | string (uuid) | PK |
| usuario_id | string | destinatario (`sub` de Keycloak) |
| tipo | string | `PLANILLA_PRESENTADA`, `PLANILLA_APROBADA`, `PLANILLA_OBSERVADA`, `STOCK_BAJO`, `COBRO_VENCIDO`, `CONTRATO_RECHAZADO` (las capas agregan los suyos) |
| titulo | string | máx. 80 caracteres |
| mensaje | string | máx. 600 caracteres |
| referencia | `{ tipo, obra_id, planilla_id, material_id, cobro_id }` | embebido; `tipo`: `PLANILLA`, `OBRA`, `STOCK_OBRA`, `COBRO`; los ids que no aplican van `null` |
| evento_id | string (uuid) | `id` del sobre del evento que la originó |
| leida | bool | |
| leida_en | date | nulo si no está leída |
| creada_en | date | |
| push | `{ estado, intentos, enviada_en, dispositivos_ok, dispositivos_error }` | `estado`: `PENDIENTE`, `ENVIADA`, `SIN_DISPOSITIVOS`, `FALLIDA`, `DESACTIVADO` |

Índices: único (`evento_id`, `usuario_id`) · (`usuario_id`, `creada_en` desc) · (`usuario_id`, `leida`) · (`push.estado`, `creada_en`) · TTL sobre `creada_en` de 90 días (criterio 14).

**`dispositivo`**

| Campo | Tipo | Notas |
|---|---|---|
| _id | string | el token de FCM (único por navegador o instalación) |
| usuario_id | string | último usuario que lo registró |
| plataforma | string | `WEB`, `ANDROID` |
| aplicacion | string | `erp`, `portal`, `app-obra` |
| registrado_en | date | |
| actualizado_en | date | cada vez que la aplicación lo vuelve a registrar (al iniciar sesión) |

Índices: (`usuario_id`) · TTL sobre `actualizado_en` de 60 días (decisión del equipo: un token que no se renueva en 2 meses se considera abandonado; las aplicaciones lo vuelven a registrar en cada inicio de sesión).

**`usuario_conocido`**

| Campo | Tipo | Notas |
|---|---|---|
| _id | string | `sub` del token |
| nombre | string | `name` del token (o `preferred_username`) |
| roles | arreglo de string | solo los 6 roles de la plataforma, de `realm_access.roles` |
| visto_en | date | última llamada con token |

Índice: (`roles`, `visto_en`).

**`obra_acceso`**: igual que en Materiales (`_id` = `obraId`, `nombre`, `residente_id`, `maestro_id`, `almacenero_id`, `cliente_id`, `actualizado_en`), desde `ObraRegistrada`.

**`mensaje_procesado`**: `_id` = `id` del mensaje, `procesado_en`; TTL de 30 días (la segunda barrera es el índice único de `notificacion`).

### `usuario_conocido`: cómo se llena

- `usuario-conocido.interceptor.ts` corre en todas las rutas con token. Hace *upsert* de `{ _id: sub, nombre, roles, visto_en: ahora }`.
- Para no escribir en cada llamada, guarda en memoria la última escritura por usuario y solo vuelve a escribir si pasaron 10 minutos o cambiaron los roles (decisión del equipo).
- El ERP llega con el token del usuario reenviado por el gateway; el shell consulta el contador al iniciar sesión, así que basta con entrar una vez.

### Mensajería

- Cola durable `notificaciones` en el exchange `plataforma`, con estos enlaces (se declaran en las definiciones de RabbitMQ de `infra` y también al conectarse, como la cola `ia` de la 401):

| Clave | Qué hace |
|---|---|
| `evento.obras.ObraRegistrada` | *upsert* de `obra_acceso` |
| `evento.obras.PlanillaPresentada` (nuevo) | `PLANILLA_PRESENTADA` |
| `evento.obras.PlanillaAprobada` | `PLANILLA_APROBADA` |
| `evento.obras.PlanillaObservada` | `PLANILLA_OBSERVADA` |
| `evento.materiales.StockBajo` | `STOCK_BAJO` |
| `evento.finanzas.CobroVencido` (nuevo) | `COBRO_VENCIDO` |
| `evento.finanzas.ContratoRechazado` | `CONTRATO_RECHAZADO` |

- Prefetch 10. Por cada mensaje, **en una transacción**: inserta `mensaje_procesado` (si ya existe → confirma sin hacer nada), calcula destinatarios, inserta las notificaciones (`insertMany` sin orden; un choque con el índice único se ignora). Confirma el mensaje **después** del *commit* y luego envía el *push* de las notificaciones creadas.
- Si la obra no está en `obra_acceso` (evento que llegó antes que `ObraRegistrada`, o una obra registrada antes de que existiera la cola) → error → reintento. Reintentos como en la 401: se vuelve a publicar en la cola con el encabezado `x-intentos` + 1; al tercer fallo va a `plataforma.fallidos` con el error y se confirma el original. Las obras registradas antes de crear la cola `notificaciones` no se conocen (en desarrollo se vuelven a cargar los datos).
- Un mensaje con datos incompletos (por ejemplo, sin `obraId`) va directo a `plataforma.fallidos`.

### Destinatarios (`destinatarios.ts`)

| Tipo | Destinatarios | Referencia |
|---|---|---|
| `PLANILLA_PRESENTADA` | `cliente_id` de la obra | `PLANILLA` (obraId, planillaId) |
| `PLANILLA_APROBADA` | `residente_id` de la obra + todos los `admin` | `PLANILLA` |
| `PLANILLA_OBSERVADA` | `residente_id` de la obra + todos los `admin` | `PLANILLA` |
| `STOCK_BAJO` | `almacenero_id` y `residente_id` de la obra | `STOCK_OBRA` (obraId, materialId) |
| `COBRO_VENCIDO` | todos los `admin` y `gerente` | `COBRO` (obraId, cobroId) |
| `CONTRATO_RECHAZADO` | todos los `admin` | `OBRA` (obraId) |

- «Todos los `admin`/`gerente`» = `usuario_conocido` con ese rol y `visto_en` de los últimos 90 días.
- La lista se deduplica (criterio 7). Si queda vacía, se registra en el log y se confirma el mensaje (no es un error).

### Redacción (`redaccion.ts`, decisión del equipo)

Montos con `Intl.NumberFormat('es-BO')` y 2 decimales (`Bs 41.881,80`), fechas `dd/mm/aaaa` en `America/La_Paz`, periodos como «marzo 2027». Si un campo opcional del evento no viene (eventos publicados antes de este cambio), se omite la parte que lo usa.

| Tipo | Título | Mensaje |
|---|---|---|
| `PLANILLA_PRESENTADA` | «Planilla para revisar» (con `reenvio`: «Planilla corregida para revisar») | «Se presentó la planilla N.º 3 (marzo 2027) de Edificio Las Palmas por Bs 41.881,80. Revísala para aprobarla u observarla.» (con `reenvio`: «Se corrigió y volvió a presentar la planilla N.º 3 …») |
| `PLANILLA_APROBADA` | «Planilla aprobada» | «Se aprobó la planilla N.º 3 (marzo 2027) de Edificio Las Palmas. Neto: Bs 41.881,80.» |
| `PLANILLA_OBSERVADA` (`origen = CLIENTE`) | «Planilla observada» | «El cliente observó la planilla N.º 3 (marzo 2027) de Edificio Las Palmas: «<motivo>».» |
| `PLANILLA_OBSERVADA` (`origen = SAGA`) | «No se pudo aprobar la planilla» | «La aprobación de la planilla N.º 3 (marzo 2027) de Edificio Las Palmas falló y quedó observada: <motivo>.» |
| `STOCK_BAJO` | «Stock bajo: Cemento IP-30» | «En Edificio Las Palmas quedan 40 bolsas de Cemento IP-30 (mínimo 100).» |
| `COBRO_VENCIDO` | «Cobro vencido COB-2027-0003» | «El cobro COB-2027-0003 de Edificio Las Palmas por Bs 41.881,80 venció el 02/05/2027.» |
| `CONTRATO_RECHAZADO` | «Contrato rechazado» | «Finanzas rechazó el contrato de Edificio Las Palmas: <motivo>.» |

- Cantidades de stock con hasta 3 decimales y `unidadPlural` (o `unidad` si la cantidad es 1). Si `StockBajo` no trae `material`, el título es «Stock bajo» y el mensaje «En <obra> un material quedó por debajo del mínimo».
- En el *push* el mensaje se corta a 200 caracteres con «…»; en el historial queda completo.

### Envío *push* (`enviador-push.firebase.ts`)

- Busca los `dispositivo` de los destinatarios y arma un mensaje por token:
  - **`ANDROID`**: `notification { title, body }` + `data` + `android { priority: "high", notification { channelId: "avisos", color: "#0E4D5C" } }`.
  - **`WEB`**: solo `data` (sin `notification`) + `webpush { headers { Urgency: "high" } }`; el service worker arma la notificación.
  - `data` (todos los valores como texto; los vacíos se omiten): `notificacionId`, `tipo`, `titulo`, `mensaje`, `referenciaTipo`, `obraId`, `planillaId`, `materialId`, `cobroId`.
- Envía con `sendEach` (hasta 500 mensajes por llamada).
- Por cada respuesta: los tokens con error de token no registrado o inválido (`messaging/registration-token-not-registered`, `messaging/invalid-registration-token`; confirmar en la documentación) se borran de `dispositivo` (criterio 23). Errores temporales (servidor no disponible, error interno, límite de envíos) dejan la notificación `PENDIENTE` con `intentos + 1`.
- Estado de cada notificación: sin dispositivos → `SIN_DISPOSITIVOS`; al menos un envío correcto → `ENVIADA`; todos fallaron de forma definitiva o `intentos = 3` → `FALLIDA`.
- `reintentador-push.ts`: cada 60 s (y al iniciar) toma las notificaciones `PENDIENTE` con `intentos < 3` y `creada_en` de la última hora y las vuelve a enviar. Cubre también un corte del proceso entre el *commit* y el envío (decisión del equipo: un aviso de más de una hora ya no se empuja; queda en la bandeja).
- Registros: un renglón por evento con `correlacionId`, tipo, cantidad de destinatarios y resultado del *push* (sin tokens ni textos de los avisos).

### REST que expone (puerto 8086)

Todas las rutas, salvo `/salud`, exigen token. Roles: los 6 roles de la plataforma. Cada usuario solo ve y cambia **sus** notificaciones y dispositivos (`usuario_id = sub`). Errores en Problem Details.

#### GET /salud
Sin token · `200 {"estado":"ok"}`

#### GET /notificaciones?soloNoLeidas=&limite=&antesDe= · 010
Servicio: Notificaciones · Quién llama: gateway (ERP), portal, app

- `soloNoLeidas` (por defecto `false`), `limite` 1 a 50 (por defecto 20), `antesDe` ISO 8601 (la `creadaEn` del último elemento recibido, para «Ver más»).

```json
{
  "elementos": [{
    "id": "uuid", "tipo": "PLANILLA_PRESENTADA",
    "titulo": "Planilla para revisar",
    "mensaje": "Se presentó la planilla N.º 3 (marzo 2027) de Edificio Las Palmas por Bs 41.881,80. Revísala para aprobarla u observarla.",
    "referencia": { "tipo": "PLANILLA", "obraId": "uuid", "planillaId": "uuid", "materialId": null, "cobroId": null },
    "leida": false, "leidaEn": null, "creadaEn": "2027-04-01T14:30:00Z"
  }],
  "noLeidas": 3,
  "hayMas": true
}
```

Orden: `creadaEn` descendente. Errores: `400` (parámetros mal formados, con `errores[]`) · `401`.

#### GET /notificaciones/no-leidas · 010
`200 { "noLeidas": 3 }` (consulta liviana para el contador).

#### POST /notificaciones/{id}/leida · 010
Sin cuerpo. Devuelve `200` con la notificación (`leida: true`, `leidaEn`). Si ya estaba leída, la devuelve sin cambios.
Errores: `404 NOTIFICACION_NO_ENCONTRADA` (también si es de otro usuario).

#### POST /notificaciones/leidas · 010
Sin cuerpo. Marca todas las no leídas del usuario. `200 { "marcadas": 5 }`.

#### POST /dispositivos · 010
Quién llama: gateway (ERP, con `aplicacion: "erp"`), portal, app.

```json
{ "token": "token de FCM", "plataforma": "WEB", "aplicacion": "portal" }
```

- `token` texto de 1 a 4096 caracteres; `plataforma` `WEB` o `ANDROID`; `aplicacion` `erp`, `portal` o `app-obra`.
- *Upsert* por token: si el token era de otro usuario, pasa al usuario actual (criterio 22). Actualiza `actualizado_en`.
- Máximo 10 dispositivos por usuario (decisión del equipo): al pasar el límite se borra el de `actualizado_en` más antiguo.
- Devuelve `201` si es nuevo o `200` si ya existía: `{ "plataforma": "WEB", "aplicacion": "portal", "actualizadoEn": "…" }` (no devuelve el token).
- Errores: `400` (con `errores[]`) · `401`.

#### POST /dispositivos/baja · 010
Recibe `{ "token": "…" }`. Borra el dispositivo solo si es del usuario actual. Devuelve `204` siempre (también si no existía o era de otro usuario, para no revelar nada). La llaman las aplicaciones al cerrar sesión.

## Obras (`services/obras`)

- `POST /planillas/{id}/presentar` (007): en la misma transacción que el cambio a `PRESENTADA`, outbox **`evento.obras.PlanillaPresentada`** con `datos`:
  `planillaId, obraId, numero, periodo ("2027-03"), neto, reenvio (true si venía de OBSERVADA), presentadaEn`.
- `evento.obras.PlanillaAprobada` agrega `numero`; `evento.obras.PlanillaObservada` agrega `numero` y `periodo`. Solo se agregan campos: siguen en `version: 1` (decisión del equipo, como `StockBajo` en la 201).

## Finanzas (`services/finanzas`)

- `MarcarCobrosVencidos` (tarea diaria 00:10 La Paz, 008): por cada cobro que pasa de `PENDIENTE` a `VENCIDO`, en la misma transacción, outbox **`evento.finanzas.CobroVencido`** con `datos`:
  `cobroId, numero, obraId (del contrato), planillaId, montoNeto, venceEn ("2027-05-02")`.
- Solo publican los cobros que cambian de estado en esa ejecución (`UPDATE … WHERE estado = 'PENDIENTE'`): si la tarea corre dos veces el mismo día, no repite eventos.

## Materiales (`services/materiales`)

- `evento.materiales.StockBajo` agrega `obraNombre` (de `obra_acceso.nombre`) y `material { codigo, nombre, unidad, unidadPlural }` (del catálogo en ese momento), en los dos lugares donde se publica (003 y 004). Es el mismo cambio que hace la 201 (que además suma `precioReferencial` y `proveedorHabitualId` dentro de `material`); si la 201 ya está hecha, no hay nada que cambiar.

## Gateway

```graphql
enum TipoNotificacion { PLANILLA_PRESENTADA PLANILLA_APROBADA PLANILLA_OBSERVADA STOCK_BAJO COBRO_VENCIDO CONTRATO_RECHAZADO }
enum TipoReferencia { PLANILLA OBRA STOCK_OBRA COBRO }
enum PlataformaDispositivo { WEB ANDROID }

type ReferenciaNotificacion { tipo: TipoReferencia! obraId: ID planillaId: ID materialId: ID cobroId: ID }
type Notificacion {
  id: ID! tipo: TipoNotificacion! titulo: String! mensaje: String!
  referencia: ReferenciaNotificacion
  leida: Boolean! leidaEn: String creadaEn: String!
}
type PaginaNotificaciones { elementos: [Notificacion!]! noLeidas: Int! hayMas: Boolean! }
input RegistrarDispositivoEntrada { token: String! plataforma: PlataformaDispositivo! }

extend type Query {
  notificaciones(soloNoLeidas: Boolean, limite: Int, antesDe: String): PaginaNotificaciones!   # 010 · todos
  notificacionesNoLeidas: Int!                                                                 # 010 · todos
}
extend type Mutation {
  marcarNotificacionLeida(id: ID!): Notificacion!                      # 010 · todos
  marcarNotificacionesLeidas: Int!                                     # 010 · todos (devuelve las marcadas)
  registrarDispositivo(entrada: RegistrarDispositivoEntrada!): Boolean!  # 010 · todos (aplicacion = "erp")
  darDeBajaDispositivo(token: String!): Boolean!                       # 010 · todos
}
```

- Módulo `notificaciones/` (`notificaciones.cliente.ts`, `notificaciones.resolver.ts`, `modelos/`, `entradas/`), URL `NOTIFICACIONES_URL` (`http://localhost:8086`).
- Mismo cliente HTTP que el resto (token del usuario, `X-Request-Id`, 3 s, un reintento en consultas, sin reintento en mutaciones). Si Notificaciones no responde → `SERVICIO_NO_DISPONIBLE` en `extensions.codigo` (`extensions.servicio = "notificaciones"`); el resto del ERP no se ve afectado porque estas operaciones van en consultas separadas.
- Cuando una capa agrega un tipo de notificación, agrega su valor a `TipoNotificacion` (y `TipoReferencia` si hace falta) en su «Cambios a contratos y datos».

## ERP · shell (`frontend/erp-shell`)

El shell no consultaba datos del negocio; las notificaciones son una excepción acotada (decisión del equipo): son del usuario, no de un área, y la campana vive en la barra superior. Se consultan por GraphQL al gateway con `HttpClient` (un `POST` con el documento, como la comprobación `{ salud }` de la 104), **sin Apollo**.

### Archivos

```
src/app/notificaciones/
  notificaciones.api.ts            # documentos GraphQL y llamadas con HttpClient (el interceptor agrega el token)
  notificaciones.service.ts        # signals noLeidas, elementos, estado (cargando | ok | error); sondeo; marcar
  campana.component.ts             # mat-icon-button «notifications» + matBadge (acento) + panel (mat-menu)
  bandeja.component.ts             # lista, «Ver más», «Marcar todas como leídas», aviso de permisos
  rutas-notificacion.ts            # referencia → ruta del ERP (función pura, con pruebas)
  abrir-notificacion.component.ts  # ruta /notificaciones/abrir (la usa el service worker)
  push-web.service.ts              # Firebase Messaging: configuración, permiso, token, onMessage, baja
public/firebase-messaging-sw.js    # service worker de FCM
firebase-config.example.json       # ejemplo; la copia real va en public/firebase-config.json (no se sube)
```

### Bandeja y contador

- Al tener sesión: `notificacionesNoLeidas`; luego cada 60 s mientras la pestaña está visible (`document.visibilityState`) y la sesión no está `sinConexion` (104). Si falla: sin número en la campana y estado de error en la bandeja.
- Al abrir el panel: `notificaciones(limite: 20)`; «Ver más» con `antesDe` = `creadaEn` del último. No leídas con fondo `primario-suave` y punto `acento`; fecha relativa corta («hace 5 min») con la fecha completa en el *tooltip*.
- Clic en un aviso: `marcarNotificacionLeida(id)` (optimista) y navegación a `rutaDeNotificacion(referencia)` si no es `null`.
- `rutaDeNotificacion` (ERP): `PLANILLA` → `/obras/planillas/{planillaId}`; `STOCK_OBRA` → `/materiales/stock?obraId={obraId}`; `OBRA` y `COBRO` → `/obras/{obraId}`. Para rutas de un remoto *web component* (`/materiales/**`), después de `router.navigateByUrl` el shell emite `popstate` (mismo mecanismo que usan los microfrontends para cambiar de área).
- Ruta del shell `/notificaciones/abrir?id=&referenciaTipo=&obraId=&planillaId=&materialId=&cobroId=`: marca leída la notificación `id`, calcula la ruta con `rutaDeNotificacion` y navega con `replaceUrl` (si no hay ruta, abre la bandeja en `/`).

### *Push* web (`push-web.service.ts`)

- Paquete **`firebase` 13** (SDK web modular; versión mayor verificada con `npm view firebase version` → 13.1.0 el 28/10/2026). Se usa `firebase/app` y `firebase/messaging`.
- Configuración en tiempo de ejecución: `GET /firebase-config.json` (`{ apiKey, projectId, messagingSenderId, appId, vapidKey }`). Si no existe (404) o le falta un campo → *push* desactivado sin error (un `console.info`), la bandeja no ofrece «Activar avisos».
- También se desactiva si `isSupported()` de `firebase/messaging` devuelve `false` (navegador sin soporte).
- Registro del service worker propio: `navigator.serviceWorker.register('/firebase-messaging-sw.js?config=' + encodeURIComponent(JSON.stringify(configSinVapid)), { scope: '/firebase-cloud-messaging-push-scope' })`. La configuración web de Firebase no es secreta (va al navegador); se pasa por la URL porque el service worker no puede leer el entorno de Angular.
- Permiso: si `Notification.permission === 'default'`, la bandeja muestra «Activar avisos en este navegador» y solo pide permiso al pulsarlo (gesto del usuario). Si es `denied`: «Los avisos están bloqueados en este navegador». Si es `granted`: en cada inicio de sesión `getToken(messaging, { vapidKey, serviceWorkerRegistration })` y `registrarDispositivo({ token, plataforma: WEB })`.
- `onMessage` (pestaña visible): actualiza el contador y muestra un `MatSnackBar` con el título y «Ver» (criterio 19).
- Mensajes del service worker (`navigator.serviceWorker` evento `message` con `{ tipo: 'plataforma:abrir-notificacion', url }`): navega a esa URL.
- Cerrar sesión: antes de `keycloak.logout()`, `darDeBajaDispositivo(token)` y `deleteToken(messaging)`, con 2 s máximo; si fallan, se sigue cerrando la sesión (el siguiente usuario reasigna el token al registrarlo).

### `public/firebase-messaging-sw.js` (mismo archivo en el shell y el portal)

- Carga los scripts *compat* de Firebase desde `https://www.gstatic.com/firebasejs/<versión>/firebase-app-compat.js` y `firebase-messaging-compat.js` con **la misma versión** que el paquete `firebase` instalado (verificado que existen para 13.1.0). Lee la configuración de `new URL(self.location).searchParams.get('config')`; si no hay, no inicializa nada.
- `messaging.onBackgroundMessage(payload)`: `self.registration.showNotification(payload.data.titulo, { body: payload.data.mensaje, icon: '/favicon.ico', tag: payload.data.notificacionId, data: payload.data })`.
- `notificationclick`: cierra la notificación; arma `/notificaciones/abrir?id=…&referenciaTipo=…&…` con `data`; si hay una ventana del mismo origen, la enfoca y le envía `postMessage({ tipo: 'plataforma:abrir-notificacion', url })`; si no, `clients.openWindow(url)`.
- No usa `localStorage` ni guarda datos.

### Convivencia con el service worker de Angular (104)

- `ngsw-worker.js` controla el alcance `/`; `firebase-messaging-sw.js` usa el alcance `/firebase-cloud-messaging-push-scope` (el que usa Firebase por defecto). Son dos registros distintos y no se pisan; la suscripción *push* es del segundo.
- `ngsw-config.json`: excluir `/firebase-messaging-sw.js` y `/firebase-config.json` del grupo `app` (`"!/firebase-messaging-sw.js"`, `"!/firebase-config.json"`) para que el service worker de Angular no los guarde ni sirva una versión vieja.
- No se usa `SwPush` de Angular (sería otro canal *push* con sus propias claves VAPID).
- En desarrollo (`ng serve`) el service worker de Angular no se registra, pero el de Firebase sí (`localhost` cuenta como origen seguro). Con la versión compilada de la 104 deben funcionar los dos: lo comprueba la prueba manual.

## mf-materiales

- La ruta `/materiales/stock` acepta el parámetro de búsqueda `obraId` (validado con Zod) para dejar elegida esa obra al abrirse desde una notificación. Sin el parámetro se comporta como en la 003.

## Portal (`frontend/portal`)

```
src/notificaciones/
  api.ts                           # fetch a VITE_NOTIFICACIONES_URL con el token; queryOptions
  Campana.tsx                      # IconButton + Badge (acento) + Popover con la lista
  rutas-notificacion.ts            # PLANILLA → /planillas/{planillaId}; otro → null
  push-web.ts                      # igual que el shell, con la configuración de VITE_FIREBASE_*
src/routes/notificaciones.abrir.tsx  # mismo papel que /notificaciones/abrir del shell (search validado con Zod)
public/firebase-messaging-sw.js    # copia del archivo del shell
```

- `api/cliente.ts` se generaliza para recibir la URL base (Obras o Notificaciones).
- Campana en la barra superior de `__root.tsx`. TanStack Query: `noLeidas` con `refetchInterval: 60000` y `refetchIntervalInBackground: false`; lista con `useInfiniteQuery` (`antesDe`); mutaciones `marcarLeida` y `marcarTodas` invalidan ambas.
- Variables (validadas con Zod al iniciar): `VITE_NOTIFICACIONES_URL` (obligatoria) y `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_APP_ID`, `VITE_FIREBASE_VAPID_KEY` (opcionales: o están todas o ninguna; sin ellas no hay *push*).
- `onMessage` en primer plano → `Snackbar` de MUI con «Ver» e invalida el contador.
- Cerrar sesión: baja del dispositivo y `deleteToken` antes de `signoutRedirect`, con 2 s máximo.
- `registrarDispositivo` → `POST /dispositivos` con `aplicacion: "portal"`.

## App de obra (`mobile/app-obra`)

### Paquetes y configuración

- `npx expo install expo-notifications expo-constants` (**`expo-notifications` 58**, versión mayor verificada con `npm view expo-notifications version` → 58.1.6 el 28/10/2026; `expo-constants` 58). La app se instala en Android como *development build* (`expo-dev-client`, igual que en la 301) o como APK: **los avisos *push* no funcionan en Expo Go en Android** (desde el SDK 53), aunque la bandeja sí.
- `app.json` pasa a `app.config.ts` (lee `app.json` y agrega lo dinámico):
  - `android.package`: `bo.supervision.appobra` (decisión del equipo; si la 301 ya fijó otro, se usa ese y se registra ese mismo en Firebase).
  - `android.googleServicesFile`: `process.env.GOOGLE_SERVICES_JSON` (variable de archivo de EAS) o `./google-services.json` **solo si el archivo existe**; si no existe, se omite y la *build* se hace igual (sin *push*).
  - Plugin `["expo-notifications", { "color": "#0E4D5C", "defaultChannel": "avisos" }]` (confirmar las opciones del plugin en la documentación del SDK 58).
  - `extra.notificacionesUrl` (por ejemplo `http://10.0.2.2:8086` en el emulador), validada con Zod en `nucleo/configuracion.ts`.
- `.gitignore`: agregar `google-services.json`.

### Archivos

```
src/notificaciones/
  api.ts                           # fetch a notificacionesUrl con el token; queryOptions
  push.ts                          # canal, permiso, token nativo, registro, baja, listeners
  rutas-notificacion.ts            # STOCK_OBRA → /obras/{obraId}/stock; otro → null
src/app/(app)/avisos.tsx           # pestaña «Avisos» (todos los roles de la app)
```

### *Push* (`push.ts`)

- Al iniciar la app: `Notifications.setNotificationChannelAsync('avisos', { name: 'Avisos', importance: HIGH })` (antes de pedir permiso: en Android 13 o superior el diálogo solo aparece si existe un canal) y `setNotificationHandler` que en primer plano **no** muestra el aviso del sistema (la app muestra un `Snackbar` y actualiza el contador).
- Si `Constants.executionEnvironment` indica Expo Go → no pide permiso ni token; registra en consola «Push no disponible en Expo Go».
- Después de iniciar sesión (y con señal): `getPermissionsAsync`; si no está concedido y nunca se pidió en este celular (marca en `expo-secure-store`), `requestPermissionsAsync` una sola vez (criterio 20). Con permiso: `getDevicePushTokenAsync()` (token nativo de FCM, `type: 'android'`) → `POST /dispositivos { token, plataforma: ANDROID, aplicacion: "app-obra" }`. Si `getDevicePushTokenAsync` falla porque la *build* no tiene `google-services.json` → registra «Firebase no configurado en la app» y sigue sin *push*.
- `addPushTokenListener`: si el token cambia, lo vuelve a registrar.
- Toque en una notificación (`addNotificationResponseReceivedListener` y, al abrir la app desde cerrada, `getLastNotificationResponseAsync`): lee `data`, marca leída (`POST /notificaciones/{id}/leida`) y navega con `rutaDeNotificacion` o, si es `null`, a la pestaña «Avisos».
- Cerrar sesión (101): `POST /dispositivos/baja` con el token antes de borrar los tokens de sesión, con 2 s máximo; sin señal se omite (el siguiente usuario que inicie sesión en el celular reasigna el token).

### Pestaña «Avisos»

- Ícono `bell` de MaterialCommunityIcons con `Badge` de Paper (número; «9+»). Lista con `List.Item` (no leídas en negrita y con punto), «Marcar todas como leídas», *pull to refresh*, «Ver más».
- TanStack Query con `refetchInterval: 60000` mientras la app está en primer plano y al volver a primer plano.
- Marcar como leída **no** pasa por la cola de la 101 (no es un registro de obra): necesita señal. Sin señal la pestaña muestra «Sin señal · no se pueden cargar los avisos» y lo último cargado, si lo hay.

## Infra

- Definiciones de RabbitMQ: cola durable `notificaciones` con los 7 enlaces de la tabla «Mensajería».
- MongoDB: nada que crear (`notificaciones_db` se crea sola); el *replica set* de la fase 1 ya está.
- Si el Docker Compose levanta los servicios: servicio `notificaciones` en 8086 con sus variables (sin Firebase por defecto) y el volumen de solo lectura para `secretos/` documentado como opcional.
- README: enlace a la sección «Configuración de Firebase» de este diseño y cómo comprobar el aviso en el log.

## Configuración de Firebase (lo hace el usuario)

Mientras no se haga, todo funciona sin *push*. Los nombres de los menús son los de la consola de Firebase al 28/10/2026; si cambian, buscar la opción equivalente.

### Pasos en la consola (https://console.firebase.google.com)

1. **Crear el proyecto**: «Agregar proyecto» → nombre `supervision-obras` (o el que se quiera). Google Analytics no hace falta.
2. **App web** (sirve para el ERP y el portal): Configuración del proyecto (engranaje) → General → «Tus apps» → ícono web `</>` → apodo `plataforma-web`, sin Firebase Hosting → copiar de `firebaseConfig` los valores `apiKey`, `projectId`, `messagingSenderId` y `appId`.
3. **Clave VAPID**: Configuración del proyecto → Cloud Messaging → «Configuración web» → «Certificados push web» → «Generar par de claves» → copiar la **clave pública**. Verificar en la misma pestaña que la «API de Firebase Cloud Messaging (V1)» esté habilitada (la usa `firebase-admin`).
4. **App Android**: Configuración del proyecto → General → «Agregar app» → Android → nombre del paquete **exactamente** el de `app.config.ts` (`bo.supervision.appobra`); el SHA-1 no hace falta para FCM → descargar **`google-services.json`**.
5. **Cuenta de servicio** (para el servidor): Configuración del proyecto → Cuentas de servicio → Firebase Admin SDK → «Generar nueva clave privada» → se descarga un JSON (`<proyecto>-firebase-adminsdk-….json`). **Es una credencial con acceso de administrador al proyecto**: no se comparte ni se sube.

### Dónde va cada cosa

| Qué | Dónde | ¿Al repositorio? |
|---|---|---|
| JSON de la cuenta de servicio | `services/notificaciones/secretos/firebase-cuenta-servicio.json` | **No** (`secretos/` en `.gitignore`) |
| Ruta a ese JSON | `services/notificaciones/.env` → `FIREBASE_CUENTA_SERVICIO_RUTA=./secretos/firebase-cuenta-servicio.json` | **No** (`.env`) |
| Configuración web + VAPID del ERP | `frontend/erp-shell/public/firebase-config.json` → `{ "apiKey": "…", "projectId": "…", "messagingSenderId": "…", "appId": "…", "vapidKey": "…" }` (copiar de `firebase-config.example.json`) | **No** (en `.gitignore`) |
| Configuración web + VAPID del portal | `frontend/portal/.env.local` → `VITE_FIREBASE_API_KEY`, `VITE_FIREBASE_PROJECT_ID`, `VITE_FIREBASE_MESSAGING_SENDER_ID`, `VITE_FIREBASE_APP_ID`, `VITE_FIREBASE_VAPID_KEY` | **No** (`.env.*` ya está en `.gitignore`) |
| `google-services.json` | `mobile/app-obra/google-services.json` (o variable de archivo `GOOGLE_SERVICES_JSON` en EAS) | **No** (en `.gitignore`) |

- La configuración web y `google-services.json` no son secretos para Firebase (terminan dentro de la aplicación), pero los repositorios son públicos y se dejan fuera por decisión del equipo; en la consola de Google Cloud se puede restringir la `apiKey` a los orígenes `http://localhost:4200` y `http://localhost:4300` (opcional).
- Si la cuenta de servicio se sube por error: borrar la clave en Google Cloud → IAM → Cuentas de servicio → Claves, generar otra y limpiar el historial del repositorio.

### `.gitignore` de cada proyecto (lo agregan las tareas)

| Proyecto | Líneas |
|---|---|
| `services/notificaciones` | `.env`, `.env.*`, `!.env.example`, `secretos/`, `*-firebase-adminsdk-*.json` |
| `frontend/erp-shell` | `public/firebase-config.json` |
| `frontend/portal` | (ya cubierto por `.env.*`) |
| `mobile/app-obra` | `google-services.json` |

### Después de poner las credenciales

1. Reiniciar Notificaciones: el log debe decir «Firebase configurado (proyecto …)» en lugar del aviso.
2. ERP y portal: recargar; en la bandeja aparece «Activar avisos en este navegador».
3. App: `npx expo prebuild --clean` y `npx expo run:android` (o EAS Build con perfil `development`) para que la *build* incluya `google-services.json`; abrir la app, iniciar sesión y aceptar el permiso.

## Pruebas

- Notificaciones (con `mongodb-memory-server` y FCM simulado detrás de la interfaz `EnviadorPush`):
  - cada evento produce las notificaciones de la tabla de destinatarios con el título y mensaje esperados (montos, fechas en La Paz, periodo en letras, `reenvio`, `origen`), y su referencia;
  - deduplicación de destinatarios; «todos los `admin`» solo con `visto_en` de los últimos 90 días;
  - el mismo mensaje dos veces → una notificación por destinatario; dos mensajes distintos del mismo hecho no rompen el índice;
  - obra desconocida → reintento con `x-intentos` y, al tercero, `plataforma.fallidos`; datos incompletos → `plataforma.fallidos`;
  - `ObraRegistrada` → `obra_acceso` (repetido no duplica);
  - `usuario_conocido`: se crea con la primera llamada, no se reescribe antes de 10 min salvo que cambien los roles;
  - REST: listado paginado con `antesDe`, `soloNoLeidas`, contador, marcar una (ajena → 404), marcar todas, dispositivos (alta, reasignación del token a otro usuario, límite de 10, baja propia y ajena → 204), 401 sin token;
  - *push*: Android con `notification` y canal, web solo `data`; token inválido → se borra el dispositivo; error temporal → `PENDIENTE` y reintento; tres fallos → `FALLIDA`; sin dispositivos → `SIN_DISPOSITIVOS`;
  - sin `FIREBASE_CUENTA_SERVICIO_RUTA` (y con ruta inexistente): el servicio arranca, registra el aviso una sola vez y las notificaciones quedan `DESACTIVADO`.
- Obras: presentar publica `PlanillaPresentada` (con `reenvio` falso y verdadero); `PlanillaAprobada` y `PlanillaObservada` con los campos nuevos.
- Finanzas: la tarea diaria publica un `CobroVencido` por cada cobro vencido y nada en la segunda ejecución del día.
- Materiales: `StockBajo` con `obraNombre` y `material` desde 003 y 004.
- Gateway: consultas y mutaciones contra un servicio simulado; `aplicacion: "erp"` en el alta; servicio caído → `SERVICIO_NO_DISPONIBLE` solo en esa operación.
- erp-shell: `rutaDeNotificacion`; servicio de notificaciones (sondeo, estado de error, marcar optimista); campana con «9+»; `push-web` sin configuración y sin soporte (no ofrece activar); ruta `/notificaciones/abrir`.
- Portal: campana, lista, marcar, `rutaDeNotificacion`, esquema Zod de las variables (todas o ninguna de Firebase).
- App: `rutaDeNotificacion`, pestaña con contador, `push.ts` con `expo-notifications` simulado (Expo Go → no pide; permiso negado; token registrado; fallo de token sin `google-services.json`).
- mf-materiales: `/materiales/stock?obraId=` deja elegida la obra.
- Integración (infra, con Docker Compose y **sin Firebase**): presentar una planilla → el cliente tiene la notificación en `GET /notificaciones`; aprobarla → residente y `admin` (que entró antes) la tienen; volver a publicar el mismo mensaje → sin duplicados.
- Manual (lo hace el equipo, con Firebase configurado): en Chrome, ERP y portal con la pestaña en segundo plano y luego cerrada → llega la notificación y el clic abre la pantalla; con la pestaña visible → solo el mensaje breve; con la versión compilada de la 104 → siguen funcionando los dos service workers; en un celular Android con la *development build*, app cerrada → llega el aviso de stock bajo y al tocarlo abre el stock de la obra; cerrar sesión y entrar con otro usuario → el celular ya no recibe los avisos del primero; en Expo Go → no pide permiso y la bandeja funciona.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/contratos/eventos.md`

- Nuevas filas en «Sistema base»:

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.PlanillaPresentada` | Obras | Notificaciones | `planillaId, obraId, numero, periodo, neto, reenvio, presentadaEn` | 007, 010 |
| `evento.finanzas.CobroVencido` | Finanzas | Notificaciones | `cobroId, numero, obraId, planillaId, montoNeto, venceEn` | 008, 010 |

- Filas que cambian: `ObraRegistrada` y `ContratoRechazado` agregan «Notificaciones» en «Escuchan»; `StockBajo` agrega «Notificaciones» y los `datos` `obraNombre, material{codigo, nombre, unidad, unidadPlural}`; `PlanillaAprobada` agrega «Notificaciones» y `numero`; `PlanillaObservada` agrega «Notificaciones», `numero` y `periodo`. Todos siguen en `version: 1`.

### `docs/contratos/rest.md`

Nueva sección **«Notificaciones (puerto 8086)»** con `GET /salud`, `GET /notificaciones`, `GET /notificaciones/no-leidas`, `POST /notificaciones/{id}/leida`, `POST /notificaciones/leidas`, `POST /dispositivos` y `POST /dispositivos/baja`, tal como están arriba (código `NOTIFICACION_NO_ENCONTRADA`).

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

El SDL de la sección «Gateway» (`TipoNotificacion`, `TipoReferencia`, `PlataformaDispositivo`, `ReferenciaNotificacion`, `Notificacion`, `PaginaNotificaciones`, `RegistrarDispositivoEntrada`, consultas `notificaciones` y `notificacionesNoLeidas`, mutaciones `marcarNotificacionLeida`, `marcarNotificacionesLeidas`, `registrarDispositivo`, `darDeBajaDispositivo`). En «Consume (REST)» la fila Notificaciones con sus 6 endpoints y la variable `NOTIFICACIONES_URL`.

### `docs/convenciones.md`

- «Puertos en desarrollo»: **Notificaciones · 8086**.
- «Eventos y comandos»: agregar la cola `notificaciones` a la lista de colas por servicio.
- «Autenticación y permisos»: aclarar que Notificaciones **no** llama a la API de administración de Keycloak; conoce los roles por `usuario_conocido` (roles del token en cada llamada).
- Nueva sección corta «Notificaciones»: los servicios no envían avisos; publican hechos y el servicio Notificaciones decide destinatarios; una notificación por evento y destinatario; Firebase opcional (sin credenciales, solo historial).

### `docs/reglas-negocio.md`

Nueva sección «Notificaciones» con la tabla de destinatarios de este diseño y las decisiones del equipo: avisos «para todos los `admin`/`gerente`» solo a quienes entraron en los últimos 90 días, historial de 90 días, un aviso por hecho y persona.

### `docs/stack.md`

- Nueva sección `services/notificaciones (NestJS 12 · MongoDB)`: las librerías de Materiales y **`firebase-admin` 14** (envío *push* por FCM).
- `frontend/erp-shell`: **`firebase` 13** (Messaging web) y la nota «el shell consulta solo las notificaciones, por `HttpClient` al gateway, sin Apollo».
- `frontend/portal`: **`firebase` 13**.
- `mobile/app-obra`: **`expo-notifications`** y **`expo-constants`** (con `npx expo install`); *development build* con `expo-dev-client` también para el *push*.

### `docs/arquitectura.md`

- «Piezas»: Notificaciones · Microservicio · NestJS · MongoDB (`notificaciones_db`).
- «Conexiones»: gateway → Notificaciones (REST); portal → Notificaciones (REST); app → Notificaciones (REST); RabbitMQ → Notificaciones (AMQP, eventos para avisar); Notificaciones → Firebase Cloud Messaging (HTTPS, envío *push*); FCM → navegadores y celulares Android.
- «Versiones»: `firebase-admin` 14 · `firebase` 13 · `expo-notifications` 58.
- «Despliegue» (capa 6, propuesta): Notificaciones en Google Cloud junto a Materiales y MongoDB; la cuenta de servicio de Firebase como secreto montado en el contenedor.

### `docs/producto.md`

«Funciones del sistema base»: agregar «recibir notificaciones (bandeja y avisos *push*)».

### `docs/diseno-visual.md`

«Distribución del ERP (shell)»: la barra superior agrega la campana (ícono `notifications`, contador con fondo `acento`); en la bandeja, no leídas con fondo `primario-suave`.

### `CLAUDE.md` (carpeta general)

- «Mapa de proyectos»: fila `services/notificaciones` · NestJS 12 · TypeScript · MongoDB · Avisos (historial y *push* con Firebase) · Base (010).
- Lista de repositorios: `ms-notificaciones`; la indicación de GitHub CLI agrega `supervision-ms-notificaciones`.

### `docs/plan.md`

Agregar la fila **010 · Notificaciones** en la fase 2 (proyectos: notificaciones, obras, finanzas, materiales, gateway, erp-shell, mf-materiales, portal, app-obra, infra; depende de 001, 002, 003, 004, 007 y 008).

### Documentos de cada proyecto

- `services/notificaciones/docs/` (se crean con el proyecto): `servicio.md` (responsabilidades: historial, destinatarios, *push*; qué no hace: no publica eventos, no envía correo, no llama a Keycloak), `datos.md` (las 5 colecciones), `contratos.md` (REST de arriba; escucha los 7 eventos), `estructura.md` (árbol y librerías de arriba).
- `services/obras/docs/contratos.md`: publica `PlanillaPresentada`; campos nuevos de `PlanillaAprobada` y `PlanillaObservada`.
- `services/finanzas/docs/contratos.md`: publica `CobroVencido`. `services/finanzas/docs/estructura.md`: `MarcarCobrosVencidos` publica por el outbox.
- `services/materiales/docs/contratos.md`: `StockBajo` ampliado.
- `gateway/docs/estructura.md`: módulo `notificaciones/`. `gateway/docs/app.md`: área «Notificaciones» → servicio Notificaciones.
- `frontend/erp-shell/CLAUDE.md`, `docs/estructura.md`, `docs/app.md` y `docs/contratos.md`: carpeta `notificaciones/`, `firebase-messaging-sw.js`, `firebase` 13, excepción «consulta notificaciones por GraphQL con `HttpClient`», consume del gateway las operaciones de notificaciones.
- `frontend/mf-materiales/docs/app.md`: `/materiales/stock?obraId=`.
- `frontend/portal/docs/estructura.md`, `app.md` y `contratos.md`: carpeta `notificaciones/`, ruta `notificaciones.abrir`, consume Notificaciones (REST), variables `VITE_NOTIFICACIONES_URL` y `VITE_FIREBASE_*`.
- `mobile/app-obra/docs/estructura.md`, `app.md` y `contratos.md`: pestaña «Avisos», `src/notificaciones/`, `app.config.ts`, consume Notificaciones (REST), nota de la *development build*.
- `infra/docs/contratos.md` (o README): cola `notificaciones` y sus enlaces.
