# 003 · Gestionar materiales (catálogo y stock mínimo)

**Estado:** aprobado · **Proyectos:** services/materiales, gateway, mf-materiales

## Historia

Como **administración** quiero mantener el catálogo de materiales y definir el stock mínimo de cada material en cada obra, para controlar qué se usa y saber cuándo falta.

## Criterios de aceptación

1. CUANDO un usuario del ERP abre Materiales → «Catálogo», ENTONCES ve la lista de materiales con código, nombre, tipo, unidad, precio referencial y si está activo, con búsqueda por código o nombre.
2. Solo `admin` ve los botones «Nuevo material», «Editar» y «Activar/Desactivar»; los demás roles solo consultan.
3. Un material tiene: código (obligatorio, único, máx. 20, se guarda en mayúsculas), nombre (obligatorio, máx. 120), tipo (uno de: `CEMENTO`, `ACERO`, `AGREGADO`, `LADRILLO`, `MADERA`, `ELECTRICO`, `SANITARIO`, `PINTURA`, `OTRO`), unidad y unidad en plural (obligatorias, por ejemplo «bolsa» y «bolsas»), precio referencial (≥ 0) y atributos opcionales (pares nombre–valor, por ejemplo «resistencia: 210 kg/cm²»).
4. SI el código ya existe, ENTONCES se muestra «Ya existe un material con el código X».
5. Desactivar un material no lo borra: deja de aparecer para nuevos insumos y movimientos, pero sigue en el historial.
6. CUANDO un usuario del ERP abre Materiales → «Stock por obra» y elige una obra, ENTONCES ve cada material con movimientos o mínimo definido en esa obra: cantidad actual, mínimo y estado (`BAJO`, `JUSTO`, `OK`) con color (rojo, ámbar, verde).
7. Solo `admin` puede definir o cambiar el mínimo de un material en una obra (≥ 0). Puede agregar un material del catálogo a la obra solo para fijarle el mínimo, aunque todavía no tenga movimientos (cantidad 0).
8. Los residentes solo ven en la lista de obras las obras que tienen asignadas.

## Fuera del alcance

Eliminar materiales, importar el catálogo desde Excel, precios por proveedor.
