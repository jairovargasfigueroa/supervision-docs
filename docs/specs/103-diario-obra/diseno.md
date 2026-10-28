# 103 · Diseño

## Flujo

```
App (maestro): formulario → cola: ENTRADA_DIARIO { id, obraId, fecha, clima, texto }
App --POST /lotes--> Sincronización --POST /obras/{obraId}/diario { id, fecha, clima, texto }--> Obras → 201 (o 200 si el id ya existía)
App --GET /paquete-datos--> Sincronización --GET /obras/{id}/diario--> Obras   (solo si el token tiene rol maestro)
```

## Obras

### Dominio (hexagonal)

- Agregado `EntradaDiario` con `id`, `obraId`, `fecha`, `clima`, `texto`, `registradoPor`, `registradoEn`.
- `Clima`: `SOLEADO`, `NUBLADO`, `LLUVIA_LEVE`, `LLUVIA_FUERTE` (decisión del equipo).
- Reglas: texto de 10 a 2000 caracteres (sin contar espacios a los costados); `fecha ≤ hoy` en `America/La_Paz`; `fecha ≥ obra.fecha_inicio`; obra `EN_EJECUCION`.
- Caso de uso `RegistrarEntradaDiario`: si el `id` ya existe → devuelve el existente (`200`), aunque el cuerpo sea distinto; si existe otra entrada para la misma obra y fecha → `409`; si no, valida y guarda.

### Tabla `entrada_diario` (cambios)

- Agregar `registrado_en timestamptz` (momento en que el servidor la recibió).
- Restricción única (`obra_id`, `fecha`). Si dos entradas del mismo día llegan a la vez, la base rechaza la segunda y se responde `409 DIARIO_DIA_YA_REGISTRADO`.
- `clima` guarda uno de los cuatro valores.

### POST /obras/{obraId}/diario · 103

Roles: `maestro` asignado. Quién llama: Sincronización (con el token del maestro).

```json
{ "id": "uuid generado en el celular", "fecha": "2026-11-15", "clima": "LLUVIA_LEVE", "texto": "Se vació la losa del 2do piso. Lluvia por la tarde, se cubrió con nylon." }
```

Devuelve `201` (o `200` si el `id` ya existía):

```json
{ "id": "uuid", "obraId": "uuid", "fecha": "2026-11-15", "clima": "LLUVIA_LEVE", "texto": "…", "registradoPor": "uuid-keycloak", "registradoEn": "2026-11-15T23:10:00Z" }
```

Errores: `400` (formato; `errores[]` con `texto` o `clima`) · `403 SIN_PERMISO` (ve la obra pero no es `maestro`, por ejemplo el residente asignado) · `404 OBRA_NO_ENCONTRADA` (no existe o no la ve, por ejemplo un maestro no asignado) · `409 DIARIO_DIA_YA_REGISTRADO` · `422 OBRA_NO_EN_EJECUCION` · `422 FECHA_DIARIO_INVALIDA` (futura o anterior al inicio de la obra).

### GET /obras/{obraId}/diario?desde=&hasta= · 103

Roles: `maestro` y `residente` asignados, `admin`, `gerente`. Sin `desde`/`hasta`: últimos 30 días hasta hoy (La Paz). Máximo 366 días por consulta (`400 RANGO_INVALIDO`).

`[{ "id", "obraId", "fecha", "clima", "texto", "registradoPor", "registradoEn" }]`, de la fecha más reciente a la más antigua.

Errores: `404 OBRA_NO_ENCONTRADA` (también si el usuario no puede verla o es `cliente`).

## Sincronización

- Tipo `ENTRADA_DIARIO` en `POST /lotes`: `datos` = `{ id, obraId, fecha, clima, texto }`; llama a Obras `POST /obras/{obraId}/diario` con `{ id, fecha, clima, texto }`. `idOperacion` = `datos.id`.
- `GET /paquete-datos`: si el token tiene rol `maestro`, agrega a cada obra `"diario": [{ "id", "fecha", "clima", "texto" }]` con `GET /obras/{id}/diario` (últimos 30 días). Si Obras responde `403` o `404` para esa obra, se envía `diario: []`.

## App de obra

- Pantalla `obras/[id]/diario` (rol `maestro`), con acceso desde el detalle de la obra.
- Lista de los últimos 30 días: entradas del paquete más las operaciones `ENTRADA_DIARIO` de esa obra que no estén `ENVIADO` (marcadas «Sin enviar» o «Rechazada»).
- Formulario: selector de fecha (hoy y los 7 días anteriores, en hora de La Paz), clima con cuatro botones, texto con contador de caracteres.
- Antes de guardar, comprueba que no haya otra entrada de esa obra y fecha en el paquete ni en la cola (criterio 4).
- Corregir: solo si la operación está `PENDIENTE` (no `ENVIANDO`); se actualizan `datos` y `descripcion` en la misma fila, conservando el `id`.
- Descripción en «Pendientes de envío»: «Diario · 15/11 · Lluvia leve».
- Mensajes de rechazo por `codigo`: `DIARIO_DIA_YA_REGISTRADO` → «Ya existe una entrada del diario para ese día»; `FECHA_DIARIO_INVALIDA` → «La fecha no es válida para esta obra»; `OBRA_NO_EN_EJECUCION` → «La obra no está en ejecución».

## Pruebas

- Obras (dominio): texto en los bordes (9, 10, 2000, 2001 caracteres), fecha de hoy en La Paz cuando en UTC ya es mañana (por ejemplo 23:30 del 15 en La Paz = 03:30Z del 16), fecha futura, fecha anterior al inicio.
- Obras (API): mismo `id` dos veces → una sola fila y `200`; otro `id` en la misma fecha → `409`; maestro no asignado → `404`; residente asignado → `403 SIN_PERMISO`; obra no en ejecución → `422`; `GET` por rol (cliente recibe `404`), rango por defecto de 30 días.
- Sincronización: reparto de `ENTRADA_DIARIO`; `diario` en el paquete solo con rol `maestro`.
- App: bloqueo de dos entradas del mismo día (paquete y cola), edición solo en `PENDIENTE`, lista combinada.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/contratos/rest.md` y `services/obras/docs/contratos.md`

Obras: agregar `POST /obras/{obraId}/diario` y `GET /obras/{obraId}/diario` como arriba (códigos `DIARIO_DIA_YA_REGISTRADO`, `FECHA_DIARIO_INVALIDA`, `RANGO_INVALIDO`). Sincronización: tipo `ENTRADA_DIARIO` en `POST /lotes` y el campo `diario` por obra en `GET /paquete-datos`.

### `services/obras/docs/datos.md`

`entrada_diario`: agregar `registrado_en timestamptz`; `clima` con los valores `SOLEADO`, `NUBLADO`, `LLUVIA_LEVE`, `LLUVIA_FUERTE`; único (`obra_id`, `fecha`).

### `docs/reglas-negocio.md`

«Diario de obra (capa 1)»: agregar «Valores de clima: soleado, nublado, lluvia leve, lluvia fuerte (**decisión del equipo**). Texto de 10 a 2000 caracteres. La fecha no puede ser futura (hora de La Paz) ni anterior al inicio de la obra; la obra debe estar en ejecución. La app permite elegir hasta 7 días atrás (**decisión del equipo**). Una entrada enviada no se edita».

### `services/sincronizacion/docs/contratos.md`

Tipo `ENTRADA_DIARIO`; consume Obras `POST /obras/{obraId}/diario` y `GET /obras/{obraId}/diario`.

### `mobile/app-obra/docs/app.md`

Agregar la pantalla «Diario de obra (clima y texto del día)» · Maestro · Registrar entrada del diario · Capa 1.

### `docs/plan.md`

Agregar la fila de la funcionalidad 103 (obras, sincronizacion, app-obra).
