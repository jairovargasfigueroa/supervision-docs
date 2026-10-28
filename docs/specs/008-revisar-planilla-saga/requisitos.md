# 008 · Revisar planilla en el portal (saga «aprobar planilla»)

**Estado:** aprobado · **Proyectos:** services/obras, services/finanzas, services/materiales, portal, gateway, mf-obras

## Historia

Como **cliente** quiero ver el avance de mis obras y aprobar u observar las planillas que me presentan, para pagar solo lo ejecutado y con respaldo.

## Criterios de aceptación

### Portal

1. CUANDO el cliente entra al portal, ENTONCES ve sus obras con nombre, ubicación, avance % y plazo transcurrido %.
2. CUANDO abre una obra, ENTONCES ve el avance por partida (código, nombre, unidad, contratado, ejecutado acumulado, avance %) y las fotos publicadas, y la lista de planillas presentadas y anteriores (número, periodo, estado, neto). No ve borradores.
3. CUANDO abre una planilla `PRESENTADA`, ENTONCES ve sus líneas, totales y fotos de respaldo, y los botones «Aprobar» y «Observar».
4. «Observar» pide un motivo (obligatorio, 10 a 500 caracteres) y pasa la planilla a `OBSERVADA`.
5. «Aprobar» pide confirmación, pasa la planilla a `APROBANDO` y muestra «En aprobación…» hasta que termina (consulta cada 2 s mientras siga `APROBANDO`, hasta 4 minutos). SI pasan 90 s sin resultado, ENTONCES muestra además «La aprobación está tardando más de lo normal; puedes cerrar esta pantalla, el resultado aparecerá aquí». A los 4 minutos deja de consultar; al volver a abrir la planilla se ve su estado actual.
6. CUANDO la aprobación termina bien, ENTONCES la planilla queda `APROBADA` con el número de cobro. SI falla, ENTONCES queda `OBSERVADA` con el motivo del fallo (por ejemplo «Saldo del contrato insuficiente»).

### Saga

7. Al aprobar, en orden: (1) Obras pasa la planilla a `APROBANDO`; (2) Finanzas reserva el neto contra el saldo del contrato; (3) Materiales cierra los movimientos del periodo de la obra; (4) Finanzas emite el cobro y consume la reserva; (5) Obras marca `APROBADA` y guarda el cobro.
8. SI el paso 2 falla (saldo insuficiente), ENTONCES la planilla queda `OBSERVADA` con «Saldo del contrato insuficiente».
9. SI el paso 3 falla, ENTONCES se libera la reserva y la planilla queda `OBSERVADA` con el motivo.
10. SI el paso 4 falla, ENTONCES se reabren los consumos, se libera la reserva y la planilla queda `OBSERVADA` con el motivo.
11. SI un paso no responde en 60 segundos, ENTONCES se trata como fallo y se compensa lo hecho.
12. Ningún mensaje repetido produce dos reservas, dos cierres ni dos cobros.
13. Después de aprobar, el avance de la obra incluye las cantidades de esa planilla y los movimientos del periodo cerrado ya no aceptan cambios (004, criterio 7).

### ERP

14. El residente ve en la planilla el estado actualizado, la observación del cliente o del fallo, y el número de cobro cuando está aprobada.

## Fuera del alcance

Pagos del cliente, anular una planilla aprobada.
