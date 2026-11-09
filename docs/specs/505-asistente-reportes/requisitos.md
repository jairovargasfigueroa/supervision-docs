# 505 · Asistente de reportes y agentes completos

**Estado:** aprobado (09/11/2026, Jairo: «defínelo todo y haz la implementación») · **Capa:** 5 (puntos 5, 14 y 15) · **Proyectos:** services/ia, services/obras, services/materiales, gateway, mf-supervision, infra · **Depende de:** 501, 502, 503 y 602

**Decisiones de Jairo (09/11/2026):**

- Los reportes y los agentes tienen que responder bien a **cualquier pedido coherente con los datos del sistema**, con la seguridad de siempre (la IA no escribe SQL ni ejecuta acciones).
- La conversación va **en la misma pantalla de reportes que ya existe**, ampliando la misma consulta: nada de pantallas o consultas aparte.
- El asistente responde **con texto en pantalla** (tabla, resumen y «lo que entendí»); no habla. El dictado por voz para preguntar sigue igual (302).
- Hasta **5 preguntas** de aclaración por conversación, y **reintentos generosos** para que no falle al primer intento.
- Exportación a **PDF y Word**, además de Excel y CSV.
- Modelo: Claude Haiku 5.5 en la nube (602, decisión 3).

## Historia

Como **gerente** (o administración) quiero pedir cualquier reporte de mis datos escribiendo o hablando, y que el asistente me pregunte cuando falta algo o algo es ambiguo, recuerde lo que ya hablamos y me deje exportar el resultado, para obtener la información que necesito sin conocer el catálogo. Y quiero que los tres agentes revisen **todo** lo que dice su misión sin quedarse a medias.

## Criterios de aceptación

### Conversación en la pantalla de reportes

1. CUANDO hago un pedido en la pantalla de reportes, ENTONCES el asistente responde con **un reporte** o con **una pregunta** de aclaración, en la misma pantalla, y la conversación queda visible (mis pedidos y sus respuestas, en orden).
2. CUANDO el asistente pregunta, ENTONCES muestra la pregunta y, si las hay, **opciones en botones** que salen de los datos reales (obras, materiales, clientes, periodos); puedo pulsar una opción, escribir o dictar la respuesta.
3. El asistente pregunta **solo cuando lo necesita**: el pedido es vago o tiene interpretaciones muy distintas, un nombre coincide con varios (por ejemplo «cemento» con dos materiales) o un nombre no existe. SI solo falta algo que tiene valor por defecto (por ejemplo el periodo), ENTONCES usa el defecto y lo dice en «lo que entendí».
4. Como máximo **5 preguntas por conversación**. Al llegar al tope, responde con lo que tiene y dice qué supuso.
5. CUANDO respondo una pregunta, ENTONCES el asistente combina mi respuesta con el pedido original (no tengo que repetir nada).
6. CUANDO, después de un reporte, pido un cambio («¿y en Torre Norte?», «solo los vencidos», «ahora por mes»), ENTONCES el asistente ajusta el último reporte en lugar de empezar de cero.
7. CUANDO pulso «Nueva consulta» o un reporte común, ENTONCES empieza una conversación nueva.
8. La conversación dura **30 minutos sin uso**; SI respondo después, ENTONCES veo «La conversación expiró: vuelve a hacer el pedido» y empieza una nueva.
9. Cada reporte muestra, como hoy: título, pedido, **lo que entendí**, resumen, avisos y la tabla.

### Cualquier pedido coherente con los datos

10. Puedo filtrar por **cualquier campo** de cada conjunto con los operadores de su tipo: textos y nombres con «contiene» o «es uno de» (por ejemplo «arena y grava»), números y montos con «desde» y «hasta», fechas y periodos con «desde» y «hasta», estados con «igual» o «es uno de».
11. En todos los conjuntos puedo filtrar por los datos de la obra: zona, nivel de riesgo y «solo en riesgo».
12. En **Obras** puedo pedir y filtrar, por obra: planillas observadas, planillas aprobadas, cobros vencidos (cantidad y monto), monto por cobrar y salidas sin stock. Así se responden pedidos que cruzan temas («obras con planillas observadas y riesgo alto», «obras con cobros vencidos en la zona norte»).
13. SI el pedido es sobre algo que el sistema no registra o no es un reporte («hola», «dame las contraseñas»), ENTONCES lo dice y sugiere cómo pedirlo; nunca inventa datos.

### Que no falle al primer intento

14. SI la receta que arma la IA no es válida, ENTONCES el asistente la **corrige solo** con el error, hasta **3 intentos** por pedido, antes de rendirse.
15. SI el modelo de lenguaje falla de forma pasajera (saturado, corte de red), ENTONCES se reintenta **hasta 2 veces** con una espera breve.
16. Un pedido igual a uno ya resuelto hoy se responde **sin llamar al modelo** (caché de recetas por 24 horas).
17. Todo pedido termina en **menos de 50 s**; el límite es de **20 consultas por minuto** por usuario.

### Exportar

18. Cada reporte se puede exportar a **Excel, CSV, PDF y Word**. El PDF y el Word llevan título, pedido, lo que entendí, resumen, avisos, la tabla y la fecha.

### Agentes completos

19. **Control de materiales** revisa en cada ejecución, para **todas** las obras en ejecución y el periodo actual, el consumo por partida contra lo previsto (usado > 1,20 × previsto) y las salidas que superaron el stock, además del stock bajo o justo y los consumos atípicos.
20. Cada agente puede hacer hasta **15 llamadas** a herramientas y **8 vueltas** con el modelo, en **4 minutos** como máximo.
21. SI una herramienta falla de forma pasajera, ENTONCES se **reintenta una vez**; SI sigue fallando, ENTONCES el agente sigue con lo demás y lo dice en el resumen.
22. SI el reporte del agente sale mal armado, ENTONCES se corrige con el error, hasta **3 intentos**.
23. El resumen de cada agente dice qué **no pudo revisar** y por qué, si algo quedó sin revisar.

### Medición

24. Un **banco de preguntas** (claras, difíciles, ambiguas, fuera de tema y maliciosas) se corre contra un despliegue y da: reportes correctos, aclaraciones, rechazos, tiempos y fallas. Metas: 9 de cada 10 pedidos claros con reporte, los ambiguos con al menos una pregunta, los fuera de tema y maliciosos rechazados.

## Fuera del alcance

- Respuesta hablada (texto a voz).
- Datos que la base de reportes no tiene: lo **previsto por partida** en los reportes de personas (sigue en la pestaña «Material» de la obra, 006; los agentes sí lo usan por MCP), los nombres de las partidas y el **diario de obra** como conjunto de reportes. Llevarlos a la base de reportes pide eventos nuevos de Obras: queda para otra funcionalidad.
- Atajo por parecido con *embeddings*: la API de Anthropic no tiene *embeddings* y agregar otro proveedor no se justifica; lo cubren la caché de recetas y los reportes comunes.
- Que la IA escriba SQL, ejecute acciones o vea datos que el usuario no puede ver.
