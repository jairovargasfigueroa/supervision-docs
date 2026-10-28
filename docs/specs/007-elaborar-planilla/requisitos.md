# 007 · Elaborar y presentar planilla

**Estado:** aprobado · **Proyectos:** services/obras, gateway, mf-obras

## Historia

Como **residente** quiero elaborar la planilla de avance del mes con las cantidades ejecutadas por partida y fotos de respaldo, y presentarla al cliente, para cobrar lo ejecutado.

## Criterios de aceptación

1. CUANDO el residente abre una obra `EN_EJECUCION` asignada a él y pulsa «Nueva planilla», ENTONCES elige el periodo (mes) y se crea la planilla en `BORRADOR` con el número siguiente y una línea por partida con cantidad 0.
2. SI ya hay una planilla no aprobada en la obra, o el periodo no es posterior al de la última planilla, o es un mes futuro, ENTONCES no se crea y se explica el motivo (un mensaje distinto para cada caso: planilla abierta, periodo no posterior y mes futuro; textos en `docs/mensajes.md`).
3. En la planilla, por cada partida se ve: código, nombre, unidad, cantidad contratada, acumulado anterior, cantidad del periodo (editable), acumulado total, saldo por ejecutar y monto.
4. Los totales se recalculan al escribir: subtotal, descuento por anticipo, retención y neto a cobrar (reglas del negocio).
5. SI la cantidad del periodo hace que el acumulado supere lo contratado, ENTONCES la fila se marca en rojo con «Supera lo contratado (saldo: X)» y no se puede guardar.
6. El residente puede adjuntar fotos de avance de la obra registradas dentro del periodo, eligiéndolas de una galería.
7. «Guardar» guarda el borrador. SI otra persona la guardó antes (versión distinta), ENTONCES se avisa «La planilla cambió, recarga para ver la última versión».
8. «Presentar» la pasa a `PRESENTADA`; SI el subtotal es 0, ENTONCES no se permite. Al presentarla, las fotos adjuntas quedan visibles para el cliente.
9. Una planilla `PRESENTADA`, `APROBANDO` o `APROBADA` ya no se puede editar. Una `OBSERVADA` muestra la observación y se puede corregir y volver a presentar.
10. Solo el `residente` asignado a la obra elabora y presenta planillas; `admin` y `gerente` las ven en modo lectura.

## Fuera del alcance

Eliminar planillas, planillas de obras concluidas, exportar a PDF.
