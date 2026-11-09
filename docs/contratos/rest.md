# Contratos REST

> Copia generada de los `docs/contratos.md` de cada proyecto. Si cambias algo, cámbialo en el proyecto y aquí.

Convenciones comunes (errores, token, idempotencia, paginación): `docs/convenciones.md`.

## Obras (puerto 8081)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### POST /obras · 002, 401
Roles: `admin` (el `403` se comprueba antes que el formato del cuerpo). Montos, precios y porcentajes con hasta 2 decimales; cantidades con hasta 3. Los errores de validación traen `errores[]` por campo; se revisan en este orden: contrato, códigos de partida, insumos, presupuesto.
```json
{
  "nombre": "Edificio Las Palmas",
  "ubicacion": "Av. Banzer 4to anillo, Santa Cruz",
  "zona": "NORTE",
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
`zona` (401): opcional; `NORTE`, `SUR`, `ESTE`, `OESTE` o `CENTRO` (decisión del equipo). Ausente o `null`: la obra queda sin zona. Otro valor (también minúsculas o vacío): `400 DATOS_INVALIDOS` con `errores[].campo = zona`.
Errores: `400` formato · `422 PRESUPUESTO_NO_COINCIDE` · `422 CODIGO_PARTIDA_REPETIDO` · `422 INSUMO_REPETIDO` · `422 CONTRATO_INVALIDO` · `403`.
Publica `ObraRegistrada` (desde la 401, con `ubicacion` y `zona`).

### GET /obras?estado=&busqueda= · 006, 009, 101, 401, 010
Roles: todos; filtra por visibilidad (convenciones). Quién llama: el gateway; Sincronización (capa 1), con el token del usuario (`estado=EN_EJECUCION`, para el paquete de datos); el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`); n8n (010, flujo «Recordar diario»: `estado=EN_EJECUCION`), con el token de *service account* del cliente `n8n` (`gerente`).
```json
[{
  "id": "uuid", "nombre": "Edificio Las Palmas", "ubicacion": "…", "zona": "NORTE", "estado": "EN_EJECUCION",
  "fechaInicio": "2026-11-01", "avancePct": 32.5, "plazoPct": 41.0, "enRiesgo": false,
  "ultimaPlanilla": { "periodo": "2027-02", "estado": "APROBADA" }
}]
```
`ultimaPlanilla` es `null` si no hay planillas; `zona` (401) es `null` si la obra no tiene zona.

### GET /obras/{id} · 002, 004, 006, 101, 401, 201, 010
Roles: los que pueden ver la obra. Quién llama: el gateway; Sincronización (capa 1), con el token del usuario (partidas del paquete de datos); el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`); n8n (201, flujos de cobranza: nombre y `asignaciones.clienteId`; 010, flujos «Avisar stock bajo» y «Avisar planilla para revisar»: nombre y, en el segundo, `asignaciones.clienteId`), con el token de *service account* del cliente `n8n` (`gerente`).
```json
{
  "id": "uuid", "nombre": "…", "ubicacion": "…", "zona": "NORTE", "estado": "EN_EJECUCION",
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
`zona` (401): `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO` o `null` (sin zona).
Errores: `404 OBRA_NO_ENCONTRADA` (también si el usuario no puede verla).

### GET /obras/{id}/material-previsto?periodo=AAAA-MM · 006
Roles: `admin`, `gerente` y `residente` asignado (si no ve la obra: `404 OBRA_NO_ENCONTRADA`).
`{ "periodo": "2027-02", "hayPlanilla": true, "items": [{ "partidaId": "…", "materialId": "…", "cantidadPrevista": 55.0 }] }`

### POST /obras/{obraId}/fotos/url-subida · 005, 102
Roles: `maestro`, `residente` asignados. Quién llama: Sincronización (capa 1), con el token del usuario. Recibe `{ "fotoId": "uuid" }`.
Devuelve `{ "url": "https://…", "claveArchivo": "fotos/{obraId}/{fotoId}.jpg", "expiraEn": "…" }`.

### POST /obras/{obraId}/fotos · 005, 102, 301
Roles: `maestro`, `residente` asignados. Quién llama: Sincronización (capa 1), con el token del usuario (operación `FOTO_AVANCE`).
Recibe `{ "id": "uuid", "partidaId": "uuid", "claveArchivo": "fotos/…jpg", "tomadaEn": "2026-11-15T15:20:00Z", "deteccion": { "personas": 4, "sinCasco": 1, "sinChaleco": 2, "versionModelo": "epp-1.0.0" } }`; `deteccion` es opcional (301, hecha en el celular).
Devuelve `201` (o `200` si el `id` ya existía; la detección no cambia) `{ "id", "partidaId", "registradoPor", "registradoEn", "publicadaCliente": false, "deteccion", "avisos" }`. `deteccion` es `null` si no llegó o no era válida; en ese caso `avisos: ["DETECCION_DESCARTADA"]` y la foto se guarda igual.
Errores: `404 OBRA_NO_ENCONTRADA` · `422 PARTIDA_NO_ES_DE_LA_OBRA` · `422 CLAVE_ARCHIVO_INVALIDA`.

### GET /obras/{obraId}/fotos?partidaId=&desde=&hasta= · 005, 006, 007, 008, 301
Roles: los que pueden ver la obra; `cliente` solo recibe publicadas. Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `registradoEn desc`. Cada elemento:
`[{ "id", "partidaId", "registradoPor", "registradoEn", "publicadaCliente", "urlDescarga", "deteccion" }]`; `deteccion` (301) es `{ personas, sinCasco, sinChaleco, versionModelo }` o `null`, y siempre `null` para `cliente`.

### POST /obras/{obraId}/diario · 103
Roles: `maestro` asignado. Quién llama: Sincronización (capa 1), con el token del maestro (la app no llama directo; operación `ENTRADA_DIARIO`).
Recibe `{ "id": "uuid generado en el celular", "fecha": "2026-11-15", "clima": "LLUVIA_LEVE", "texto": "Se vació la losa del 2do piso. Lluvia por la tarde, se cubrió con nylon." }`.
Devuelve `201` (o `200` si el `id` ya existía, aunque el cuerpo sea distinto) `{ "id", "obraId", "fecha", "clima", "texto", "registradoPor", "registradoEn" }`.
Errores: `400 DATOS_INVALIDOS` (`errores[]` con `clima` o `texto`) · `403 SIN_PERMISO` (ve la obra pero no como `maestro`, por ejemplo el residente asignado) · `404 OBRA_NO_ENCONTRADA` (no existe o no la ve, por ejemplo un maestro no asignado) · `409 DIARIO_DIA_YA_REGISTRADO` · `422 OBRA_NO_EN_EJECUCION` · `422 FECHA_DIARIO_INVALIDA` (futura en `America/La_Paz` o anterior a `fechaInicio`).
- `clima`: `SOLEADO`, `NUBLADO`, `LLUVIA_LEVE` o `LLUVIA_FUERTE`. `texto`: de 10 a 2000 caracteres sin contar los espacios de los extremos (se guarda sin ellos). `registradoPor` = `sub` del token; `registradoEn` = momento en que Obras la recibió.
- Una entrada por obra y día (único `obra_id`, `fecha`): si dos llegan a la vez con distinto `id`, la segunda recibe `409 DIARIO_DIA_YA_REGISTRADO`. Un `id` que ya existe en otra obra también responde `409 DIARIO_DIA_YA_REGISTRADO`.

### GET /obras/{obraId}/diario?desde=&hasta= · 103, 010
Roles: `maestro` y `residente` asignados, `admin`, `gerente`. Quién llama: Sincronización (capa 1), con el token del usuario (`diario` del paquete de datos, solo para el `maestro`); n8n (010, flujo «Recordar diario»: `desde` y `hasta` = hoy en La Paz, para saber si hay entrada), con el token de *service account* del cliente `n8n` (`gerente`).
`[{ "id", "obraId", "fecha", "clima", "texto", "registradoPor", "registradoEn" }]`, de la fecha más reciente a la más antigua.
- `desde` y `hasta` (`AAAA-MM-DD`, incluidas). Sin ninguna: los últimos 30 días hasta hoy (La Paz); sin `hasta`: hoy; sin `desde`: `hasta` − 29 días.
- Errores: `400 DATOS_INVALIDOS` (fecha mal formada o `desde` posterior a `hasta`) · `400 RANGO_INVALIDO` (más de 366 días) · `404 OBRA_NO_ENCONTRADA` (no existe, no la ve o la ve solo como `cliente`) · `403 SIN_PERMISO` (la ve con otro papel, por ejemplo el almacenero asignado).

### POST /obras/{obraId}/planillas · 007
Roles: `residente` asignado. Recibe `{ "periodo": "2027-03" }`. Devuelve `201` con el detalle (`GET /planillas/{id}`).
Errores: `409 PLANILLA_ABIERTA_EXISTE` · `422 PERIODO_NO_POSTERIOR` (no es posterior al de la última planilla) · `422 PERIODO_FUTURO` (mes futuro) · `422 OBRA_NO_EN_EJECUCION`.

### GET /obras/{obraId}/planillas · 006, 007, 008, 401
Roles: los que pueden ver la obra; `cliente` no recibe `BORRADOR`. Quién llama: el gateway, el portal y el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`).
`[{ "id", "numero", "periodo", "estado", "neto", "cobroId", "cobroNumero" }]` (`cobroNumero`: número del cobro, `COB-AAAA-NNNN`, que Obras guarda al recibir `CobroEmitido`; `null` hasta que se aprueba)

### GET /planillas/{id} · 007, 008, 401, 201, 010
Roles: los que pueden ver la obra. Quién llama: el gateway, el portal, el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`), y n8n (201, flujo «Enviar nota de cobro»; 010, flujo «Avisar planilla para revisar»), con el token de *service account* del cliente `n8n` (`gerente`). `404 PLANILLA_NO_ENCONTRADA` si no existe, es de una obra que no ve o, para el `cliente`, si es `BORRADOR`.
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

### POST /planillas/{id}/presentar · 007, 010
Roles: `residente` asignado. Recibe `{ "version": 3 }`. Devuelve `200` con el detalle (`PRESENTADA`).
Errores: `409 VERSION_DESACTUALIZADA` · `409 PLANILLA_NO_EDITABLE` · `422 SUBTOTAL_CERO`.
Publica `PlanillaPresentada` (010) en la misma transacción que el cambio a `PRESENTADA`; `reenvio` es `true` si venía de `OBSERVADA`.

### POST /planillas/{id}/aprobar · 008
Roles: `cliente` dueño de la obra. Sin cuerpo. Devuelve `202 { "estado": "APROBANDO" }`.
Errores: `409 PLANILLA_NO_PRESENTADA`.

### POST /planillas/{id}/observar · 008
Roles: `cliente` dueño de la obra. Recibe `{ "motivo": "texto de 10 a 500 caracteres" }`. Devuelve `200` con el detalle (`OBSERVADA`).
Errores: `409 PLANILLA_NO_PRESENTADA` · `422 MOTIVO_INVALIDO`.

### Herramientas MCP (capa 5, solo lectura) · 501
Ruta: `POST /mcp` (MCP, HTTP «streamable», sin estado, respuestas JSON; versión común 2025-11-25) · Rol: `agente_ia` (*service account* de `ia-agentes`) · Solo lo llama el servicio de IA (`ia-worker`, host de los agentes)

- Sin token o inválido: `401 NO_AUTENTICADO`; token válido sin `agente_ia` (también `gerente` o `admin`): `403 SIN_PERMISO`; ningún endpoint REST acepta `agente_ia`. Solo `POST` (`GET` responde `405`; no hay sesión ni flujo SSE). Sin recursos ni *prompts*.
- Cada herramienta: solo lectura (`annotations: { readOnlyHint: true, openWorldHint: false }`), `inputSchema` y `outputSchema` con `additionalProperties: false`, `structuredContent` con la salida y el mismo JSON como texto en `content`; consulta con tiempo máximo de 5 s.
- Errores de herramienta (resultado con `isError: true` y texto JSON `{"codigo", "mensaje"}`): `ARGUMENTO_INVALIDO` (no cumple el esquema; no consulta la base), `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`. Una herramienta que no existe es un error del protocolo.
- Registro: una línea JSON por llamada con `herramienta`, `argumentos`, `filas`, `duracionMs` y `requestId` (`X-Request-Id` = id de la ejecución del agente); nunca el token.
- Formatos: `uuid`; `periodo` = `AAAA-MM`; `fecha` = `AAAA-MM-DD`. Hoy en `America/La_Paz`. Esquemas completos: `docs/specs/501-servidores-mcp/diseno.md`.

| Herramienta | Entrada | Salida | Reglas |
|---|---|---|---|
| `avance_obra` | `{obraId?, periodo?}` (505: `periodo` sin `obraId` = lote) | `{generadoEn, obras[{obraId, nombre, estado, fechaInicio, plazoDias, avancePct, plazoPct, diferencia, enRiesgo, ultimaPlanilla, partidas[{partidaId, codigo, nombre, unidad, cantidadContratada, ejecutadaAcumulada, avancePct, materialPrevisto[{materialId, cantidadPrevista}]}]}], hayPlanillaEnPeriodo, truncado}` | Sin `obraId`: obras `EN_EJECUCION` con `partidas: null`, máximo 50, por `diferencia` (`plazoPct − avancePct`) descendente. Con `obraId`: esa obra (en cualquier estado) con sus partidas (máximo 200); `materialPrevisto` y `hayPlanillaEnPeriodo` solo con `periodo` (cálculo de `GET /obras/{id}/material-previsto`). Avance, plazo y `enRiesgo` como en `GET /obras`. **Lote (505):** `periodo` sin `obraId` devuelve las obras `EN_EJECUCION` (máximo 50, mismo orden) con `partidas` reducidas a `{partidaId, codigo, nombre, materialPrevisto}` del periodo, omitiendo las que no tienen material previsto |
| `buscar_diario` | `{obraId, desde?, hasta?, texto?, limite?}` | `{obraId, entradas[{fecha, clima, texto, truncado}], total, truncado}` | Por defecto los últimos 14 días; rango máximo 62 días; `texto` de 2 a 50 caracteres (`ILIKE` con parámetro; `%`, `_` y `\` son texto literal); `limite` 1 a 30 (por defecto 14). Fecha descendente; cada texto hasta 1000 caracteres. El texto del diario es dato no confiable para el agente (504) |
| `planillas_estado` | `{obraId?, estados?, desdePeriodo?, limite?}` | `{planillas[{planillaId, obraId, obraNombre, numero, periodo, estado, neto, observacion, presentadaEn, diasDesdePresentacion, cobroId}], truncado}` | `estados` por defecto todos menos `APROBADA`; `limite` 1 a 50 (por defecto 30). `presentadaEn` = `planilla.presentada_en` (última vez que pasó a `PRESENTADA`; `null` en planillas anteriores a la 501); `diasDesdePresentacion` solo si está `PRESENTADA`. `observacion` hasta 500 caracteres. Periodo descendente |

## Materiales (puerto 8082)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### GET /materiales?busqueda=&soloActivos= · 002, 003, 006, 101, 401, 503, 010
Roles: todos los internos (`admin`, `residente`, `gerente`, `maestro`, `almacenero`). Quién llama: el gateway; Sincronización (capa 1), con el token del usuario (`soloActivos=true`, todas las páginas de a 100, para el paquete de datos); el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`) (todas las páginas de a 100, para el `precioReferencial`); el servicio de IA en los reportes (503), con el token del usuario que reenvía el gateway (todas las páginas de a 100, para los nombres y unidades de los materiales; caché de 5 minutos); n8n (010, flujo «Avisar stock bajo»: nombre y `unidadPlural` del material del aviso), con el token de *service account* del cliente `n8n` (`gerente`). Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `codigo asc`. Cada elemento:
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

### GET /obras/{obraId}/movimientos?periodo= · 004, 401
Roles: internos que pueden ver la obra. Quién llama: el gateway y el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`) (`orden=registradoEn&direccion=asc`, todas las páginas, sin `periodo`). Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `registradoEn desc`. Cada elemento: `[{ "id", "materialId", "tipo", "cantidad", "partidaId", "periodo", "superaStock", "cerrado", "registradoPor", "registradoEn" }]`

### GET /obras/{obraId}/consumos?periodo=AAAA-MM · 006
Roles: `admin`, `gerente` y `residente` asignado (si no ve la obra: `404 OBRA_NO_ENCONTRADA`). `[{ "partidaId", "materialId", "cantidad" }]` (suma de salidas).

### GET /stock/resumen?obraIds=a,b,c · 009
Roles: `admin`, `residente`, `gerente`. `[{ "obraId", "materialesBajos": 2 }]` (solo obras visibles).
`obraIds` obligatorio, de 1 a 100 ids separados por coma (sin ellos o con más de 100: `400 DATOS_INVALIDOS`). Una fila por obra visible, en el orden pedido; una obra visible sin stock devuelve `0`; las que el usuario no ve se omiten sin error. `materialesBajos` = materiales en estado `BAJO` (calculado al leer). El gateway pide en lotes de 100.

### Herramientas MCP (capa 5, solo lectura) · 501
Ruta: `POST /mcp` (MCP, HTTP «streamable», sin estado, respuestas JSON; versión común 2025-11-25) · Rol: `agente_ia` (*service account* de `ia-agentes`) · Solo lo llama el servicio de IA (`ia-worker`, host de los agentes)

- Sin token o inválido: `401 NO_AUTENTICADO`; token válido sin `agente_ia` (también `gerente` o `admin`): `403 SIN_PERMISO`; ningún endpoint REST acepta `agente_ia`. Solo `POST` (`GET` y `DELETE` responden `405`; no hay sesión ni flujo SSE). Sin recursos ni *prompts*.
- Cada herramienta: solo lectura (`annotations: { readOnlyHint: true, openWorldHint: false }`), `inputSchema` y `outputSchema` con `additionalProperties: false`, `structuredContent` con la salida y el mismo JSON como texto en `content`; consulta con tiempo máximo de 5 s.
- Errores de herramienta (resultado con `isError: true` y texto JSON `{"codigo", "mensaje"}`): `ARGUMENTO_INVALIDO` (no cumple el esquema; no consulta la base), `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`. Una herramienta que no existe es un error del protocolo.
- Registro: una línea JSON por llamada con `herramienta`, `argumentos`, `filas`, `duracionMs` y `requestId` (`X-Request-Id` = id de la ejecución del agente); nunca el token.
- `agente_ia` ve todas las obras de `obra_acceso` (como `gerente`). `OBRA_NO_ENCONTRADA` si la obra no está en `obra_acceso`.

| Herramienta | Entrada | Salida | Reglas |
|---|---|---|---|
| `stock_obra` | `{obraId?, estados?, limite?}` | `{filas[{obraId, obraNombre, materialId, codigo, nombre, unidad, cantidad, minimo, estado}], total, truncado}` | `estados` de `BAJO`, `JUSTO`, `OK` (por defecto los tres); `limite` 1 a 100 (por defecto 100). `obraNombre` de `obra_acceso`; estado como en `GET /obras/{obraId}/stock`. Orden: `BAJO`, `JUSTO`, `OK`, luego obra y código; `total` antes de recortar |
| `consumos_partida` | `{obraId?, periodo, partidaId?}` (505: `obraId` opcional) | `{obraId, periodo, cerrado, filas[{obraId, obraNombre, partidaId, materialId, codigo, nombre, unidad, usado, salidas, salidasSuperanStock}], truncado}` | `usado` = suma de salidas (como `GET /obras/{obraId}/consumos`); `cerrado` = periodo cerrado (`cierre_periodo`). Máximo 200 filas. **Sin `obraId` (505):** todas las obras con consumo en el periodo, `obraId` y `cerrado` en `null`, máximo 500 filas |

## Finanzas (puerto 8083)

### GET /salud
Sin token · `200 {"estado":"ok"}`

### GET /contratos?obraId= · 006, 201
Roles: `admin`, `gerente`.
`[{ "id", "obraId", "monto": 1250000.00, "plazoDias": 300, "anticipoPct": 10, "retencionPct": 7, "firmadoEn": "2026-10-20", "saldoDisponible": 1180000.00, "totalCobrado": 41881.80, "totalReservado": 0.00 }]`
(lista con 0 o 1 elemento). `totalCobrado` suma los cobros emitidos: `PENDIENTE`, `VENCIDO` y `PAGADO` (201); el saldo disponible no cambia al registrar un pago.

### GET /cobros?obraId=&estado= · 006, 008, 401, 201
Roles: `admin`, `gerente`. Quién llama: el gateway y el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`) (todas las páginas de a 100; lee `estado` y `pagadoEn`). Paginado (convenciones): `pagina`, `tamano`, `orden`, `direccion`; responde `{ items, total, pagina, tamano }` con orden por defecto `venceEn asc`. `estado` (también como filtro): `PENDIENTE`, `VENCIDO` o `PAGADO` (201). Cada elemento:
`[{ "id", "numero": "COB-2027-0003", "obraId", "planillaId", "montoNeto": 41881.80, "emitidoEn": "2027-04-02", "venceEn": "2027-05-02", "estado": "PENDIENTE", "pagadoEn": null, "comprobante": null, "envios": [{ "tipo": "NOTA_COBRO", "destinatario": "cliente1@correo.test", "enviadoEn": "2027-04-02T12:00:41Z" }] }]`
- `pagadoEn` (`AAAA-MM-DD`, La Paz) y `comprobante`: `null` si no está `PAGADO` (201).
- `envios` (201): correos de la cobranza que anotó n8n, ordenados por `enviadoEn`. `tipo`: `NOTA_COBRO`, `RECORDATORIO_POR_VENCER`, `RECORDATORIO_VENCIDO` o `CONSTANCIA_PAGO`; como máximo uno de cada tipo.

### GET /cobros/{id} · 008, 201
Roles: `admin`, `gerente`. Mismo objeto que en la lista. (El gateway lo usa para el detalle del cobro de una planilla, solo para `admin` y `gerente`; el número del cobro lo guarda Obras en la planilla y lo ven todos los que ven la planilla.) También lo llama n8n (201), con el token de *service account* del cliente `n8n` (`gerente`), para saber por `envios` si un correo ya salió.

### GET /cobros/resumen · 009
Roles: `admin`, `gerente`.
`{ "vencidos": { "cantidad": 1, "monto": 41881.80 }, "porVencer30Dias": { "cantidad": 2, "monto": 90000.00 } }`
Vencidos: estado `VENCIDO` y también `PENDIENTE` con vencimiento anterior a hoy (hora de La Paz), por si todavía no se marcó. Por vencer: `PENDIENTE` con vencimiento entre hoy y hoy + 30, ambos incluidos. Cada cobro cuenta en un solo grupo; los `PAGADO` (201) no cuentan.

### POST /cobros/{id}/pago · 201
Roles: `admin`. Quién llama: el gateway, con el token del usuario (`registrarPagoCobro`). Se paga el cobro completo.
```json
{ "pagadoEn": "2027-04-28", "comprobante": "TRF-883412" }
```
1. `pagadoEn` obligatorio (`AAAA-MM-DD`); `comprobante` opcional, de 1 a 50 caracteres (vacío se guarda como `null`).
2. En una transacción, bloquea la fila del cobro (`FOR UPDATE`). Si no existe → `404 COBRO_NO_ENCONTRADO`; si está `PAGADO` → `409 COBRO_YA_PAGADO`.
3. `pagadoEn` posterior a hoy (La Paz) o anterior a la emisión del cobro → `422 FECHA_PAGO_INVALIDA`.
4. Guarda `PAGADO`, la fecha, el comprobante, quién lo registró (`sub`) y cuándo; agrega `CobroPagado` al outbox. Un `PAGADO` no cambia más: no se vence, no se paga otra vez ni se deshace.

Devuelve `200` con el cobro (mismo objeto que `GET /cobros/{id}`). Errores: `400 DATOS_INVALIDOS` · `401` · `403` · `404 COBRO_NO_ENCONTRADO` · `409 COBRO_YA_PAGADO` · `422 FECHA_PAGO_INVALIDA`.

Las tres rutas que siguen (capa 2, 201) las llama solo n8n: rol `automatizacion` (*service account* del cliente confidencial `n8n`), con el middleware `rol:automatizacion`; `automatizacion` no entra en ninguna otra ruta y cualquier otro rol recibe `403`. `GET /cobros/recordatorios` se registra antes de `GET /cobros/{id}` (como `resumen`).

### GET /cobros/recordatorios · 201
Roles: `automatizacion`. Quién llama: n8n (flujo «Recordar cobros», todos los días a las 08:00 de La Paz). «Hoy» = fecha actual en `America/La_Paz`.
```json
{
  "hoy": "2027-04-29",
  "porVencer": [{ "id", "numero", "obraId", "planillaId", "montoNeto", "emitidoEn", "venceEn", "estado", "diasParaVencer": 3 }],
  "vencidos":  [{ "id", "numero", "obraId", "planillaId", "montoNeto", "emitidoEn", "venceEn", "estado", "diasVencido": 1 }]
}
```
- `porVencer`: `PENDIENTE` con `venceEn` entre hoy y hoy + 3 (ambos incluidos) y sin envío `RECORDATORIO_POR_VENCER`.
- `vencidos`: `VENCIDO`, o `PENDIENTE` con `venceEn` anterior a hoy, sin envío `RECORDATORIO_VENCIDO`.
- Un cobro aparece en un solo grupo; un `PAGADO`, en ninguno. Orden por `venceEn` y `numero`. Sin paginar (pocos por día).

### POST /cobros/{id}/envios · 201
Roles: `automatizacion`. Quién llama: n8n, después de enviar cada correo. Recibe `{ "tipo": "NOTA_COBRO", "destinatario": "cliente1@correo.test", "ejecucionN8n": "1532" }` (`ejecucionN8n`, opcional: id de la ejecución de n8n, para buscarla en su panel).
- Si ya existe un envío de ese `tipo` para el cobro → `200` con el existente (no lo cambia). Si no → lo crea con `enviadoEn` = ahora → `201`.
- Errores: `400 DATOS_INVALIDOS` (tipo desconocido, destinatario vacío) · `404 COBRO_NO_ENCONTRADO`.

### POST /cobros/{id}/nota-cobro · 201
Roles: `automatizacion`. Quién llama: n8n (flujo «Enviar nota de cobro»). Recibe los datos que n8n leyó de Obras y Keycloak y devuelve el PDF de la nota de cobro (`application/pdf`, `Content-Disposition: attachment; filename="nota-cobro-COB-2027-0003.pdf"`). No se guarda: se genera en cada llamada.
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
2. Coherencia → `422 NOTA_COBRO_INCONSISTENTE` si `planilla.id` no es la del cobro, si `obra.id` no es la del contrato, si `neto` difiere del neto del cobro (más de 0,005) o si los totales no cuadran (suma de líneas = subtotal; subtotal − anticipo − retención = neto).
3. Contenido: empresa (`EMPRESA_NOMBRE`, «Constructora Andina»), cliente, obra, planilla N.º y periodo («septiembre 2026»), líneas con `cantidadPeriodo` > 0, totales, número de cobro, emisión, vencimiento y la leyenda «Este documento no es una factura». Montos como `Bs 330.149,10` y fechas `dd/mm/aaaa` (convenciones).

Errores: `401` · `403` · `404 COBRO_NO_ENCONTRADO` · `422 NOTA_COBRO_INCONSISTENTE`.

### Herramientas MCP (capa 5, solo lectura) · 501
Ruta: `POST /mcp` (MCP, HTTP «streamable», sin estado, respuestas JSON; versión común 2025-11-25) · Rol: `agente_ia` (*service account* de `ia-agentes`) · Solo lo llama el servicio de IA (`ia-worker`, host de los agentes)

- Sin token o inválido: `401 NO_AUTENTICADO`; token válido sin `agente_ia` (también `gerente` o `admin`): `403 SIN_PERMISO`; ningún endpoint REST acepta `agente_ia`. Solo `POST` (`GET` y `DELETE` responden `405`; no hay sesión ni flujo SSE). Sin recursos ni *prompts*.
- Cada herramienta: solo lectura (`annotations: { readOnlyHint: true, openWorldHint: false }`), `inputSchema` y `outputSchema` con `additionalProperties: false`, `structuredContent` con la salida y el mismo JSON como texto en `content`; consulta con tiempo máximo de 5 s.
- Errores de herramienta (resultado con `isError: true` y texto JSON `{"codigo", "mensaje"}`): `ARGUMENTO_INVALIDO` (no cumple el esquema; no consulta la base), `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`. Una herramienta que no existe es un error del protocolo.
- Registro: una línea JSON por llamada con `herramienta`, `argumentos`, `filas`, `duracionMs` y `requestId` (`X-Request-Id` = id de la ejecución del agente); nunca el token.
- `OBRA_NO_ENCONTRADA` si la obra no tiene contrato en Finanzas.

| Herramienta | Entrada | Salida | Reglas |
|---|---|---|---|
| `cobros_por_vencer` | `{dias?, incluirVencidos?, obraId?}` | `{hoy, cobros[{cobroId, numero, obraId, planillaId, montoNeto, emitidoEn, venceEn, estado, diasParaVencer}], totales{vencidos{cantidad, monto}, porVencer{cantidad, monto}}, truncado}` | `dias` 1 a 90 (por defecto 15); `incluirVencidos` por defecto `true`. Por vencer: `PENDIENTE` con `venceEn` entre hoy y hoy + `dias`; vencidos: como en `GET /cobros/resumen` (sin los `PAGADO`, 201). `diasParaVencer` = `venceEn − hoy` (negativo si venció). Por `venceEn`, máximo 50; los totales cuentan todos. Finanzas no guarda el nombre de la obra (el agente lo toma de Obras) |

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
| `FOTO_AVANCE` | Obras | `POST /obras/{datos.obraId}/fotos` con `{ id, partidaId, claveArchivo, tomadaEn, deteccion? }` de `datos` | 102, 301 |
| `ENTRADA_DIARIO` | Obras | `POST /obras/{datos.obraId}/diario` con `{ id, fecha, clima, texto }` de `datos` | 103 |

- `tipo` que no está en la tabla → resultado `ERROR` con `400 TIPO_OPERACION_DESCONOCIDO`.
- `idOperacion` distinto de `datos.id` (en `FOTO_AVANCE`, el `fotoId`), o sin `datos.obraId` en `FOTO_AVANCE` y `ENTRADA_DIARIO` → `ERROR` con `400 OPERACION_INVALIDA`.
- Cada operación, en orden: se guarda en DynamoDB «solo si no existe» (convenciones, «Idempotencia»). Si ya existía: de otro usuario → `ERROR` con `403 OPERACION_AJENA`; ya `PROCESADO` o `ERROR` → la respuesta guardada con `repetida: true`; en proceso (o tomada por otra petición) → `REINTENTAR` con `409 OPERACION_EN_PROCESO` (un `PROCESANDO` de más de 60 s se retoma).
- Respuesta del dueño (tiempo máximo 5 s): `2xx` → `PROCESADO`; `400`, `403`, `404`, `409`, `422` → `ERROR` con su Problem Details; otro `4xx` también → `ERROR` (decisión de implementación); `401` → `REINTENTAR` con `TOKEN_VENCIDO` (la app renueva el token); `408`, `429`, `5xx` → `REINTENTAR` con el `status` recibido; tiempo agotado → `REINTENTAR` con `504 TIEMPO_AGOTADO`; error de red o falla de DynamoDB → `REINTENTAR` con `503 SERVICIO_NO_DISPONIBLE`.
- Si pasan 20 s desde que empezó el lote, las operaciones que faltan vuelven `REINTENTAR` con `504 TIEMPO_AGOTADO` sin empezarse.

## IA (puerto 8085, capas 4 y 5)

Atiende solo al ERP (lo llama el gateway). Toda ruta salvo `/salud` exige token (`401 NO_AUTENTICADO`; `503 SERVICIO_NO_DISPONIBLE` si Keycloak no entrega el JWKS). Solo `admin`, `gerente` y `residente` (roles efectivos según `azp`); los demás roles (también `agente_ia`) reciben `403 SIN_PERMISO` en todas las rutas REST. **Excepción (501):** `/mcp` acepta **solo** `agente_ia`; las rutas REST no lo aceptan. Visibilidad: `admin` y `gerente` ven todas las obras; `residente`, las de `rpt_obra_resumen.residente_id = sub`. Una ruta que no existe (con token válido): `404 RUTA_NO_ENCONTRADA`. Las consultas leen `reportes_db` y `ia_db`; no calculan nada en la petición.

### GET /salud · 401
Sin token · `200 {"estado":"ok"}`

### GET /reportes/estado · 401
Servicio: IA · Quién llama: (pruebas y administración) · Rol: `admin`. No se expone por GraphQL.
```json
{
  "tablas": { "rptObraResumen": 12, "rptPlanilla": 40, "rptConsumoMaterial": 310, "rptMovimiento": 2210, "rptCobro": 35 },
  "ultimosEventos": [{ "tipo": "PlanillaAprobada", "aplicadoEn": "2026-11-15T14:30:00Z" }],
  "cargaInicial": {
    "cargaId": "uuid", "estado": "TERMINADA", "iniciadaEn": "2026-11-01T13:00:00Z", "terminadaEn": "2026-11-01T13:00:09Z",
    "obras": 3, "filas": { "rptObraResumen": 3, "rptPlanilla": 4, "rptMovimiento": 67, "rptCobro": 3 }, "error": null
  }
}
```
`cargaInicial`: la última corrida (`EN_CURSO`, `TERMINADA` o `FALLIDA`); `null` si nunca se corrió. Con los datos de prueba (011) la carga trae 4 de las 5 planillas: la N.º 3 de la obra 1 está `PRESENTADA` sin observación y no se carga (no llega ningún evento por ella). Errores: `401` · `403`.

### GET /predicciones?obraIds=a,b,c · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`. Recibe hasta 100 ids separados por coma.
```json
[{
  "obraId": "uuid", "probabilidad": 0.72, "nivel": "ALTO",
  "factores": [{ "variable": "relacion_ritmo", "descripcion": "El ritmo de avance de los últimos meses es menor al necesario para terminar a tiempo", "peso": 0.81 }],
  "versionModelo": "rr-1.0.0", "calculadaEn": "2026-11-15T05:00:00Z"
}]
```
Solo las obras visibles que tengan predicción, en el orden pedido; las demás se omiten. Con `SIN_DATOS`: `"probabilidad": null`, `"factores": []`. `nivel`: `BAJO` < 0,30 ≤ `MEDIO` < 0,60 ≤ `ALTO`, o `SIN_DATOS`.
Errores: `400 DEMASIADAS_OBRAS` (más de 100) · `400 DATOS_INVALIDOS` (sin ids o con un id que no es UUID) · `401` · `403`.

### GET /obras/{obraId}/prediccion?historial=30 · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente` (que pueda ver la obra).
Devuelve `200` con el mismo objeto más `"historial": [{ "probabilidad": 0.65, "calculadaEn": "…" }]` (`historial` de 1 a 90, por defecto 30; del más antiguo al más reciente; omite los cálculos `SIN_DATOS`). Obra visible sin predicción todavía: `200` con `"nivel": "SIN_DATOS"`, `"probabilidad": null`, `"factores": []`, `"versionModelo": null`, `"calculadaEn": null`, `"historial": []`.
Errores: `404 OBRA_NO_ENCONTRADA` (también si no la puede ver) · `400 DATOS_INVALIDOS` (`historial` fuera de 1 a 90) · `401` · `403`.

### GET /modelos/riesgo-retraso · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`.
```json
{
  "versionModelo": "rr-1.0.0", "entrenadoEn": "2026-11-20T15:00:00Z", "datos": "SINTETICOS", "filasEntrenamiento": 9600,
  "metricas": { "aucRoc": 0.86, "aucRocRegla": 0.74, "recallMedio": 0.83, "precisionAlto": 0.74, "brier": 0.14 },
  "umbrales": { "medio": 0.30, "alto": 0.60 },
  "variables": [{ "nombre": "relacion_ritmo", "descripcion": "Ritmo reciente / ritmo necesario" }]
}
```
`datos`: `SINTETICOS` o `REALES`. Errores: `503 MODELO_NO_DISPONIBLE` · `401` · `403`.

### GET /consumos-atipicos?obraId=&estado=&desde=&hasta= · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`. `obraId` opcional (sin él, todas las obras visibles); `estado` opcional (`PENDIENTE`, `NORMAL`, `CONFIRMADO`; sin él, todos); `desde` y `hasta` opcionales (`AAAA-MM-DD` en La Paz, ambas incluidas, sobre `registradoEn`).
```json
[{
  "id": "uuid-del-movimiento", "movimientoId": "uuid", "obraId": "uuid", "materialId": "id", "partidaId": "uuid",
  "cantidad": 120.0, "periodo": "2026-11", "registradoEn": "2026-11-15T02:40:00Z",
  "puntaje": 0.71, "motivos": ["La cantidad es 4,2 veces la habitual de este material en la obra", "Se registró fuera del horario habitual (22:40)"],
  "estadoRevision": "PENDIENTE", "revisadoPor": null, "revisadoEn": null, "comentario": null,
  "versionModelo": "ca-1.0.0", "detectadoEn": "2026-11-15T02:40:03Z"
}]
```
Máximo 200, de la más reciente a la más antigua.
Errores: `400 DATOS_INVALIDOS` (estado o fechas inválidos, o `desde` posterior a `hasta`) · `404 OBRA_NO_ENCONTRADA` (también si no la puede ver) · `401` · `403`.

### GET /consumos-atipicos/resumen?obraIds=a,b,c · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`.
`[{ "obraId": "uuid", "pendientes": 2 }]`: solo obras visibles, en el orden pedido; las que no tienen pendientes vienen con 0.
Errores: `400 DEMASIADAS_OBRAS` (más de 100 distintas) · `401` · `403`.

### PUT /consumos-atipicos/{id}/revision · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `residente` asignado a la obra.
Recibe `{ "estado": "CONFIRMADO", "comentario": "Se usó en la losa de otra obra sin registrarlo" }`. Devuelve `200` con el consumo atípico actualizado (`revisadoPor` = `sub`, `revisadoEn`, `comentario` sin espacios a los lados).
Errores: `400 DATOS_INVALIDOS` (estado `PENDIENTE`, desconocido o falta) · `404 CONSUMO_ATIPICO_NO_ENCONTRADO` (también si el residente no está asignado a su obra) · `409 REVISION_YA_REGISTRADA` · `422 COMENTARIO_INVALIDO` (falta en `CONFIRMADO` o fuera de 5 a 300 caracteres; `errores[]` con `campo` = `comentario` y la regla en `mensaje`) · `403` (por ejemplo `gerente`) · `401`.
- La revisión es una actualización atómica que solo cambia un consumo `PENDIENTE`; si existe pero ya no está pendiente, `409`.

### POST /consultas-reporte · 503 y 505
Servicio: IA · Quién llama: Gateway (60 s, sin reintento) · Roles: `admin`, `gerente` (`residente` recibe `403`). Recibe exactamente uno de `texto` (3 a 500 caracteres; **de 1 a 500 con `conversacionId`**) o `atajo`; `conversacionId` (505, opcional, uuid) continúa una conversación (sin él empieza una nueva; un atajo siempre empieza una nueva); `directorio` lo agrega el gateway (opcional; hasta 1000 clientes):
```json
{ "texto": "¿Cuánto cemento se usó en Las Palmas este trimestre?",
  "directorio": { "clientes": [{ "id": "uuid-keycloak", "nombre": "Constructora Andina SRL" }] } }
{ "atajo": "COBROS_POR_VENCER", "directorio": { "clientes": [] } }
{ "texto": "IP-30", "conversacionId": "uuid" }
```
Devuelve `200` (505): `{ "conversacionId": "uuid", "tipo": "REPORTE" | "ACLARACION", "consulta": ConsultaReporte | null, "aclaracion": { "pregunta", "opciones": [≤6 textos de ≤60], "preguntasRestantes" } | null }`. Con `REPORTE`, `consulta` es:
```json
{
  "id": "uuid", "texto": "…", "atajo": null, "conjunto": "CONSUMO_MATERIAL", "tituloConjunto": "Material usado",
  "receta": { "conjunto": "CONSUMO_MATERIAL", "filtros": [ … ], "agruparPor": ["obra", "material"], "metricas": [ … ], "orden": [ … ], "limite": 100 },
  "aplicado": [{ "nombre": "Obra", "valor": "contiene «Las Palmas»" }],
  "resumen": "…", "resumenPlantilla": false, "avisos": [],
  "columnas": [{ "clave": "obra", "titulo": "Obra", "tipo": "TEXTO" }],
  "filas": [["Edificio Las Palmas", "Cemento IP-30", "bolsa", "1240.000", "76880.00", "31"]],
  "totalFilas": 1, "truncado": false, "creadaEn": "2027-03-20T14:00:00Z"
}
```
- `tipo` de columna: `TEXTO`, `NUMERO`, `MONTO`, `PORCENTAJE`, `FECHA`, `BOOLEANO`. Filas como texto (números con punto decimal y sin separador de miles, fechas ISO, booleanos `true`/`false`, nulos `null`); hasta 100 filas (`truncado` si hay más).
- Conjuntos: `OBRAS`, `CONSUMO_MATERIAL`, `MOVIMIENTOS`, `COBROS`, `PLANILLAS`, `CONSUMOS_ATIPICOS` (catálogo, receta y validación: `docs/specs/503-reportes-voz/diseno.md`). Atajos: `AVANCE_OBRAS`, `OBRAS_EN_RIESGO`, `CONSUMO_MATERIAL_MES`, `SALIDAS_SIN_STOCK`, `COBROS_VENCIDOS`, `COBROS_POR_VENCER`, `COBRADO_POR_OBRA`, `PLANILLAS_OBSERVADAS`, `PLANILLAS_APROBADAS`, `CONSUMOS_ATIPICOS_PENDIENTES` (sin modelo de lenguaje para entender el pedido).
- Conversación (505): el asistente pregunta (`ACLARACION`, hasta 5 por conversación) cuando el pedido es vago o un nombre coincide con varios o con ninguno; los seguimientos ajustan la última receta; autocorrección hasta 3 intentos; caché de recetas de 24 h. Diseño: `docs/specs/505-asistente-reportes/diseno.md`.
- El modelo de lenguaje (Ollama o Anthropic, `IA_LLM_PROVEEDOR`) solo devuelve una **receta**; el código la valida contra el catálogo y arma la consulta con SQLAlchemy Core y valores enlazados (usuario `ia_reportes_lector`, `READ ONLY`, 5 s). Nunca ejecuta SQL del modelo.
- `avisos`: por ejemplo «Nombres de materiales no disponibles», «Nombres de clientes no disponibles», «Las planillas sin periodo no se incluyen al filtrar por periodo».
Errores: `400 TEXTO_INVALIDO` (largo fuera de 3 a 500) · `400 DATOS_INVALIDOS` (ni `texto` ni `atajo`, los dos, atajo desconocido o `directorio` mal formado) · `422 INTENCION_NO_RECONOCIDA` · `422 RECETA_INVALIDA` (`errores[]` con `campo` = ruta en la receta y `mensaje` = la regla) · `404 CONVERSACION_NO_ENCONTRADA` (505: no existe, expiró a los 30 min sin uso o es de otro usuario) · `429 DEMASIADAS_CONSULTAS` (20 por minuto por usuario, cada turno cuenta; `IA_CONSULTAS_POR_MINUTO`; con `Retry-After`) · `503 LLM_NO_DISPONIBLE` (el modelo no responde al interpretar; nunca con un atajo) · `503 REPORTES_NO_DISPONIBLES` (no responde `reportes_db` o `ia_db`, o la consulta pasa de 5 s) · `503 SERVICIO_NO_DISPONIBLE` (Materiales con filtro de material, o sin directorio con filtro de cliente) · `504 TIEMPO_AGOTADO` (más de 50 s dentro de IA) · `401` · `403`.
Todos los casos, salvo `400`, `401`, `403` y `429`, guardan `consulta_reporte`. El límite se cuenta antes de validar el cuerpo.

### GET /consultas-reporte?limite= · 503
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`. Las del usuario del token, más recientes primero; `limite` 1 a 20 (por defecto 10).
`[{ "id", "texto", "atajo", "conjunto", "resultado", "resumen", "totalFilas", "creadaEn" }]` (`resultado`: `OK`, `NO_RECONOCIDA`, `RECETA_INVALIDA`, `ERROR`).
Errores: `400 DATOS_INVALIDOS` (`limite` fuera de 1 a 20) · `401` · `403`.

### GET /catalogo-reportes · 503
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`. El catálogo del modo `REST`:
```json
{
  "conjuntos": [{ "conjunto": "CONSUMO_MATERIAL", "titulo": "Material usado", "descripcion": "…",
                  "columnas": [{ "clave": "material", "titulo": "Material", "tipo": "TEXTO" }],
                  "filtros": ["obra", "zona", "cliente", "material", "periodo"], "agrupaciones": ["obra", "zona", "cliente", "material", "periodo"],
                  "ejemplos": ["¿Cuánto cemento se usó en Las Palmas este trimestre?"] }],
  "atajos": [{ "atajo": "COBROS_POR_VENCER", "titulo": "Cobros que vencen en los próximos 30 días", "descripcion": "…" }]
}
```
Errores: `401` · `403`.

### Agentes (502)

Tres agentes fijos (`SEGUIMIENTO_OBRAS`, `CONTROL_MATERIALES`, `CONTROL_COBROS`) que corren en `ia-worker` a las 06:00 (La Paz) y a pedido. Para `residente`: solo sus obras (`rpt_obra_resumen.residente_id`) y nunca `CONTROL_COBROS`. `EjecucionCorta` = `{ "id", "agente", "origen", "estado", "iniciadaEn", "terminadaEn", "cantidadHallazgos" }`.

### GET /agentes · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`.
`[{ "agente": "SEGUIMIENTO_OBRAS", "nombre": "Seguimiento de obras", "mision": "…", "herramientas": ["avance_obra", "buscar_diario", "planillas_estado", "riesgo_retraso", "consultar_reporte"], "ultimaEjecucion": EjecucionCorta | null, "sugerenciasPendientes": 2 }]`
Para `residente` no aparece `CONTROL_COBROS` y `sugerenciasPendientes` cuenta solo sus obras.

### POST /agentes/{agente}/ejecuciones · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`. Sin cuerpo. Devuelve `202` con la `EjecucionCorta` (`origen: "MANUAL"`, `estado: "EN_CURSO"`).
Errores: `400 AGENTE_INVALIDO` · `409 EJECUCION_EN_CURSO` · `401` · `403`.

### GET /ejecuciones?agente=&estado=&limite= · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`. `limite` 1 a 50 (por defecto 20). `[EjecucionCorta]`, más recientes primero.
Errores: `400 DATOS_INVALIDOS` (agente, estado o `limite`) · `401` · `403`.

### GET /ejecuciones/{id} · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`.
```json
{
  "id": "uuid", "agente": "CONTROL_MATERIALES", "origen": "MANUAL", "estado": "TERMINADA",
  "solicitadaPor": "uuid-keycloak", "iniciadaEn": "…", "terminadaEn": "…", "proveedorLlm": "ollama", "modelo": "qwen3:8b",
  "resumen": "2 obras con cemento bajo…", "error": null,
  "pasos": [{ "numero": 1, "servidor": "materiales", "herramienta": "stock_obra", "argumentos": "{\"estados\":[\"BAJO\",\"JUSTO\"]}",
              "resultadoResumen": "4 filas: …", "en": "…", "duracionMs": 180, "error": null }],
  "hallazgos": [{ "obraId": "uuid", "obraNombre": "Edificio Las Palmas", "tipo": "STOCK_BAJO", "severidad": "ALTA",
                  "situacion": "Cemento IP-30: 80 bolsas, mínimo 100", "causaProbable": "Consumo de la losa mayor al previsto",
                  "evidencia": [{ "herramienta": "stock_obra", "dato": "cantidad 80, mínimo 100, estado BAJO" }] }]
}
```
`error`: `{ "codigo", "mensaje" }` solo si `FALLIDA` (`SIN_HERRAMIENTAS`, `REPORTE_INVALIDO`, `EJECUCION_TIEMPO_AGOTADO`, `INTERRUMPIDA`, `LLM_NO_DISPONIBLE` o `ERROR_INTERNO`); `servidor` de cada paso: `obras`, `materiales`, `finanzas` o `ia`.
Errores: `404 EJECUCION_NO_ENCONTRADA` · `401` · `403` (también `residente`).

### GET /hallazgos?agente=&obraId= · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente` (sus obras; sin `CONTROL_COBROS`).
Hallazgos vigentes (los de la última ejecución `TERMINADA` de cada agente), con los campos de `hallazgos` de arriba más `ejecucionId`, `agente` y `detectadoEn` (= `terminadaEn`).
Errores: `400 DATOS_INVALIDOS` (agente) · `401` · `403`.

### GET /sugerencias?estado=&agente=&obraId=&limite= · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente` (sus obras; sin `CONTROL_COBROS`). `limite` 1 a 100 (por defecto 50); más recientes primero.
```json
[{
  "id": "uuid", "ejecucionId": "uuid", "agente": "CONTROL_MATERIALES", "obraId": "uuid", "obraNombre": "Edificio Las Palmas",
  "accion": "VERIFICAR_INVENTARIO", "accionTexto": "Hacer un conteo físico del material en el depósito de la obra",
  "descripcion": "Contar el cemento IP-30: el stock está bajo el mínimo.",
  "estado": "PENDIENTE", "creadaEn": "…", "decididaPor": null, "decididaEn": null, "comentario": null
}]
```
Errores: `400 DATOS_INVALIDOS` · `401` · `403`.

### POST /sugerencias/{id}/aprobar · 502
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente` (sus obras; sin `CONTROL_COBROS`). Recibe `{ "comentario": "opcional, hasta 300 caracteres" }`. Devuelve `200` con la sugerencia (`APROBADA`, `decididaPor` = `sub`, `decididaEn`). Solo registra la decisión: no llama a otros servicios ni publica eventos.
Errores: `404 SUGERENCIA_NO_ENCONTRADA` (también si no puede verla) · `409 SUGERENCIA_YA_DECIDIDA` · `422 COMENTARIO_INVALIDO` (`errores[]` con `campo` = `comentario` y la regla en `mensaje`) · `401` · `403`.

### POST /sugerencias/{id}/rechazar · 502
Mismos roles. Recibe `{ "motivo": "10 a 500 caracteres" }`. Devuelve `200` (`RECHAZADA`; el motivo queda en `comentario`).
Errores: `404 SUGERENCIA_NO_ENCONTRADA` · `409 SUGERENCIA_YA_DECIDIDA` · `422 MOTIVO_INVALIDO` (`errores[]` con `campo` = `motivo`) · `401` · `403`.

### Herramientas MCP (capa 5, solo lectura) · 501
Ruta: `POST /mcp` (MCP, HTTP «streamable», sin estado, respuestas JSON; versión común 2025-11-25) · Rol: `agente_ia` (*service account* de `ia-agentes`) · Solo lo llama el servicio de IA (`ia-worker`, host de los agentes)

- Sin token o inválido: `401 NO_AUTENTICADO`; token válido sin `agente_ia` (también `gerente` o `admin`): `403 SIN_PERMISO`; ningún endpoint REST acepta `agente_ia`. Solo `POST` (`GET` responde `405`; no hay sesión ni flujo SSE). Sin recursos ni *prompts*.
- Cada herramienta: solo lectura (`annotations: { readOnlyHint: true, openWorldHint: false }`), `inputSchema` y `outputSchema` con `additionalProperties: false`, `structuredContent` con la salida y el mismo JSON como texto en `content`; consulta con tiempo máximo de 5 s.
- Errores de herramienta (resultado con `isError: true` y texto JSON `{"codigo", "mensaje"}`): `ARGUMENTO_INVALIDO` (no cumple el esquema; no consulta la base), `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`. Una herramienta que no existe es un error del protocolo.
- Registro: una línea JSON por llamada con `herramienta`, `argumentos`, `filas`, `duracionMs` y `requestId` (`X-Request-Id` = id de la ejecución del agente); nunca el token.
- Montado en `ia-api`, con la lista de hosts permitidos `IA_MCP_HOSTS_PERMITIDOS` (con un `Host` que no está en la lista, el SDK responde `421`). `OBRA_NO_ENCONTRADA` si una obra pedida no está en `rpt_obra_resumen`.

| Herramienta | Entrada | Salida | Reglas |
|---|---|---|---|
| `riesgo_retraso` | `{obraIds?: uuid[1..50], niveles?: (BAJO\|MEDIO\|ALTO\|SIN_DATOS)[], limite?: 1..50 = 50}` | `{generadoEn, predicciones[{obraId, obraNombre, probabilidad, nivel, factores[{variable, descripcion, peso}], versionModelo, calculadaEn}], total, truncado}` | Obras `EN_EJECUCION` de `rpt_obra_resumen` con su última predicción (402); probabilidad descendente, `SIN_DATOS` al final. Sin modelo o sin predicciones: `[]` |
| `consumos_atipicos` | `{obraId?: uuid, estados?: (PENDIENTE\|NORMAL\|CONFIRMADO)[] = [PENDIENTE], dias?: 1..90 = 30, limite?: 1..50 = 50}` | `{consumos[{movimientoId, obraId, obraNombre, materialId, partidaId, cantidad, periodo, registradoEn, puntaje, motivos[], estadoRevision}], total, truncado}` | `ia_db.consumo_atipico` (403) de los últimos `dias` (La Paz); puntaje descendente; cada motivo hasta 200 caracteres. Solo lectura: la revisión la hace una persona |
| `consultar_reporte` | La receta de la 503 en modo `MCP`, en el primer nivel: `{conjunto, columnas?, filtros?, agruparPor?, metricas?, orden?, limite?: 1..50 = 20}` (filtros `obraId`, `materialId` y `clienteId` por id; sin `material` ni `cliente` por nombre; sin `NINGUNO`) | `{conjunto, titulo, aplicado[{nombre, valor}], columnas[{clave, titulo, tipo}], filas[[texto\|null]], totalFilas, truncado, avisos[]}` (las columnas `material` y `cliente` traen el id) | Mismo `validar_receta` y `MotorReportes` de la 503. `ARGUMENTO_INVALIDO` con hasta 5 problemas, cada uno con su ruta; `ERROR_INTERNO` si `reportes_db` o `ia_db` no responden o la consulta pasa de 5 s. El host limita los conjuntos de cada agente (502) |

### Carga inicial (401): lo que llama IA

Comando `ia-carga-inicial` (no es un endpoint). Con el token del cliente `ia-reportes` (*client credentials*, rol `gerente`), solo `GET`, 10 s por llamada y un reintento tras 1 s ante `5xx`, error de red o tiempo agotado; cada corrida manda su `cargaId` como `X-Request-Id`. En orden: Materiales `GET /materiales` (todas las páginas de a 100) → Obras `GET /obras` → por cada obra, Obras `GET /obras/{id}`, `GET /obras/{id}/planillas` y `GET /planillas/{id}` de cada una, Finanzas `GET /cobros?obraId=` (todas las páginas) y Materiales `GET /obras/{id}/movimientos?orden=registradoEn&direccion=asc` (todas las páginas; un `404 OBRA_NO_ENCONTRADA` se toma como «sin movimientos»).

### Reportes (503) y agentes (502): lo que llama IA

- **Materiales** `GET /materiales?pagina=N&tamano=100` (todas las páginas; `IA_MATERIALES_URL`) con el token del usuario que reenvía el gateway: nombres y unidades de los materiales en los reportes y el filtro `material`. Caché de 5 minutos, 3 s por llamada; no alimenta la base de reportes. Los nombres de los clientes los trae el gateway en `directorio.clientes` (IA no llama a Keycloak).
- **Modelo de lenguaje** (`IA_LLM_PROVEEDOR`): Ollama (`IA_OLLAMA_URL`; `qwen3:8b` por defecto) o la API de Anthropic (`IA_ANTHROPIC_API_KEY`; `claude-sonnet-5-5` por defecto). Con Anthropic, el texto del usuario y los datos delimitados salen a su API.
- **MCP** (solo `ia-worker`, host de los agentes): token de `ia-agentes` (*client credentials*, rol `agente_ia`; el secreto solo lo lee `ia-worker`), reutilizado hasta 30 s antes de vencer; encabezados `Authorization: Bearer …` y `X-Request-Id: <ejecucionId>`; 10 s por llamada; `tools/list` de cada servidor al iniciar cada ejecución (una herramienta que no está en el contrato, o con otro esquema, se ignora con una advertencia). Servidores: Obras `IA_OBRAS_MCP_URL`, Materiales `IA_MATERIALES_MCP_URL`, Finanzas `IA_FINANZAS_MCP_URL` e IA `IA_PROPIO_MCP_URL` (las herramientas de cada sección «Herramientas MCP» de arriba).
