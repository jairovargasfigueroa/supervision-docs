# 002 · Registrar obra (datos, contrato y presupuesto)

**Estado:** aprobado · **Proyectos:** services/obras, services/finanzas, services/materiales, gateway, mf-obras

## Historia

Como **administración** quiero registrar una obra con su contrato, su presupuesto por partidas y el material previsto por partida, y asignar a su residente, maestro de obra, almacenero y cliente, para que la obra quede lista para ejecutarse.

## Criterios de aceptación

1. CUANDO un `admin` abre Obras → «Nueva obra», ENTONCES ve un formulario en tres pasos: (1) datos y asignaciones, (2) contrato, (3) presupuesto por partidas.
2. Paso 1: nombre (obligatorio, máx. 150), ubicación (obligatorio, máx. 200), fecha de inicio (obligatoria), y cuatro listas para elegir residente, maestro de obra, almacenero y cliente entre los usuarios de Keycloak con ese rol (todas obligatorias).
3. Paso 2: monto (> 0), plazo en días (> 0), anticipo % y retención % (0 a 100, y su suma < 100), fecha de firma (obligatoria).
4. Paso 3: lista de partidas (al menos una) con código (único en la obra), nombre, unidad, cantidad contratada (> 0), precio unitario (> 0) y meses de ejecución (texto libre, opcional). Cada partida puede tener insumos previstos: material del catálogo (solo activos) y cantidad por unidad (> 0), sin repetir material en la misma partida.
5. El formulario muestra en todo momento la suma del presupuesto (Σ cantidad × precio) y la diferencia con el monto del contrato.
6. SI la suma del presupuesto no es igual al monto del contrato (con tolerancia de 0,01), ENTONCES no se puede guardar y se muestra «El presupuesto (Bs X) no coincide con el monto del contrato (Bs Y)».
7. CUANDO se guarda, ENTONCES la obra queda en estado `SIN_CONTRATO` y aparece en la lista de obras con la etiqueta «Registrando contrato».
8. CUANDO Finanzas registra el contrato, ENTONCES la obra pasa a `EN_EJECUCION` en pocos segundos, sin que el usuario haga nada más.
9. SI Finanzas rechaza el contrato, ENTONCES la obra queda en `SIN_CONTRATO` con el motivo visible en su detalle.
10. Solo `admin` puede registrar obras. `residente`, `gerente` no ven el botón «Nueva obra» y el servicio responde `403` si lo intentan.
11. CUANDO la obra se registra, ENTONCES Materiales conoce sus asignaciones (para que el almacenero pueda registrar movimientos en esa obra).

## Fuera del alcance

Editar o eliminar una obra ya registrada, cambiar asignaciones, concluir la obra.
