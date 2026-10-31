# 403 · Consumos de material atípicos (ML no supervisado)

**Estado:** aprobado (31/10/2026) · **Capa:** 4 (Datos y predicciones) · **Punto:** 11 (no supervisado) · **Proyectos:** services/ia, gateway, mf-obras, mf-supervision

**Decisión de Jairo (31/10/2026):** el ML no supervisado del punto 11 son los consumos de material raros con Isolation Forest, entrenado con datos sintéticos (script reproducible que tarda segundos) y que se puede reentrenar después con datos reales. No usa modelo de lenguaje (eso es de la capa 5).

**Depende de:** 401 (servicio de IA y base de reportes). Si la 402 está implementada, un consumo atípico recalcula el riesgo de retraso de la obra; si no, ese paso se omite.

## Historia

Como **residente** (y gerente o administración) quiero que el sistema marque solo las salidas de material que se salen de lo normal, con el motivo, para revisarlas y detectar pérdidas o desperdicio sin revisar cada movimiento.

## Criterios de aceptación

### Detección

1. CUANDO se registra una `SALIDA` de material (004), ENTONCES el servicio de IA la evalúa con un modelo Isolation Forest y, si resulta atípica, la guarda como **consumo atípico** `PENDIENTE` de revisión en menos de 10 segundos (decisión del equipo).
2. Los ingresos no se evalúan.
3. Cada consumo atípico tiene un **puntaje** de 0 a 1 (más alto = más raro) y de 1 a 3 **motivos** en palabras simples, por ejemplo: «La cantidad es 4,2 veces la habitual de este material en la obra», «Se registró fuera del horario habitual (22:40)», «Salió más material del que había en stock».
4. SI la misma salida llega dos veces, ENTONCES se evalúa y se guarda una sola vez.
5. Esta detección es distinta de la alerta «consumo fuera de lo previsto» (usado > 1,20 × previsto, 006): aquella compara contra el presupuesto; esta compara contra el comportamiento habitual. Ambas se muestran por separado.

### Revisión (mf-obras)

6. CUANDO el usuario abre la pestaña «Material» del detalle de obra (006), ENTONCES ve la sección «Consumos atípicos» con fecha, material, partida, cantidad, puntaje, motivos y estado; por defecto los `PENDIENTE`, con filtro por estado.
7. El `residente` asignado y `admin` pueden marcar un consumo atípico como «Es normal» (`NORMAL`) o «Confirmar problema» (`CONFIRMADO`). Confirmar exige un comentario de 5 a 300 caracteres; «Es normal» lo admite opcional.
8. SI el consumo ya fue revisado, ENTONCES no se puede revisar de nuevo y se avisa «Este consumo ya fue revisado».
9. Queda registrado quién lo revisó, cuándo y su comentario. `gerente` solo lo ve.

### Tablero (mf-supervision)

10. CUANDO el usuario abre Supervisión (009), ENTONCES ve el indicador «Consumos atípicos por revisar» (suma de `PENDIENTE` en sus obras) y una columna con los pendientes de cada obra.

### Permisos y fallos

11. Ven los consumos atípicos `admin`, `gerente` y `residente` (este solo de sus obras).
12. SI el servicio de IA no responde, ENTONCES la sección y la columna muestran «—» con «Datos de IA no disponibles» y el resto de la pantalla se ve normal.

### Modelo

13. El modelo se entrena primero con **datos sintéticos** (salidas normales y anomalías inyectadas, documentados y reproducibles) y se puede reentrenar con las salidas reales de la base de reportes (las que llegaron por eventos y las de la carga inicial de la 401) cuando haya al menos 500 (decisión del equipo), con un comando manual que genera una versión nueva.
14. El modelo cumple las métricas mínimas de `diseno.md` sobre los datos sintéticos de prueba; con datos reales, marca como atípicas como máximo el 3 % de las salidas (decisión del equipo).
15. Generar los datos sintéticos y entrenar tarda **segundos** (menos de un minuto entre los dos) en la computadora del equipo, solo con CPU (sin GPU); reentrenar con datos reales, lo mismo.

## Fuera del alcance

- Evaluar las salidas que trajo la carga inicial de la 401 sin evento (se evalúan solo las salidas que llegan por `MovimientoRegistrado`).

- Bloquear salidas o pedir aprobación antes de registrarlas.
- Evaluar ingresos, precios u órdenes de compra.
- Reentrenar automáticamente.
- Avisos por correo (los agentes de la capa 5 usan estos datos).
