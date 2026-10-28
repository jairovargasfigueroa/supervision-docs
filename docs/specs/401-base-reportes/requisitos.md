# 401 · Servicio de IA y base de reportes

**Estado:** borrador · **Capa:** 4 (Datos y predicciones) · **Puntos:** 20 (nivel de datos) y 17 · **Proyectos:** services/ia (nuevo), services/obras, services/materiales, gateway, mf-obras, infra

## Historia

Como **gerente** quiero que los datos que cruzan servicios (avance, consumo de material y cobros por obra, zona y cliente) estén reunidos en una base de reportes que se actualiza sola con los eventos, para que las predicciones (402, 403) y los reportes por voz (capa 5) no tengan que consultar las bases de Obras, Materiales y Finanzas.

## Criterios de aceptación

### Zona de la obra

1. CUANDO Administración registra una obra (002), ENTONCES puede indicar su **zona** eligiéndola de una lista (Norte, Sur, Este, Oeste, Centro; decisión del equipo). Es opcional.
2. La zona se ve en la lista y en el detalle de la obra del ERP; si no se indicó, se muestra «Sin zona».

### Base de reportes

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
14. El servicio de IA no lee ni escribe las bases de otros servicios; solo escucha eventos. Nadie más lee la base de reportes.

### Servicio

15. `GET /salud` responde sin token `200 {"estado":"ok"}`.
16. `admin` puede consultar el estado de la base de reportes: cuántas filas tiene cada tabla y cuándo se aplicó el último evento de cada tipo.

## Fuera del alcance

- Predicciones (402) y consumos atípicos (403).
- Reportes por voz, agentes y herramientas MCP (capa 5).
- Cargar en la base de reportes lo que pasó antes de que existiera la cola `ia` (no hay carga inicial; decisión del equipo).
- Obras `CONCLUIDA` (el sistema base no tiene esa transición).
