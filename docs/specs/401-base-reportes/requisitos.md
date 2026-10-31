# 401 · Servicio de IA y base de reportes

**Estado:** aprobado (31/10/2026) · **Capa:** 4 (Datos y predicciones) · **Puntos:** 20 (nivel de datos) y 17 · **Proyectos:** services/ia (nuevo), services/obras, services/materiales, gateway, mf-obras, infra

**Mecanismo (decisión de Jairo, 31/10/2026):** el ingeniero pidió «algún mecanismo» para los reportes que cruzan servicios. Se usa **CQRS solo para lo que cruza servicios**: un **modelo de lectura** (`reportes_db`, tablas `rpt_*`) alimentado por los eventos de RabbitMQ, que vive dentro del servicio de IA. Cada microservicio sigue escribiendo y leyendo lo suyo; no hay *event sourcing*.

## Historia

Como **gerente** quiero que los datos que cruzan servicios (avance, consumo de material y cobros por obra, zona y cliente) estén reunidos en un modelo de lectura que se actualiza solo con los eventos, para que las predicciones (402, 403) y los reportes por voz (capa 5) no tengan que consultar las bases de Obras, Materiales y Finanzas.

## Criterios de aceptación

### Zona de la obra

1. CUANDO Administración registra una obra (002), ENTONCES puede indicar su **zona** eligiéndola de una lista (Norte, Sur, Este, Oeste, Centro; decisión del equipo). Es opcional.
2. La zona se ve en la lista y en el detalle de la obra del ERP; si no se indicó, se muestra «Sin zona».

### Base de reportes (modelo de lectura)

3. CUANDO se registra una obra, ENTONCES en menos de 10 segundos (decisión del equipo) aparece en la base de reportes con su nombre, ubicación, zona, cliente, asignaciones, fecha de inicio, plazo, monto del contrato, avance 0 % y plazo transcurrido.
4. CUANDO Finanzas registra el contrato de la obra, ENTONCES la obra queda `EN_EJECUCION` en la base de reportes.
5. CUANDO se aprueba una planilla (008), ENTONCES la base de reportes guarda la planilla (periodo, neto, monto del periodo) y recalcula el avance de la obra con la misma regla que Obras (reglas del negocio, «Avance y plazo»); el valor coincide con el que muestra Obras.
6. CUANDO se aprueba una planilla y Finanzas emite su cobro, ENTONCES la base de reportes tiene el cobro con su número, obra, cliente, zona, monto, emisión, vencimiento y estado `PENDIENTE`, sin importar en qué orden llegaron los dos eventos.
7. CUANDO se observa una planilla (por el cliente o por la saga), ENTONCES la base de reportes cuenta cuántas veces se observó y guarda el último motivo.
8. CUANDO se registra un movimiento de material, ENTONCES la base de reportes lo guarda; SI es una `SALIDA`, ENTONCES suma su cantidad y su monto (cantidad × precio referencial del material en ese momento) al consumo de la obra, periodo, material y partida.
9. Un cobro `PENDIENTE` pasa a `VENCIDO` en la base de reportes al día siguiente de su vencimiento (misma regla que Finanzas).
10. El plazo transcurrido de cada obra se recalcula todos los días.
11. SI un evento llega repetido, ENTONCES se aplica una sola vez.
12. SI un evento falla 3 veces, ENTONCES va a la cola `plataforma.fallidos` y los demás eventos se siguen procesando.
13. SI el servicio de IA está apagado, ENTONCES los eventos se guardan en su cola y se procesan cuando vuelve (la cola existe desde que se levanta la infraestructura).
14. El servicio de IA no lee ni escribe las bases de otros servicios: escucha eventos y, solo en la carga inicial, llama a endpoints REST de lectura que ya existen. Nadie más escribe en la base de reportes.

### Servicio

15. `GET /salud` responde sin token `200 {"estado":"ok"}`.
16. `admin` puede consultar el estado de la base de reportes: cuántas filas tiene cada tabla, cuándo se aplicó el último evento de cada tipo y cómo terminó la última carga inicial.

### Carga inicial (decisión de Jairo, 31/10/2026)

17. CUANDO se crea la base de reportes, ENTONCES se corre **una vez** la carga inicial: el servicio de IA pide a Obras, Materiales y Finanzas, por sus endpoints REST de lectura, lo que ya tienen (obras con su contrato y asignaciones, planillas aprobadas u observadas, cobros, movimientos de material y precios del catálogo) y llena las tablas `rpt_*` con las mismas reglas que los eventos. Después sigue con los eventos.
18. La carga usa **solo endpoints que ya existen** (`docs/contratos/rest.md`) y un token de servicio propio (cliente `ia-reportes` de Keycloak); no lee las bases de otros servicios.
19. Correrla otra vez no duplica filas ni suma dos veces un movimiento (idempotente). Si ya hay una carga en curso, la segunda se niega con un mensaje claro.
20. SI llegan eventos mientras corre la carga (o hay eventos viejos esperando en la cola `ia`), ENTONCES los dos caminos se aplican sin duplicar ni perder datos, y al terminar el avance de cada obra coincide con el de Obras.
21. SI un servicio no responde, ENTONCES la carga termina con error e indica en qué obra y servicio; lo que ya se cargó queda, y correrla de nuevo lo completa.
22. Lo que los servicios no exponen queda aproximado y documentado en `diseno.md`: cuántas veces se observó una planilla antes de la carga (se cuenta como máximo 1), su fecha de aprobación (vacía) y el precio de cada movimiento anterior (el precio actual del catálogo).

## Fuera del alcance

- Predicciones (402) y consumos atípicos (403).
- Reportes por voz, agentes y herramientas MCP (capa 5).
- *Event sourcing* (el estado de cada servicio sigue en sus tablas; los eventos solo alimentan el modelo de lectura).
- Que la carga inicial evalúe consumos atípicos de movimientos pasados (la 403 evalúa las salidas que llegan por evento).
- Obras `CONCLUIDA` (el sistema base no tiene esa transición).
