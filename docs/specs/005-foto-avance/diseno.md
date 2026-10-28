# 005 · Diseño

## Flujo

```
App: genera fotoId (UUID) → comprime
App --POST /obras/{obraId}/fotos/url-subida {fotoId}--> Obras --> URL firmada PUT (RustFS/S3, 10 min)
App --PUT archivo--> RustFS (bucket supervision, clave fotos/{obraId}/{fotoId}.jpg)
App --POST /obras/{obraId}/fotos {id, partidaId, claveArchivo, tomadaEn}--> Obras --> 201 (o 200 si ya existía)
```

## Obras

- Cliente S3 del AWS SDK v2 apuntando a RustFS en desarrollo (`OBRAS_S3_ENDPOINT`, `OBRAS_S3_ACCESS_KEY`, `OBRAS_S3_SECRET_KEY`, `OBRAS_S3_BUCKET=supervision`), con *path-style access*.
- `POST /obras/{obraId}/fotos/url-subida` (roles `maestro`, `residente`, asignados): devuelve `{ url, claveArchivo, expiraEn }`. La clave la arma el servicio: `fotos/{obraId}/{fotoId}.jpg`.
- `POST /obras/{obraId}/fotos`: valida que la partida sea de la obra y que la clave corresponda a `fotos/{obraId}/{id}.jpg`; si el `id` ya existe devuelve `200` con el registro. Guarda `registrado_en = tomadaEn` y `registrado_por = sub`.
- `GET /obras/{obraId}/fotos?partidaId=`: lista con `urlDescarga` firmada (GET, 30 min). El cliente solo recibe las que tienen `publicada_cliente = true`.
- Errores: `404 OBRA_NO_ENCONTRADA`, `422 PARTIDA_NO_ES_DE_LA_OBRA`, `422 CLAVE_ARCHIVO_INVALIDA`, `403`.

## App

- Pantalla `obras/[id]/foto` (rol `maestro`): selector de partida, `expo-image-picker` (cámara o galería), compresión con `expo-image-manipulator` (ancho o alto máximo 1600, `compress: 0.8`, JPEG), vista previa, botón «Enviar».
- Subida con `fetch(url, { method: 'PUT', body: blob, headers: { 'Content-Type': 'image/jpeg' } })`.
- Conserva el `fotoId` y el archivo comprimido en memoria hasta confirmar el registro (criterio 5).

## Gateway y mf-obras

- `Obra.fotos(partidaId: ID): [Foto!]!` resuelto con `GET /obras/{id}/fotos`.
- En el detalle de obra (006) se muestra una galería por partida. Si la 006 no está hecha, esta parte se hace junto con la 006.

## Pruebas

- Obras: URL firmada con la clave esperada, registro idempotente, partida de otra obra (422), maestro no asignado (`404 OBRA_NO_ENCONTRADA`), `almacenero` asignado (`403 SIN_PERMISO`), cliente solo ve publicadas.
- App: compresión invocada con los parámetros correctos; reintento conserva el mismo `fotoId`.
