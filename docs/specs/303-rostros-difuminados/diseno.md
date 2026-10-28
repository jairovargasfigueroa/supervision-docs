# 303 · Diseño

## Flujo

```
Residente pulsa «Presentar» (mf-obras)
  → por cada foto adjunta sin versión para el cliente:
      fetch(urlDescarga original) → Blob → createImageBitmap
      → detectar rostros (MediaPipe FaceDetector, imagen completa + mosaicos) → cajas
      → canvas: dibujar la foto, difuminar cada caja (+ margen 30 %)
  → vista previa (marcar zonas a mano, quitar fotos) → «Confirmar y presentar»
  → por cada foto: mutation prepararSubidaFotoCliente(obraId, fotoId) → { url, claveArchivoCliente }
      → canvas.toBlob("image/jpeg", 0.8) → PUT url (RustFS/S3)
      → mutation registrarFotoCliente(obraId, fotoId, claveArchivoCliente, rostrosDifuminados)
  → mutation presentarPlanilla(id, version) (007)
Portal → GET /obras/{id}/fotos (cliente) → urlDescarga firmada de clave_archivo_cliente
```

## Detección en el navegador (mf-obras)

- Librería (decisión del equipo): `@mediapipe/tasks-vision` 1 (MediaPipe Tasks, mantenida por Google), tarea `FaceDetector` con el modelo `blaze_face_short_range.tflite` (float16). URL verificada el 28/10/2026: `https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/blaze_face_short_range.tflite`.
- Los archivos WASM de MediaPipe y el modelo se sirven desde `public/modelos/mediapipe/` del propio microfrontend (se copian una vez en la primera tarea), para no depender de un CDN externo al presentar.
- Carga diferida: el módulo de detección se importa con `import()` solo al pulsar «Presentar».
- **Mosaicos** (decisión del equipo): el modelo *short range* está pensado para rostros grandes; en fotos de obra los rostros son pequeños. Por eso se detecta sobre la imagen completa y además sobre una cuadrícula de mosaicos de 512 px con 25 % de solape. Las cajas se pasan a coordenadas de la foto y se unen con supresión de no máximos (IoU 0,3).
- Confianza mínima 0,40 (se prefiere difuminar de más).
- Alternativa documentada: `@tensorflow-models/face-detection` con el modelo *full range* (TF.js). No se elige porque su última versión es de 2024 y depende de TF.js 4.
- Difuminado: sobre la región de cada caja ampliada 30 %, se aplica un pixelado fuerte (la región se reduce a 8 bloques de ancho y se vuelve a ampliar con `imageSmoothingEnabled = false`) y encima `ctx.filter = "blur(8px)"` cuando el navegador lo soporta. Las zonas marcadas a mano se tratan igual.
- La imagen resultante se exporta con `canvas.toBlob("image/jpeg", 0.8)`: el canvas no copia los metadatos EXIF (criterio 6). Tamaño igual al original (máximo 1600 px, 005).
- `rostrosDifuminados` = rostros detectados + zonas marcadas a mano.

## mf-obras

- Carpeta `src/app/planillas/fotos-cliente/`:
  - `detector-rostros.ts`: carga de MediaPipe, detección con mosaicos y unión de cajas (funciones puras probadas aparte: cálculo de mosaicos, paso de coordenadas, NMS).
  - `difuminar.ts`: difuminado sobre un canvas.
  - `preparar-fotos-cliente.service.ts`: orquesta descarga, detección, difuminado, subida y registro; reintento por foto.
  - `vista-previa-fotos-cliente.component.ts`: diálogo con las versiones, contador de rostros, herramienta de rectángulo, «Volver a preparar», «Quitar de la planilla» (guarda la planilla sin esa foto con `guardarPlanilla`) y «Confirmar y presentar».
- La descarga del original usa `fetch` sobre `urlDescarga` (URL firmada, 30 min); necesita CORS en RustFS/S3 (ver infra). Si la URL venció, se vuelve a pedir la lista de fotos.

## Obras

- Migración: `foto_avance` agrega `rostros_difuminados int null` y `version_cliente_en timestamptz null`. `clave_archivo_cliente` ya existe.
- `POST /obras/{obraId}/fotos/{fotoId}/url-subida-cliente` (rol `residente` asignado): devuelve `{ "url": "https://…", "claveArchivoCliente": "fotos-cliente/{obraId}/{fotoId}.jpg", "expiraEn": "…" }` (PUT firmado, 10 min). Errores: `404 FOTO_NO_ENCONTRADA` (también si la foto no es de esa obra).
- `PUT /obras/{obraId}/fotos/{fotoId}/version-cliente` (rol `residente` asignado): recibe `{ "claveArchivoCliente": "fotos-cliente/…jpg", "rostrosDifuminados": 2 }`; valida que la clave sea exactamente `fotos-cliente/{obraId}/{fotoId}.jpg` (`422 CLAVE_ARCHIVO_INVALIDA`), que el archivo exista en el almacenamiento (`HeadObject`; si no, `422 ARCHIVO_NO_SUBIDO`) y `rostrosDifuminados ≥ 0` (`400`). Guarda los campos y `version_cliente_en = ahora`. Devuelve `200` con la foto. Repetirlo sobrescribe la versión (es la forma de «Volver a preparar»).
- `POST /planillas/{id}/presentar` (007): si alguna foto adjunta no tiene `clave_archivo_cliente`, responde `422 FOTO_SIN_VERSION_CLIENTE` con `errores[]` (`campo` = `fotoId`, `mensaje` = «Falta la versión para el cliente»). La regla vive en el dominio (`Planilla.presentar(fotos)`).
- `GET /obras/{obraId}/fotos`:
  - Rol `cliente`: `urlDescarga` firmada sobre `clave_archivo_cliente`. Las fotos publicadas **antes** de la capa 3 que no tienen versión para el cliente se siguen mostrando con el original (decisión del equipo, para no dejar planillas aprobadas sin respaldo); toda presentación nueva exige la versión.
  - Roles internos: además de `urlDescarga` (original), agrega `urlDescargaCliente` (firmada, u `null`) y `rostrosDifuminados` (u `null`).

## Gateway

```graphql
type SubidaFotoCliente { url: String! claveArchivoCliente: String! expiraEn: String! }
extend type Foto { urlDescargaCliente: String  rostrosDifuminados: Int }
extend type Mutation {
  prepararSubidaFotoCliente(obraId: ID!, fotoId: ID!): SubidaFotoCliente!                    # 303 · residente
  registrarFotoCliente(obraId: ID!, fotoId: ID!, claveArchivoCliente: String!, rostrosDifuminados: Int!): Foto!  # 303 · residente
}
```

- `presentarPlanilla` ya existe; mapea el nuevo `codigo` `FOTO_SIN_VERSION_CLIENTE` y sus `errores` en `extensions`.

## Portal

- Sin cambios en las llamadas: sigue usando `urlDescarga` de `GET /obras/{obraId}/fotos`, que ahora apunta a la versión para el cliente.
- Agrega la nota del criterio 11 bajo la galería de la obra y de la planilla.

## Infra

- RustFS: permitir CORS para `GET` y `PUT` desde `http://localhost:4200` y `http://localhost:4201` (se configura en la regla CORS del bucket que aplica `almacen-init` con `PutBucketCors`; hay que dejarlo explícito en el `docker-compose.yml`). En S3 (capa 6) se configura la regla CORS del bucket.

## Métricas mínimas (decisión del equipo)

- Conjunto de prueba: 30 fotos de obra (propias del equipo con permiso o de un banco de imágenes con licencia libre) con los rostros visibles marcados a mano.
- Detección automática: sensibilidad (*recall*) de rostros ≥ 0,80 con confianza 0,40 y mosaicos; los que falten se cubren con la marca manual del criterio 4.
- Tiempo de preparación ≤ 3 s por foto de 1600 px en un equipo con 8 GB de RAM.
- El resultado se anota en la tarea correspondiente.

## Pruebas

- Obras: URL de subida con la clave esperada; registro con clave de otra foto (422), sin archivo subido (422), residente no asignado (`404 OBRA_NO_ENCONTRADA`), `gerente` (`403 SIN_PERMISO`); presentar con una foto sin versión (422 `FOTO_SIN_VERSION_CLIENTE`) y con todas (200); el cliente recibe la URL de la versión para el cliente y los internos ambas.
- mf-obras: funciones puras de mosaicos, coordenadas y NMS; servicio de preparación con detector y subida simulados (reintento, fallo de carga del modelo, foto ya preparada); el diálogo no permite confirmar si falta alguna versión.
- Gateway: nuevas mutaciones y mapeo del error.
- Portal: muestra la nota bajo la galería.

## Cambios a contratos y datos

### `services/obras/docs/datos.md` — tabla `foto_avance`

| Campo | Tipo | Notas |
|---|---|---|
| clave_archivo_cliente | varchar | versión con rostros difuminados (303); clave `fotos-cliente/{obraId}/{fotoId}.jpg` |
| rostros_difuminados | int | 303; rostros detectados + zonas marcadas a mano; null si no hay versión |
| version_cliente_en | timestamptz | 303; cuándo se registró la versión para el cliente |

### `docs/contratos/rest.md` y `services/obras/docs/contratos.md`

```
### POST /obras/{obraId}/fotos/{fotoId}/url-subida-cliente · 303
Roles: `residente` asignado. Sin cuerpo.
Devuelve `{ "url": "https://…", "claveArchivoCliente": "fotos-cliente/{obraId}/{fotoId}.jpg", "expiraEn": "…" }`.
Errores: `404 FOTO_NO_ENCONTRADA` · `403`.

### PUT /obras/{obraId}/fotos/{fotoId}/version-cliente · 303
Roles: `residente` asignado. Recibe `{ "claveArchivoCliente": "fotos-cliente/…jpg", "rostrosDifuminados": 2 }`.
Devuelve `200` con la foto (como un elemento de `GET /obras/{obraId}/fotos`).
Errores: `400` · `404 FOTO_NO_ENCONTRADA` · `422 CLAVE_ARCHIVO_INVALIDA` · `422 ARCHIVO_NO_SUBIDO` · `403`.
```

- `GET /obras/{obraId}/fotos · …, 303`: para `cliente`, `urlDescarga` apunta a la versión para el cliente (o al original si la foto se publicó antes de la capa 3 sin versión). Para roles internos agrega `urlDescargaCliente` y `rostrosDifuminados` (u `null`).
- `POST /planillas/{id}/presentar · 007, 303`: nuevo error `422 FOTO_SIN_VERSION_CLIENTE` (con `errores[]`, `campo` = `fotoId`).

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

```graphql
type SubidaFotoCliente { url: String! claveArchivoCliente: String! expiraEn: String! }
type Foto { … urlDescargaCliente: String  rostrosDifuminados: Int }        # 303
type Mutation {
  …
  prepararSubidaFotoCliente(obraId: ID!, fotoId: ID!): SubidaFotoCliente!   # 303 · residente
  registrarFotoCliente(obraId: ID!, fotoId: ID!, claveArchivoCliente: String!, rostrosDifuminados: Int!): Foto!  # 303 · residente
}
```

Consume (Obras): agregar `POST /obras/{id}/fotos/{fotoId}/url-subida-cliente` y `PUT /obras/{id}/fotos/{fotoId}/version-cliente`.

### `docs/reglas-negocio.md` — «Fotos de avance»

- Agregar: «Capa 3 (303): una planilla con fotos adjuntas solo se presenta si todas tienen versión con rostros difuminados. La versión la prepara el ERP en el navegador del residente, que puede marcar zonas adicionales a mano. Las fotos publicadas antes de la capa 3 sin esa versión se siguen mostrando con el original».

### `frontend/mf-obras/docs/contratos.md`

- Consume: mutaciones `prepararSubidaFotoCliente` y `registrarFotoCliente`; `Foto.urlDescargaCliente`; subida directa (PUT) a RustFS/S3 con URL firmada; archivos de MediaPipe servidos desde `public/modelos/mediapipe/`.

### `frontend/portal/docs/contratos.md`

- Sin operaciones nuevas; `urlDescarga` de las fotos ahora es la versión con rostros difuminados.

### Infra (`docker-compose.yml`)

- Regla CORS del bucket `supervision` explícita para los orígenes del ERP.

### Eventos

Ninguno.
