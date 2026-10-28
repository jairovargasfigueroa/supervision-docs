# 104 · ERP sin conexión (PWA) y borrador de planilla local

**Estado:** borrador (por aprobar) · **Capa:** 1 · **Puntos del ingeniero:** 7 (PWA) y 9 · **Proyectos:** erp-shell, mf-obras, mf-materiales, mf-supervision

## Historia

Como **residente** quiero seguir consultando en el ERP lo que ya abrí y seguir llenando el borrador de la planilla aunque se corte internet, y que el borrador se envíe al volver la conexión, para no perder trabajo en oficinas de obra con conexión inestable.

## Criterios de aceptación

### Instalación y carga

1. El ERP se puede instalar como aplicación (PWA) desde Chrome o Edge, con el nombre «Supervisión de obras» y su ícono.
2. CUANDO se abre sin conexión y el ERP ya se abrió antes en ese navegador, ENTONCES carga el shell y los microfrontends que ya se visitaron, desde el equipo.
3. CUANDO se abre sin conexión y el usuario inició sesión en ese navegador en las últimas 24 horas (decisión del equipo), ENTONCES entra con ese usuario en «modo sin conexión». SI no, ENTONCES muestra «Conéctate a internet para iniciar sesión».
4. CUANDO vuelve la conexión en «modo sin conexión», ENTONCES la sesión se reanuda sola si la sesión de Keycloak sigue vigente; si no, se muestra el botón «Iniciar sesión».
5. CUANDO hay una versión nueva del ERP, ENTONCES se muestra «Hay una versión nueva · Recargar».

### Indicador

6. Mientras no hay conexión, la barra superior muestra «Sin conexión». Si hay borradores de planilla sin enviar, muestra «Borradores sin enviar (N)», que abre la planilla correspondiente.

### Consultas guardadas

7. Estas pantallas guardan en el equipo la última respuesta de cada consulta: lista de obras, detalle de obra, planilla, catálogo de materiales, stock de una obra y tablero.
8. SI no hay conexión o el gateway no responde, ENTONCES esas pantallas muestran lo guardado con el aviso «Sin conexión · datos del dd/mm/aaaa hh:mm». SI esa pantalla nunca se abrió en el equipo, ENTONCES «No hay datos guardados de esta pantalla».
9. Sin conexión, las acciones que escriben (registrar obra, crear o presentar planilla, crear o editar material, fijar mínimo) quedan deshabilitadas con «Requiere conexión». La única excepción es guardar el borrador de una planilla.

### Borrador de planilla

10. CUANDO el residente edita una planilla `BORRADOR` u `OBSERVADA` que ya abrió antes y pulsa «Guardar» sin conexión (o el envío falla por la red), ENTONCES el borrador (cantidades y fotos adjuntas) se guarda en el equipo y se muestra «Guardado en este equipo; se enviará al volver la conexión».
11. Las validaciones de la 007 (no superar lo contratado, totales en vivo) funcionan igual sin conexión, con los datos guardados.
12. CUANDO se vuelve a abrir una planilla que tiene borrador local, ENTONCES se muestran las cantidades del borrador con el aviso «Borrador local sin enviar (guardado dd/mm hh:mm)».
13. CUANDO vuelve la conexión, la sesión está activa y el microfrontend de Obras está abierto, ENTONCES el borrador se envía solo; SI se guarda bien, ENTONCES se borra del equipo y se muestra «Borrador de la planilla N.º X enviado».
14. SI la planilla cambió en el servidor mientras tanto (versión distinta), ENTONCES no se pisa: se muestra «La planilla cambió en el servidor» con dos opciones: «Aplicar mi borrador sobre la última versión» o «Descartar mi borrador».
15. SI la planilla ya no es editable (por ejemplo, ya fue presentada), ENTONCES se avisa «La planilla ya no se puede editar (estado X)» y solo se puede descartar el borrador.
16. SI el servidor rechaza el borrador por una regla (por ejemplo, supera lo contratado), ENTONCES el borrador se conserva y el editor muestra los errores para corregirlos.
17. «Presentar» requiere conexión y no se permite mientras haya un borrador local sin enviar. Crear una planilla nueva también requiere conexión.

### Privacidad

18. Los datos guardados se separan por usuario: otro usuario en el mismo navegador no ve los del anterior.
19. CUANDO el usuario cierra sesión, ENTONCES se borran del equipo sus datos guardados; SI tiene borradores sin enviar, ENTONCES se le avisa antes y se pide confirmación.

## Fuera del alcance

Crear o presentar planillas sin conexión; registrar obras o materiales sin conexión; trabajar sin conexión en el portal del cliente; notificaciones *push*; envío en segundo plano con el ERP cerrado (*Background Sync*); ver las fotos sin conexión (sus enlaces firmados vencen).
