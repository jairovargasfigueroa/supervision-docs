# 201 · Compra automática por stock bajo

**Estado:** borrador (por aprobar) · **Capa:** 2 · **Punto del ingeniero:** 13 · **Proyectos:** infra (n8n, Mailpit, Keycloak, RabbitMQ), services/finanzas, services/materiales, services/sincronizacion, gateway, mf-materiales, app-obra · **Depende de:** 003, 004 y 101

## Historia

Como **administración** quiero que, cuando un material queda por debajo del mínimo en una obra, se genere sola la orden de compra al proveedor habitual y se le envíe por correo, y que al recibir ese material se registre la cuenta por pagar, para no quedarnos sin material ni olvidar lo que se debe.

## Criterios de aceptación

### Proveedor habitual

1. Los proveedores vienen como datos iniciales (nombre, correo y teléfono); no hay pantalla para darlos de alta.
2. CUANDO administración crea o edita un material (003), ENTONCES puede elegir su proveedor habitual de la lista de proveedores (opcional).
3. SI un material no tiene proveedor habitual, ENTONCES el catálogo lo marca «Sin proveedor habitual: no se generarán órdenes automáticas».

### Orden de compra

4. CUANDO el stock de un material en una obra queda por debajo del mínimo (aviso «stock bajo» de la 003 y la 004), ENTONCES n8n pide a Finanzas crear una orden de compra al proveedor habitual de ese material.
5. La orden tiene número `OC-<año>-<correlativo de 4 dígitos>` (correlativo global por año, como el cobro; decisión del equipo), obra, material, proveedor, cantidad, precio unitario (el precio referencial del material) y monto = cantidad × precio unitario.
6. Cantidad a pedir = lo necesario para llegar al doble del mínimo: 2 × mínimo − cantidad actual, redondeado hacia arriba al entero (decisión del equipo).
7. SI el mismo aviso llega más de una vez, ENTONCES se crea una sola orden.
8. SI ya hay una orden sin recibir (`CREADA` o `ENVIADA`) del mismo material para la misma obra, ENTONCES no se crea otra ni se envía otro correo.
9. SI el material no tiene proveedor habitual, ENTONCES no se crea la orden y la ejecución queda registrada como fallida en n8n con el motivo.

### Correo al proveedor

10. CUANDO se crea la orden, ENTONCES n8n envía un correo al proveedor con número de orden, nombre de la empresa, obra, material, cantidad con su unidad, precio unitario y monto, y la orden pasa a `ENVIADA`.
11. SI el correo no se puede enviar, ENTONCES n8n lo reintenta 3 veces; si sigue fallando, la orden queda `CREADA` y la pantalla la muestra como «Correo no enviado».

### Recepción del material

12. CUANDO el almacenero registra en la app un ingreso, ENTONCES puede indicar que corresponde a una orden de compra pendiente de esa obra y ese material (lista con número, proveedor y cantidad pedida). Funciona también sin señal (101).
13. CUANDO ese ingreso queda registrado, ENTONCES Materiales avisa «compra recibida», n8n pide a Finanzas crear la cuenta por pagar y la orden pasa a `RECIBIDA`.
14. Cuenta por pagar: proveedor, orden, monto = cantidad recibida × precio unitario de la orden, emitida en la fecha del ingreso (hora de La Paz) y con vencimiento a los 30 días calendario (decisión del equipo).
15. SI el aviso de compra recibida llega más de una vez, ENTONCES se crea una sola cuenta por pagar.
16. Una orden se recibe en un solo ingreso (decisión del equipo). SI la orden ya fue recibida o no corresponde a la obra o al material, ENTONCES el ingreso se rechaza con «La orden de compra no está pendiente para este material» y el almacenero lo vuelve a registrar sin orden.

### Pantalla

17. CUANDO administración o gerencia abre «Órdenes de compra» en Materiales, ENTONCES ve la lista con número, fecha, obra, material, cantidad con unidad, proveedor, monto, estado y, si existe, la cuenta por pagar (monto y vencimiento), con filtros por obra y estado. Es solo de lectura.
18. Solo `admin` y `gerente` ven las órdenes de compra.

## Fuera del alcance

Aprobación de compras de monto alto; crear, editar, anular o reenviar órdenes desde pantalla; recepciones parciales en varios ingresos; registro de pagos al proveedor; avisos por WhatsApp o Telegram; respuesta del proveedor; comparación de precios entre proveedores.
