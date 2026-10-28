# 101 · Diseño

## Flujo

```
(con señal, al iniciar sesión o abrir la app)
App --GET /paquete-datos (If-None-Match: versión anterior)--> Sincronización
    Sincronización --GET /obras?estado=EN_EJECUCION, GET /obras/{id}--> Obras        (token del usuario)
    Sincronización --GET /materiales?soloActivos=true, GET /obras/{id}/stock--> Materiales
    → 200 { versionDatos, obras, materiales }  |  304 sin cambios
App: guarda el paquete en SQLite

(con o sin señal)
App: registra el movimiento → cola local (SQLite) con su UUID, estado PENDIENTE

(cuando hay señal)
App --POST /lotes { operaciones[≤20] }--> Sincronización
    por cada operación, en orden:
      DynamoDB operacion_procesada: PutItem «solo si no existe» (estado PROCESANDO)
        ya existía → devuelve la respuesta guardada (no llama al servicio dueño)
        no existía → POST /movimientos a Materiales (token del usuario) → guarda estado y respuesta
    → 200 { resultados[] }
App: ENVIADO | RECHAZADO | vuelve a PENDIENTE con espera creciente
```

La app ya no llama directo a Obras ni a Materiales para registrar: todo registro pasa por la cola local y por Sincronización (regla de `mobile/app-obra/CLAUDE.md`). Los servicios dueños mantienen su propia idempotencia por `id` (004, 005): es la segunda barrera.

## Sincronización (servicio nuevo, `services/sincronizacion`)

- NestJS 12 · TypeScript con módulos ES · Vitest · oxlint (misma base que Materiales). Puerto `8084`.
- Arquitectura Clean, como Materiales (decisión del equipo): `dominio/` (operación, clasificación de respuestas, cálculo de la versión de datos), `aplicacion/` (casos de uso `ProcesarLote`, `ArmarPaqueteDatos`), `infraestructura/` (repositorios DynamoDB, clientes REST de Obras y Materiales), `presentacion/` (controladores y DTOs).
- DynamoDB con AWS SDK v3 (`@aws-sdk/client-dynamodb` y `@aws-sdk/lib-dynamodb`). En desarrollo, DynamoDB Local (`DYNAMODB_ENDPOINT=http://localhost:8000`).
- Token: valida firma (JWKS), emisor, vencimiento y audiencia `plataforma-api` con `jose`, igual que Materiales. No tiene cliente propio en Keycloak: reenvía el token del usuario a los servicios dueños, que aplican sus reglas finas (obras asignadas, roles por endpoint).
- Respuestas comprimidas con gzip (`compression`) para gastar menos datos móviles (decisión del equipo).
- Variables de entorno: `PORT=8084`, `KEYCLOAK_URL`, `KEYCLOAK_REALM=supervision`, `AUDIENCIA=plataforma-api`, `OBRAS_URL`, `MATERIALES_URL`, `DYNAMODB_ENDPOINT`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (valores de prueba con DynamoDB Local), `DYNAMODB_CREAR_TABLAS` (`true` solo en desarrollo: crea las tablas al iniciar si no existen), `TIEMPO_MAXIMO_LLAMADA_MS=5000`, `TIEMPO_MAXIMO_LOTE_MS=20000`.

### Tablas (DynamoDB)

**`operacion_procesada`** · clave de partición `id_operacion` · modo *on demand* · TTL sobre `expira_en`

| Atributo | Tipo | Notas |
|---|---|---|
| id_operacion | S | UUID creado en el celular (es el `id` del registro cuando la operación crea uno) |
| id_dispositivo | S | encabezado `X-Dispositivo-Id` |
| usuario_id | S | `sub` del token |
| tipo | S | `MOVIMIENTO_MATERIAL` (101); `FOTO_AVANCE`, `FOTO_NOTA_REMISION` (102); `ENTRADA_DIARIO` (103) |
| servicio_destino | S | `materiales` u `obras` |
| estado | S | `PROCESANDO`, `PROCESADO`, `ERROR` |
| respuesta | S | JSON `{ status, cuerpo }` del servicio dueño (en `ERROR`, el Problem Details) |
| recibida_en | S | ISO 8601 UTC |
| actualizada_en | S | ISO 8601 UTC; sirve para detectar un `PROCESANDO` abandonado |
| expira_en | N | segundos *epoch* = `recibida_en` + 30 días |

**`estado_dispositivo`** · clave de partición `id_dispositivo`

| Atributo | Tipo | Notas |
|---|---|---|
| id_dispositivo | S | UUID generado por la app al instalarse |
| usuario_id | S | último usuario que sincronizó desde ese celular |
| obra_id | S | obra con la que trabaja el usuario en la app (`obraActivaId`) |
| ultima_sincronizacion | S | ISO 8601 UTC; último paquete o lote atendido con éxito |
| version_datos | S | `versionDatos` del último paquete entregado |

- No se verificó si DynamoDB Local borra los elementos vencidos por TTL; las pruebas comprueban que `expira_en` se calcula bien, no que el elemento desaparezca. Si una operación llega después de los 30 días, la vuelve a frenar la idempotencia del servicio dueño.

### Encabezados comunes

- `Authorization: Bearer <token>` y `X-Dispositivo-Id: <uuid>` en todas las rutas salvo `/salud`. Sin `X-Dispositivo-Id` → `400 DISPOSITIVO_REQUERIDO`.
- `X-Request-Id`: si no viene, Sincronización lo crea y lo reenvía a los servicios dueños.

### GET /salud

Sin token · `200 {"estado":"ok"}`

### GET /paquete-datos?obraActivaId= · 101

Servicio: Sincronización · Quién llama: App · Roles: `maestro`, `almacenero`

Encabezado opcional `If-None-Match: "<versionDatos>"`.

Devuelve `200` con encabezado `ETag: "<versionDatos>"`, o `304` sin cuerpo si la versión no cambió:

```json
{
  "versionDatos": "9f2c…(sha256 en hexadecimal)",
  "generadoEn": "2026-11-15T13:00:00Z",
  "obras": [{
    "id": "uuid", "nombre": "Edificio Las Palmas", "ubicacion": "Av. Banzer 4to anillo",
    "partidas": [{ "id": "uuid", "codigo": "P-01", "nombre": "Losa de hormigón armado", "unidad": "m2" }],
    "stock": [{ "materialId": "id", "cantidad": 120.0, "minimo": 100.0, "estado": "JUSTO" }]
  }],
  "materiales": [{ "id": "id", "codigo": "CEM-IP30", "nombre": "Cemento IP-30", "unidad": "bolsa", "unidadPlural": "bolsas" }]
}
```

- Arma el paquete con el token del usuario: Obras `GET /obras?estado=EN_EJECUCION` (ya filtra por obras asignadas), y por cada obra, en paralelo, Obras `GET /obras/{id}` (partidas) y Materiales `GET /obras/{id}/stock`; además Materiales `GET /materiales?soloActivos=true`.
- Solo copia los campos de arriba (datos livianos). Si Materiales responde `404` al stock de una obra recién registrada (todavía no llegó `ObraRegistrada`), envía `stock: []`.
- `versionDatos` = SHA-256 del JSON del paquete sin `generadoEn`, con las claves ordenadas y las listas ordenadas por `id`.
- Actualiza `estado_dispositivo` (`usuario_id`, `obra_id` si vino `obraActivaId`, `version_datos`, `ultima_sincronizacion`).
- Errores: `401` · `403` (rol no permitido) · `503 SERVICIO_NO_DISPONIBLE` si Obras o Materiales fallan, o `504 TIEMPO_AGOTADO` si tardan más de 5 s (la app conserva los datos que ya tenía).
- Las especificaciones 103 (diario) y 201 (órdenes de compra) agregan campos por obra a este paquete.

### POST /lotes · 101

Servicio: Sincronización · Quién llama: App · Roles: `maestro`, `almacenero`

Recibe (máximo 20 operaciones, decisión del equipo):

```json
{
  "operaciones": [{
    "idOperacion": "uuid creado en el celular",
    "tipo": "MOVIMIENTO_MATERIAL",
    "creadaEn": "2026-11-15T14:00:00Z",
    "datos": {
      "id": "uuid (igual a idOperacion)", "obraId": "uuid", "materialId": "id",
      "tipo": "SALIDA", "cantidad": 12.5, "partidaId": "uuid", "registradoEn": "2026-11-15T14:00:00Z"
    }
  }]
}
```

Devuelve `200` con un resultado por operación, en el mismo orden:

```json
{
  "resultados": [
    { "idOperacion": "uuid", "estado": "PROCESADO", "repetida": false, "status": 201,
      "respuesta": { "id": "uuid", "periodo": "2026-11", "superaStock": false, "stock": { "cantidad": 107.5, "minimo": 100.0, "estado": "JUSTO" } } },
    { "idOperacion": "uuid", "estado": "ERROR", "repetida": true, "status": 409,
      "respuesta": { "title": "El periodo está cerrado", "status": 409, "detail": "El periodo 2026-10 ya está cerrado.", "codigo": "PERIODO_CERRADO" } },
    { "idOperacion": "uuid", "estado": "REINTENTAR", "status": 503,
      "respuesta": { "title": "Servicio no disponible", "status": 503, "codigo": "SERVICIO_NO_DISPONIBLE" } }
  ]
}
```

- `estado`: `PROCESADO` (el servicio dueño lo aceptó), `ERROR` (lo rechazó de forma definitiva; no se reintenta) o `REINTENTAR` (no se pudo completar; la app lo vuelve a enviar más tarde con el mismo `idOperacion`).
- `repetida: true` cuando la respuesta sale de lo guardado en DynamoDB y no se llamó al servicio dueño.
- Errores del lote completo: `400 LOTE_INVALIDO` (vacío, más de 20 operaciones, `idOperacion` repetido dentro del lote, datos mal formados) · `401` · `403` · `413` (cuerpo mayor a 256 KB).

#### Tipos de operación y servicio destino

| `tipo` | Servicio | Llamada | Espec. |
|---|---|---|---|
| `MOVIMIENTO_MATERIAL` | Materiales | `POST /movimientos` con cuerpo = `datos` | 101 |
| `FOTO_AVANCE` | Obras | `POST /obras/{datos.obraId}/fotos` | 102 |
| `FOTO_NOTA_REMISION` | Materiales | `PUT /movimientos/{datos.movimientoId}/nota-remision/foto` | 102 |
| `ENTRADA_DIARIO` | Obras | `POST /obras/{datos.obraId}/diario` | 103 |

- Si el `tipo` no está en la tabla → resultado `ERROR` con `400 TIPO_OPERACION_DESCONOCIDO` (no se guarda en DynamoDB).
- En los tipos que crean un registro, `idOperacion` debe ser igual a `datos.id`; si no → `ERROR` con `400 OPERACION_INVALIDA`.

#### Procesamiento de cada operación (en orden, una tras otra)

1. `PutItem` en `operacion_procesada` con `estado = PROCESANDO`, `recibida_en = actualizada_en = ahora`, `expira_en = ahora + 30 días` y `ConditionExpression: attribute_not_exists(id_operacion)` («guardar solo si no existe»).
2. Si falla la condición (`ConditionalCheckFailedException`), `GetItem` con lectura consistente:
   - `usuario_id` distinto del `sub` del token → `ERROR` con `403 OPERACION_AJENA` (no se devuelve la respuesta guardada).
   - `PROCESADO` o `ERROR` → devuelve `status` y `respuesta` guardados con `repetida: true`.
   - `PROCESANDO` con `actualizada_en` de hace más de 60 s (un proceso anterior se cortó) → la toma con `UpdateItem` condicionado a `estado = PROCESANDO AND actualizada_en = <valor leído>` y sigue al paso 3; si la condición falla → `REINTENTAR` con `409 OPERACION_EN_PROCESO`.
   - `PROCESANDO` reciente → `REINTENTAR` con `409 OPERACION_EN_PROCESO`.
3. Llama al servicio destino con el token del usuario y `X-Request-Id`, con tiempo máximo de 5 s.
4. Según la respuesta:
   - `2xx` → `UpdateItem` a `PROCESADO` con `respuesta`; resultado `PROCESADO`.
   - `400`, `403`, `404`, `409`, `422` → `UpdateItem` a `ERROR` con el Problem Details; resultado `ERROR`. Son rechazos definitivos de las reglas del servicio dueño (por ejemplo `PERIODO_CERRADO`, `MATERIAL_INACTIVO`).
   - `401`, `408`, `429`, `5xx`, tiempo agotado o error de red → `DeleteItem` condicionado a `estado = PROCESANDO` (libera el identificador para el siguiente intento); resultado `REINTENTAR` con el `status` recibido, `504 TIEMPO_AGOTADO` si se agotaron los 5 s, o `503 SERVICIO_NO_DISPONIBLE` si hubo error de red. Un `401` usa el código `TOKEN_VENCIDO` para que la app renueve el token.
5. Presupuesto del lote: si pasaron 20 s desde que empezó el lote, las operaciones que faltan no se empiezan y vuelven como `REINTENTAR` con `504 TIEMPO_AGOTADO`.
6. Al terminar, actualiza `estado_dispositivo` (`usuario_id`, `ultima_sincronizacion`).

- Registros: un renglón por operación con `X-Request-Id`, `idOperacion`, `tipo`, resultado y `status`; nunca el contenido de `datos`.

## App de obra

### Paquetes

`npx expo install expo-sqlite @react-native-community/netinfo` (además de los de 001 y 004: `expo-secure-store`, `expo-crypto`).

### Identificador del celular

`idDispositivo`: UUID generado con `expo-crypto` la primera vez que se abre la app y guardado en `expo-secure-store`. Va en `X-Dispositivo-Id`.

### Base local (`expo-sqlite`)

Migraciones con `PRAGMA user_version`.

```sql
CREATE TABLE operacion_pendiente (
  id_operacion        TEXT PRIMARY KEY,   -- UUID (expo-crypto randomUUID)
  usuario_id          TEXT NOT NULL,      -- sub del usuario que registró
  tipo                TEXT NOT NULL,      -- MOVIMIENTO_MATERIAL, …
  obra_id             TEXT NOT NULL,
  datos               TEXT NOT NULL,      -- JSON que va en la operación
  descripcion         TEXT NOT NULL,      -- texto corto para «Pendientes de envío»
  estado              TEXT NOT NULL,      -- PENDIENTE, ENVIANDO, ENVIADO, RECHAZADO
  intentos            INTEGER NOT NULL DEFAULT 0,
  proximo_intento_en  TEXT,               -- ISO; nulo = enviar ya
  error_codigo        TEXT,
  error_mensaje       TEXT,
  respuesta           TEXT,               -- JSON de la respuesta del servicio dueño
  creada_en           TEXT NOT NULL,
  enviada_en          TEXT
);
CREATE INDEX operacion_pendiente_envio ON operacion_pendiente (usuario_id, estado, creada_en);

CREATE TABLE paquete_datos (
  usuario_id     TEXT PRIMARY KEY,
  version_datos  TEXT NOT NULL,
  contenido      TEXT NOT NULL,           -- JSON de GET /paquete-datos
  descargado_en  TEXT NOT NULL
);
```

### Módulo `src/sync/`

- `cola.ts`: `agregar(operacion)`, `listar(usuarioId)`, `contarPendientes(usuarioId)`, `descartar(idOperacion)`, `marcar…`. Al iniciar la app, las operaciones que quedaron en `ENVIANDO` (la app se cerró a mitad de un envío) vuelven a `PENDIENTE`: es seguro porque el servidor no las procesa dos veces.
- `paquete.ts`: descarga `GET /paquete-datos` con `If-None-Match` y lo guarda; con `304` solo actualiza `descargado_en`.
- `red.ts`: estado de la red con NetInfo (`isConnected` e `isInternetReachable`).
- `enviador.ts`: un solo envío a la vez (candado en memoria). Pasos:
  1. Obtiene un token vigente (renueva con el refresh token). Si no se puede renovar por falta de red, se detiene; si Keycloak rechaza el refresh token, se detiene y pide iniciar sesión.
  2. Toma hasta 20 operaciones `PENDIENTE` del usuario actual con `proximo_intento_en` vencido o nulo, ordenadas por `creada_en`; las marca `ENVIANDO`.
  3. `POST /lotes` con tiempo máximo de 30 s (`AbortController`).
  4. Por resultado: `PROCESADO` → `ENVIADO` (guarda `respuesta`; en un movimiento, actualiza el stock del paquete local con `respuesta.stock`); `ERROR` → `RECHAZADO` con `codigo` (el `detail` o `title` se guarda en `error_mensaje` solo para soporte); `REINTENTAR` → `PENDIENTE` con espera creciente (si el código es `TOKEN_VENCIDO`, renueva el token antes del siguiente lote).
  5. Si falla el lote completo (red, tiempo agotado, `5xx`) → todas vuelven a `PENDIENTE` con espera creciente.
  6. Repite mientras queden operaciones listas. Si envió al menos una, vuelve a pedir el paquete (con `If-None-Match`, cuesta poco).
- Espera creciente: `min(2^(intentos−1), 300)` segundos multiplicado por un factor aleatorio entre 0,8 y 1,2 (decisión del equipo; evita que todos los celulares reintenten a la vez).
- Disparadores del envío: después de `agregar`, cuando NetInfo pasa a conectado, cuando la app vuelve a primer plano (`AppState` → `active`), cada 60 s mientras la app está abierta y hay pendientes, y el botón «Enviar ahora».
- Limpieza: al abrir la app se borran las operaciones `ENVIADO` con `enviada_en` de hace más de 24 h.
- Reemplaza el reintento de la 004 (3 intentos de 1 s, 2 s y 4 s) por esta cola.

### Pantallas

- Formularios `obras/[id]/ingreso` y `obras/[id]/salida` (004): mismas validaciones (cantidad > 0 con hasta 3 decimales, partida obligatoria en la salida) con los datos del paquete local. Al pulsar «Registrar», `cola.agregar` y dispara el envío; espera hasta 5 s el resultado de esa operación: «Registrado» (con los avisos de la 004 según la respuesta), el motivo del rechazo, o «Guardado en el celular · se enviará cuando haya señal».
- `obras/[id]/stock`: stock del paquete más los movimientos `PENDIENTE` y `ENVIANDO` de esa obra (ingresos suman, salidas restan), con el estado recalculado con la regla de `reglas-negocio.md` y la nota «Incluye N movimientos sin enviar».
- `obras` (lista): sale del paquete local; encabezado «Sin señal · datos del dd/mm hh:mm» cuando NetInfo dice que no hay conexión.
- Nueva pestaña `pendientes` (roles `maestro` y `almacenero`) con contador; lista agrupada por estado; «Enviar ahora», «Descartar» (en `PENDIENTE` y `RECHAZADO`, con confirmación) y «Actualizar datos».
- Mensajes de rechazo: se muestran según `codigo` (por ejemplo `PERIODO_CERRADO` → «El periodo AAAA-MM ya está cerrado», como la 004); si el código no es conocido, el mensaje genérico de su estado HTTP (`docs/mensajes.md`); el `detail` del servicio no se muestra al usuario.

### Sesión sin señal

- Al iniciar sesión con éxito se guarda en `expo-secure-store` el `usuarioLocal` `{ id, nombre, roles }` (del token).
- Al abrir la app: si hay red, renueva el token como en la 001; si no hay red y existe `usuarioLocal`, entra en «modo sin señal» con ese usuario; si Keycloak rechaza la renovación, muestra el inicio de sesión (la cola no se toca).
- Cerrar sesión: si hay pendientes del usuario, muestra el aviso del criterio 18; borra tokens, `usuarioLocal` y `paquete_datos` de ese usuario; las operaciones quedan en la cola con su `usuario_id`.

## Obras y Materiales

Sin cambios de código: Sincronización usa los endpoints existentes (`GET /obras`, `GET /obras/{id}`, `GET /materiales`, `GET /obras/{id}/stock`, `POST /movimientos`) con el token del usuario. La idempotencia por `id` de `POST /movimientos` (004) sigue vigente.

## Infra

- Contenedor DynamoDB Local (imagen oficial `amazon/dynamodb-local` con versión fija), puerto `8000`, con `-sharedDb` y un volumen para no perder los datos al reiniciar.
- Variables de ejemplo de Sincronización en el `.env.example` de infra (si el compose levanta el servicio) y en el del propio servicio.

## Pruebas

- Sincronización (con DynamoDB Local y servicios dueños simulados con un servidor HTTP de prueba):
  - operación nueva: se guarda `PROCESADO` con la respuesta y `expira_en` = recibida + 30 días;
  - la misma operación dos veces (en lotes distintos): el servicio dueño se llama una sola vez y la segunda respuesta es igual, con `repetida: true`;
  - dos lotes simultáneos con el mismo `idOperacion`: el servicio dueño se llama una sola vez y el otro recibe `REINTENTAR` (`OPERACION_EN_PROCESO`);
  - rechazo `422` o `409` del dueño: se guarda `ERROR` y al repetir se devuelve sin llamar al dueño;
  - `503`, tiempo agotado y `401` del dueño: se borra el elemento, resultado `REINTENTAR`, y el siguiente intento sí llama al dueño;
  - `PROCESANDO` de hace más de 60 s se retoma; uno reciente no;
  - operación de otro usuario → `OPERACION_AJENA`;
  - lote vacío, con más de 20 o con ids repetidos → `400 LOTE_INVALIDO`; tipo desconocido → resultado `ERROR`;
  - presupuesto de 20 s agotado → las restantes vuelven `REINTENTAR` sin llamar al dueño;
  - paquete: `304` con la misma versión, versión distinta si cambia el stock, `503` si un servicio falla, stock vacío ante `404`, `estado_dispositivo` actualizado;
  - sin token (401), con rol `cliente` o `residente` (403), sin `X-Dispositivo-Id` (400).
- App: cola (orden, filtro por usuario, `ENVIANDO` → `PENDIENTE` al iniciar, limpieza a las 24 h), cálculo de la espera creciente, enviador con `fetch` simulado (`PROCESADO`, `ERROR`, `REINTENTAR`, fallo del lote, `TOKEN_VENCIDO`), stock local con pendientes.
- Manual (lo hace el equipo): con el celular en modo avión registrar tres movimientos, cerrar y abrir la app, quitar el modo avión y comprobar que llegan una sola vez a Materiales; cortar la red a mitad de un lote y comprobar que no se duplica nada.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/contratos/rest.md`

Nueva sección **«Sincronización (puerto 8084)»** con `GET /salud`, `GET /paquete-datos` y `POST /lotes`, tal como están arriba (encabezados `X-Dispositivo-Id` e `If-None-Match`, tabla de tipos de operación, estados `PROCESADO` / `ERROR` / `REINTENTAR`, códigos `DISPOSITIVO_REQUERIDO`, `LOTE_INVALIDO`, `TIPO_OPERACION_DESCONOCIDO`, `OPERACION_INVALIDA`, `OPERACION_AJENA`, `OPERACION_EN_PROCESO`, `TOKEN_VENCIDO`, `TIEMPO_AGOTADO`, `SERVICIO_NO_DISPONIBLE`).

En Materiales, `POST /movimientos`, `GET /materiales` y `GET /obras/{obraId}/stock`: agregar «Quién llama: Sincronización (capa 1), con el token del usuario». En Obras, `GET /obras` y `GET /obras/{id}`: ídem.

### `docs/contratos/eventos.md`

Sin cambios (Sincronización no publica ni escucha eventos).

### `docs/convenciones.md`

- «Puertos en desarrollo»: agregar **DynamoDB Local · 8000**.
- «Idempotencia»: agregar «En la capa 1, la primera barrera es Sincronización: guarda cada `idOperacion` en DynamoDB (`operacion_procesada`, «guardar solo si no existe», TTL de 30 días) y devuelve la respuesta guardada si se repite. Los servicios dueños mantienen su propia idempotencia por `id`».
- «Registros y salud»: agregar el encabezado `X-Dispositivo-Id` (UUID del celular) en las llamadas de la app a Sincronización.

### `docs/arquitectura.md`

- Tabla «Conexiones», fila App → Sincronización: quitar «en el sistema base, la app llama directo…» cuando la 101 esté hecha; agregar App → Sincronización `GET /paquete-datos` («datos para trabajar sin señal»).

### `services/sincronizacion/docs/` (se crean con el proyecto)

- `datos.md`: tablas `operacion_procesada` y `estado_dispositivo` como arriba (y `subida_archivo` de la 102).
- `contratos.md`: los tres endpoints de arriba; consume Obras (`GET /obras`, `GET /obras/{id}`) y Materiales (`GET /materiales`, `GET /obras/{id}/stock`, `POST /movimientos`).
- `servicio.md`: responsabilidades (recibir lotes sin duplicar, repartirlos por REST al servicio dueño, armar el paquete de datos del celular) y qué no hace (no guarda datos del negocio, no publica eventos, no valida reglas del negocio).

### `mobile/app-obra/docs/`

- `contratos.md`: consume Sincronización `GET /paquete-datos` y `POST /lotes`; deja de llamar directo a `POST /movimientos` de Materiales y a `GET /obras`, `GET /obras/{id}`, `GET /materiales`, `GET /obras/{id}/stock`.
- `app.md`: la pantalla «Pendientes de envío» queda descrita (contador, estados, «Enviar ahora», «Descartar»).

### `docs/plan.md`

Agregar la fila de la funcionalidad 101 en la fase de la capa 1 (proyectos: sincronizacion, app-obra, infra).
