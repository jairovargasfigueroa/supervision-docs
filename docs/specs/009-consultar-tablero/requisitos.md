# 009 · Consultar tablero

**Estado:** aprobado · **Proyectos:** gateway, mf-supervision, services/obras, services/materiales, services/finanzas

## Historia

Como **gerente** (y residente o administración) quiero un tablero con el estado de todas las obras que puedo ver, para saber de un vistazo cuáles necesitan atención.

## Criterios de aceptación

1. CUANDO abre Supervisión, ENTONCES ve cuatro indicadores: obras en ejecución, obras en riesgo, materiales en estado `BAJO` (suma en sus obras) y cobros vencidos (cantidad y monto; solo `admin` y `gerente`).
2. Debajo, una tabla de obras en ejecución: nombre, avance %, plazo %, diferencia (plazo − avance), materiales bajos, última planilla (periodo y estado) y la etiqueta «En riesgo».
3. La tabla se ordena por defecto por diferencia, de mayor a menor; se puede ordenar por cualquier columna.
4. Al pulsar una obra se abre su detalle en el área Obras (`/obras/:id`).
5. SI un servicio no responde, ENTONCES sus columnas o indicadores muestran «—» con el aviso «Datos de X no disponibles» y el resto se ve normal.
6. Los datos se actualizan al abrir la pantalla y con un botón «Actualizar».

## Fuera del alcance

Predicciones de riesgo (capa 4), agentes (capa 5), gráficos históricos.
