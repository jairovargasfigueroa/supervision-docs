# 505 · Diseño

## Visión general

```
mf-supervision (pantalla de reportes, ahora con conversación)
   │ consultarReporte(texto|atajo, conversacionId?)  ── GraphQL
gateway ── POST /consultas-reporte {texto|atajo, conversacionId?, directorio} ──► ia-api
                                                      │
   caché de recetas ─► (si no) interpretar con el modelo: RECETA | ACLARAR | NINGUNO
                       │  autocorrección (3 intentos) · reintentos pasajeros (2)
                       ▼
   validar receta (catálogo ampliado) ─► dudas del código (nombres ambiguos o inexistentes)
                       ▼                                   └─► ACLARACION con opciones reales
   SQL seguro en reportes_db (solo lectura) ─► resumen ─► REPORTE
   estado de la conversación en ia_db.conversacion_reporte (30 min)
```

Los agentes (502) siguen igual de forma, con límites más amplios, reintentos y un paso compuesto para el consumo contra lo previsto.

**Orden de implementación:** contratos y datos → Obras y Materiales (herramientas por lote) → IA → gateway → mf-supervision → infra (banco). Todo se despliega junto (release): el contrato de las herramientas cambia en los servidores y en el catálogo del host a la vez.

## IA: conversación en `POST /consultas-reporte` (amplía la 503)

### Pedido

```json
{ "texto": "¿Cuánto cemento se usó?", "conversacionId": "uuid", "directorio": { "clientes": [ … ] } }
{ "atajo": "COBROS_VENCIDOS", "conversacionId": null }
```

- Exactamente uno de `texto` o `atajo`, como hoy. `texto`: de 3 a 500 caracteres, o **de 1 a 500 si viene `conversacionId`** (para responder «sí», «IP-30»).
- `conversacionId` (opcional, uuid): continúa esa conversación. Sin él, empieza una nueva. Un atajo siempre empieza una nueva (y su receta queda como la última de la conversación, para poder ajustarla).

### Respuesta (200)

```json
{ "conversacionId": "uuid", "tipo": "REPORTE",    "consulta": { …ConsultaReporte de la 503… }, "aclaracion": null }
{ "conversacionId": "uuid", "tipo": "ACLARACION", "consulta": null,
  "aclaracion": { "pregunta": "«cemento» coincide con dos materiales. ¿Cuál?", "opciones": ["Cemento IP-30", "Cemento cola", "Todos"], "preguntasRestantes": 4 } }
```

- `consulta` tiene exactamente los campos de hoy (`id`, `texto`, `atajo`, `conjunto`, `tituloConjunto`, `receta`, `aplicado`, `resumen`, `resumenPlantilla`, `avisos`, `columnas`, `filas`, `totalFilas`, `truncado`, `creadaEn`).
- `opciones`: de 0 a 6 textos de hasta 60 caracteres.
- Errores: los de la 503, más `404 CONVERSACION_NO_ENCONTRADA` (no existe, expiró o es de otro usuario). `422 INTENCION_NO_RECONOCIDA` solo cuando, tras los intentos, no hay receta ni pregunta posible.
- Límite: **20 por minuto** por usuario (`IA_CONSULTAS_POR_MINUTO`, por defecto 20), contando cada turno y cada atajo.

### Estado: `ia_db.conversacion_reporte`

| Campo | Tipo | Notas |
|---|---|---|
| `_id` | string (uuid) | `conversacionId` |
| `usuario_id` | string | solo su dueño la continúa |
| `turnos` | array de `{rol: USUARIO\|ASISTENTE, texto, tipo: PEDIDO\|REPORTE\|ACLARACION\|NO_RECONOCIDO, en}` | máximo 20 (se guardan los últimos) |
| `receta` | object \| null | última receta **válida** (la que ajustan los seguimientos) |
| `preguntas` | int | aclaraciones hechas (tope 5) |
| `duda` | object \| null | pregunta del código pendiente: `{campo, termino, opciones}` |
| `aceptados` | array de string | términos que el usuario aceptó «tal cual» («Todos»): no se vuelven a preguntar |
| `creada_en`, `actualizada_en` | datetime | |
| `expira_en` | datetime | índice TTL; se renueva en cada turno (+30 min) |

`consulta_reporte` (503) agrega `conversacion_id` (string \| null).

### Flujo de un turno (`ConsultarReporte`, 50 s en total)

1. Límite por minuto. Cargar o crear la conversación (404 si no es del usuario o expiró).
2. **Atajo:** receta fija, como hoy (sin modelo). Ir al paso 6.
3. **Respuesta a una duda del código** (`duda` pendiente): si el texto coincide (sin mayúsculas ni tildes) con una opción, el código reemplaza el término por ese nombre exacto en la receta pendiente; si es «Todos», agrega el término a `aceptados`. Sin modelo. Ir al paso 5.
4. **Caché de recetas** (solo el primer turno de una conversación): clave = hash de `texto normalizado + fecha de hoy`; si existe, se usa esa receta (24 h, colección `receta_cache` con TTL). Si no, **interpretar** con el modelo:
   - Sistema: instrucciones + hoy + catálogo + **ejemplos** (fijo para aprovechar la caché del proveedor).
   - Usuario: `como_dato("conversacion", {recetaAnterior, turnos: últimos 10, pedido})`.
   - Salida (`RespuestaInterprete`, esquema estricto): `{accion: RECETA|ACLARAR|NINGUNO, receta: RecetaReporte|null, pregunta: string|null, opciones: string[]|null}`. Con 5 preguntas hechas, el esquema y las instrucciones ya no ofrecen `ACLARAR`.
   - **Autocorrección:** si la receta no valida, se devuelve al modelo con los errores (`errores[{campo, mensaje}]`), hasta **3 intentos**. Una salida ilegible también cuenta como intento.
   - `ACLARAR` → respuesta `ACLARACION` (cuenta una pregunta). `NINGUNO` → `422 INTENCION_NO_RECONOCIDA`.
5. **Validar** la receta (503, con el catálogo ampliado).
6. **Dudas del código** (antes de consultar; solo en modo REST, con preguntas restantes): para cada filtro de texto `obra`, `cliente` o `material` (`CONTIENE` o cada valor de `EN`) cuyo campo no esté en `agruparPor` ni en las columnas, y cuyo término no esté en `aceptados`:
   - Coincide con **varios** nombres distintos → `ACLARACION`: «"{término}" coincide con varios {materiales|clientes|obras}. ¿Cuál?», opciones = hasta 5 nombres + «Todos».
   - No coincide con **ninguno** y hay nombres parecidos (`difflib`, corte 0,6) → `ACLARACION`: «No encontré "{término}". ¿Quisiste decir…?», opciones = hasta 5 nombres + «Ninguno». Sin parecidos, sigue (reporte vacío con aviso).
   - La duda queda en `duda`; la receta, en `receta` pendiente.
7. **Motor** (SQL seguro, como la 503) y **resumen** (modelo con plantilla de respaldo).
8. Guardar `consulta_reporte`, la receta en la conversación y la caché; responder `REPORTE`.

### Instrucciones nuevas para el modelo (interpretar)

- Arma la receta cuando puedas. Usa los valores por defecto para lo que falte (por ejemplo, el periodo) y no preguntes por eso.
- Pregunta (`ACLARAR`) solo si el pedido es vago o tiene interpretaciones muy distintas. Una sola pregunta, corta, con opciones concretas tomadas del catálogo o de las palabras del usuario.
- Si hay `recetaAnterior` y el pedido es un ajuste («y en…», «solo…», «ahora por…»), modifica esa receta.
- Si el usuario respondió una pregunta, combina la respuesta con su pedido original.
- Si no es un reporte posible con el catálogo, `NINGUNO`.

### Ejemplos en las instrucciones

Entre 8 y 12 pares «pedido → respuesta JSON» (los de `ejemplos` del catálogo más casos de filtros nuevos, seguimiento y aclaración). Una prueba comprueba que **cada ejemplo valida** con `validar_receta`.

## IA: catálogo ampliado

Los nombres de los filtros siguen en *camelCase*, como hoy. Los operadores son los de la 503 (`IGUAL`, `EN`, `CONTIENE`, `DESDE`, `HASTA`): `DESDE` y `HASTA` sirven también para números (≥ y ≤).

| Cambio | Detalle |
|---|---|
| `obra`, `cliente`, `material` | `CONTIENE` y **`EN`** (lista de 1 a 20 textos; cada uno por «contiene»; se unen) |
| Filtros numéricos (`DESDE`/`HASTA`, valor `V_NUMERO`) | Obras: `avancePct`, `plazoPct`, `diferencia`, `riesgoPct`, `montoContrato`, `plazoDias` y los nuevos de abajo · Cobros: `monto`, `diasParaVencer` · Planillas: `neto`, `vecesObservada`, `avancePeriodoPct` · Movimientos: `cantidad` |
| Filtros de fecha (`DESDE`/`HASTA`) | Obras: `fechaInicio` · Cobros: `emitidoEn`, `venceEn`, `pagadoEn` (además de los que ya hay) |
| Datos de la obra en los demás conjuntos | `nivelRiesgo` (`IGUAL`/`EN`) y `soloEnRiesgo` en Material usado, Movimientos, Cobros y Planillas (por la obra unida) |
| Obras: campos nuevos (columna, medida con `GENERALES` y filtro numérico) | `planillas_observadas` (`rpt_planilla` en `OBSERVADA`), `planillas_aprobadas`, `cobros_vencidos` (cantidad en `VENCIDO`), `monto_vencido`, `monto_por_cobrar` (`PENDIENTE` + `VENCIDO`), `salidas_sin_stock` (`rpt_movimiento.supera_stock`); subconsultas escalares por obra. Filtros: `planillasObservadas`, `planillasAprobadas`, `cobrosVencidos`, `montoVencido`, `montoPorCobrar`, `salidasSinStock` |

El SQL lo sigue armando solo `constructor_sql.py`, con valores enlazados, y lo ejecuta el usuario de solo lectura.

## IA: modelo de lenguaje

- **Reintentos pasajeros:** `LlmNoDisponible` lleva `reintentable` (Anthropic: conexión, 429, 5xx y 529; Ollama: conexión). Un envoltorio `ModeloConReintentos` reintenta hasta 2 veces (esperas de 1 y 3 s, recortadas al tiempo que quede). Lo usan el constructor y los agentes.
- **Caché del proveedor (Anthropic):** el mensaje de sistema va como bloque con `cache_control: {type: "ephemeral"}`. Los registros anotan `cache_read_input_tokens`.

## IA: agentes (amplía la 502)

| Cambio | Detalle |
|---|---|
| Límites | `llamadas` 15, `vueltas` 8, `bucle_s` 200, `total_s` 240, `llm_s` 60 |
| Herramienta que falla (`FalloMcp`) | 1 reintento tras 1 s antes de marcar el servidor como caído |
| Reporte | hasta 3 intentos con los errores |
| Argumentos con `$periodo_actual` | en los pasos iniciales, se reemplaza por el periodo actual de La Paz |
| Paso compuesto `consumo_vs_previsto` (Control de materiales) | Llama `avance_obra {periodo}` y `consumos_partida {periodo}` (2 llamadas, 2 pasos) para todas las obras; el código cruza obra + partida + material y entrega al modelo solo: `excesos[{obraId, obraNombre, partidaId, materialId, material, previsto, usado, porcentaje}]` (usado > 1,20 × previsto) y `salidasSinStock[{obraId, obraNombre, partidaId, material, salidasSuperanStock}]`, hasta 30 filas de cada uno, con `truncado`. Evidencia del hallazgo: `consumos_partida` |
| Instrucciones | «Si algo no se pudo revisar (herramienta caída, límite, datos recortados), dilo en el resumen.» |

Pasos iniciales de Control de materiales: `stock_obra {estados: [BAJO, JUSTO]}`, `consumos_atipicos {}`, `consumo_vs_previsto {periodo: $periodo_actual}`.

## Obras: `avance_obra` por lote (501)

- `periodo` **sin** `obraId` deja de ser error: devuelve las obras `EN_EJECUCION` (hasta 50, mismo orden) **con** `partidas` y `materialPrevisto` del periodo, como hoy con una obra.
- Para no crecer de más: en el lote, cada partida trae solo `partidaId`, `codigo`, `nombre` y `materialPrevisto[{materialId, cantidadPrevista}]` (las que no tienen material previsto se omiten).
- Sin `periodo`, igual que hoy (`partidas: null`).
- Esquema de entrada sin cambios (los dos campos ya son opcionales).

## Materiales: `consumos_partida` por lote (501)

- `obraId` pasa a **opcional**; `periodo` sigue obligatorio. Sin `obraId`: filas de todas las obras con consumo en el periodo, cada una con `obraId` y `obraNombre`; hasta 500 filas, con `truncado`.
- Salida sin `obraId`: `{obraId: null, periodo, cerrado: null, filas[{obraId, obraNombre, partidaId, materialId, codigo, nombre, unidad, usado, salidas, salidasSuperanStock}], truncado}`. Con `obraId`, igual que hoy (las filas agregan `obraId` y `obraNombre`).
- El catálogo de contrato del host (IA) cambia `obraId` a opcional a la vez (`coincide` compara los obligatorios).

## Gateway

```graphql
enum TipoRespuestaReporte { REPORTE ACLARACION }
type AclaracionReporte { pregunta: String! opciones: [String!]! preguntasRestantes: Int! }
type RespuestaReporte { conversacionId: ID! tipo: TipoRespuestaReporte! consulta: ConsultaReporte aclaracion: AclaracionReporte }
# Mutation (cambia el tipo de retorno y agrega conversacionId)
consultarReporte(texto: String, atajo: AtajoReporte, conversacionId: ID): RespuestaReporte!
```

- Sigue exigiendo exactamente uno de `texto` o `atajo`, agrega el `directorio` y quita `receta` de `consulta`.
- `CONVERSACION_NO_ENCONTRADA` (404) pasa tal cual en `extensions.codigo`.
- Tiempo máximo sin cambios (60 s).

## mf-supervision: la misma pantalla de reportes, con conversación

- La pantalla guarda la **lista de turnos** de la conversación actual y el `conversacionId`. Cada turno del usuario se muestra como su pedido; cada respuesta, como **reporte** (el `ResultadoReporte` de hoy) o como **pregunta** con sus **opciones en botones**.
- El campo de pedido (con el dictado) queda abajo de la conversación. Con conversación abierta acepta respuestas desde 1 carácter.
- Botón **«Nueva consulta»**: borra la conversación de la pantalla. Los reportes comunes empiezan una conversación nueva.
- `CONVERSACION_NO_ENCONTRADA` → aviso «La conversación expiró: vuelve a hacer el pedido» y conversación nueva.
- Exportación: **Excel, CSV, PDF y Word** en cada reporte. PDF con `jspdf` 4 y `jspdf-autotable` 5; Word con `docx` 9; cargados al pulsar (`import()`), fuera de lo compartido con el shell (`skipList`), como `xlsx`. El archivo lleva título, pedido, lo que entendí, resumen, avisos, la tabla y la fecha; nombre `reporte-<conjunto>-AAAA-MM-DD-HHmm.pdf|docx`.
- El historial sigue igual (vuelve a pedir el mismo texto).

## Infra: banco de preguntas

- `infra/pruebas/banco-ia.mjs --entorno <archivo .env> [--agentes]`: ~40 pedidos en categorías (claros, difíciles, ambiguos, seguimientos, fuera de tema, maliciosos) contra `IA_URL` con el token de `gerente1`. En las aclaraciones elige la primera opción (hasta 5). Imprime por categoría: reporte, aclaraciones, rechazo, error y tiempo, y si cumple las metas. Con `--agentes`, ejecuta los tres agentes y resume estado, tiempo, pasos y hallazgos.
- Gasta saldo del modelo: se corre a mano, no en el CI.

## Pruebas

- **IA (pytest):** conversación (nueva, continuar, expirada y de otro usuario: 404; tope de 5 preguntas; seguimiento que ajusta la receta), dudas del código (varios, ninguno con parecidos, «Todos», opción elegida), autocorrección (receta inválida → corregida en el 2.º intento; 3 fallos → 422), caché de recetas, reintentos pasajeros (sí con 529 y conexión; no con 400), filtros nuevos y campos cruzados de Obras (SQL con valores enlazados), ejemplos válidos, agentes (límites nuevos, reintento MCP, paso compuesto con excesos y salidas sin stock, `$periodo_actual`). Las de seguridad (504) siguen pasando.
- **Obras (IT):** `avance_obra` con `periodo` sin `obraId` (lote con partidas y material previsto). **Materiales (e2e):** `consumos_partida` sin `obraId`.
- **Gateway (Vitest y e2e):** `RespuestaReporte` con reporte y con aclaración, `conversacionId` reenviado, `receta` quitada, `CONVERSACION_NO_ENCONTRADA`.
- **mf-supervision (Vitest):** conversación (pregunta con opciones → pulsar → reporte; seguimiento; nueva consulta; expirada), respuesta de 1 carácter, PDF y Word generados.
- **A mano, con el modelo real:** el banco de preguntas y los tres agentes contra un despliegue.

## Cambios a contratos y datos

- `docs/contratos/rest.md`: `POST /consultas-reporte` (pedido y respuesta nuevos, `CONVERSACION_NO_ENCONTRADA`, 20 por minuto); `avance_obra` (lote con `periodo`) y `consumos_partida` (`obraId` opcional, `obraNombre`).
- `docs/contratos/graphql-erp.md`, `gateway/docs/contratos.md` y `frontend/mf-supervision/docs/contratos.md`: `RespuestaReporte`, `AclaracionReporte`, `TipoRespuestaReporte` y la mutación.
- `services/ia/docs/datos.md`: `conversacion_reporte`, `receta_cache` y `consulta_reporte.conversacion_id`. `services/ia/docs/contratos.md`: el endpoint y los filtros nuevos del catálogo.
- `services/obras/docs/contratos.md` y `services/materiales/docs/contratos.md`: las dos herramientas.
- `docs/mensajes.md`: `CONVERSACION_NO_ENCONTRADA` y los textos de la conversación («Nueva consulta», «La conversación expiró: vuelve a hacer el pedido»).
- `docs/stack.md` y `frontend/mf-supervision/docs/estructura.md`: `jspdf` 4.2, `jspdf-autotable` 5.0 y `docx` 9.15 (MIT), solo en mf-supervision, para exportar.
- `docs/specs/503-reportes-voz/requisitos.md`: la conversación deja de estar fuera del alcance (la hace la 505).
- `docs/plan.md`: fila de la 505.
