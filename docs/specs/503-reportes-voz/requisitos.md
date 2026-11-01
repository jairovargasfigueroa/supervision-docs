# 503 · Reportes generativos por voz (constructor de reportes)

**Estado:** aprobado (31/10/2026) · **Capa:** 5 (puntos 14 y 16) · **Proyectos:** services/ia, gateway, mf-supervision, infra · **Depende de:** 302 (dictado), 401 (base de reportes), 402 (riesgo de retraso) y 403 (consumos atípicos)

**Decisiones de Jairo (31/10/2026):**

- La lista cerrada de 7 reportes se reemplaza por un **constructor de reportes**: un **catálogo** de conjuntos de datos sobre la base de reportes (por conjunto: columnas, filtros, agrupaciones, métricas y orden permitidos). El modelo de lenguaje devuelve una **receta estructurada** (conjunto, columnas, filtros, agrupar por, métricas, orden, límite) que el código **valida contra el catálogo** y convierte en una consulta **parametrizada**. El modelo nunca escribe SQL.
- Además hay **reportes comunes predefinidos** (atajos con receta fija), que se piden con un botón, sin modelo de lenguaje para entender el pedido.
- Resultado: **tabla en pantalla + resumen corto** (lo redacta el modelo; si falla, una plantilla) y **exportación a Excel y CSV** generada en el navegador.
- El mismo motor lo usan los agentes por MCP (herramienta `consultar_reporte` del servidor MCP del servicio de IA, 501).
- El modelo de lenguaje se elige por configuración (Ollama local o la API de Anthropic) detrás de un puerto `ModeloLenguaje`; esta spec lo crea y la 502 lo reutiliza.
- Las consultas y el límite por minuto se guardan en MongoDB `ia_db`.

## Historia

Como **gerente o administración** quiero pedir un reporte hablando o escribiendo («¿cuánto cemento se usó en Las Palmas este trimestre?», «planillas observadas de la zona norte por cliente»), o con un botón de los reportes comunes, verlo en pantalla con un resumen corto y una tabla, y descargarlo en Excel o CSV, para no tener que armar consultas ni buscar pantalla por pantalla.

## Qué se puede consultar (catálogo)

Todo sale de la base de reportes de la 401 (que se actualiza con los eventos; el plazo y el estado de los cobros se recalculan una vez al día) y de los consumos atípicos de la 403. Detalle de columnas, filtros, agrupaciones y métricas en el diseño.

| Conjunto | Qué tiene | Se puede filtrar por | Se puede agrupar por |
|---|---|---|---|
| Obras | Avance, plazo, diferencia, «En riesgo», riesgo de retraso (402), monto de contrato | obra, zona, cliente, estado, nivel de riesgo, solo en riesgo | zona, estado, nivel de riesgo, cliente |
| Material usado | Cantidad, monto referencial y número de salidas | obra, zona, cliente, material, periodo | obra, zona, cliente, material, periodo |
| Movimientos de material | Ingresos y salidas, con la alerta «superó el stock» | obra, zona, cliente, material, tipo, solo los que superaron el stock, periodo, fecha | obra, zona, material, tipo, periodo |
| Cobros | Número, monto, emisión, vencimiento, estado, días para vencer | obra, zona, cliente, estado, periodo de emisión, vencen en los próximos N días | obra, zona, cliente, estado, mes de emisión |
| Planillas | Aprobadas u observadas: periodo, neto, avance del periodo, veces observada, último motivo | obra, zona, cliente, estado, periodo, fecha de aprobación | obra, zona, cliente, estado, periodo |
| Consumos atípicos (403) | Salidas marcadas como atípicas, con puntaje, motivos y revisión | obra, zona, cliente, material, estado de revisión, periodo, fecha | obra, zona, material, estado de revisión, periodo |

## Reportes comunes (atajos)

Avance y plazo de las obras en ejecución · Obras con riesgo de retraso alto o medio · Material usado este mes · Salidas que superaron el stock (últimos 3 meses) · Cobros vencidos · Cobros que vencen en los próximos 30 días · Total cobrado por obra este año · Planillas observadas · Planillas aprobadas (últimos 3 meses) · Consumos atípicos sin revisar.

## Criterios de aceptación

### Pedir el reporte

1. En Supervisión, vista «Reportes» (roles `admin` y `gerente`), CUANDO el usuario pulsa el micrófono y habla, ENTONCES la voz se convierte en texto **en el navegador** (componente de dictado de la 302) y el texto aparece en un cuadro editable.
2. Al servidor solo llega el texto; nunca el audio.
3. El usuario puede corregir el texto o escribirlo directamente, y pulsa «Consultar». El texto debe tener entre 3 y 500 caracteres.
4. La vista muestra los reportes comunes como botones; CUANDO el usuario pulsa uno, ENTONCES se ejecuta su receta fija (sin interpretar texto) y el resultado se muestra igual que el de una consulta.

### Entender el pedido

5. El servicio de IA traduce el texto a una **receta**: un conjunto del catálogo, las columnas, los filtros, la agrupación, las métricas, el orden y el límite. El modelo de lenguaje **nunca escribe SQL**; el código valida la receta contra el catálogo y arma una consulta parametrizada.
6. SI el pedido no corresponde a ningún conjunto del catálogo, ENTONCES se muestra «No encontré un reporte para tu pedido» con los conjuntos disponibles, ejemplos de preguntas y los reportes comunes.
7. SI la receta trae un conjunto desconocido, una columna, filtro, agrupación, métrica u orden que el conjunto no permite, o valores fuera de rango, ENTONCES se rechaza con el mismo mensaje del criterio 6 y no se ejecuta ninguna consulta.

### Resultado

8. CUANDO la consulta se ejecuta, ENTONCES la pantalla muestra:
   - el nombre del conjunto y lo que se aplicó (filtros, agrupación, métricas y orden), para que el usuario compruebe que se entendió bien;
   - un **resumen** en español de no más de 120 palabras que solo usa cifras del resultado;
   - la tabla con encabezados en español (hasta 100 filas) y el aviso «Se muestran las primeras 100 filas» si hay más;
   - los materiales con su nombre y unidad (del catálogo de Materiales) y los clientes con su nombre (de Keycloak, por el gateway); SI alguno de esos datos no está disponible, ENTONCES se muestra su identificador con el aviso «Nombres de materiales no disponibles» o «Nombres de clientes no disponibles».
9. SI el resultado está vacío, ENTONCES el resumen dice que no hay datos para esos filtros y la tabla aparece vacía.
10. SI la redacción con el modelo falla o tarda demasiado, ENTONCES se muestra un resumen de plantilla («Se encontraron N filas para «X» con los filtros …») y la tabla igual se muestra.
11. Todo el proceso tarda como máximo 60 segundos; mientras tanto se ve «Preparando el reporte…». SI se supera, ENTONCES se muestra «El reporte tardó demasiado; intenta de nuevo».

### Exportar

12. CUANDO el usuario pulsa «Exportar a Excel», ENTONCES el navegador genera y descarga un archivo `.xlsx` (sin pasar por el servidor) con una hoja «Datos» (la tabla, con números como números y fechas como fechas) y una hoja «Consulta» (texto pedido o reporte común, conjunto, lo aplicado, resumen, fecha y usuario).
13. CUANDO el usuario pulsa «Exportar a CSV», ENTONCES el navegador genera y descarga un `.csv` en UTF-8 con la tabla (encabezados en español).
14. En los dos archivos, un texto que empieza con `=`, `+`, `-` o `@` se guarda de forma que la hoja de cálculo no lo tome como fórmula.

### Historial y registro

15. Cada consulta se guarda (usuario, texto o reporte común, receta aplicada, resumen y fecha), también las no reconocidas.
16. La vista muestra las últimas 10 consultas del usuario; al pulsar una, se vuelve a consultar con el mismo texto o el mismo reporte común.
17. Un usuario puede hacer como máximo 10 consultas por minuto (también con los reportes comunes); si se pasa, ve «Demasiadas consultas; espera un momento».

## Fuera del alcance

Conjuntos o tablas fuera del catálogo, gráficos, editar la receta a mano, envío del archivo por correo, consultas en el portal o en la app, respuesta hablada (texto a voz), conversación de varias preguntas encadenadas, la comparación «usado frente a previsto» (la base de reportes no guarda lo previsto; está en la pestaña «Material» de la obra, 006) y el nombre de las partidas (la base de reportes solo guarda su id).
