# 102 · Diseño

Simplificado en la evaluación de la capa 1 (30/10/2026): la foto se comprime a unos 300 KB y se sube completa y directo a S3 con la URL firmada de Obras, igual que en la 005. Ya no hay subida por partes a través de Sincronización (ni tabla `subida_archivo` ni prefijo `temporal/`), ni foto de la nota de remisión.

## Flujo

```
App: toma la foto → comprime (1280 px por lado, compress 0,7)
     → guarda el archivo en documentDirectory/pendientes/{fotoId}.jpg
     → cola: FOTO_AVANCE { id: fotoId, obraId, partidaId, tomadaEn } con archivo local (estado_archivo PENDIENTE)

(con señal, después de los livianos; un archivo a la vez)
App --POST /fotos/url-subida { obraId, fotoId }--> Sincronización
    --POST /obras/{obraId}/fotos/url-subida { fotoId }--> Obras (token del usuario) → { url, claveArchivo, expiraEn }
App --PUT archivo (image/jpeg, 30 s)--> S3 (fotos/{obraId}/{fotoId}.jpg)
App: datos.claveArchivo = claveArchivo; estado_archivo SUBIDO → la operación pasa a liviana lista
App --POST /lotes [FOTO_AVANCE]--> Sincronización --POST /obras/{obraId}/fotos--> Obras → 201 (200 si ya existía)
App: borra el archivo local
```

- Repetir el `PUT` sobrescribe el mismo objeto (misma clave): es idempotente.
- La URL firmada vence (10 minutos): se pide una nueva en cada intento de subida.
- Se respeta la convención de archivos: el servicio dueño entrega la URL firmada y guarda solo la clave; el archivo no pasa por nuestros servidores.

## Sincronización

### POST /fotos/url-subida · 102

Servicio: Sincronización · Quién llama: App · Roles: `maestro` (los mismos que `POST /obras/{obraId}/fotos/url-subida` de Obras).

Recibe `{ "obraId": "uuid", "fotoId": "uuid" }`. Reenvía a Obras `POST /obras/{obraId}/fotos/url-subida { fotoId }` con el token del usuario (tiempo máximo 5 s) y devuelve su respuesta tal cual (`{ url, claveArchivo, expiraEn }`).

- `400`, `403`, `404` o `422` de Obras → mismo `status` y `codigo`.
- `5xx` de Obras → `503 SERVICIO_NO_DISPONIBLE`; tiempo agotado → `504 TIEMPO_AGOTADO`.
- Sin estado: no guarda nada en DynamoDB.

### Nuevo tipo en `POST /lotes`

| `tipo` | `datos` | Llamada |
|---|---|---|
| `FOTO_AVANCE` | `{ id, obraId, partidaId, claveArchivo, tomadaEn }` | Obras `POST /obras/{obraId}/fotos` con `{ id, partidaId, claveArchivo, tomadaEn }` |

`idOperacion` = `datos.id` (el `fotoId`). La 301 agrega después el campo opcional `deteccion`.

## Obras

Sin cambios de código: Sincronización usa `POST /obras/{obraId}/fotos/url-subida` y `POST /obras/{obraId}/fotos` de la 005 con el token del usuario.

## App de obra

### Paquetes

`npx expo install expo-file-system` (además de `expo-image-picker` y `expo-image-manipulator` de la 005).

### Cambios en la base local

```sql
ALTER TABLE operacion_pendiente ADD COLUMN archivo_local TEXT;                              -- ruta en documentDirectory/pendientes/
ALTER TABLE operacion_pendiente ADD COLUMN estado_archivo TEXT NOT NULL DEFAULT 'NINGUNO';  -- NINGUNO, PENDIENTE, SUBIENDO, SUBIDO
```

- Una operación es **liviana lista** si `estado_archivo` es `NINGUNO` o `SUBIDO`.
- Al iniciar la app, una operación que quedó en `SUBIENDO` vuelve a `PENDIENTE` (subir otra vez es seguro).

### Captura

- Pantalla `obras/[id]/foto` (005): comprime a 1280 px por lado (`compress: 0.7`), copia a `documentDirectory/pendientes/{fotoId}.jpg` con `expo-file-system` y agrega la operación a la cola. Ya no sube en el momento.
- Aviso del criterio 3 si hay más de 100 fotos sin enviar.

### Subidor (`src/sync/subidor.ts`)

Lo llama el enviador de la 101 cuando ya no quedan operaciones livianas listas:

1. Toma la operación más antigua con `estado_archivo` `PENDIENTE`; la marca `SUBIENDO`.
2. `POST /fotos/url-subida` (tiempo máximo 10 s).
3. `PUT` del archivo a la URL con `Content-Type: image/jpeg` (tiempo máximo 30 s).
4. Resultado:
   - `PUT` correcto → guarda `claveArchivo` en `datos`, `estado_archivo = SUBIDO`.
   - `400`, `403`, `404` o `422` al pedir la URL → `RECHAZADO` con el motivo.
   - Red, tiempo agotado, `503`, `504` o fallo del `PUT` → `estado_archivo = PENDIENTE` con la espera creciente de la 101, y detiene el subidor hasta el próximo envío.
5. Después de cada archivo, el enviador vuelve a mandar primero las operaciones livianas listas (así un movimiento nuevo no espera detrás de varias fotos).

- Un solo archivo a la vez.
- El archivo local se borra cuando la operación queda `ENVIADO` o cuando el usuario la descarta.

### Pantalla «Pendientes de envío»

- Las fotos muestran miniatura (del archivo local), partida y estado; durante la subida, «Subiendo foto…».

## Pruebas

- Sincronización (servicios dueños simulados): `POST /fotos/url-subida` reenvía con el token y devuelve la URL; `403`/`404`/`422` de Obras se devuelven igual; `5xx` → `503`; tiempo agotado → `504`; `FOTO_AVANCE` en un lote llega a Obras con `claveArchivo`, y repetido no llama dos veces al dueño.
- App: compresión a 1280 px, orden livianos antes que archivos, `SUBIENDO` → `PENDIENTE` al iniciar, URL nueva en cada intento, rechazo por `404`, reintento por red, borrado del archivo solo al confirmar, aviso de más de 100 fotos.
- Manual (lo hace el equipo; necesita el bucket S3): con el celular en modo avión tomar dos fotos y registrar un movimiento; al volver la señal, el movimiento llega primero y las fotos aparecen una sola vez en el detalle de la obra del ERP; con la red limitada del emulador, cortar la red durante una subida y comprobar que al volver se sube completa sin duplicar el registro.

## Cambios a contratos y datos

Para integrar en los documentos compartidos.

### `docs/contratos/rest.md`

- Sección «Sincronización»: agregar `POST /fotos/url-subida` como arriba y el tipo `FOTO_AVANCE` en la tabla de `POST /lotes`.
- Obras: en `POST /obras/{obraId}/fotos/url-subida` y `POST /obras/{obraId}/fotos`, «Quién llama: Sincronización (capa 1), con el token del usuario».

### `docs/convenciones.md`

«Archivos»: agregar «En la capa 1 la app guarda la foto comprimida (1280 px, calidad 70) en el celular y la sube completa con la URL firmada que pide a Sincronización (que la obtiene del servicio dueño); si falla, la vuelve a subir completa».

### `services/sincronizacion/docs/contratos.md`

`POST /fotos/url-subida`; consume Obras `POST /obras/{obraId}/fotos/url-subida` y `POST /obras/{obraId}/fotos`.

### `mobile/app-obra/docs/`

- `contratos.md`: pide la URL de subida a Sincronización; deja de llamar a Obras para fotos (el `PUT` a S3 sigue siendo directo).

### `docs/plan.md`

Fila de la funcionalidad 102 (sincronizacion, app-obra).
