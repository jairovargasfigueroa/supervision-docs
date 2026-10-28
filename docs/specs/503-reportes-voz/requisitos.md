# 503 · Reportes generativos por voz

**Estado:** borrador para aprobar · **Capa:** 5 (puntos 14 y 16) · **Proyectos:** services/ia, gateway, mf-supervision, infra · **Depende de:** 401 (base de reportes) y 402 (riesgo de retraso)

## Historia

Como **gerente o administración** quiero pedir un reporte hablando («¿cuánto cemento se usó en Las Palmas este trimestre?»), verlo en pantalla con una explicación corta y una tabla, y descargarlo en Excel, para no tener que armar consultas ni buscar pantalla por pantalla.

## Reportes disponibles (lista permitida)

Todos salen de la base de reportes de la 401, que se actualiza con los eventos (el plazo y el estado de los cobros se recalculan una vez al día).

| Reporte | Qué muestra | Filtros |
|---|---|---|
| Avance y plazo de las obras | Avance %, plazo %, diferencia y «En riesgo» por obra | obra, zona, estado de la obra, solo en riesgo |
| Riesgo de retraso según el modelo | Probabilidad y nivel de riesgo (402) por obra | obra, zona, nivel |
| Material usado por obra | Cantidad, monto referencial y número de salidas por obra y material | obra, zona, material, periodo |
| Salidas que superaron el stock | Salidas con alerta de stock por obra, material y mes | obra, zona, material, periodo |
| Cobros emitidos | Número, obra, monto, emisión, vencimiento y estado | obra, zona, estado, periodo de emisión |
| Cobros por vencer | Cobros pendientes que vencen en los próximos días | obra, zona, días |
| Total cobrado por obra | Cantidad de cobros, total y monto vencido por obra | obra, zona, periodo de emisión |

La comparación «usado frente a previsto» no es un reporte por voz: la base de reportes no guarda lo previsto y esa comparación ya está en la pestaña «Material» de cada obra (006).

## Criterios de aceptación

### Pedir el reporte

1. En Supervisión, vista «Reportes por voz» (roles `admin` y `gerente`), CUANDO el usuario pulsa el micrófono y habla, ENTONCES la voz se convierte en texto **en el navegador** (componente de dictado de la capa 3) y el texto aparece en un cuadro editable.
2. Al servidor solo llega el texto; nunca el audio.
3. El usuario puede corregir el texto o escribirlo directamente, y pulsa «Consultar».
4. El texto debe tener entre 3 y 500 caracteres.

### Entender el pedido

5. El servicio de IA traduce el texto a una **intención**: un reporte de la lista permitida y sus filtros. El modelo de lenguaje **nunca escribe SQL**; el código ejecuta una consulta ya escrita y parametrizada para ese reporte.
6. SI el pedido no corresponde a ningún reporte de la lista, ENTONCES se muestra «No encontré un reporte para tu pedido» con la lista de reportes disponibles y ejemplos de preguntas.
7. SI la intención trae un reporte desconocido, filtros que el reporte no acepta o valores fuera de rango, ENTONCES se rechaza y se muestra el mismo mensaje del criterio 6 (no se ejecuta ninguna consulta).

### Resultado

8. CUANDO la consulta se ejecuta, ENTONCES la pantalla muestra:
   - el nombre del reporte y los filtros que se aplicaron (para que el usuario compruebe que se entendió bien);
   - una respuesta redactada en español, de no más de 120 palabras, que solo usa cifras del resultado;
   - la tabla con encabezados en español (hasta 100 filas) y el aviso «Se muestran las primeras 100 filas» si hay más;
   - los materiales con su nombre y unidad (tomados del catálogo de Materiales); SI el catálogo no está disponible, ENTONCES se muestra el código interno del material con el aviso «Nombres de materiales no disponibles».
9. SI el resultado está vacío, ENTONCES la respuesta dice que no hay datos para esos filtros y la tabla aparece vacía.
10. SI la redacción con el modelo falla o tarda demasiado, ENTONCES se muestra una respuesta de plantilla («Se encontraron N filas para el reporte X con los filtros …») y la tabla igual se muestra.
11. Todo el proceso tarda como máximo 60 segundos; mientras tanto se ve «Preparando el reporte…». SI se supera, ENTONCES se muestra «El reporte tardó demasiado; intenta de nuevo».

### Exportar

12. CUANDO el usuario pulsa «Exportar a Excel», ENTONCES el navegador genera y descarga un archivo `.xlsx` (sin pasar por el servidor) con una hoja «Datos» (la tabla, con números como números) y una hoja «Consulta» (texto pedido, reporte, filtros, respuesta, fecha y usuario).

### Historial y registro

13. Cada consulta se guarda (usuario, texto, reporte, filtros, respuesta y fecha), también las no reconocidas.
14. La vista muestra las últimas 10 consultas del usuario; al pulsar una, se vuelve a consultar con ese texto.
15. Un usuario puede hacer como máximo 10 consultas por minuto; si se pasa, ve «Demasiadas consultas; espera un momento».

## Fuera del alcance

Reportes fuera de la lista permitida, gráficos, envío del Excel por correo, consultas por voz en el portal o en la app, respuesta hablada (texto a voz) y conversación de varias preguntas encadenadas.
