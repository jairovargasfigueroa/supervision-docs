# Contratos REST

> Copia generada de los `docs/contratos.md` de cada proyecto. Si cambias algo, cámbialo en el proyecto y aquí.

Convenciones comunes (errores, token, idempotencia, paginación): `docs/convenciones.md`.

## Obras (puerto 8081)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### POST /obras · 002
Roles: `admin` (el `403` se comprueba antes que el formato del cuerpo). Montos, precios y porcentajes con hasta 2 decimales; cantidades con hasta 3. Los errores de validación traen `errores[]` por campo; se revisan en este orden: contrato, códigos de partida, insumos, presupuesto.
```json
{
  "nombre": "Edificio Las Palmas",
  "ubicacion": "Av. Banzer 4to anillo, Santa Cruz",
  "fechaInicio": "2026-11-01",
  "asignaciones": {
    "residenteId": "uuid-keycloak", "maestroId": "uuid-keycloak",
    "almaceneroId": "uuid-keycloak", "clienteId": "uuid-keycloak"
  },
  "contrato": { "monto": 1250000.00, "plazoDias": 300, "anticipoPct": 10, "retencionPct": 7, "firmadoEn": "2026-10-20" },
  "partidas": [
    {
      "codigo": "P-01", "nombre": "Losa de hormigón armado", "unidad": "m2",
      "cantidadContratada": 850, "precioUnitario": 420.50, "meses": "nov-dic",
      "insumos": [{ "materialId": "id-material", "cantidadPorUnidad": 1.1 }]
    }
  ]
}
```
Devuelve `201` con el detalle de la obra (como `GET /obras/{id}`), `estado: "SIN_CONTRATO"`.
Errores: `400` formato · `422 PRESUPUESTO_NO_COINCIDE` · `422 CODIGO_PARTIDA_REPETIDO` · `422 INSUMO_REPETIDO` · `422 CONTRATO_INVALIDO` · `403`.
Publica `ObraRegistrada`.

### GET /obras?estado=&busqueda= · 006, 009, 101
Roles: todos; filtra por visibilidad (convenciones). Quién llama: Sincronización (capa 1), con el token del usuario (`estado=EN_EJECUCION`, para el paquete de datos).
```json
[{
  "id": "uuid", "nombre": "Edificio Las Palmas", "ubicacion": "…", "estado": "EN_EJECUCION",
  "fechaInicio": "2026-11-01", "avancePct": 32.5, "plazoPct": 41.0, "enRiesgo": false,
  "ultimaPlanilla": { "periodo": "2027-02", "estado": "APROBADA" }
}]
```
`ultimaPlanilla` es `null` si no hay planillas.

### GET /obras/{id} · 002, 004, 006, 101
Roles: los que pueden ver la obra. Quién llama: Sincronización (capa 1), con el token del usuario (partidas del paquete de datos).
```json
{
  "id": "uuid", "nombre": "…", "ubicacion": "…", "estado": "EN_EJECUCION",
  "motivoRechazoContrato": null, "fechaInicio": "2026-11-01",
  "asignaciones": { "residenteId": "…", "maestroId": "…", "almaceneroId": "…", "clienteId": "…" },
  "contrato": { "contratoId": "uuid|null", "monto": 1250000.00, "plazoDias": 300, "anticipoPct": 10, "retencionPct": 7 },
  "avancePct": 32.5, "plazoPct": 41.0, "enRiesgo": false,
  "partidas": [{
    "id": "uuid", "codigo": "P-01", "nombre": "…", "unidad": "m2",
    "cantidadContratada": 850, "precioUnitario": 420.50, "meses": "nov-dic",
    "ejecutadaAcumulada": 300, "avancePct": 35.29,
    "insumos": [{ "materialId": "…", "cantidadPorUnidad": 1.1 }]
  }]
}
```
Errores: `404 OBRA_NO_ENCONTRADA` (también si el usuario no puede verla).

### GET /obras/{id}/material-previsto?periodo=AAAA-MM · 006
Roles: `admin`, `gerente` y `residente` asignado (si no ve la obra: `404 OBRA_NO_ENCONTRADA`).
`{ "periodo": "2027-02", "hayPlanilla": true, "items": [{ "partidaId": "…", "materialId": "…", "cantidadPrevista": 55.0 }] }`

### POST /obras/{obraId}/fotos/url-subida · 005, 102
Roles: `maestro`, `residente` asignados. Quién llama: Sincronización (capa 1), con el token del usuario. Recibe `{ "fotoId": "uuid" }`.
Devuelve `{ "url": "https://…", "claveArchivo": "fotos/{obraId}/{fotoId}.jpg", "expiraEn": "…" }`.

### POST /obras/{obraId}/fotos · 005, 102
Roles: `maestro`, `residente` asignados. Quién llama: Sincronización (capa 1), con el token del usuario (operación `FOTO_AVANCE`).
Recibe `{ "id": "uuid", "partidaId": "uuid", "claveArchivo": "fotos/…jpg", "tomadaEn": "2026-11-15T15:20:00Z" }`.
Devuelve `201` (o `200` si el `id` ya existía) `{ "id", "partidaId", "registradoPor", "registradoEn", "publicadaCliente": false }`.
Errores: `404 OBRA_NO_ENCONTRADA` · `422 PARTIDA_NO_ES_DE_LA_OBRA` · `422 CLAVE_ARCHIVO_INVALIDA`.

### GET /obras/{obraId}/fotos?partidaId=&desde=&hasta= · 005, 006, 007, 008
Roles: los que pueden ver la obra; `cliente` solo recibe publicadas. Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `registradoEn desc`. Cada elemento:
`[{ "id", "partidaId", "registradoPor", "registradoEn", "publicadaCliente", "urlDescarga" }]`

### POST /obras/{obraId}/diario · 103
Roles: `maestro` asignado. Quién llama: Sincronización (capa 1), con el token del maestro (la app no llama directo; operación `ENTRADA_DIARIO`).
Recibe `{ "id": "uuid generado en el celular", "fecha": "2026-11-15", "clima": "LLUVIA_LEVE", "texto": "Se vació la losa del 2do piso. Lluvia por la tarde, se cubrió con nylon." }`.
Devuelve `201` (o `200` si el `id` ya existía, aunque el cuerpo sea distinto) `{ "id", "obraId", "fecha", "clima", "texto", "registradoPor", "registradoEn" }`.
Errores: `400 DATOS_INVALIDOS` (`errores[]` con `clima` o `texto`) · `403 SIN_PERMISO` (ve la obra pero no como `maestro`, por ejemplo el residente asignado) · `404 OBRA_NO_ENCONTRADA` (no existe o no la ve, por ejemplo un maestro no asignado) · `409 DIARIO_DIA_YA_REGISTRADO` · `422 OBRA_NO_EN_EJECUCION` · `422 FECHA_DIARIO_INVALIDA` (futura en `America/La_Paz` o anterior a `fechaInicio`).
- `clima`: `SOLEADO`, `NUBLADO`, `LLUVIA_LEVE` o `LLUVIA_FUERTE`. `texto`: de 10 a 2000 caracteres sin contar los espacios de los extremos (se guarda sin ellos). `registradoPor` = `sub` del token; `registradoEn` = momento en que Obras la recibió.
- Una entrada por obra y día (único `obra_id`, `fecha`): si dos llegan a la vez con distinto `id`, la segunda recibe `409 DIARIO_DIA_YA_REGISTRADO`. Un `id` que ya existe en otra obra también responde `409 DIARIO_DIA_YA_REGISTRADO`.

### GET /obras/{obraId}/diario?desde=&hasta= · 103
Roles: `maestro` y `residente` asignados, `admin`, `gerente`. Quién llama: Sincronización (capa 1), con el token del usuario (`diario` del paquete de datos, solo para el `maestro`).
`[{ "id", "obraId", "fecha", "clima", "texto", "registradoPor", "registradoEn" }]`, de la fecha más reciente a la más antigua.
- `desde` y `hasta` (`AAAA-MM-DD`, incluidas). Sin ninguna: los últimos 30 días hasta hoy (La Paz); sin `hasta`: hoy; sin `desde`: `hasta` − 29 días.
- Errores: `400 DATOS_INVALIDOS` (fecha mal formada o `desde` posterior a `hasta`) · `400 RANGO_INVALIDO` (más de 366 días) · `404 OBRA_NO_ENCONTRADA` (no existe, no la ve o la ve solo como `cliente`) · `403 SIN_PERMISO` (la ve con otro papel, por ejemplo el almacenero asignado).

### POST /obras/{obraId}/planillas · 007
Roles: `residente` asignado. Recibe `{ "periodo": "2027-03" }`. Devuelve `201` con el detalle (`GET /planillas/{id}`).
Errores: `409 PLANILLA_ABIERTA_EXISTE` · `422 PERIODO_NO_POSTERIOR` (no es posterior al de la última planilla) · `422 PERIODO_FUTURO` (mes futuro) · `422 OBRA_NO_EN_EJECUCION`.

### GET /obras/{obraId}/planillas · 006, 007, 008
Roles: los que pueden ver la obra; `cliente` no recibe `BORRADOR`.
`[{ "id", "numero", "periodo", "estado", "neto", "cobroId", "cobroNumero" }]` (`cobroNumero`: número del cobro, `COB-AAAA-NNNN`, que Obras guarda al recibir `CobroEmitido`; `null` hasta que se aprueba)

### GET /planillas/{id} · 007, 008
Roles: los que pueden ver la obra. `404 PLANILLA_NO_ENCONTRADA` si no existe, es de una obra que no ve o, para el `cliente`, si es `BORRADOR`.
```json
{
  "id": "uuid", "obraId": "uuid", "numero": 3, "periodo": "2027-03", "estado": "BORRADOR", "version": 2,
  "lineas": [{
    "partidaId": "uuid", "codigo": "P-01", "nombre": "…", "unidad": "m2", "precioUnitario": 420.50,
    "cantidadContratada": 850, "acumuladoAnterior": 300, "cantidadPeriodo": 120,
    "acumuladoTotal": 420, "saldo": 430, "monto": 50460.00
  }],
  "subtotal": 50460.00, "descuentoAnticipo": 5046.00, "retencion": 3532.20, "neto": 41881.80,
  "anticipoPct": 10, "retencionPct": 7,
  "observacion": null, "cobroId": null, "cobroNumero": null, "fotoIds": ["uuid"]
}
```

### PUT /planillas/{id} · 007
Roles: `residente` asignado. Recibe `{ "version": 2, "lineas": [{ "partidaId": "uuid", "cantidadPeriodo": 120 }], "fotoIds": ["uuid"] }`.
Devuelve `200` con el detalle. Errores: `409 VERSION_DESACTUALIZADA` · `409 PLANILLA_NO_EDITABLE` · `422 SUPERA_CANTIDAD_CONTRATADA` (con `errores[]`, `campo` = `partidaId`) · `422 FOTO_FUERA_DEL_PERIODO`.

### POST /planillas/{id}/presentar · 007
Roles: `residente` asignado. Recibe `{ "version": 3 }`. Devuelve `200` con el detalle (`PRESENTADA`).
Errores: `409 VERSION_DESACTUALIZADA` · `409 PLANILLA_NO_EDITABLE` · `422 SUBTOTAL_CERO`.

### POST /planillas/{id}/aprobar · 008
Roles: `cliente` dueño de la obra. Sin cuerpo. Devuelve `202 { "estado": "APROBANDO" }`.
Errores: `409 PLANILLA_NO_PRESENTADA`.

### POST /planillas/{id}/observar · 008
Roles: `cliente` dueño de la obra. Recibe `{ "motivo": "texto de 10 a 500 caracteres" }`. Devuelve `200` con el detalle (`OBSERVADA`).
Errores: `409 PLANILLA_NO_PRESENTADA` · `422 MOTIVO_INVALIDO`.

## Materiales (puerto 8082)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### GET /materiales?busqueda=&soloActivos= · 002, 003, 006, 101
Roles: todos los internos (`admin`, `residente`, `gerente`, `maestro`, `almacenero`). Quién llama: Sincronización (capa 1), con el token del usuario (`soloActivos=true`, todas las páginas de a 100, para el paquete de datos). Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `codigo asc`. Cada elemento:
`[{ "id", "codigo": "CEM-IP30", "nombre": "Cemento IP-30", "tipo": "CEMENTO", "unidad": "bolsa", "unidadPlural": "bolsas", "precioReferencial": 62.00, "activo": true, "atributos": [{ "nombre": "peso", "valor": "50 kg" }] }]`

### POST /materiales · 003
Roles: `admin`. Recibe el material sin `id` (`activo` por defecto `true`). Devuelve `201` con el material.
Errores: `400` · `409 CODIGO_MATERIAL_REPETIDO`.

### PUT /materiales/{id} · 003
Roles: `admin`. Recibe el material completo (incluye `activo`). Devuelve `200`.
Errores: `404 MATERIAL_NO_ENCONTRADO` · `409 CODIGO_MATERIAL_REPETIDO`.

### GET /obras/{obraId}/stock · 003, 004, 101
Roles: internos que pueden ver la obra (`obra_acceso`). Quién llama: Sincronización (capa 1), con el token del usuario (paquete de datos; un `404` se toma como stock vacío).
`[{ "materialId", "codigo", "nombre", "unidad", "unidadPlural", "cantidad": 120.0, "minimo": 100.0, "estado": "JUSTO" }]`
Errores: `404 OBRA_NO_ENCONTRADA`.

### PUT /obras/{obraId}/stock/{materialId}/minimo · 003
Roles: `admin`. Recibe `{ "minimo": 100 }`. Devuelve `200` con la fila de stock.
Errores: `404 OBRA_NO_ENCONTRADA` · `404 MATERIAL_NO_ENCONTRADO` · `422 MATERIAL_INACTIVO`.

### POST /movimientos · 004, 101
Roles: `almacenero` asignado. Quién llama: Sincronización (capa 1), con el token del usuario (operación `MOVIMIENTO_MATERIAL`; desde la 101 la app no llama directo).
```json
{
  "id": "uuid generado en el celular", "obraId": "uuid", "materialId": "id",
  "tipo": "SALIDA", "cantidad": 12.5, "partidaId": "uuid",
  "notaRemision": { "numero": "NR-00123" }, "registradoEn": "2026-11-15T14:00:00Z"
}
```
`partidaId` obligatorio en `SALIDA`; `notaRemision` solo en `INGRESO` y opcional.
Devuelve `201` (o `200` si el `id` ya existía) `{ "id", "periodo": "2026-11", "superaStock": false, "stock": { "cantidad", "minimo", "estado" } }`.
Errores: `400` · `403` · `404 OBRA_NO_ENCONTRADA` · `422 MATERIAL_INACTIVO` · `409 PERIODO_CERRADO`.

### GET /obras/{obraId}/movimientos?periodo= · 004
Roles: internos que pueden ver la obra. Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `registradoEn desc`. Cada elemento: `[{ "id", "materialId", "tipo", "cantidad", "partidaId", "periodo", "superaStock", "cerrado", "registradoPor", "registradoEn" }]`

### GET /obras/{obraId}/consumos?periodo=AAAA-MM · 006
Roles: `admin`, `gerente` y `residente` asignado (si no ve la obra: `404 OBRA_NO_ENCONTRADA`). `[{ "partidaId", "materialId", "cantidad" }]` (suma de salidas).

### GET /stock/resumen?obraIds=a,b,c · 009
Roles: `admin`, `residente`, `gerente`. `[{ "obraId", "materialesBajos": 2 }]` (solo obras visibles).
`obraIds` obligatorio, de 1 a 100 ids separados por coma (sin ellos o con más de 100: `400 DATOS_INVALIDOS`). Una fila por obra visible, en el orden pedido; una obra visible sin stock devuelve `0`; las que el usuario no ve se omiten sin error. `materialesBajos` = materiales en estado `BAJO` (calculado al leer). El gateway pide en lotes de 100.

## Finanzas (puerto 8083)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### GET /contratos?obraId= · 006
Roles: `admin`, `gerente`.
`[{ "id", "obraId", "monto": 1250000.00, "plazoDias": 300, "anticipoPct": 10, "retencionPct": 7, "firmadoEn": "2026-10-20", "saldoDisponible": 1180000.00, "totalCobrado": 41881.80, "totalReservado": 0.00 }]`
(lista con 0 o 1 elemento).

### GET /cobros?obraId=&estado= · 006, 008
Roles: `admin`, `gerente`. Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `venceEn asc`. Cada elemento:
`[{ "id", "numero": "COB-2027-0003", "obraId", "planillaId", "montoNeto": 41881.80, "emitidoEn": "2027-04-02", "venceEn": "2027-05-02", "estado": "PENDIENTE" }]`

### GET /cobros/{id} · 008
Roles: `admin`, `gerente`. Mismo objeto que en la lista. (El gateway lo usa para el detalle del cobro de una planilla, solo para `admin` y `gerente`; el número del cobro lo guarda Obras en la planilla y lo ven todos los que ven la planilla.)

### GET /cobros/resumen · 009
Roles: `admin`, `gerente`.
`{ "vencidos": { "cantidad": 1, "monto": 41881.80 }, "porVencer30Dias": { "cantidad": 2, "monto": 90000.00 } }`
Vencidos: estado `VENCIDO` y también `PENDIENTE` con vencimiento anterior a hoy (hora de La Paz), por si todavía no se marcó. Por vencer: `PENDIENTE` con vencimiento entre hoy y hoy + 30, ambos incluidos. Cada cobro cuenta en un solo grupo.

### Capa 2

Crear orden de compra y cuenta por pagar (las llama n8n). Se especifican en la capa 2.

## Sincronización (puerto 8084)

Solo la llama la app de obra (capa 1). Reenvía el token del usuario a los servicios dueños, que aplican sus reglas finas; no guarda datos del negocio ni publica eventos. Respuestas con gzip si el cliente manda `Accept-Encoding: gzip`.

Encabezados comunes (todas las rutas salvo `/salud`):
- `Authorization: Bearer <token>`: sin token o inválido, `401 NO_AUTENTICADO`; si Keycloak no responde al pedir el JWKS, `503 SERVICIO_NO_DISPONIBLE`.
- Roles `maestro` y `almacenero` (roles efectivos según `azp`); otro rol: `403 SIN_PERMISO`.
- `X-Dispositivo-Id: <uuid>` (UUID del celular): falta o no es UUID → `400 DISPOSITIVO_REQUERIDO` (se comprueba después del token y del rol).
- `X-Request-Id`: si no viene, Sincronización lo crea; se reenvía a los servicios dueños y vuelve en la respuesta.

### GET /salud
Sin token ni `X-Dispositivo-Id` · `200 {"estado":"ok"}`

### GET /paquete-datos?obraActivaId= · 101, 103
Roles: `maestro`, `almacenero`. Encabezado opcional `If-None-Match: "<versionDatos>"`.
Devuelve `200` con `ETag: "<versionDatos>"`, o `304` sin cuerpo si la versión no cambió:
```json
{
  "versionDatos": "9f2c…(sha256 en hexadecimal)",
  "generadoEn": "2026-11-15T13:00:00Z",
  "obras": [{
    "id": "uuid", "nombre": "Edificio Las Palmas", "ubicacion": "Av. Banzer 4to anillo",
    "partidas": [{ "id": "uuid", "codigo": "P-01", "nombre": "Losa de hormigón armado", "unidad": "m2" }],
    "stock": [{ "materialId": "id", "cantidad": 120.0, "minimo": 100.0, "estado": "JUSTO" }],
    "diario": [{ "id": "uuid", "fecha": "2026-11-15", "clima": "LLUVIA_LEVE", "texto": "Se vació la losa…" }]
  }],
  "materiales": [{ "id": "id", "codigo": "CEM-IP30", "nombre": "Cemento IP-30", "unidad": "bolsa", "unidadPlural": "bolsas" }]
}
```
- Se arma con el token del usuario: Obras `GET /obras?estado=EN_EJECUCION` y, por cada obra, en paralelo, Obras `GET /obras/{id}` (partidas) y Materiales `GET /obras/{id}/stock` (`404` → `stock: []`); además Materiales `GET /materiales?soloActivos=true`.
- `diario` (103): solo si el token tiene el rol `maestro`; Obras `GET /obras/{id}/diario` (últimos 30 días). `403` o `404` de Obras para esa obra → `diario: []`. Para los demás roles el campo no va.
- `versionDatos` = SHA-256 del JSON del paquete sin `generadoEn`, con las claves ordenadas y las listas ordenadas por `id` (el stock, por `materialId`).
- `obraActivaId` opcional (UUID): solo se guarda en el estado del celular.
- Errores: `401` · `403` · `400 DISPOSITIVO_REQUERIDO` · `400 DATOS_INVALIDOS` (`obraActivaId` que no es UUID) · `503 SERVICIO_NO_DISPONIBLE` (Obras o Materiales fallan) · `504 TIEMPO_AGOTADO` (alguno tarda más de 5 s). La app conserva los datos que ya tenía.

### POST /fotos/url-subida · 102
Roles: `maestro`. Recibe `{ "obraId": "uuid", "fotoId": "uuid" }`.
Reenvía a Obras `POST /obras/{obraId}/fotos/url-subida { fotoId }` con el token del usuario (tiempo máximo 5 s) y devuelve su respuesta tal cual: `{ "url": "https://…", "claveArchivo": "fotos/{obraId}/{fotoId}.jpg", "expiraEn": "…" }`. La app sube la foto con `PUT` directo a esa URL (vence a los 10 minutos: se pide una nueva en cada intento).
- `400`, `403`, `404` o `422` de Obras (y cualquier otro `4xx`) → mismo `status` y `codigo`.
- `5xx` de Obras o error de red → `503 SERVICIO_NO_DISPONIBLE`; tiempo agotado → `504 TIEMPO_AGOTADO`.
- `400 DATOS_INVALIDOS` si `obraId` o `fotoId` faltan o no son UUID. No guarda nada.

### POST /lotes · 101, 102, 103
Roles: `maestro`, `almacenero`. Cuerpo de hasta 256 KB.
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
    { "idOperacion": "uuid", "estado": "REINTENTAR", "repetida": false, "status": 503,
      "respuesta": { "title": "Servicio no disponible", "status": 503, "codigo": "SERVICIO_NO_DISPONIBLE" } }
  ]
}
```
- `estado`: `PROCESADO` (el servicio dueño lo aceptó), `ERROR` (rechazo definitivo; no se reintenta) o `REINTENTAR` (la app lo vuelve a enviar más tarde con el mismo `idOperacion`). `repetida: true` cuando la respuesta sale de lo guardado y no se llamó al dueño.
- Errores del lote completo: `400 LOTE_INVALIDO` (vacío, más de 20 operaciones, `idOperacion` repetido dentro del lote o datos mal formados; con `errores[]`) · `401` · `403` · `400 DISPOSITIVO_REQUERIDO` · `413 ARCHIVO_DEMASIADO_GRANDE` (más de 256 KB).

| `tipo` | Servicio | Llamada | Espec. |
|---|---|---|---|
| `MOVIMIENTO_MATERIAL` | Materiales | `POST /movimientos` con cuerpo = `datos` | 101 |
| `FOTO_AVANCE` | Obras | `POST /obras/{datos.obraId}/fotos` con `{ id, partidaId, claveArchivo, tomadaEn }` de `datos` | 102 |
| `ENTRADA_DIARIO` | Obras | `POST /obras/{datos.obraId}/diario` con `{ id, fecha, clima, texto }` de `datos` | 103 |

- `tipo` que no está en la tabla → resultado `ERROR` con `400 TIPO_OPERACION_DESCONOCIDO`.
- `idOperacion` distinto de `datos.id` (en `FOTO_AVANCE`, el `fotoId`), o sin `datos.obraId` en `FOTO_AVANCE` y `ENTRADA_DIARIO` → `ERROR` con `400 OPERACION_INVALIDA`.
- Cada operación, en orden: se guarda en DynamoDB «solo si no existe» (convenciones, «Idempotencia»). Si ya existía: de otro usuario → `ERROR` con `403 OPERACION_AJENA`; ya `PROCESADO` o `ERROR` → la respuesta guardada con `repetida: true`; en proceso (o tomada por otra petición) → `REINTENTAR` con `409 OPERACION_EN_PROCESO` (un `PROCESANDO` de más de 60 s se retoma).
- Respuesta del dueño (tiempo máximo 5 s): `2xx` → `PROCESADO`; `400`, `403`, `404`, `409`, `422` → `ERROR` con su Problem Details; otro `4xx` también → `ERROR` (decisión de implementación); `401` → `REINTENTAR` con `TOKEN_VENCIDO` (la app renueva el token); `408`, `429`, `5xx` → `REINTENTAR` con el `status` recibido; tiempo agotado → `REINTENTAR` con `504 TIEMPO_AGOTADO`; error de red o falla de DynamoDB → `REINTENTAR` con `503 SERVICIO_NO_DISPONIBLE`.
- Si pasan 20 s desde que empezó el lote, las operaciones que faltan vuelven `REINTENTAR` con `504 TIEMPO_AGOTADO` sin empezarse.
