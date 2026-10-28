# 402 · Riesgo de retraso por obra (ML supervisado)

**Estado:** borrador · **Capa:** 4 (Datos y predicciones) · **Punto:** 11 (supervisado) · **Proyectos:** services/ia, gateway, mf-supervision, mf-obras

**Depende de:** 401 (servicio de IA y base de reportes).

## Historia

Como **gerente** (y residente o administración) quiero ver, para cada obra en ejecución, la probabilidad de que termine con retraso según un modelo entrenado y las razones principales, para actuar antes de que el atraso sea evidente.

## Criterios de aceptación

### Predicción

1. Para cada obra `EN_EJECUCION` con al menos 5 % de plazo transcurrido, el servicio de IA calcula la **probabilidad de retraso** (0 a 100 %) con un modelo XGBoost y la clasifica en `BAJO` (< 30 %), `MEDIO` (30 % a < 60 %) o `ALTO` (≥ 60 %) (umbrales: decisión del equipo).
2. Las obras con menos de 5 % de plazo transcurrido, o sin contrato registrado, se muestran como «Sin datos suficientes» (`SIN_DATOS`).
3. Cada predicción trae hasta 3 **factores** que más suben el riesgo, en palabras simples (por ejemplo «El ritmo de avance de los últimos meses es menor al necesario para terminar a tiempo»).
4. La predicción se recalcula cuando se aprueba u observa una planilla de la obra, cuando se detecta un consumo atípico en ella (403) y todos los días a la 01:00 (hora de La Paz).
5. Se guarda el historial de predicciones de cada obra con la versión del modelo y la fecha de cálculo.

### Tablero (mf-supervision)

6. CUANDO el usuario abre Supervisión (009), ENTONCES ve un quinto indicador «Riesgo alto (modelo)» con el número de obras en nivel `ALTO`, y en la tabla una columna «Riesgo (modelo)» con el porcentaje y el nivel en color; la columna se puede ordenar.
7. La etiqueta «En riesgo» de la regla actual (plazo − avance > 10 puntos) se mantiene y se muestra junto al riesgo del modelo; son dos señales distintas.
8. CUANDO el usuario abre «Riesgo de retraso», ENTONCES ve las obras ordenadas de mayor a menor probabilidad con nivel, factores y fecha de cálculo; al elegir una ve el historial de su probabilidad en un gráfico simple.
9. La pantalla «Riesgo de retraso» muestra la versión del modelo, la fecha de entrenamiento, sus métricas y el aviso «Modelo entrenado con datos sintéticos; es una estimación de apoyo, no reemplaza la revisión de la obra».

### Detalle de obra (mf-obras)

10. CUANDO se abre una obra (006), ENTONCES el encabezado muestra «Riesgo de retraso (modelo): ALTO · 72 %» con sus factores al pasar el cursor, o «Sin datos suficientes».

### Permisos y fallos

11. Ven el riesgo `admin`, `gerente` y `residente` (este solo de sus obras). El cliente no lo ve.
12. SI el servicio de IA no responde, ENTONCES el riesgo del modelo se muestra como «—» con el aviso «Datos de IA no disponibles» y el resto del tablero y del detalle se ve normal (009, criterio 5).

### Modelo

13. El modelo se entrena con **datos sintéticos** generados por un script documentado y reproducible (misma semilla, mismos datos), porque la constructora no tiene historial real de obras terminadas.
14. El modelo cumple las métricas mínimas de `diseno.md` y supera a la regla actual (plazo − avance > 10) en el mismo conjunto de prueba; si no, no se publica.
15. Las variables del modelo se calculan solo con datos de la base de reportes (401), las mismas para entrenar y para predecir.

## Fuera del alcance

- Reentrenar automáticamente con obras reales terminadas (no hay transición a `CONCLUIDA`).
- Predecir la fecha exacta de término o el monto del retraso.
- Avisos por correo o notificaciones (los agentes de la capa 5 usan la predicción).
- Cambiar la regla «obra en riesgo» de Obras.
