# 101 · Registrar material sin señal (sincronización sin duplicados)

**Estado:** borrador (por aprobar) · **Capa:** 1 · **Puntos del ingeniero:** 7, 8 y 9 · **Proyectos:** services/sincronizacion (nuevo), app-obra, infra (DynamoDB Local)

## Historia

Como **almacenero** quiero registrar los ingresos y salidas de material aunque en la obra no haya señal, y que la app los envíe sola cuando vuelva la señal, para que el stock se conozca sin que ningún registro se pierda ni se cuente dos veces.

## Criterios de aceptación

### Datos guardados en el celular

1. CUANDO el usuario inicia sesión o abre la app con señal, ENTONCES la app descarga y guarda en el celular lo que necesita para trabajar sin señal: sus obras asignadas en ejecución, las partidas de cada obra (código, nombre y unidad), los materiales activos del catálogo y el stock de cada obra.
2. SI los datos no cambiaron desde la última descarga, ENTONCES el servidor responde «sin cambios» y no se vuelven a descargar.
3. CUANDO no hay señal, ENTONCES la app trabaja con los datos guardados y muestra «Sin señal · datos del dd/mm hh:mm».
4. SI la app nunca descargó los datos (primer uso sin señal), ENTONCES muestra «Necesitas señal la primera vez para descargar tus obras».
5. El usuario puede pulsar «Actualizar datos» cuando tiene señal.

### Sesión sin señal

6. CUANDO la app se abre sin señal y el usuario ya inició sesión antes en ese celular, ENTONCES entra con el último usuario (nombre y rol guardados) aunque su token haya vencido; los envíos esperan a que el token se renueve.
7. SI al volver la señal la sesión ya no se puede renovar, ENTONCES la app pide iniciar sesión de nuevo y no pierde los registros pendientes.

### Registro

8. CUANDO el almacenero registra un ingreso o una salida (mismos datos y validaciones que la 004), ENTONCES el registro se guarda primero en el celular con su UUID y la app muestra «Registrado» si el servidor lo confirma en ese momento, o «Guardado en el celular · se enviará cuando haya señal» si no.
9. El stock que muestra la app incluye los movimientos todavía no enviados y lo indica: «Incluye N movimientos sin enviar».
10. SI una salida supera el stock mostrado, ENTONCES la app muestra el mismo aviso que la 004 (criterio 5) y la guarda.

### Envío

11. CUANDO hay señal, ENTONCES la app envía los pendientes sola, en el orden en que se registraron y en lotes: al registrar, al volver la señal, al abrir la app y cada minuto mientras haya pendientes y la app esté abierta.
12. SI un envío falla por la red, por tiempo agotado o porque el servidor no está disponible, ENTONCES se reintenta con espera creciente (1 s, 2 s, 4 s… hasta un máximo de 5 minutos entre intentos).
13. SI una misma operación llega más de una vez al servidor (reintento, respuesta perdida, doble toque), ENTONCES se procesa una sola vez y se devuelve la misma respuesta que la primera vez.
14. SI el servicio dueño rechaza la operación por una regla del negocio (por ejemplo «El periodo 2026-11 ya está cerrado»), ENTONCES la operación queda «Rechazada» con ese motivo y no se reintenta.
15. Solo se envían los pendientes del usuario que tiene la sesión abierta en el celular.

### Pendientes de envío

16. Pantalla «Pendientes de envío» (maestro y almacenero), con un contador en el menú. Cada registro muestra tipo, descripción corta (por ejemplo «Salida · 12,5 bolsas de Cemento IP-30 · P-01»), fecha y hora de registro y estado: `Pendiente`, `Enviando`, `Enviado` o `Rechazado` (con el motivo).
17. Botón «Enviar ahora» (solo con señal). Los registros `Pendiente` y `Rechazado` tienen «Descartar», que pide confirmación. Los `Enviado` se muestran 24 horas y luego se borran del celular.
18. SI el usuario cierra sesión con pendientes, ENTONCES la app avisa «Tienes N registros sin enviar; se enviarán cuando vuelvas a iniciar sesión con este usuario», los conserva y borra los datos descargados.

### Servidor de sincronización

19. El servidor recuerda cada operación recibida durante 30 días, con su resultado.
20. El servidor guarda, por celular, el usuario, la obra con la que trabaja, la fecha de la última sincronización y la versión de los datos que descargó.

## Fuera del alcance

Envío en segundo plano con la app cerrada; editar o anular registros ya enviados; panel para ver los celulares y su última sincronización; fotos sin señal y subida por partes (102); diario de obra (103).
