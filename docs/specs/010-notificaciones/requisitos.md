# 010 · Avisos al celular y al cliente

**Estado:** borrador (por aprobar) · **Etapa:** sistema base (se hace después de la 201) · **Proyectos:** services/obras, mobile/app-obra, infra (n8n, Firebase) · **Depende de:** 003, 004, 007, 103 y 201

**Decisiones de Jairo (02/11/2026):** reemplaza a la versión anterior (servicio `services/notificaciones` nuevo, bandeja con campanita en el ERP, el portal y la app, *push* web y seis tipos de aviso), que era grande para lo que aporta y no la pidió el ingeniero. Cada usuario recibe pocos avisos, solo los importantes y por el canal que usa de verdad: el **cliente** usa el portal web, así que se le avisa por **correo** (como la cobranza de la 201); el **maestro** y el **almacenero** usan la app, así que se les avisa con *push* al **celular**. Sin bandeja ni historial.

## Historia

Como **almacenero** quiero que me llegue un aviso al celular cuando un material de mi obra baja del mínimo, para pedirlo antes de que falte. Como **maestro** quiero que el celular me recuerde el diario de obra si no lo registré, para no olvidarlo. Como **cliente** quiero recibir un correo cuando me presentan una planilla, para revisarla a tiempo.

## Criterios de aceptación

### Aviso de stock bajo (*push* al almacenero)

1. CUANDO el stock de un material en una obra baja del mínimo (aviso «stock bajo» de la 003 y la 004: una salida que lo deja por debajo, o un mínimo nuevo mayor que el stock), ENTONCES al celular del **almacenero** de esa obra le llega «Stock bajo: {material}» con «{obra}: quedan {cantidad} {unidad} (mínimo {mínimo})», en menos de 1 minuto.
2. Llega una vez por cada vez que el material cruza el mínimo (así se publica el aviso «stock bajo»); si el mismo aviso llega dos veces, se manda un solo *push*.
3. CUANDO el almacenero toca el aviso, ENTONCES la app abre el stock de esa obra.

### Recordatorio del diario (*push* al maestro)

4. Todos los días a las 18:00 de La Paz (decisión del equipo), por cada obra `EN_EJECUCION` que no tiene entrada del diario de ese día, al celular del **maestro** de la obra le llega «Diario pendiente: {obra}» con «Todavía no registraste el diario de hoy.».
5. CUANDO el maestro toca el aviso, ENTONCES la app abre el diario de esa obra.
6. SI el maestro registró el diario sin señal y todavía no se envió, ENTONCES el recordatorio puede llegar igual: el texto agrega «Si ya lo registraste sin señal, se enviará al volver la señal.».

### En la app

7. La primera vez que el maestro o el almacenero entra con señal, la app pide permiso para mostrar notificaciones (Android 13 o posterior). SI lo niega, ENTONCES la app funciona igual, sin avisos.
8. La app recibe los avisos de **sus obras asignadas** (las del paquete de datos de la 101) y deja de recibirlos de una obra que ya no tiene asignada (al actualizar los datos) y de todas al cerrar sesión.
9. Con la app abierta, el aviso se muestra dentro de la app (mensaje breve) en lugar de la notificación del sistema.
10. Los avisos funcionan en la *development build* y en la versión instalable de Android, no en Expo Go (como la 301).

### Planilla para revisar (correo al cliente)

11. CUANDO el residente presenta una planilla (007), ENTONCES n8n envía al **cliente** de la obra un correo «Planilla para revisar: N.º {número} · {obra} · {periodo}» con el neto y el enlace a la planilla en el portal, en menos de 1 minuto. SI la vuelve a presentar después de una observación, ENTONCES el asunto es «Planilla corregida para revisar: …».
12. SI el aviso de planilla presentada llega más de una vez, ENTONCES se envía un solo correo.
13. El correo va solo al cliente, sin copia a cobranzas (es un aviso de trabajo, no de cobro). Como en la 201, en desarrollo llega a Mailpit y, si el cliente no tiene correo, la ejecución queda fallida en n8n con el motivo «El cliente no tiene correo registrado».

### Funcionamiento

14. Los tres avisos los envía n8n (con los de la 201, toda la mensajería automática queda en un solo lugar): escucha los eventos y la hora, pide los datos a Obras, Materiales y Keycloak con los endpoints que ya existen, y envía el correo por SMTP o el *push* por Firebase Cloud Messaging.
15. SI Firebase no está configurado, ENTONCES los dos flujos de *push* no se activan (quedan en el panel de n8n sin publicar) y el resto de la plataforma funciona igual.
16. SI un envío falla, ENTONCES n8n reintenta 3 veces; si sigue fallando, la ejecución queda fallida en su panel con el motivo.

## Fuera del alcance

Bandeja de avisos, campanita y contador; historial y marcas de leído; *push* en el navegador (ERP y portal); *push* en iOS; otros avisos (planilla aprobada u observada, cobro vencido, contrato rechazado, registros rechazados al sincronizar); que el usuario elija qué avisos recibir; un servicio de notificaciones propio.
