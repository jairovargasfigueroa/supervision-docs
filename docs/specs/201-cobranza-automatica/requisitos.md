# 201 · Cobranza automática

**Estado:** borrador (por aprobar) · **Capa:** 2 · **Punto del ingeniero:** 13 · **Proyectos:** infra (n8n, Mailpit, Keycloak, RabbitMQ), services/finanzas, services/ia, gateway, mf-obras (services/obras solo da datos, sin cambios de código) · **Depende de:** 006, 008 y 401

**Decisiones de Jairo (01/11/2026):** reemplaza a la compra automática por stock bajo (comprar sin que nadie revise no es realista). La automatización del punto 13 es la **cobranza**: lo que pasa con el cobro después de que la saga lo emite. El ingeniero describe flujos 100 % automáticos que pasan por varios servicios y terminan en una salida para el usuario, con n8n; aquí el disparador es la aprobación de la planilla (o la hora), los servicios son Obras, Finanzas y Keycloak, y la salida son los correos al cliente. Se agrega un **registro de pago mínimo** (antes fuera del alcance desde el recorte del 26/10/2026): sin él, un cobro pagado termina `VENCIDO` y el sistema le recordaría la deuda a un cliente que ya pagó.

## Historia

Como **administración** quiero que, cuando el cliente aprueba una planilla, le llegue solo su nota de cobro, que se le recuerde antes y después del vencimiento y que reciba una constancia cuando registro su pago, para cobrar a tiempo sin hacer ese seguimiento a mano. Como **cliente** quiero recibir por correo lo que debo, cuándo vence y la constancia de lo que pagué.

## Criterios de aceptación

### Registro de pago (ERP)

1. CUANDO `admin` abre la pestaña «Cobros» del detalle de una obra (006), ENTONCES cada cobro `PENDIENTE` o `VENCIDO` tiene el botón «Registrar pago».
2. «Registrar pago» pide la **fecha de pago** (obligatoria; por defecto hoy en La Paz; no puede ser futura ni anterior a la emisión del cobro) y el **n.º de comprobante** (opcional, hasta 50 caracteres). Se paga el cobro completo (decisión del equipo).
3. CUANDO confirma, ENTONCES el cobro pasa a `PAGADO` con la fecha, el comprobante y quién lo registró, y la pestaña muestra «Pagado el dd/mm/aaaa» en verde.
4. Un cobro `PAGADO` no vuelve a vencerse, no se puede pagar otra vez ni deshacer. SI se intenta pagar un cobro ya pagado, ENTONCES se muestra «El cobro ya está pagado».
5. Solo `admin` registra pagos; `gerente` ve el estado y los datos del pago.
6. Un cobro `PAGADO` no cuenta como vencido ni por vencer en el tablero (009), no lo informa el agente de cobros (502) y no recibe recordatorios. Los reportes de cobros (503) muestran el estado `PAGADO` y su fecha de pago. El saldo del contrato no cambia al pagar (se calcula con los cobros emitidos).

### Nota de cobro al cliente (flujo «Enviar nota de cobro»)

7. CUANDO la saga emite un cobro (008), ENTONCES n8n, sin que nadie intervenga, envía al cliente de la obra un correo «Nota de cobro {número} · {obra} · {periodo}» con la **nota de cobro en PDF** adjunta, en menos de 1 minuto (decisión del equipo).
8. La nota de cobro tiene: nombre de la empresa, cliente, obra, planilla N.º y periodo, las líneas del mes (código, partida, unidad, cantidad del periodo, precio unitario y monto; solo las de cantidad mayor a 0), subtotal, descuento por anticipo, retención, neto a cobrar, número de cobro, fecha de emisión y vencimiento, y la leyenda «Este documento no es una factura».
9. Cada correo al cliente va con copia oculta al correo de cobranzas de la empresa (`cobranzas@constructora-andina.test` en desarrollo; decisión del equipo).
10. SI el aviso de cobro emitido llega más de una vez, ENTONCES se envía una sola nota de cobro.

### Recordatorios (flujo «Recordar cobros»)

11. Todos los días a las 08:00 de La Paz (decisión del equipo), n8n pide a Finanzas los cobros que necesitan recordatorio:
    - **por vencer:** `PENDIENTE` que vence entre hoy y hoy + 3 días (decisión del equipo), sin recordatorio «por vencer» enviado;
    - **vencido:** vencido (estado `VENCIDO`, o `PENDIENTE` con vencimiento anterior a hoy), sin recordatorio «vencido» enviado.
12. A cada cliente le envía un correo:
    - por vencer: «Su cobro {número} de Bs {monto} por la obra {obra} vence el {fecha}.»;
    - vencido: «Su cobro {número} de Bs {monto} por la obra {obra} venció el {fecha}.»;
    - los dos terminan con «Si ya realizó el pago, no tome en cuenta este mensaje.».
13. Si hubo al menos un recordatorio, envía a cobranzas un **resumen del día** con la lista de cobros recordados (número, obra, monto, vencimiento y tipo). Sin recordatorios, no envía nada.
14. Cada cobro recibe como máximo un recordatorio de cada tipo. Un cobro `PAGADO` no recibe ninguno.

### Constancia de pago (flujo «Enviar constancia de pago»)

15. CUANDO `admin` registra el pago de un cobro (criterio 3), ENTONCES n8n envía al cliente un correo «Constancia de pago {número} · {obra}» con el número de cobro, la obra, el monto, la fecha de pago y el comprobante (si lo hay), con copia oculta a cobranzas.
16. SI el aviso de pago llega más de una vez, ENTONCES se envía una sola constancia.

### Seguimiento en el ERP

17. En la pestaña «Cobros» (`admin` y `gerente`), cada cobro muestra qué correos se enviaron y cuándo: «Nota enviada», «Recordatorio por vencer», «Recordatorio de vencido», «Constancia enviada» (con fecha y hora). Si la nota todavía no salió: «Nota sin enviar».

### Funcionamiento de la automatización

18. Los flujos viven en n8n. Las reglas (qué cobros necesitan recordatorio, qué datos lleva la nota, los montos) las deciden los servicios: n8n pide los datos, los une, envía los correos y anota en Finanzas lo que envió (decisión del equipo).
19. SI un paso falla (un servicio no responde o el correo no sale), ENTONCES n8n lo reintenta 3 veces; si sigue fallando, la ejecución queda como fallida en el panel de n8n con el motivo y el ERP muestra el correo como no enviado. Se puede reintentar desde el panel de n8n sin enviar dos veces el mismo correo.
20. SI el cliente de la obra no tiene correo en Keycloak, ENTONCES no se envía nada y la ejecución queda fallida con el motivo «El cliente no tiene correo registrado».
21. En desarrollo los correos no salen a internet: llegan a Mailpit (buzón de prueba). En la nube se configura un servidor de correo real (capa 6).

## Fuera del alcance

Pagos parciales; anular o corregir un pago; devolución de la retención; medios de pago y conciliación con el banco; facturación ante Impuestos Nacionales (la nota de cobro no es una factura); pagos a proveedores, órdenes de compra y cuentas por pagar; avisos por WhatsApp, Telegram o SMS; ver los cobros o pagar desde el portal; que el cliente elija no recibir correos; plantillas de correo editables desde el ERP.
