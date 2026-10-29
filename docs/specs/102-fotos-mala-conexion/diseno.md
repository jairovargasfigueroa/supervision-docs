# 102 · Diseño

## Flujos

### Foto de avance

```
App: toma la foto → comprime (1600 px, 0,8; si pasa de 1 MB: 1280 px, 0,7)
     → guarda el archivo en documentDirectory/pendientes/{fotoId}.jpg
     → cola: FOTO_AVANCE { id: fotoId, obraId, partidaId, tomadaEn } con archivo local (estado_archivo PENDIENTE)

(con señal, después de los livianos)
App --POST /subidas { idSubida: fotoId, tipoArchivo: FOTO_AVANCE, obraId, idRegistro: fotoId, tamanoBytes, sha256 }--> Sincronización
    → 201 { tamanoParte: 262144, totalPartes, partesRecibidas: [] }
App --PUT /subidas/{fotoId}/partes/{n} (application/octet-stream)--> Sincronización → S3 temporal/subidas/{fotoId}/{n} → 204
App --POST /subidas/{fotoId}/completar--> Sincronización
    arma el archivo, verifica SHA-256
    --POST /obras/{obraId}/fotos/url-subida { fotoId }--> Obras (token del usuario) → URL firmada
    --PUT archivo--> S3 (fotos/{obraId}/{fotoId}.jpg)
    borra temporal/subidas/{fotoId}/*
    → 200 { claveArchivo }
App: datos.claveArchivo = claveArchivo; estado_archivo SUBIDO → la operación pasa a liviana lista
App --POST /lotes [FOTO_AVANCE]--> Sincronización --POST /obras/{obraId}/fotos--> Obras → 201
App: borra el archivo local
```

### Foto de la nota de remisión

```
App (ingreso con foto de nota): cola
   MOVIMIENTO_MATERIAL { id: movimientoId, tipo: INGRESO, notaRemision: { numero } }
   FOTO_NOTA_REMISION  { idOperacion: uuid nuevo, movimientoId, obraId }  con archivo local, depende_de = movimientoId
1) lote: MOVIMIENTO_MATERIAL → Materiales POST /movimientos (stock al día)
2) subida tipoArchivo NOTA_REMISION, idSubida = idOperacion de FOTO_NOTA_REMISION, idRegistro = movimientoId
   completar → Materiales POST /obras/{obraId}/notas-remision/url-subida { movimientoId }
             → PUT a notas-remision/{obraId}/{movimientoId}.jpg
3) lote: FOTO_NOTA_REMISION { movimientoId, claveFoto } → Materiales PUT /movimientos/{movimientoId}/nota-remision/foto
```

Se respeta la convención de archivos: el servicio dueño entrega la URL firmada y guarda solo la clave. Lo nuevo es que el archivo llega por partes a Sincronización y es Sincronización quien hace el `PUT` final, porque S3 no permite partes menores a 5 MB en sus subidas multiparte y una foto comprimida pesa mucho menos.

## Sincronización

### Tabla `subida_archivo` (DynamoDB, decisión del equipo) · clave de partición `id_subida` · TTL sobre `expira_en`

| Atributo | Tipo | Notas |
|---|---|---|
| id_subida | S | UUID: el `idOperacion` de la operación que usará el archivo (`fotoId` o el de `FOTO_NOTA_REMISION`); si el servidor respondió `SUBIDA_DISTINTA`, la app usa uno nuevo |
| usuario_id | S | `sub` del token |
| id_dispositivo | S | |
| tipo_archivo | S | `FOTO_AVANCE`, `NOTA_REMISION` |
| obra_id | S | |
| id_registro | S | `fotoId` o `movimientoId` |
| tamano_bytes | N | 1 a 5 242 880 (5 MB) |
| total_partes | N | `ceil(tamano_bytes / 262144)` |
| partes_recibidas | NS | números de parte recibidos (desde 0) |
| sha256 | S | huella en hexadecimal enviada por la app |
| estado | S | `RECIBIENDO`, `COMPLETADA` |
| clave_archivo | S | clave final, al completar |
| creada_en | S | ISO 8601 UTC |
| expira_en | N | *epoch* = `creada_en` + 7 días |

### Almacenamiento

- Cliente S3 (`@aws-sdk/client-s3`) con *path-style access*: `SINC_S3_ENDPOINT`, `SINC_S3_ACCESS_KEY`, `SINC_S3_SECRET_KEY`, `SINC_S3_BUCKET=supervision`.
- Solo escribe, lee y borra en el prefijo `temporal/subidas/`. En producción su rol de IAM solo permite ese prefijo (602); en desarrollo usa el usuario IAM de desarrollo.
- La URL firmada que devuelven Obras y Materiales usa el *endpoint* configurado en esos servicios; Sincronización debe poder llegar a ese host (en Docker Compose, el mismo nombre de red).

### POST /subidas · 102

Servicio: Sincronización · Quién llama: App · Roles: `maestro`, `almacenero`

```json
{
  "idSubida": "uuid", "tipoArchivo": "FOTO_AVANCE", "obraId": "uuid", "idRegistro": "uuid",
  "tamanoBytes": 612345, "sha256": "64 caracteres hexadecimales"
}
```

Devuelve `201` (nueva) o `200` (ya existía, mismos datos):

```json
{ "idSubida": "uuid", "estado": "RECIBIENDO", "tamanoParte": 262144, "totalPartes": 3, "partesRecibidas": [0], "claveArchivo": null }
```

- Creación con *conditional put* (`attribute_not_exists(id_subida)`).
- Errores: `400 SUBIDA_INVALIDA` (tipo desconocido, tamaño fuera de rango, huella mal formada) · `403 SUBIDA_AJENA` (existe con otro usuario) · `409 SUBIDA_DISTINTA` (existe con otro tamaño o huella).

### GET /subidas/{idSubida} · 102

Roles: los mismos. Devuelve el mismo objeto. Errores: `404 SUBIDA_NO_ENCONTRADA` · `403 SUBIDA_AJENA`.

### PUT /subidas/{idSubida}/partes/{n} · 102

Roles: los mismos. Cuerpo binario `application/octet-stream` (límite 300 KB en esta ruta).

- `n` va de `0` a `totalPartes − 1`. Cada parte mide `tamanoParte`, salvo la última (`tamanoBytes − n × tamanoParte`).
- Guarda el objeto `temporal/subidas/{idSubida}/{n}` y luego `UpdateItem ADD partes_recibidas :n`. Repetir una parte la sobrescribe (idempotente).
- Devuelve `204`. Si la subida ya está `COMPLETADA`, también `204` sin hacer nada.
- Errores: `400 PARTE_INVALIDA` (número fuera de rango o tamaño incorrecto) · `404 SUBIDA_NO_ENCONTRADA` · `403 SUBIDA_AJENA`.

### POST /subidas/{idSubida}/completar · 102

Roles: los mismos. Sin cuerpo.

1. Si está `COMPLETADA` → `200` con `claveArchivo` (no vuelve a llamar al dueño).
2. Si faltan partes → `409 SUBIDA_INCOMPLETA` con `partesFaltantes: [n…]` en el cuerpo.
3. Lee las partes en orden; si falta algún objeto (lo borró la expiración) → reinicia `partes_recibidas` y responde `409 SUBIDA_REINICIADA`.
4. Concatena y calcula SHA-256; si no coincide → borra las partes, reinicia `partes_recibidas` y responde `422 HUELLA_NO_COINCIDE`.
5. Pide la URL firmada al servicio dueño con el token del usuario (tiempo máximo 5 s):
   - `FOTO_AVANCE` → Obras `POST /obras/{obraId}/fotos/url-subida { fotoId: idRegistro }`.
   - `NOTA_REMISION` → Materiales `POST /obras/{obraId}/notas-remision/url-subida { movimientoId: idRegistro }`.
   - `403`, `404` o `422` del dueño → se devuelve el mismo `status` y `codigo` (por ejemplo `404 OBRA_NO_ENCONTRADA`); la app rechaza la operación.
   - `5xx` → `503 SERVICIO_NO_DISPONIBLE`; tiempo agotado → `504 TIEMPO_AGOTADO`. En los dos casos las partes se conservan para reintentar.
6. `PUT` del archivo a la URL firmada con `Content-Type: image/jpeg` (tiempo máximo 15 s; si falla → `503 SERVICIO_NO_DISPONIBLE`, o `504 TIEMPO_AGOTADO` si se pasa del tiempo; partes conservadas).
7. Borra las partes, marca `COMPLETADA` con `clave_archivo` y devuelve `200 { "idSubida", "estado": "COMPLETADA", "claveArchivo": "fotos/{obraId}/{fotoId}.jpg" }`.

### Nuevos tipos en `POST /lotes`

| `tipo` | `datos` | Llamada |
|---|---|---|
| `FOTO_AVANCE` | `{ id, obraId, partidaId, claveArchivo, tomadaEn }` | Obras `POST /obras/{obraId}/fotos` con `{ id, partidaId, claveArchivo, tomadaEn }` |
| `FOTO_NOTA_REMISION` | `{ movimientoId, obraId, claveFoto }` | Materiales `PUT /movimientos/{movimientoId}/nota-remision/foto` con `{ claveFoto }` |

En `FOTO_AVANCE`, `idOperacion` = `datos.id`. En `FOTO_NOTA_REMISION`, `idOperacion` es un UUID propio (no crea un registro nuevo).

## Materiales

- Cliente S3 del AWS SDK v3 (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`) configurado por variables (en desarrollo, el bucket S3 de desarrollo): `MATERIALES_S3_ENDPOINT`, `MATERIALES_S3_ACCESS_KEY`, `MATERIALES_S3_SECRET_KEY`, `MATERIALES_S3_BUCKET=supervision`, *path-style access*.

### POST /obras/{obraId}/notas-remision/url-subida · 102

Roles: `almacenero` asignado. Quién llama: Sincronización (con el token del usuario).

Recibe `{ "movimientoId": "uuid" }`. Devuelve `{ "url": "https://…", "claveArchivo": "notas-remision/{obraId}/{movimientoId}.jpg", "expiraEn": "…" }` (URL `PUT` firmada por 10 minutos).

Errores: `404 OBRA_NO_ENCONTRADA` · `403`. No exige que el movimiento exista todavía.

### PUT /movimientos/{id}/nota-remision/foto · 102

Roles: `almacenero` asignado. Quién llama: Sincronización.

Recibe `{ "claveFoto": "notas-remision/{obraId}/{id}.jpg" }`. Devuelve `200` con el movimiento (mismo objeto que en `GET /obras/{obraId}/movimientos`).

- Guarda `nota_remision.clave_foto` (crea `nota_remision { numero: null }` si no existía).
- Idempotente: con la misma clave devuelve `200` sin cambios.
- Se permite aunque el periodo esté cerrado: la foto no cambia cantidades (decisión del equipo).
- Errores: `404 MOVIMIENTO_NO_ENCONTRADO` (también si el usuario no puede ver la obra) · `422 MOVIMIENTO_NO_ES_INGRESO` · `422 CLAVE_ARCHIVO_INVALIDA` (la clave no es `notas-remision/{obraId del movimiento}/{id}.jpg`).

### GET /obras/{obraId}/movimientos (cambio)

Cada elemento agrega `"notaRemision": { "numero": "NR-00123", "urlFoto": "https://… | null" } | null`; `urlFoto` firmada (`GET`, 30 min).

## Obras

Sin cambios de código: Sincronización usa `POST /obras/{obraId}/fotos/url-subida` y `POST /obras/{obraId}/fotos` de la 005 con el token del usuario.

## App de obra

### Paquetes

`npx expo install expo-file-system` (además de `expo-image-picker` y `expo-image-manipulator` de la 005).

### Cambios en la base local

```sql
ALTER TABLE operacion_pendiente ADD COLUMN archivo_local TEXT;        -- ruta en documentDirectory/pendientes/
ALTER TABLE operacion_pendiente ADD COLUMN estado_archivo TEXT NOT NULL DEFAULT 'NINGUNO'; -- NINGUNO, PENDIENTE, SUBIENDO, SUBIDO
ALTER TABLE operacion_pendiente ADD COLUMN tamano_bytes INTEGER;
ALTER TABLE operacion_pendiente ADD COLUMN sha256 TEXT;
ALTER TABLE operacion_pendiente ADD COLUMN partes_subidas INTEGER NOT NULL DEFAULT 0;
ALTER TABLE operacion_pendiente ADD COLUMN total_partes INTEGER;
ALTER TABLE operacion_pendiente ADD COLUMN reinicios_subida INTEGER NOT NULL DEFAULT 0;
ALTER TABLE operacion_pendiente ADD COLUMN depende_de TEXT;           -- id_operacion que debe estar ENVIADO antes
ALTER TABLE operacion_pendiente ADD COLUMN id_subida TEXT;            -- nulo = id_operacion; cambia si el servidor responde SUBIDA_DISTINTA
```

- Una operación es **liviana lista** si `estado_archivo` es `NINGUNO` o `SUBIDO` y, si tiene `depende_de`, esa operación ya está `ENVIADO`. Si la dependencia queda `RECHAZADO`, esta también pasa a `RECHAZADO` con «El ingreso asociado fue rechazado».
- La huella SHA-256 y el tamaño se calculan una vez al guardar la foto (`expo-crypto` `digest` sobre los bytes del archivo).

### Captura

- Pantalla `obras/[id]/foto` (005): después de comprimir, si el archivo pasa de 1 MB se comprime otra vez (1280 px, `compress: 0.7`); se copia a `documentDirectory/pendientes/{fotoId}.jpg` con `expo-file-system` y se agrega a la cola. Ya no sube en el momento.
- Pantalla `obras/[id]/ingreso` (004): botón opcional «Foto de la nota»; si se toma, se agregan las dos operaciones (`MOVIMIENTO_MATERIAL` y `FOTO_NOTA_REMISION` con `depende_de`).

### Subidor (`src/sync/subidor.ts`)

Lo llama el enviador de la 101 cuando ya no quedan operaciones livianas listas:

1. Toma la operación más antigua con `estado_archivo` `PENDIENTE` o `SUBIENDO` (cuya dependencia, si tiene, ya esté `ENVIADO`).
2. `POST /subidas` (o `GET /subidas/{id}` si ya se creó) para saber qué partes tiene el servidor. Si responde `409 SUBIDA_DISTINTA` (ya existe una subida con ese id y otro tamaño o huella), descarta esa subida: genera un `idSubida` nuevo (UUID), lo guarda en `id_subida`, pone `partes_subidas = 0` y vuelve a empezar. El `fotoId` (o el `movimientoId`) y el `idRegistro` no cambian, así que la foto se registra una sola vez.
3. Sube cada parte que falta con `PUT` (tiempo máximo 20 s), leyendo solo ese tramo del archivo; actualiza `partes_subidas` para mostrar el progreso.
4. `POST /subidas/{id}/completar` (tiempo máximo 30 s):
   - `200` → guarda `claveArchivo` (o `claveFoto`) en `datos`, `estado_archivo = SUBIDO`.
   - `409 SUBIDA_INCOMPLETA` → sube las `partesFaltantes` y vuelve a completar.
   - `422 HUELLA_NO_COINCIDE` o `409 SUBIDA_REINICIADA` → `reinicios_subida + 1` y vuelve a empezar; al tercer reinicio por huella, `RECHAZADO` con «El archivo de la foto está dañado».
   - `403`, `404`, `422` del servicio dueño → `RECHAZADO` con el motivo.
   - Red, tiempo agotado, `503` o `504` → espera creciente (101) y detiene el subidor hasta el próximo envío.
5. Después de cada archivo, el enviador vuelve a mandar primero las operaciones livianas listas (así un movimiento nuevo no espera detrás de varias fotos).

- Un solo archivo a la vez.
- Lectura por tramos y cuerpo binario: verificar en la documentación de Expo SDK 58 (ver `AGENTS.md`) la forma soportada; por ejemplo, la API de archivos de `expo-file-system` para leer bytes desde una posición y `fetch` de `expo/fetch` para enviar un `Uint8Array`. Si no hubiera lectura por tramos, se lee el archivo completo (pesa menos de 1 MB) y se corta en memoria.
- El archivo local se borra cuando la operación que lo usa queda `ENVIADO` o cuando el usuario la descarta.

### Pantalla «Pendientes de envío»

- Las fotos muestran miniatura (del archivo local), partida y estado; durante la subida, «Subiendo foto · X de Y partes».

## Infra

- Desarrollo: el usuario IAM de desarrollo ya tiene acceso al bucket; en producción, el rol de Sincronización solo puede leer, escribir y borrar en `temporal/*` (602).
- Regla de ciclo de vida del bucket S3 que borra los objetos del prefijo `temporal/` a los 7 días (en desarrollo se crea en la consola de AWS junto con el bucket).

## Pruebas

- Sincronización (con DynamoDB Local y un doble de S3):
  - crear subida dos veces con los mismos datos → `200` con el mismo estado; con otra huella → `409 SUBIDA_DISTINTA`; de otro usuario → `403`;
  - parte fuera de rango o de tamaño incorrecto → `400`; repetir una parte no la cuenta dos veces;
  - completar con partes faltantes → `409` con la lista; con huella distinta → `422` y partes borradas; con un objeto temporal ausente → `409 SUBIDA_REINICIADA`;
  - completar dos veces → misma clave y el dueño se llama una sola vez;
  - dueño responde `403` → `403`; responde `503` → `503` y las partes siguen;
  - `FOTO_NOTA_REMISION` en un lote llega a Materiales con `claveFoto`.
- Materiales: clave de la URL firmada, `PUT` de la foto (no es ingreso → `422`, clave de otra obra → `422`, repetido → `200` sin cambios, periodo cerrado permitido), `urlFoto` en la lista de movimientos, almacenero no asignado (`404`), maestro asignado (`403 SIN_PERMISO`).
- App: orden livianos antes que archivos, espera de la dependencia, rechazo en cascada, reanudación desde `partesRecibidas`, recompresión cuando pasa de 1 MB, borrado del archivo solo al confirmar, progreso, `SUBIDA_DISTINTA` → nueva subida con otro `idSubida` y el mismo `fotoId`.
- Manual (lo hace el equipo): con la red limitada del emulador de Android, tomar dos fotos y registrar un ingreso; cortar la red a mitad de una foto y comprobar que al volver sigue desde la parte que faltaba y que la foto aparece una sola vez en el detalle de la obra del ERP.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/contratos/rest.md`

- Sección «Sincronización»: agregar `POST /subidas`, `GET /subidas/{idSubida}`, `PUT /subidas/{idSubida}/partes/{n}`, `POST /subidas/{idSubida}/completar` como arriba, con los códigos `SUBIDA_INVALIDA`, `SUBIDA_AJENA`, `SUBIDA_DISTINTA`, `SUBIDA_NO_ENCONTRADA`, `PARTE_INVALIDA`, `SUBIDA_INCOMPLETA`, `SUBIDA_REINICIADA`, `HUELLA_NO_COINCIDE`; y los tipos `FOTO_AVANCE` y `FOTO_NOTA_REMISION` en la tabla de `POST /lotes`.
- Materiales: agregar `POST /obras/{obraId}/notas-remision/url-subida` y `PUT /movimientos/{id}/nota-remision/foto` (códigos `MOVIMIENTO_NO_ENCONTRADO`, `MOVIMIENTO_NO_ES_INGRESO`, `CLAVE_ARCHIVO_INVALIDA`); en `GET /obras/{obraId}/movimientos`, el campo `notaRemision { numero, urlFoto }`.
- Obras: en `POST /obras/{obraId}/fotos/url-subida` y `POST /obras/{obraId}/fotos`, «Quién llama: Sincronización (capa 1), con el token del usuario».

### `docs/convenciones.md`

«Archivos»: agregar «En la capa 1 la app no sube directo al almacenamiento: sube el archivo por partes de 256 KB a Sincronización, que lo arma, verifica la huella SHA-256 y lo sube con la URL firmada del servicio dueño. Las partes van al prefijo `temporal/`, que expira a los 7 días. Si la foto comprimida pasa de 1 MB, se comprime otra vez a 1280 px y calidad 70. Claves: `fotos/{obraId}/{fotoId}.jpg` y `notas-remision/{obraId}/{movimientoId}.jpg`».

### `services/materiales/docs/datos.md`

Sin campos nuevos (`nota_remision.clave_foto` ya existe). Agregar en la nota del campo el formato de la clave `notas-remision/{obraId}/{movimientoId}.jpg`.

### `services/materiales/docs/contratos.md`

Los dos endpoints nuevos y el cambio en `GET /obras/{obraId}/movimientos`.

### `services/sincronizacion/docs/datos.md` y `contratos.md`

Tabla `subida_archivo`; los cuatro endpoints de subidas; consume Obras `POST /obras/{obraId}/fotos/url-subida`, `POST /obras/{obraId}/fotos` y Materiales `POST /obras/{obraId}/notas-remision/url-subida`, `PUT /movimientos/{id}/nota-remision/foto`.

### `mobile/app-obra/docs/`

- `contratos.md`: consume las subidas de Sincronización; deja de llamar a Obras para fotos.
- `app.md`: «Registrar ingreso de material» agrega la foto opcional de la nota de remisión.

### `docs/specs/004-movimientos-material/requisitos.md`

En «Fuera del alcance», la foto de la nota de remisión queda cubierta por la 102.

### `docs/plan.md`

Agregar la fila de la funcionalidad 102 (sincronizacion, materiales, app-obra, infra).
