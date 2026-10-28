# 402 · Riesgo de retraso · tareas de `services/ia`

Requisitos y diseño: `docs/specs/402-riesgo-retraso/` de esta carpeta. Requiere la 401 terminada. Contratos: `docs/contratos.md` de este proyecto.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Agregar `xgboost` 3, `scikit-learn` 1, `pandas` 3, `numpy` 2 y `pyyaml` 6 al `pyproject.toml`
- [ ] `riesgo/dominio/variables.py`: `calcular_variables(estado_obra, hoy)`, textos de factores y niveles; pruebas con casos fijos
- [ ] Generador `ml/riesgo/generar.py` con `parametros.yaml` y semilla 2026; pruebas de reproducibilidad y proporción de retrasadas
- [ ] `ml/riesgo/entrenar.py`: división por obra, búsqueda de hiperparámetros, línea base de la regla, métricas mínimas y artefactos en `modelos/riesgo_retraso/rr-1.0.0/`; entrenar y versionar `rr-1.0.0`
- [ ] Carga del modelo y predicción con factores (`pred_contribs`); colección `prediccion` con índice único por `clave`; pruebas
- [ ] Disparadores en el worker (tras `PlanillaAprobada`, `PlanillaObservada`, `ContratoRegistrado`) y tarea diaria de la 01:00; actualización de `rpt_obra_resumen`; pruebas
- [ ] Endpoints `GET /predicciones`, `GET /obras/{obraId}/prediccion` y `GET /modelos/riesgo-retraso` con visibilidad y errores; pruebas
- [ ] Notebook `ml/riesgo/exploracion.ipynb` con la curva ROC y la importancia de variables para el documento
