# 403 · Diseño

## Qué hace el modelo

- **Modelo:** `sklearn.ensemble.IsolationForest` (scikit-learn 1). No necesita etiquetas: aprende cómo son las salidas habituales y aísla las que se separan del resto. Es ML clásico en CPU: no usa GPU ni modelo de lenguaje.
- **Datos:** se entrena con datos sintéticos y se reentrena con las salidas reales de `rpt_movimiento` cuando haya suficientes (sección «Entrenamiento»).
- **Unidad evaluada:** cada `SALIDA` de material, en el momento en que llega `MovimientoRegistrado`, comparada con el historial de salidas **anteriores** a ella.
- **Puntaje:** `puntaje = −score_samples(x)` (valor entre 0 y 1; más alto = más raro). **Atípica** si `predict(x) = −1`, con `contamination = 0,02` (decisión del equipo: se espera que alrededor del 2 % de las salidas merezca revisión).

## Variables (las mismas para entrenar y evaluar)

Función pura `calcular_variables_salida(salida, historial)` en `src/ia/atipicos/dominio/variables.py`. `historial` son las salidas anteriores de `rpt_movimiento` (401): las de la misma obra y material, y las del mismo material en todas las obras. El generador sintético usa la misma función.

| Variable | Cálculo |
|---|---|
| `log_cantidad` | `ln(1 + cantidad)` |
| `z_obra_material` | `(cantidad − mediana) / (1,4826 × MAD)` de las últimas 50 salidas de la misma obra y material; si hay menos de 5, se usan las del material en todas las obras; si aún hay menos de 5, 0. Recortado a [−10, 10] |
| `razon_material` | `cantidad / mediana` de las salidas del material en todas las obras (1 si no hay historial) |
| `razon_periodo` | consumo del periodo de la obra y material (incluida esta salida) / promedio mensual de los periodos anteriores (1 si no hay; máximo 10) |
| `hora_sin`, `hora_cos` | hora local (La Paz) de `registradoEn` en forma circular |
| `fuera_horario` | 1 si la hora local es antes de las 06:00 o desde las 20:00 (decisión del equipo) |
| `domingo` | 1 si es domingo (el sábado se trabaja; decisión del equipo) |
| `supera_stock` | 1 si la salida superó el stock (004) |
| `log_horas_anterior` | `ln(1 + horas desde la salida anterior del mismo material en la obra)`, máximo 720 h |
| `salidas_dia` | salidas del mismo material en la obra ese día (incluida esta) |

### Motivos (texto para la persona)

El Isolation Forest no explica sus decisiones, así que los motivos salen de reglas simples sobre las variables, usando los percentiles del entrenamiento guardados con el modelo (`percentiles.json`). Se muestran hasta 3, del más fuerte al más débil:

| Condición | Motivo |
|---|---|
| `z_obra_material ≥ p99` | «La cantidad es X veces la habitual de este material en la obra» |
| `razon_material ≥ p99` | «La cantidad es X veces la habitual de este material en todas las obras» |
| `razon_periodo ≥ p99` | «El consumo del mes ya es X veces el promedio mensual» |
| `fuera_horario = 1` | «Se registró fuera del horario habitual (HH:MM)» |
| `domingo = 1` | «Se registró en domingo» |
| `supera_stock = 1` | «Salió más material del que había en stock» |
| `salidas_dia ≥ p99` | «Hubo X salidas de este material el mismo día» |
| `log_horas_anterior ≤ p1` | «Salida muy seguida de la anterior (X minutos)» |
| ninguna | «Combinación poco habitual de cantidad, horario y frecuencia» |

## Datos sintéticos (`ml/atipicos/generar.py`)

Parámetros en `ml/atipicos/parametros.yaml` (decisión del equipo), semilla 2026:

1. 60 obras, 25 materiales, 12 meses por obra.
2. Cada material tiene una cantidad típica por salida (mediana log-uniforme entre 2 y 200 unidades); cada obra la escala por un factor uniforme entre 0,5 y 2.
3. Salidas normales: de 3 a 15 por semana por material activo; cantidad `LogNormal(ln(mediana_obra), 0,35)`; lunes a sábado; hora `Normal(10, 2,5)` recortada a 07:00–18:00; `supera_stock` con probabilidad 0,01.
4. **Anomalías inyectadas** (2 % de las salidas), de cuatro tipos en partes iguales: cantidad × 4 a 10; horario entre 21:00 y 05:00 o en domingo; ráfaga de 3 a 6 salidas del mismo material en una hora; `supera_stock` con cantidad × 2 o más.
5. Las salidas se recorren en orden de fecha y, para cada una, se calculan las variables con su historial anterior (≈ 50 000 salidas). Para que tarde segundos, el historial se mantiene por obra y material en memoria mientras se recorre (ventanas de las últimas 50 salidas), sin volver a filtrar toda la tabla en cada salida.
6. Salida: `ml/atipicos/datos/salidas_sinteticas.csv` (no se versiona) con la marca `anomalia` (solo para evaluar; el modelo no la usa).

## Entrenamiento (`ml/atipicos/entrenar.py`)

- División por obra 80 % / 20 %. El entrenamiento incluye las anomalías (como pasaría con datos reales, que nadie etiquetó).
- `IsolationForest(n_estimators=200, contamination=0.02, random_state=2026)`.
- **Tiempo y recursos:** generar y entrenar tarda segundos (objetivo: menos de 1 minuto entre los dos) en la computadora del equipo, **sin GPU**; igual al reentrenar con datos reales.
- Comandos:

```sh
uv run python -m ml.atipicos.generar --semilla 2026
uv run python -m ml.atipicos.entrenar --fuente sintetica --version ca-1.0.0
uv run python -m ml.atipicos.entrenar --fuente real --version ca-1.1.0      # requiere ≥ 500 salidas en rpt_movimiento
```

- Con `--fuente real` lee `rpt_movimiento` (solo salidas; incluye las que trajo la carga inicial de la 401) y calcula las variables en orden de fecha. No hay etiquetas: se reporta la proporción marcada y, si ya hay revisiones, la proporción de `CONFIRMADO` entre los revisados (precisión observada), como referencia.
- Artefactos en `modelos/consumos_atipicos/ca-1.0.0/`: `modelo.joblib`, `percentiles.json`, `metricas.json`, `parametros.yaml`. `modelos/consumos_atipicos/actual.txt` indica la versión que carga el servicio.
- `modelo.joblib` usa `pickle` por dentro: el servicio **solo** carga archivos de su propio repositorio, nunca archivos subidos o recibidos por la red.
- El script termina con error y no cambia `actual.txt` si no se cumplen las métricas mínimas.

## Métricas mínimas (decisión del equipo)

Sobre el 20 % de prueba sintético (con la marca `anomalia` solo para medir):

| Métrica | Mínimo |
|---|---|
| Sensibilidad (*recall*) de anomalías inyectadas | ≥ 0,70 |
| Precisión de las marcadas como atípicas | ≥ 0,50 |
| AUC-ROC usando el puntaje | ≥ 0,85 |
| Proporción marcada | entre 1 % y 3 % |

Con datos reales (`--fuente real`): proporción marcada ≤ 3 % (criterio 14).

## Detección en el servicio (`ia-worker`)

Al aplicar `MovimientoRegistrado` con `tipo = SALIDA` (401), en este orden:

1. Lee el historial anterior de `rpt_movimiento` (salidas con `registrado_en` anterior a la evaluada y otro `movimiento_id`) y calcula las variables.
2. Evalúa con el modelo de `actual.txt` (o `IA_MODELO_ATIPICOS_VERSION`). Si no hay modelo, registra el error y sigue sin detectar.
3. Si es atípica: `consumo_atipico` con `_id = movimientoId` y `$setOnInsert` (idempotente, criterio 4).
4. Transacción de PostgreSQL de la 401 (inbox, `rpt_movimiento`, `rpt_consumo_material`).
5. Después de confirmar, si fue atípica y la 402 está implementada: recalcula el riesgo de retraso de la obra (402, motivo `CONSUMO_ATIPICO`). Sin la 402, este paso no existe.

El historial excluye la propia salida aunque ya esté en `rpt_movimiento` (por ejemplo, si la trajo la carga inicial de la 401 y su evento llega después desde la cola): así nunca se compara consigo misma. Un evento ya aplicado (está en `evento_aplicado`) se confirma sin evaluar. Un reintento repite los pasos 1 a 3 sin duplicar.

### `ia_db.consumo_atipico`

| Campo | Tipo | Notas |
|---|---|---|
| _id | string | `movimiento_id` (ref Materiales) |
| obra_id | string | índice (`obra_id`, `estado_revision`, `registrado_en` descendente) |
| material_id | string | ref Materiales |
| partida_id | string | ref Obras |
| cantidad | decimal | |
| periodo | string | `AAAA-MM` |
| registrado_en | date | de la salida |
| puntaje | double | 0 a 1 |
| motivos | arreglo de string | 1 a 3 |
| variables | objeto | valores usados (para auditar) |
| version_modelo | string | `ca-1.0.0` |
| detectado_en | date | |
| estado_revision | string | `PENDIENTE`, `NORMAL`, `CONFIRMADO` |
| revisado_por | string | ref Keycloak |
| revisado_en | date | |
| comentario | string | |

## REST del servicio de IA

```
### GET /consumos-atipicos?obraId=&estado=&desde=&hasta= · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`
Recibe: `obraId` opcional (sin él, todas las obras visibles); `estado` opcional (`PENDIENTE`, `NORMAL`, `CONFIRMADO`); `desde`/`hasta` opcionales (fechas)
Devuelve: 200 [{
  "id": "uuid-del-movimiento", "movimientoId": "uuid", "obraId": "uuid", "materialId": "id", "partidaId": "uuid",
  "cantidad": 120.0, "periodo": "2026-11", "registradoEn": "2026-11-15T02:40:00Z",
  "puntaje": 0.71, "motivos": ["La cantidad es 4,2 veces la habitual de este material en la obra", "Se registró fuera del horario habitual (22:40)"],
  "estadoRevision": "PENDIENTE", "revisadoPor": null, "revisadoEn": null, "comentario": null,
  "versionModelo": "ca-1.0.0", "detectadoEn": "2026-11-15T02:40:03Z"
}]   (máximo 200, de la más reciente a la más antigua)
Errores: 400 (estado o fechas inválidos) · 404 OBRA_NO_ENCONTRADA (también si no la puede ver) · 401 · 403

### GET /consumos-atipicos/resumen?obraIds=a,b,c · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`
Devuelve: 200 [{ "obraId": "uuid", "pendientes": 2 }]   (solo obras visibles; las que no tienen pendientes vienen con 0 si se pidieron)
Errores: 400 DEMASIADAS_OBRAS (más de 100) · 401 · 403

### PUT /consumos-atipicos/{id}/revision · 403
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `residente` asignado a la obra
Recibe: { "estado": "CONFIRMADO", "comentario": "Se usó en la losa de otra obra sin registrarlo" }
Devuelve: 200 con el consumo atípico actualizado
Errores: 400 (estado `PENDIENTE` o desconocido) · 404 CONSUMO_ATIPICO_NO_ENCONTRADO · 409 REVISION_YA_REGISTRADA · 422 COMENTARIO_INVALIDO (falta en `CONFIRMADO` o fuera de 5 a 300 caracteres; `errores[]` con `campo` = `comentario` y la regla en `mensaje`) · 403 (por ejemplo `gerente`) · 401
```

- La revisión es una actualización atómica (`find_one_and_update` con filtro `estado_revision = PENDIENTE`); si no encuentra el documento pendiente pero sí existe, responde `409`.
- Una revisión `NORMAL` deja de contar en `atipicos_90d` (402) desde el siguiente cálculo (al día siguiente o con el próximo evento de la obra).

## Gateway

```graphql
enum EstadoRevision { PENDIENTE NORMAL CONFIRMADO }
type ConsumoAtipico {
  id: ID! movimientoId: ID! obraId: ID!
  materialId: ID! material: Material          # Materiales (GET /materiales, DataLoader)
  partidaId: ID! cantidad: Float! periodo: String! registradoEn: String!
  puntaje: Float! motivos: [String!]!
  estadoRevision: EstadoRevision!
  revisadoPor: Usuario                        # Keycloak (caché de 5 min, 006)
  revisadoEn: String comentario: String versionModelo: String!
}
extend type Obra { consumosAtipicos(estado: EstadoRevision): [ConsumoAtipico!] }        # IA
extend type FilaTablero { consumosAtipicosPendientes: Int }                              # IA, en lote
extend type IndicadoresTablero { consumosAtipicosPendientes: Int }                       # IA
extend type Mutation {
  revisarConsumoAtipico(id: ID!, estado: EstadoRevision!, comentario: String): ConsumoAtipico!   # 403 · admin, residente
}
```

- `FilaTablero.consumosAtipicosPendientes`: DataLoader que junta los `obraId` del tablero en llamadas a `GET /consumos-atipicos/resumen` de hasta 100 `obraId` cada una (más daría `400 DEMASIADAS_OBRAS`). `IndicadoresTablero.consumosAtipicosPendientes` suma ese mismo lote.
- La mutación no se reintenta; mapea `codigo` a `extensions.codigo`.
- IA caída: campos `null` con `SERVICIO_NO_DISPONIBLE` (`extensions.servicio = "ia"`).

## mf-obras

- Pestaña «Material» del detalle de obra (006): sección «Consumos atípicos» debajo de la comparación previsto/usado, con su propio manejo de error.
  - Tabla: fecha y hora, material (nombre), partida (código, tomado de las partidas que ya trae el detalle), cantidad con unidad, puntaje (barra), motivos y estado. Filtro por estado (por defecto `PENDIENTE`).
  - Botones «Es normal» y «Confirmar problema» (solo `residente` asignado y `admin`, y solo en `PENDIENTE`); diálogo con comentario (obligatorio al confirmar, contador 5 a 300).
  - Aviso «Este consumo ya fue revisado» ante `REVISION_YA_REGISTRADA` y recarga de la lista.
  - Texto de ayuda: «Detectado por comparación con el consumo habitual; es distinto de "excedido sobre lo previsto"».

## mf-supervision

- Tablero (009): tarjeta «Consumos atípicos por revisar» y columna «Atípicos» con los pendientes por obra (ordenable). Al pulsar el número se abre el detalle de la obra (`/obras/:id`) como el resto de la fila.

## Pruebas

- IA (dominio): `calcular_variables_salida` con historial vacío, corto (< 5) y largo; borde de horario (05:59, 06:00, 19:59, 20:00); domingo; motivos con percentiles fijos.
- IA (generador): reproducible con la semilla; 2 % de anomalías de los 4 tipos.
- IA (entrenamiento): artefactos escritos; falla sin tocar `actual.txt` si no se cumplen las métricas; `--fuente real` rechaza con menos de 500 salidas. Medición documentada en el README: generar y entrenar `ca-1.0.0` tarda menos de un minuto en CPU.
- IA (servicio): salida atípica crea `PENDIENTE`; salida normal no crea nada; ingreso no se evalúa; mismo evento dos veces deja un solo documento; una salida que ya trajo la carga inicial no se compara consigo misma; sin modelo la proyección sigue; recálculo de riesgo tras un atípico (y sin la 402, no se llama).
- IA (API): visibilidad por rol; filtros; revisión `CONFIRMADO` sin comentario (422), segunda revisión (409), `gerente` (403), revisión correcta guarda autor y fecha.
- Gateway: lote del resumen partido en grupos de 100; nombres de material y de revisor; mutación con mapeo de errores; IA caída.
- mf-obras: tabla con filtro, botones según rol y estado, diálogo y aviso de ya revisado.
- mf-supervision: tarjeta y columna, con datos parciales.

## Cambios a contratos y datos

Comprobado el 31/10/2026: el único evento que usa es `MovimientoRegistrado`, con los campos actuales de `docs/contratos/eventos.md` más `precioReferencial` (lo agrega Materiales en la 401; esta spec no lo necesita para detectar). No llama a endpoints de otros servicios salvo el gateway, que resuelve el nombre del material con `GET /materiales`.

### `docs/contratos/rest.md` (sección «IA (puerto 8085)») y `services/ia/docs/contratos.md`

- `GET /consumos-atipicos`, `GET /consumos-atipicos/resumen` y `PUT /consumos-atipicos/{id}/revision`, tal como en la sección «REST del servicio de IA».

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

- Los tipos y campos de la sección «Gateway» (`EstadoRevision`, `ConsumoAtipico`, `Obra.consumosAtipicos`, `FilaTablero.consumosAtipicosPendientes`, `IndicadoresTablero.consumosAtipicosPendientes`, `Mutation.revisarConsumoAtipico`).
- «Consume»: fila IA con `GET /consumos-atipicos`, `GET /consumos-atipicos/resumen`, `PUT /consumos-atipicos/{id}/revision`.

### `services/ia/docs/datos.md`

- Colección `consumo_atipico` de `ia_db` como en «`ia_db.consumo_atipico`».

### `docs/reglas-negocio.md` — «Material y stock»

- Agregar: «Consumo atípico (capa 4, 403): una salida que el modelo de detección de anomalías marca como rara frente al consumo habitual (alrededor del 2 % de las salidas; decisión del equipo). No bloquea nada; queda `PENDIENTE` hasta que el residente asignado o administración la marca `NORMAL` o `CONFIRMADO` (confirmar exige comentario). Es distinto del "consumo fuera de lo previsto" (> 1,20 × previsto)».

### `frontend/mf-obras/docs/contratos.md` y `frontend/mf-supervision/docs/contratos.md`

- mf-obras consume `obra.consumosAtipicos` y `revisarConsumoAtipico`; mf-supervision consume `tablero.obras.consumosAtipicosPendientes` y `tablero.indicadores.consumosAtipicosPendientes`.

### Eventos

Ninguno nuevo (usa `MovimientoRegistrado` con `precioReferencial`, de la 401).
