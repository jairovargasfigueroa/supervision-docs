# 006 · Consultar obra

**Estado:** aprobado · **Proyectos:** services/obras, services/materiales, services/finanzas, gateway, mf-obras

## Historia

Como **residente, gerente o administración** quiero ver el estado de una obra (avance frente al plazo, material usado frente al previsto, fotos, planillas y cobros) para detectar atrasos y desperdicios a tiempo.

## Criterios de aceptación

1. CUANDO un usuario del ERP abre Obras, ENTONCES ve la lista de las obras que puede ver (convenciones) con nombre, ubicación, estado, avance %, plazo transcurrido % y la etiqueta «En riesgo» cuando corresponde.
2. La lista permite filtrar por estado y buscar por nombre.
3. CUANDO abre una obra, ENTONCES ve:
   - Encabezado: nombre, ubicación, estado, fecha de inicio, residente, maestro, almacenero y cliente (nombres).
   - Avance de la obra %, plazo transcurrido % y si está en riesgo.
   - Contrato (de Obras): monto, plazo, anticipo %, retención %. Para `admin` y `gerente`, además el saldo disponible y el total cobrado (de Finanzas).
   - Tabla de partidas: código, nombre, unidad, cantidad contratada, ejecutada acumulada, avance %, precio unitario.
   - Pestaña «Material»: para el periodo elegido (por defecto el mes actual), por partida y material: previsto, usado y diferencia; en rojo si usado > 1,20 × previsto.
   - Pestaña «Fotos»: galería por partida (005).
   - Pestaña «Planillas»: número, periodo, estado, neto (007).
   - Pestaña «Cobros» (solo `admin` y `gerente`): número, emisión, vencimiento, monto y estado.
4. SI un servicio no responde, ENTONCES solo su sección muestra «No disponible por el momento» y el resto de la pantalla se ve normal.
5. Material previsto del periodo = cantidad de la partida en la planilla de ese periodo × cantidad por unidad; si no hay planilla en ese periodo, el previsto es 0 y se indica «Sin planilla en este periodo».
6. Un usuario que intenta abrir una obra que no puede ver recibe «Obra no encontrada».

## Fuera del alcance

Exportar el detalle, gráficos históricos (capa 4).
