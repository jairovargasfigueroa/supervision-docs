# 402 · Diseño

## Qué predice el modelo

- **Etiqueta** (decisión del equipo): una obra «se retrasa» si termina después de `plazo_dias × 1,10` (más de 10 % de retraso sobre el plazo).
- **Momento de la predicción:** cualquier día de la obra entre 5 % y 100 % de plazo transcurrido; el modelo responde «¿con lo que se sabe hoy, qué probabilidad hay de que se retrase?».
- **Modelo:** clasificador binario `xgboost.XGBClassifier` (XGBoost 3), salida = probabilidad de la clase «se retrasa».

## Variables (las mismas para entrenar y predecir)

Se calculan en `src/ia/riesgo/dominio/variables.py` con una función pura `calcular_variables(estado_obra, hoy)`; `estado_obra` se arma con lo que hay en la base de reportes (401) y en `ia_db`. El generador sintético usa **la misma función** para que no haya diferencias entre entrenamiento y uso.

| Variable | Cálculo | Texto del factor (si sube el riesgo) |
|---|---|---|
| `plazo_pct` | `rpt_obra_resumen.plazo_pct` | «Ya transcurrió X % del plazo» |
| `avance_pct` | `rpt_obra_resumen.avance_pct` | «El avance es de solo X %» |
| `brecha` | `plazo_pct − avance_pct` | «El avance está X puntos por debajo del plazo transcurrido» |
| `ritmo_reciente` | promedio de `avance_periodo_pct` de las últimas 3 planillas aprobadas (puntos por mes; 0 si no hay) | «El avance mensual reciente es bajo (X puntos por mes)» |
| `ritmo_requerido` | `(100 − avance_pct) / max(meses_restantes, 0,5)`, con `meses_restantes = plazo_dias × (1 − plazo_pct/100) / 30,44` | «Para terminar a tiempo se necesitan X puntos por mes» |
| `relacion_ritmo` | `min(ritmo_reciente / ritmo_requerido, 3)` (3 si `ritmo_requerido` = 0) | «El ritmo de avance de los últimos meses es menor al necesario para terminar a tiempo» |
| `meses_sin_planilla` | meses entre el último periodo aprobado (o `fecha_inicio`) y el mes actual | «Hace X meses que no se aprueba una planilla» |
| `planillas_observadas` | Σ `rpt_planilla.veces_observada` de la obra | «Se observaron X planillas» |
| `atipicos_90d` | documentos de `consumo_atipico` (403) de la obra detectados en los últimos 90 días con estado distinto de `NORMAL` (0 si la 403 no está hecha) | «Hubo X consumos de material atípicos en los últimos 90 días» |
| `supera_stock_90d` | salidas con `supera_stock` en `rpt_movimiento` en los últimos 90 días | «Hubo X salidas de material sin stock suficiente» |
| `plazo_dias` | `rpt_obra_resumen.plazo_dias` | «El plazo de la obra es largo (X días)» |
| `log_monto` | `ln(monto_contrato)` | «La obra es de monto alto» |

## Datos sintéticos (`ml/riesgo/generar.py`)

La constructora no tiene historial de obras terminadas, así que se simulan obras completas mes a mes con reglas simples y documentadas. Parámetros en `ml/riesgo/parametros.yaml` (decisión del equipo), semilla 2026.

1. **Obras:** 4 000 obras. `plazo_dias` uniforme entre 90 y 720; `monto_contrato` log-uniforme entre Bs 100 000 y Bs 20 000 000; mes de inicio al azar.
2. **Factores ocultos por obra** (el modelo no los ve directamente):
   - eficiencia `e ~ Normal(1,0; 0,2)`, recortada a [0,4; 1,6];
   - problemas de material `p ~ Beta(2, 8)`;
   - propensión a observaciones `q ~ Beta(1,5; 8)`.
3. **Avance planificado:** curva S (logística) sobre los meses del plazo.
4. **Avance real por mes** = planificado × `e` × (1 − choque) × (1 − 0,15 × `p`), donde:
   - choque de lluvia con probabilidad 0,25 en diciembre a marzo y 0,08 en el resto, que reduce 30 % a 70 % el avance del mes;
   - los problemas de material generan, por mes, `Poisson(3p)` consumos atípicos y `Poisson(2p)` salidas sin stock.
5. **Planillas:** cada mes con avance se aprueba una planilla; con probabilidad `q` se observa primero y su avance se aprueba el mes siguiente (cuenta en `planillas_observadas` y en `meses_sin_planilla`).
6. Se sigue simulando después del plazo hasta llegar a 100 %: así se conoce la **fecha real de término** y la etiqueta.
7. **Cortes:** por obra se toman 3 días al azar con plazo transcurrido entre 5 % y 95 %; en cada corte se arma `estado_obra` con lo ocurrido hasta ese día y se llama a `calcular_variables`. Resultado ≈ 12 000 filas.
8. Salida: `ml/riesgo/datos/riesgo_sintetico.csv` (no se versiona; se regenera con el comando) y un resumen con la proporción de obras retrasadas (objetivo entre 25 % y 45 % para que el problema no quede desbalanceado; si no, se ajustan los parámetros y se documenta).

## Entrenamiento (`ml/riesgo/entrenar.py`)

- División por **obra** (`GroupShuffleSplit` de scikit-learn, 80 % / 20 %): los 3 cortes de una misma obra quedan del mismo lado.
- Búsqueda pequeña de hiperparámetros con validación cruzada por grupos (5 pliegues) sobre `max_depth ∈ {3, 4, 5}`, `learning_rate ∈ {0,05; 0,1}`, `n_estimators` hasta 600 con parada temprana (métrica `logloss`); `subsample = 0,8`, `colsample_bytree = 0,8`.
- **Línea base:** la regla actual de Obras usando `brecha` como puntaje (AUC) y `brecha > 10` como decisión (sensibilidad y precisión).
- **Explicación:** factores con las contribuciones por variable que da XGBoost (`predict(..., pred_contribs=True)`), sin librerías extra. Se muestran las 3 variables con mayor contribución positiva y valor > 0,05 en la escala del modelo.
- Comandos:

```sh
uv run python -m ml.riesgo.generar --obras 4000 --semilla 2026
uv run python -m ml.riesgo.entrenar --version rr-1.0.0
```

- Artefactos versionados en el repositorio (decisión del equipo; pesan menos de 1 MB) en `modelos/riesgo_retraso/rr-1.0.0/`:
  - `modelo.ubj` (formato nativo de XGBoost; no se usa `pickle`);
  - `variables.json` (orden de las variables y textos de los factores);
  - `metricas.json` (métricas del modelo y de la línea base, umbrales, filas, semilla, fecha);
  - `parametros.yaml` (copia de los parámetros del generador).
- `modelos/riesgo_retraso/actual.txt` indica la versión que carga el servicio. Versiones `rr-MAYOR.MENOR.PARCHE`.
- `entrenar.py` termina con error y no escribe `actual.txt` si no se cumplen las métricas mínimas.
- Notebook opcional `ml/riesgo/exploracion.ipynb` solo para gráficos (curva ROC, importancia de variables) del documento.

## Métricas mínimas (decisión del equipo)

Sobre el 20 % de prueba:

| Métrica | Mínimo |
|---|---|
| AUC-ROC | ≥ 0,80 |
| AUC-ROC del modelo − AUC-ROC de la regla (`brecha`) | ≥ 0,05 |
| Sensibilidad (*recall*) de «se retrasa» con probabilidad ≥ 0,30 (nivel `MEDIO` o más) | ≥ 0,80 |
| Precisión de «se retrasa» con probabilidad ≥ 0,60 (nivel `ALTO`) | ≥ 0,70 |
| Brier score | ≤ 0,18 |

Advertencia que se repite en la pantalla y en el documento: estas métricas muestran que el modelo aprende las relaciones simuladas; no prueban que acierte con obras reales.

## Cálculo en el servicio (`ia-worker`)

- Al iniciar, `riesgo/infraestructura/modelo_xgboost.py` carga la versión de `actual.txt` (o la de `IA_MODELO_RIESGO_VERSION` si está definida). Si no hay modelo, las predicciones quedan `SIN_DATOS` y se registra el error.
- **Disparadores** (criterio 4): después de aplicar `PlanillaAprobada`, `PlanillaObservada` o `ContratoRegistrado` de una obra, y después de registrar un consumo atípico (403); y la tarea diaria de la 01:00 (La Paz) para todas las obras `EN_EJECUCION`.
- La predicción se calcula **después** de confirmar la transacción del evento (necesita los datos ya actualizados). Si el cálculo falla, se registra el error y lo corrige la siguiente ejecución diaria; el evento no se reintenta por esto.
- Reglas de `SIN_DATOS`: obra `SIN_CONTRATO` o `plazo_pct < 5`.
- Nivel: `BAJO` < 0,30 ≤ `MEDIO` < 0,60 ≤ `ALTO`.
- Guarda un documento en `ia_db.prediccion` y actualiza `rpt_obra_resumen.riesgo_retraso`, `nivel_riesgo` y `actualizado_en`.

### `ia_db.prediccion`

| Campo | Tipo | Notas |
|---|---|---|
| _id | ObjectId | |
| clave | string | único: `{obraId}:{eventoId}` o `{obraId}:diario:{AAAA-MM-DD}` (idempotencia) |
| obra_id | string | índice (`obra_id`, `calculada_en` descendente) |
| riesgo_retraso | double | probabilidad 0 a 1; null si `SIN_DATOS` |
| nivel | string | `BAJO`, `MEDIO`, `ALTO`, `SIN_DATOS` |
| factores | arreglo de `{ variable, descripcion, peso }` | hasta 3 |
| variables | objeto | valores usados (para auditar) |
| version_modelo | string | `rr-1.0.0` |
| motivo | string | `PLANILLA_APROBADA`, `PLANILLA_OBSERVADA`, `CONTRATO_REGISTRADO`, `CONSUMO_ATIPICO`, `DIARIO` |
| calculada_en | date | |

## REST del servicio de IA

```
### GET /predicciones?obraIds=a,b,c · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`
Recibe: hasta 100 ids separados por coma
Devuelve: 200 [{
  "obraId": "uuid", "probabilidad": 0.72, "nivel": "ALTO",
  "factores": [{ "variable": "relacion_ritmo", "descripcion": "El ritmo de avance de los últimos meses es menor al necesario para terminar a tiempo", "peso": 0.81 }],
  "versionModelo": "rr-1.0.0", "calculadaEn": "2026-11-15T05:00:00Z"
}]
Solo las obras visibles para el usuario que tengan predicción; las demás se omiten. Con `SIN_DATOS`: "probabilidad": null, "factores": [].
Errores: 400 DEMASIADAS_OBRAS (más de 100) · 401 · 403

### GET /obras/{obraId}/prediccion?historial=30 · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente` (que pueda ver la obra)
Devuelve: 200 { …mismo objeto…, "historial": [{ "probabilidad": 0.65, "calculadaEn": "…" }] }   (historial de 1 a 90, por defecto 30, del más antiguo al más reciente)
Errores: 404 OBRA_NO_ENCONTRADA (también si no la puede ver) · 401 · 403

### GET /modelos/riesgo-retraso · 402
Servicio: IA · Quién llama: Gateway · Roles: `admin`, `gerente`, `residente`
Devuelve: 200 {
  "versionModelo": "rr-1.0.0", "entrenadoEn": "2026-11-20T15:00:00Z", "datos": "SINTETICOS", "filasEntrenamiento": 9600,
  "metricas": { "aucRoc": 0.86, "aucRocRegla": 0.74, "recallMedio": 0.83, "precisionAlto": 0.74, "brier": 0.14 },
  "umbrales": { "medio": 0.30, "alto": 0.60 },
  "variables": [{ "nombre": "relacion_ritmo", "descripcion": "Ritmo reciente / ritmo necesario" }]
}
Errores: 503 MODELO_NO_DISPONIBLE · 401 · 403
```

Las consultas leen MongoDB y `reportes_db`; no se calcula nada en la petición (responden en milisegundos, muy por debajo de los 3 s del gateway).

## Gateway

- Cliente REST `ia.client.ts` con `IA_URL` (por defecto `http://localhost:8085`), mismo tiempo máximo (3 s) y reintento de consultas que los demás.
- Esquema:

```graphql
enum NivelRiesgo { BAJO MEDIO ALTO SIN_DATOS }
type FactorRiesgo { variable: String! descripcion: String! peso: Float! }
type RiesgoRetraso {
  probabilidad: Float  nivel: NivelRiesgo!  factores: [FactorRiesgo!]!
  versionModelo: String  calculadaEn: String
}
type PuntoRiesgo { probabilidad: Float! calculadaEn: String! }
type MetricasModeloRiesgo { aucRoc: Float! aucRocRegla: Float! recallMedio: Float! precisionAlto: Float! brier: Float! }
type VariableModelo { nombre: String! descripcion: String! }
type ModeloRiesgo {
  versionModelo: String! entrenadoEn: String! datos: String! filasEntrenamiento: Int!
  metricas: MetricasModeloRiesgo! umbralMedio: Float! umbralAlto: Float! variables: [VariableModelo!]!
}
extend type Obra {
  riesgoRetraso: RiesgoRetraso                        # IA; null con SERVICIO_NO_DISPONIBLE si no responde
  historialRiesgo(limite: Int = 30): [PuntoRiesgo!]   # IA
}
extend type FilaTablero { riesgoRetraso: RiesgoRetraso }          # IA, en lote
extend type IndicadoresTablero { obrasRiesgoAlto: Int }           # IA; null si no responde
extend type Query { modeloRiesgo: ModeloRiesgo }                  # IA · 402 · admin, gerente, residente
```

- `FilaTablero.riesgoRetraso`: **DataLoader** que junta los `obraId` del tablero en llamadas a `GET /predicciones` de hasta 100 `obraId` cada una (el servicio rechaza más con `400 DEMASIADAS_OBRAS`; con 230 obras, 3 llamadas en paralelo). Si una obra no viene en la respuesta, se devuelve `{ nivel: SIN_DATOS, factores: [] }`.
- `IndicadoresTablero.obrasRiesgoAlto`: cuenta las filas del tablero con nivel `ALTO` usando el mismo lote.
- `Obra.riesgoRetraso` e `historialRiesgo`: una sola llamada a `GET /obras/{id}/prediccion` (DataLoader por petición). Para el rol `cliente` el ERP no aplica (no entra al ERP).
- Si IA no responde: esos campos `null` con `extensions.codigo = "SERVICIO_NO_DISPONIBLE"` y `extensions.servicio = "ia"`; el resto llega.

## mf-supervision

- Tablero (009): quinta tarjeta «Riesgo alto (modelo)»; columna «Riesgo (modelo)» con chip de color (`BAJO` verde, `MEDIO` amarillo, `ALTO` rojo, `SIN_DATOS` gris «Sin datos») y porcentaje; ordenable. «En riesgo» (regla) se mantiene en su columna.
- Pantalla `/supervision/riesgo` (enlace en el menú interno):
  - Lista con la misma consulta `tablero { obras { … riesgoRetraso { … } } }`, ordenada por probabilidad.
  - Panel de la obra elegida: factores y gráfico de línea del historial (`obra(id) { historialRiesgo }`) hecho con SVG propio (sin librería de gráficos; decisión del equipo).
  - Panel «Sobre el modelo» con `modeloRiesgo` y el aviso del criterio 9.
- Avisos de datos parciales como en la 009 («Datos de IA no disponibles»).

## mf-obras

- Detalle de obra (006): en el encabezado, junto a «En riesgo», el texto del criterio 10 con los factores en un *tooltip*. Se pide `riesgoRetraso` en la consulta del encabezado; si viene `null` con error, se muestra «—».

## Pruebas

- IA (dominio): `calcular_variables` con casos fijos (sin planillas, con 1 y con 3 planillas, plazo vencido, `ritmo_requerido` = 0); niveles en los bordes 0,30 y 0,60; `SIN_DATOS`.
- IA (generador): misma semilla produce el mismo CSV (hash); proporción de retrasadas dentro del rango; las variables salen de `calcular_variables`.
- IA (entrenamiento): con un conjunto pequeño, el script escribe los 4 artefactos; falla y no toca `actual.txt` si no se cumplen las métricas (umbral forzado en la prueba).
- IA (servicio): carga del modelo y predicción de una fila conocida; idempotencia por `clave`; recalculo tras `PlanillaAprobada`; tarea diaria; endpoints con visibilidad (residente no ve obras ajenas), `DEMASIADAS_OBRAS`, `MODELO_NO_DISPONIBLE`.
- Gateway: lote de predicciones partido en grupos de 100 (100 obras → 1 llamada; 101 → 2); obra sin predicción → `SIN_DATOS`; IA caída → campos `null` con `SERVICIO_NO_DISPONIBLE` y tablero parcial.
- mf-supervision: chip por nivel, orden por riesgo, tarjeta, aviso de datos parciales, gráfico con 1 y con 30 puntos.
- mf-obras: encabezado con nivel, sin datos y con IA caída.

## Cambios a contratos y datos

### `docs/contratos/rest.md` (sección «IA (puerto 8085)») y `services/ia/docs/contratos.md`

- `GET /predicciones?obraIds=`, `GET /obras/{obraId}/prediccion?historial=` y `GET /modelos/riesgo-retraso`, tal como en la sección «REST del servicio de IA».

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

- Los tipos y campos de la sección «Gateway» (`NivelRiesgo`, `FactorRiesgo`, `RiesgoRetraso`, `PuntoRiesgo`, `MetricasModeloRiesgo`, `VariableModelo`, `ModeloRiesgo`; `Obra.riesgoRetraso`, `Obra.historialRiesgo`, `FilaTablero.riesgoRetraso`, `IndicadoresTablero.obrasRiesgoAlto`, `Query.modeloRiesgo`).
- «Consume»: fila IA con `GET /predicciones`, `GET /obras/{id}/prediccion`, `GET /modelos/riesgo-retraso`; variable de entorno `IA_URL`.

### `services/ia/docs/datos.md`

- Colección `prediccion` de `ia_db` como en «`ia_db.prediccion`».
- `rpt_obra_resumen.riesgo_retraso` y `nivel_riesgo` (ya definidos en la 401) los escribe esta spec.

### `docs/reglas-negocio.md` — «Avance y plazo»

- Reemplazar «En la capa 4 se suma el riesgo de retraso que predice el modelo» por: «Capa 4 (402): además, el modelo da una probabilidad de retraso (más de 10 % sobre el plazo) con niveles `BAJO` < 30 %, `MEDIO` < 60 % y `ALTO` ≥ 60 % (decisión del equipo). Es una señal aparte: no cambia la etiqueta "En riesgo" de la regla. Sin predicción si la obra no tiene contrato o lleva menos de 5 % del plazo».

### `frontend/mf-supervision/docs/app.md`

- La fila «Riesgo de retraso por obra» apunta a la spec 402 (ruta `/supervision/riesgo`).

### `frontend/mf-supervision/docs/contratos.md` y `frontend/mf-obras/docs/contratos.md`

- Consume: `tablero.obras.riesgoRetraso`, `tablero.indicadores.obrasRiesgoAlto`, `obra.riesgoRetraso`, `obra.historialRiesgo`, `modeloRiesgo` (mf-supervision); `obra.riesgoRetraso` (mf-obras).

### Eventos

Ninguno nuevo (usa los de la 401).
