# 502 · Agentes en el ERP

**Estado:** borrador para aprobar · **Capa:** 5 (puntos 5, 15 y 16) · **Proyectos:** services/ia, gateway, mf-supervision, mf-obras, mf-materiales, infra · **Depende de:** 401, 402, 403 y 501

## Historia

Como **gerente** (y residente o administración) quiero que tres agentes revisen solos, cada día, las obras, los materiales y los cobros, me reporten lo que encuentran con su evidencia y me sugieran acciones de una lista conocida, para enterarme a tiempo sin revisar pantalla por pantalla. Yo decido si apruebo o rechazo cada sugerencia; el sistema nunca ejecuta nada por su cuenta.

## Los tres agentes

Los define el equipo; el gerente no los crea ni los configura.

| Agente | Misión | Herramientas MCP (501) |
|---|---|---|
| Seguimiento de obras (`SEGUIMIENTO_OBRAS`) | Detectar obras atrasadas, que van camino a atrasarse o con riesgo alto según el modelo (402), buscar en el diario la causa probable y revisar si la planilla del mes está pendiente | `avance_obra`, `buscar_diario`, `planillas_estado` + lectura local del riesgo de retraso (402) |
| Control de materiales (`CONTROL_MATERIALES`) | Detectar stock bajo o justo, salidas que superaron el stock, consumos por encima de lo previsto en el periodo y consumos atípicos sin revisar (403) | `stock_obra`, `consumos_partida`, `avance_obra` + lectura local de consumos atípicos (403) |
| Control de cobros (`CONTROL_COBROS`) | Detectar cobros vencidos o por vencer y planillas presentadas sin respuesta del cliente u observadas sin corregir | `cobros_por_vencer`, `planillas_estado` |

## Criterios de aceptación

### Ejecución

1. Los tres agentes se ejecutan solos una vez al día, a las 06:00 hora de La Paz, uno detrás de otro (origen `PROGRAMADA`).
2. CUANDO un `admin` o `gerente` pulsa «Ejecutar ahora» en un agente, ENTONCES se crea una ejecución `MANUAL` en estado `EN_CURSO` y la pantalla muestra «En curso…» hasta que termina (consulta cada 3 s, máximo 5 minutos).
3. SI ya hay una ejecución `EN_CURSO` del mismo agente, ENTONCES no se crea otra y se muestra «El agente ya se está ejecutando».
4. Cada agente usa solo sus herramientas (las MCP de su lista y, si tiene, su lectura local de datos del propio servicio de IA: predicciones de la 402 o consumos atípicos de la 403). SI el modelo pide otra, ENTONCES la llamada se rechaza, se registra como paso con error y la ejecución sigue.
5. Cada ejecución tiene límites: como máximo 8 llamadas a herramientas y 3 minutos en total. SI se alcanza un límite, ENTONCES el agente cierra el reporte con lo que tiene; SI no logra un reporte válido, ENTONCES la ejecución queda `FALLIDA` con el motivo.
6. Cada paso queda registrado: herramienta, argumentos, resumen del resultado, hora y duración.
7. SI un servicio no responde, ENTONCES el agente sigue con las demás herramientas y lo indica en el resumen; SI no responde ninguno, ENTONCES la ejecución queda `FALLIDA` con «Sin herramientas disponibles».

### Reporte

8. Al terminar, la ejecución queda `TERMINADA` con un resumen y una lista de hallazgos. Cada hallazgo tiene: obra, tipo (de la lista del agente), severidad (`ALTA`, `MEDIA`, `BAJA`), situación, causa probable y al menos una evidencia (herramienta y dato).
9. Un hallazgo solo puede referirse a una obra que apareció en los resultados de las herramientas de esa ejecución.
10. Cada sugerencia tiene una obra, una acción de la **lista permitida** del agente y una descripción; se guarda en estado `PENDIENTE`.
11. SI ya existe una sugerencia `PENDIENTE` con la misma obra y la misma acción, ENTONCES no se crea otra igual.

### Decisión humana

12. CUANDO una persona aprueba una sugerencia (con un comentario opcional), ENTONCES queda `APROBADA` con quién y cuándo. Aprobar **solo registra la decisión**: no se crea, modifica ni envía nada en otro servicio.
13. CUANDO una persona rechaza una sugerencia, ENTONCES debe escribir un motivo (10 a 500 caracteres) y queda `RECHAZADA` con quién y cuándo.
14. Una sugerencia ya decidida no se puede volver a decidir.
15. Quién decide: `admin` y `gerente`, todas; `residente`, solo las de sus obras y nunca las de Control de cobros.

### Dónde se ve

16. **Supervisión** (`admin`, `gerente`, `residente`): vista «Agentes» con una tarjeta por agente (misión, última ejecución y su estado, número de sugerencias pendientes, botón «Ejecutar ahora» solo para `admin` y `gerente`), la lista de sugerencias pendientes con «Aprobar» y «Rechazar», y el historial de ejecuciones con el detalle de pasos (solo `admin` y `gerente`).
17. **Obras** (detalle de una obra): pestaña «Agentes» con los hallazgos vigentes y las sugerencias de esa obra de Seguimiento de obras y, para `admin` y `gerente`, también de Control de cobros.
18. **Materiales** (stock por obra): panel «Control de materiales» con los hallazgos vigentes y las sugerencias de esa obra del agente de materiales.
19. Hallazgos vigentes = los de la última ejecución `TERMINADA` de cada agente.
20. El residente solo ve hallazgos y sugerencias de sus obras, y nunca los de Control de cobros.
21. SI el servicio de IA no responde, ENTONCES solo las secciones de agentes muestran «No disponible por el momento».

## Fuera del alcance

Que el agente marque un consumo atípico como normal o confirmado (lo hace una persona, 403), que el gerente cree o configure agentes, que una aprobación ejecute la acción, notificaciones por correo, agentes en el portal o en la app, y conversación libre con el agente.
