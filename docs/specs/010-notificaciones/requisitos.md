# 010 · Notificaciones

**Estado:** aprobado · **Etapa:** sistema base (se agrega al final de la fase 2) · **Proyectos:** services/notificaciones (nuevo), services/obras, services/finanzas, services/materiales, gateway, erp-shell, mf-materiales, portal, app-obra, infra · **Depende de:** 001, 002, 003, 004, 007 y 008

## Historia

Como **usuario de la plataforma** (administración, residente, gerente, almacenero o cliente) quiero recibir un aviso cuando pasa algo que me toca resolver (una planilla para revisar, una planilla aprobada u observada, un material que se acaba, un cobro vencido, un contrato rechazado) y tener una bandeja con mis avisos, para enterarme a tiempo sin tener que revisar cada pantalla.

## Criterios de aceptación

### Qué se avisa y a quién (sistema base)

1. CUANDO el residente presenta una planilla (también cuando la vuelve a presentar después de una observación), ENTONCES el **cliente** de esa obra recibe «Planilla para revisar» (o «Planilla corregida para revisar») con número, periodo, obra y neto.
2. CUANDO una planilla queda `APROBADA`, ENTONCES el **residente** de la obra y **todos los usuarios con rol `admin`** reciben «Planilla aprobada» con número, periodo, obra y neto.
3. CUANDO una planilla queda `OBSERVADA`, ENTONCES el **residente** de la obra y **todos los `admin`** reciben el aviso con el motivo: «Planilla observada» si la observó el cliente, o «No se pudo aprobar la planilla» si falló la saga.
4. CUANDO el stock de un material en una obra baja del mínimo (aviso «stock bajo» de la 003 y la 004), ENTONCES el **almacenero** y el **residente** de esa obra reciben «Stock bajo: <material>» con la cantidad que queda y el mínimo.
5. CUANDO un cobro pasa a `VENCIDO` (tarea diaria de Finanzas, 008), ENTONCES **todos los `admin` y `gerente`** reciben «Cobro vencido <número>» con la obra, el monto y la fecha de vencimiento.
6. CUANDO Finanzas rechaza el contrato de una obra recién registrada (002), ENTONCES **todos los `admin`** reciben «Contrato rechazado» con la obra y el motivo.
7. Una persona recibe **un solo aviso por hecho**, aunque cumpla dos condiciones (por ejemplo, un usuario que fuera residente y `admin` a la vez) y aunque el mensaje del hecho llegue más de una vez.
8. Los textos están en español, los montos como `Bs 41.881,80`, las fechas como `02/05/2027` en hora de La Paz y los periodos como «marzo 2027».

### Bandeja de notificaciones

9. En el **ERP** (barra superior del shell), en el **portal** (barra superior) y en la **app** (pestaña «Avisos»), el usuario ve una campana con el número de avisos sin leer (más de 9 se muestra «9+»; sin avisos sin leer, no se muestra número).
10. CUANDO abre la bandeja, ENTONCES ve sus avisos del más reciente al más antiguo (20 por vez, con «Ver más»), con título, mensaje, fecha y hora; los no leídos se distinguen. Sin avisos: «No tienes notificaciones».
11. CUANDO toca un aviso, ENTONCES el aviso queda leído y, si la aplicación tiene la pantalla relacionada, lo lleva a ella:

| Aviso | ERP | Portal | App |
|---|---|---|---|
| Planilla presentada | — | planilla | — |
| Planilla aprobada u observada | editor de la planilla | — | (solo la bandeja) |
| Stock bajo | stock de la obra en Materiales | — | stock de la obra |
| Cobro vencido | detalle de la obra | — | — |
| Contrato rechazado | detalle de la obra | — | — |

12. «Marcar todas como leídas» deja en cero el contador.
13. Un aviso leído en una aplicación aparece leído en las demás (por ejemplo, el residente que lo lee en el ERP no lo ve como nuevo en la app).
14. Cada usuario ve **solo sus avisos**. Los avisos se guardan 90 días (decisión del equipo).
15. El contador se actualiza solo: al llegar un aviso *push* con la aplicación abierta y, además, cada 60 segundos (decisión del equipo).
16. SI el servicio de notificaciones no responde, ENTONCES la campana no muestra número, la bandeja muestra «No disponible por el momento · Reintentar» y el resto de la aplicación funciona igual.

### Avisos *push*

17. **Web (ERP y portal):** la bandeja ofrece «Activar avisos en este navegador». CUANDO el usuario acepta el permiso del navegador, ENTONCES recibe los avisos como notificaciones del sistema operativo aunque la pestaña esté en segundo plano o cerrada (con el navegador abierto). Al tocarla se abre la pantalla del criterio 11.
18. SI el usuario bloqueó el permiso en el navegador, ENTONCES la bandeja lo indica («Los avisos están bloqueados en este navegador») y el historial funciona igual.
19. CUANDO llega un aviso con la aplicación web abierta y visible, ENTONCES no se muestra la notificación del sistema: se actualiza el contador y aparece un mensaje breve en la pantalla.
20. **App (solo Android, decisión del equipo):** después de iniciar sesión la app pide permiso para mostrar notificaciones (una vez). Con permiso, los avisos llegan como notificaciones de Android aunque la app esté cerrada; al tocarlas se abre la app en la pantalla del criterio 11.
21. Los avisos *push* en Android solo funcionan en la *development build* o en la versión instalada (APK), **no en Expo Go**. En Expo Go la app no pide permiso y la bandeja funciona igual.
22. Un dispositivo (navegador o celular) recibe solo los avisos del **último usuario que inició sesión en él**. Al cerrar sesión, el dispositivo deja de recibir los avisos de ese usuario.
23. SI un dispositivo ya no es válido (la aplicación se desinstaló o el navegador borró sus datos), ENTONCES se deja de usar sin afectar a los demás dispositivos del usuario.

### Funcionamiento sin Firebase

24. SI Firebase no está configurado (en el servidor, en las aplicaciones web o en la app), ENTONCES no se envían avisos *push* ni se pide permiso, todos los avisos se guardan en la bandeja igual y el servicio registra en su log «Firebase no configurado: las notificaciones se guardan sin envío push».
25. Para activar los avisos *push* basta con agregar las credenciales de Firebase (sección «Configuración de Firebase» del diseño); no hace falta cambiar código.

### Destinatarios por rol

26. Los avisos para «todos los `admin`» o «todos los `gerente`» llegan a los usuarios con ese rol que **entraron al menos una vez** a alguna aplicación de la plataforma desde que existe el servicio de notificaciones (decisión del equipo; ver diseño). Los avisos por obra (cliente, residente, almacenero) llegan aunque el usuario nunca haya entrado.

## Avisos que agregan las capas (lista para que las sumen)

Cada capa los especifica en su propio `diseno.md`, sección «Cambios a contratos y datos»; aquí solo se reservan:

| Capa | Aviso | Destinatarios propuestos | Hecho que lo dispara |
|---|---|---|---|
| 201 · Compra automática | «Orden de compra creada» | todos los `admin` y el almacenero de la obra | `evento.finanzas.OrdenCompraCreada` (ya definido en la 201) |
| 402 · Riesgo de retraso | «Riesgo alto de retraso» | residente de la obra y todos los `gerente` | evento nuevo que la 402 debe publicar cuando una obra pasa a nivel `ALTO` |
| 502 · Agentes del ERP | «El agente terminó su revisión» | el usuario que lanzó la ejecución (o todos los `gerente` si fue la programada) | evento nuevo que la 502 debe publicar cuando una ejecución termina (`COMPLETADA` o `FALLIDA`) |

## Fuera del alcance

Avisos por correo, SMS, WhatsApp o Telegram; iOS (y Safari en iOS); que el usuario elija qué tipos de aviso recibir o silencie avisos; avisos programados o recordatorios; notificaciones dentro de los microfrontends (solo la campana del shell); borrar avisos a mano; avisos para el maestro de obra en el sistema base (no hay hechos que le toquen); que un aviso ejecute acciones.
