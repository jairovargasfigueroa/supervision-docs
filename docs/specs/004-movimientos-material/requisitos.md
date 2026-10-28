# 004 · Registrar ingreso y salida de material

**Estado:** aprobado · **Proyectos:** services/materiales, app-obra

## Historia

Como **almacenero** quiero registrar desde la app cada ingreso de material a la obra y cada salida hacia una partida, para que el stock y el consumo se conozcan al día.

## Criterios de aceptación

1. CUANDO el almacenero entra a la app, ENTONCES ve sus obras asignadas y elige una.
2. **Ingreso:** elige material (activos del catálogo), cantidad (> 0, hasta 3 decimales) y, opcionalmente, número de nota de remisión. Pulsa «Registrar ingreso».
3. **Salida:** elige material, cantidad (> 0) y partida de destino (obligatoria, de la lista de partidas de la obra). Pulsa «Registrar salida».
4. CUANDO se registra, ENTONCES se muestra «Registrado» y el stock de ese material se actualiza.
5. SI una salida supera el stock conocido, ENTONCES se registra igual y la app muestra el aviso «La salida supera el stock registrado (stock: X). Queda como alerta para revisión».
6. SI el envío se repite (por ejemplo, el usuario pulsa dos veces o se reintenta por mala señal), ENTONCES el movimiento se registra una sola vez.
7. SI el periodo del movimiento ya fue cerrado por una planilla aprobada, ENTONCES se rechaza con «El periodo AAAA-MM ya está cerrado».
8. SI el stock queda por debajo del mínimo, ENTONCES se publica el aviso «stock bajo» (lo usa la automatización de la capa 2).
9. **Stock:** el almacenero ve el stock de su obra con el mismo estado y colores que el ERP.
10. Solo el `almacenero` puede registrar movimientos, y solo en sus obras asignadas.

## Fuera del alcance

Anular o editar movimientos, transferencias entre obras, foto de la nota de remisión (se agrega en la capa 1), funcionamiento sin señal (capa 1).
