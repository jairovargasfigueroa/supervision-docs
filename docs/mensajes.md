# Catálogo de mensajes para el usuario

Qué texto ve la persona para cada `codigo` de error y para cada aviso que no es un error. Se arma con los códigos de los contratos (`docs/contratos/*`, `services/*/docs/contratos.md`, `gateway/docs/contratos.md`), de las specs (`docs/specs/*`) y de `docs/convenciones.md` («Errores REST» y «Errores GraphQL»).

En la columna **Origen**, «texto de la spec» indica que el mensaje se copió tal cual de la especificación citada (si requisito y diseño decían distinto, manda el requisito y el diseño ya se corrigió); «catálogo» indica que la spec define el código o la pantalla pero no el texto, y el texto vale desde este catálogo. Ningún código de este catálogo es nuevo: todos están en las fuentes. Las contradicciones que había se resolvieron y se listan al final.

## Cómo se usa

- Cada frontend tiene un archivo `errores.ts` (en mf-obras, un servicio de Angular equivalente) que mapea `codigo` → mensaje de este catálogo: shell (notificaciones), mf-obras, mf-materiales, mf-supervision, portal y app de obra. Cada uno incluye solo los códigos que puede recibir (columna **Se ve en**).
- **Dónde está el código:** en REST, el campo `codigo` del Problem Details; en GraphQL, `errors[].extensions.codigo` (y `extensions.servicio` dice qué servicio falló); en la app de obra, el `codigo` del resultado de cada operación de `POST /lotes` (101).
- **Código desconocido:** si el código no está en el mapa, se muestra el mensaje **genérico de su estado HTTP** (tabla «Genéricos»). El `detail` del servicio no se muestra al usuario; queda en el registro para soporte. Vale también para la app (101).
- **Errores por campo:** si la respuesta trae `errores[]` (`400` o `422`), cada `mensaje` se muestra junto a su `campo`, y arriba el mensaje del código. Cuando un código puede deberse a reglas distintas (`COMENTARIO_INVALIDO`), la regla concreta llega en `errores[].mensaje` (convenciones).
- **Marcadores** entre llaves (`{codigo}`, `{saldo}`, `{periodo}`…): los completa el frontend con datos que ya tiene en pantalla o que vienen en `errores[]`. Si no tiene el dato, usa la frase sin esa parte.
- **Formato:** montos con «Bs» y 2 decimales; fechas `dd/mm/aaaa` (o `dd/mm` donde la spec lo dice); periodos `AAAA-MM` (en las notificaciones, «marzo 2027»), como en `docs/diseno-visual.md` y el `formato.ts` de cada proyecto.
- Los mensajes no muestran nombres técnicos (servicio, endpoint, `codigo`); el `codigo` y el `X-Request-Id` van a la consola para soporte.

## Genéricos

Todo error lleva `codigo`; sin uno propio, el servicio usa el genérico de su estado (convenciones). Un estado escrito sin código en un contrato («`400`», «`403`») significa este genérico.

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Origen |
|---|---|---|---|---|---|
| `DATOS_INVALIDOS` | 400 | Faltan campos o tienen un formato incorrecto | «Algunos datos no son válidos. Revisa los campos marcados.» | Corregir los campos y volver a enviar | convenciones · catálogo |
| `PAGINACION_INVALIDA` | 400 | Una lista paginada pidió más de 100 elementos por página | «No se pudo cargar la lista. Recarga la página.» | Recargar | convenciones · catálogo |
| `NO_AUTENTICADO` | 401 | Sin token o token inválido, y no se pudo renovar solo (001, criterio 8) | «Tu sesión terminó. Vuelve a iniciar sesión.» | Iniciar sesión | convenciones, 001 · catálogo |
| `SIN_PERMISO` | 403 | El rol del usuario no permite esa acción | «No tienes permiso para hacer esta acción.» | Si crees que es un error, pide a administración que revise tu rol | convenciones · catálogo |
| `RUTA_NO_ENCONTRADA` | 404 | La ruta pedida no existe en el servicio (error de programación o de versión; con token válido) | «No encontramos lo que buscas. Puede que ya no exista o que no tengas acceso.» | Volver a la lista | convenciones (fase 1) · catálogo |
| (código desconocido) | 404 | Un «no encontrado» que el frontend no conoce | «No encontramos lo que buscas. Puede que ya no exista o que no tengas acceso.» | Volver a la lista | catálogo |
| (código desconocido) | 409 | Conflicto de estado o de versión que el frontend no conoce | «Los datos cambiaron mientras trabajabas. Recarga para ver la última versión.» | Recargar | catálogo |
| `ARCHIVO_DEMASIADO_GRANDE` | 413 | El cuerpo supera el límite (lote de Sincronización de más de 256 KB) | «El envío supera el tamaño permitido.» | Si se repite, avisar a soporte | convenciones, 101 · catálogo |
| (código desconocido) | 422 | Regla del negocio que el frontend no conoce | «No se pudo completar la operación porque no cumple una regla del sistema.» | Revisar los datos o consultar al residente o a administración | catálogo |
| `DEMASIADAS_PETICIONES` | 429 | Ráfaga de pedidos | «Hiciste muchas solicitudes seguidas. Espera un momento e intenta de nuevo.» | Esperar y reintentar | convenciones · catálogo |
| `ERROR_INTERNO` | 500 | Falla inesperada del servidor (también error de una herramienta MCP, 501) | «Ocurrió un error inesperado. Intenta de nuevo; si se repite, avisa a soporte.» | Reintentar | convenciones · catálogo |
| `SERVICIO_NO_DISPONIBLE` | 503 | El servicio, o uno que necesita, no está disponible (en GraphQL, ver «Gateway») | «Este servicio no está disponible por el momento. Intenta de nuevo en unos minutos.» | Reintentar más tarde | convenciones · catálogo |
| `TIEMPO_AGOTADO` | 504 | El servicio llamó a otro y no recibió respuesta en su tiempo máximo | «El servidor tardó demasiado en responder. Intenta de nuevo.» (en reportes por voz, ver «IA») | Reintentar | convenciones · catálogo |
| (error de red) | — | No hay conexión con el servidor | ERP y portal: «No hay conexión con el servidor. Revisa tu conexión a internet e intenta de nuevo.» · ERP con la 104: se muestra lo guardado con «Sin conexión · datos del dd/mm/aaaa hh:mm». · App con la 101: «Guardado en el celular · se enviará cuando haya señal» | Revisar la conexión; en la app no hace falta hacer nada | 101, 104 · texto de la spec (app y ERP sin conexión); catálogo (resto) |
| (tiempo agotado en el navegador o la app) | — | El pedido no recibió respuesta en el tiempo máximo del cliente (por ejemplo 30 s por lote en la app) | «La respuesta está tardando demasiado. Revisa tu conexión e intenta de nuevo.» · En la app se trata como fallo de red y se reintenta solo (102, criterio 11) | Reintentar | 101, 102 · catálogo |

## Gateway (GraphQL)

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `SERVICIO_NO_DISPONIBLE` | 503 (en `extensions`) | Un servicio no respondió, por error o por pasar los 3 s del gateway (60 s en `consultarReporteVoz`); solo sus campos llegan en `null` | En una sección o pestaña: «No disponible por el momento». En el tablero: «—» con «Datos de {servicio} no disponibles» (`{servicio}`: Obras, Materiales, Finanzas o IA). En la bandeja de notificaciones: «No disponible por el momento · Reintentar» (la campana queda sin número) | Pulsar «Actualizar» o «Reintentar» | ERP | 006 (criterio 4), 009 (criterio 5), 010 (criterio 16), 402 (criterio 12), 502 (criterio 21) · texto de la spec |

Los genéricos del propio gateway (token, rol del `RolesGuard`, datos) usan los mismos códigos: `NO_AUTENTICADO`, `SIN_PERMISO`, `DATOS_INVALIDOS`.

## Obras

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `PRESUPUESTO_NO_COINCIDE` | 422 | La suma de las partidas no es igual al monto del contrato (tolerancia 0,01) | «El presupuesto (Bs {presupuesto}) no coincide con el monto del contrato (Bs {monto})» | Ajustar partidas o monto del contrato | ERP · Obras | 002 (criterio 6) · texto de la spec |
| `CODIGO_PARTIDA_REPETIDO` | 422 | Dos partidas de la obra tienen el mismo código | «Hay partidas con el mismo código ({codigo}). Cada partida debe tener un código distinto.» | Cambiar el código repetido | ERP · Obras | 002 · catálogo |
| `INSUMO_REPETIDO` | 422 | Una partida tiene el mismo material dos veces | «La partida {codigo} tiene el mismo material más de una vez.» | Dejar una sola fila por material | ERP · Obras | 002 · catálogo |
| `CONTRATO_INVALIDO` | 422 | Monto o plazo ≤ 0, anticipo o retención fuera de 0 a 100, o su suma ≥ 100 | «Los datos del contrato no son válidos: el monto y el plazo deben ser mayores a 0, y el anticipo y la retención deben estar entre 0 y 100 y sumar menos de 100.» | Corregir el paso «Contrato» | ERP · Obras | 002 · catálogo |
| `OBRA_NO_ENCONTRADA` | 404 | La obra no existe o el usuario no puede verla (también en Materiales, IA y en las herramientas MCP) | «Obra no encontrada» | Volver a la lista de obras | ERP, portal, app | 006 (criterio 6) · texto de la spec |
| `PARTIDA_NO_ES_DE_LA_OBRA` | 422 | La foto de avance indica una partida de otra obra | «La partida elegida no pertenece a esta obra.» | Pulsar «Actualizar datos» y elegir otra partida | App | 005 · catálogo |
| `CLAVE_ARCHIVO_INVALIDA` | 422 | La clave del archivo no corresponde al registro (foto de avance 005, también enviada por Sincronización en la 102; versión para el cliente 303) | «No se pudo asociar el archivo a este registro.» | App: descartar y volver a tomar la foto. ERP: «Volver a preparar» | App, ERP · Obras | 005, 102, 303 · catálogo |
| `PLANILLA_ABIERTA_EXISTE` | 409 | Ya hay una planilla sin aprobar en la obra | «Ya hay una planilla sin aprobar en esta obra. Termínala antes de crear otra.» | Abrir la planilla existente desde la pestaña «Planillas» | ERP · Obras | 007 (criterio 2) · catálogo |
| `PERIODO_NO_POSTERIOR` | 422 | El periodo no es posterior al de la última planilla | «El periodo debe ser posterior al de la última planilla ({periodoUltima}).» | Elegir un mes posterior | ERP · Obras | 007 (criterio 2) · catálogo |
| `PERIODO_FUTURO` | 422 | El periodo es un mes futuro | «No se puede crear la planilla de un mes que todavía no llegó.» | Elegir el mes actual o uno anterior | ERP · Obras | 007 (criterio 2) · catálogo |
| `OBRA_NO_EN_EJECUCION` | 422 | Crear planilla o registrar diario en una obra que no está `EN_EJECUCION` | «La obra no está en ejecución» | Esperar a que se registre el contrato de la obra | ERP · Obras, app | 007, 103 (diseño) · texto de la spec |
| `VERSION_DESACTUALIZADA` | 409 | Otra persona guardó la planilla antes (versión distinta) | «La planilla cambió, recarga para ver la última versión». Con borrador local (104): «La planilla cambió en el servidor» con «Aplicar mi borrador sobre la última versión» o «Descartar mi borrador» | Recargar / elegir una opción | ERP · Obras | 007 (criterio 7), 104 (criterio 14) · texto de la spec |
| `PLANILLA_NO_EDITABLE` | 409 | La planilla no está en `BORRADOR` ni `OBSERVADA` | «La planilla ya no se puede editar (estado {estado})» | Recargar; con borrador local, solo «Descartar mi borrador» | ERP · Obras | 104 (criterio 15) · texto de la spec |
| `SUPERA_CANTIDAD_CONTRATADA` | 422 | Acumulado anterior + cantidad del periodo > cantidad contratada (`errores[]` por partida) | En cada fila: «Supera lo contratado (saldo: {saldo})». Arriba: «Hay filas que superan lo contratado. Corrígelas para guardar.» | Bajar la cantidad de las filas marcadas | ERP · Obras | 007 (criterio 5) · texto de la spec (fila); catálogo (arriba) |
| `FOTO_FUERA_DEL_PERIODO` | 422 | Se adjuntó una foto registrada fuera del periodo de la planilla | «Una de las fotos adjuntas no es de este periodo. Quítala para guardar.» | Quitar la foto | ERP · Obras | 007 · catálogo |
| `SUBTOTAL_CERO` | 422 | Se intenta presentar una planilla con subtotal 0 | «No se puede presentar una planilla con subtotal 0. Indica las cantidades ejecutadas del periodo.» | Cargar cantidades y guardar | ERP · Obras | 007 (criterio 8) · catálogo |
| `PLANILLA_NO_ENCONTRADA` | 404 | La planilla no existe, es de una obra que el usuario no ve o es un `BORRADOR` y la pide el cliente | «Planilla no encontrada» | Volver a la obra | ERP · Obras, portal | 007, 008 · catálogo |
| `FOTO_SIN_VERSION_CLIENTE` | 422 | Al presentar, alguna foto adjunta no tiene versión con rostros difuminados (`errores[]` por `fotoId`) | Por foto: «Falta la versión para el cliente». Arriba: «Prepara la versión para el cliente de todas las fotos antes de presentar.» | Preparar las fotos que faltan o quitarlas | ERP · Obras | 303 (diseño) · texto de la spec (por foto); catálogo (arriba) |
| `FOTO_NO_ENCONTRADA` | 404 | La foto no existe o no es de esa obra (303) | «No encontramos la foto. Puede que ya no esté adjunta a la planilla.» | Recargar la planilla | ERP · Obras | 303 · catálogo |
| `ARCHIVO_NO_SUBIDO` | 422 | Se registra la versión para el cliente pero el archivo no está en el almacenamiento | «La versión para el cliente no terminó de subirse. Intenta de nuevo.» | Reintentar la foto | ERP · Obras | 303 · catálogo |
| `PLANILLA_NO_PRESENTADA` | 409 | El cliente aprueba u observa una planilla que ya no está `PRESENTADA` | «Esta planilla ya no está esperando tu revisión. Recarga para ver su estado actual.» | Recargar | Portal | 008 · catálogo |
| `MOTIVO_INVALIDO` | 422 | Motivo fuera de 10 a 500 caracteres (observar planilla, 008; rechazar sugerencia, 502) | «El motivo debe tener entre 10 y 500 caracteres.» | Ajustar el texto | Portal, ERP | 008, 502 · catálogo |
| `DIARIO_DIA_YA_REGISTRADO` | 409 | Ya existe una entrada del diario para esa obra y fecha | «Ya existe una entrada del diario para ese día» | Descartar la entrada repetida | App | 103 (criterio 9) · texto de la spec |
| `FECHA_DIARIO_INVALIDA` | 422 | Fecha futura o anterior al inicio de la obra | «La fecha no es válida para esta obra» | Descartar y registrar con otra fecha | App | 103 (diseño) · texto de la spec |
| `RANGO_INVALIDO` | 400 | Consulta del diario de más de 366 días | «El rango de fechas es demasiado amplio (máximo 366 días).» | Acortar el rango | — (solo API; no hay pantalla) | 103 · catálogo |
| `DETECCION_DESCARTADA` | 201 (aviso) | Los conteos de casco y chaleco no eran coherentes; la foto se guardó sin ellos | «La foto se guardó, pero sin el análisis de casco y chaleco.» | Ninguna | App | 301 · decisión del equipo |

### Motivos de observación que pone la saga

No son códigos: es el texto que queda en la observación de la planilla (`origen = SAGA`) y que ven el cliente en el portal, el residente en el ERP y el aviso «No se pudo aprobar la planilla» (010).

| Situación | Texto | Origen |
|---|---|---|
| Finanzas responde `SaldoInsuficiente` (paso 2) | «Saldo del contrato insuficiente» | 008 (criterio 8; diseño) · texto de la spec |
| Materiales responde `CierreFallido` (el periodo ya lo cerró otra planilla) | «Los consumos del periodo {periodo} ya fueron cerrados por otra planilla» | 008 (diseño) · texto de la spec |
| Finanzas responde `CobroFallido` porque la reserva ya no está vigente | «No se pudo emitir el cobro: la reserva de saldo ya no está vigente» | 008 (diseño) · texto de la spec |
| Finanzas responde `CobroFallido` por otro error | «No se pudo emitir el cobro por un error en Finanzas» | 008 (diseño) · texto de la spec |
| Un paso no responde en 60 s | «El paso {n} no respondió a tiempo» (`{n}` = 2, 3 o 4) | 008 (diseño) · texto de la spec |

### Motivos de rechazo del contrato

Los publica Finanzas en `ContratoRechazado`; Administración los ve en el detalle de la obra (002, criterio 9) y en el aviso «Contrato rechazado» (010). Si fallan varias reglas, se unen con «; ».

| Regla | Texto | Origen |
|---|---|---|
| Monto ≤ 0 | «El monto del contrato debe ser mayor a 0» | 002 (diseño) · texto de la spec |
| Plazo ≤ 0 | «El plazo del contrato debe ser mayor a 0 días» | 002 (diseño) · texto de la spec |
| Anticipo o retención fuera de 0 a 100 | «El anticipo y la retención deben estar entre 0 % y 100 %» | 002 (diseño) · texto de la spec |
| Anticipo + retención ≥ 100 | «El anticipo más la retención deben sumar menos de 100 %» | 002 (diseño) · texto de la spec |

## Materiales

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `CODIGO_MATERIAL_REPETIDO` | 409 | Al crear o editar, el código ya existe | «Ya existe un material con el código {codigo}» | Usar otro código | ERP · Materiales | 003 (criterio 4) · texto de la spec |
| `MATERIAL_NO_ENCONTRADO` | 404 | El material no existe (editar o fijar mínimo) | «No encontramos ese material en el catálogo.» | Recargar el catálogo | ERP · Materiales | 003 · catálogo |
| `MATERIAL_INACTIVO` | 422 | Fijar mínimo (003) o registrar un movimiento (004) con un material desactivado | «El material está desactivado; no se puede usar en movimientos ni fijarle un mínimo.» | Elegir otro material o pedir a administración que lo active | ERP · Materiales, app | 003, 004 · catálogo |
| `OBRA_NO_ENCONTRADA` | 404 | La obra no está en `obra_acceso` o el usuario no la ve | Ver «Obras» | — | ERP · Materiales, app | 003, 004 |
| `PERIODO_CERRADO` | 409 | El periodo del movimiento ya lo cerró una planilla aprobada | «El periodo {periodo} ya está cerrado» | Consultar al residente; el registro queda «Rechazado» | App | 004 (criterio 7) · texto de la spec |
| `ORDEN_COMPRA_NO_PENDIENTE` | 422 | El ingreso indica una orden ya recibida, de otra obra o de otro material | «La orden de compra no está pendiente para este material» | Volver a registrar el ingreso sin orden | App | 201 (criterio 16) · texto de la spec |

## Finanzas

Los cinco códigos de la capa 2 los recibe n8n, no una persona en pantalla: quedan en la ejecución fallida del flujo, en el panel de n8n (201, criterio 9). El texto sirve para quien revisa las ejecuciones.

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `MATERIAL_SIN_PROVEEDOR` | 422 | Stock bajo de un material sin proveedor habitual | «El material no tiene proveedor habitual; no se generó la orden de compra.» | Elegir el proveedor habitual en el catálogo | n8n | 201 · catálogo |
| `PROVEEDOR_NO_ENCONTRADO` | 422 | El proveedor habitual no existe en Finanzas | «El proveedor habitual del material no está en la lista de proveedores.» | Elegir otro proveedor en el catálogo | n8n | 201 · catálogo |
| `PRECIO_INVALIDO` | 422 | Precio referencial del material ≤ 0 | «El material tiene precio referencial 0; no se puede generar la orden.» | Corregir el precio referencial | n8n | 201 · catálogo |
| `ORDEN_COMPRA_NO_ENCONTRADA` | 404 | Se marca enviada o se registra la cuenta por pagar de una orden inexistente | «No se encontró la orden de compra.» | Revisar la ejecución en n8n | n8n | 201 · catálogo |
| `ORDEN_YA_RECIBIDA` | 409 | La orden ya tiene cuenta por pagar de otro ingreso | «La orden de compra ya fue recibida con otro ingreso.» | Ninguna (no se duplica) | n8n | 201 · catálogo |

## Sincronización (app de obra, capa 1)

La app recibe estos códigos en el resultado de cada operación (`PROCESADO`, `ERROR`, `REINTENTAR`) o al pedir la URL de subida de una foto (`POST /fotos/url-subida`, 102). Los de `REINTENTAR` **no** se muestran: la operación vuelve a «Pendiente» y se reintenta sola (101). Los de `ERROR` dejan la operación «Rechazado» con el mensaje.

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `DISPOSITIVO_REQUERIDO` | 400 | Falta el encabezado `X-Dispositivo-Id` | «No se pudo identificar este celular. Cierra y vuelve a abrir la app.» | Reabrir la app; si sigue, avisar a soporte | App | 101 · catálogo |
| `LOTE_INVALIDO` | 400 | Lote vacío, con más de 20 operaciones, ids repetidos o mal formado | «No se pudieron enviar los registros pendientes.» | Pulsar «Enviar ahora»; si se repite, avisar a soporte | App | 101 · catálogo |
| `TIPO_OPERACION_DESCONOCIDO` | 400 | La operación tiene un tipo que el servidor no conoce | «Este tipo de registro no se reconoce. Actualiza la app.» | Actualizar la app; descartar el registro | App (Rechazado) | 101 · catálogo |
| `OPERACION_INVALIDA` | 400 | `idOperacion` distinto de `datos.id` | «El registro está incompleto y no se pudo enviar.» | Descartarlo y registrarlo de nuevo | App (Rechazado) | 101 · catálogo |
| `OPERACION_AJENA` | 403 | La operación ya la había enviado otro usuario | «Este registro lo envió otro usuario y no se puede enviar con tu sesión.» | Descartarlo | App (Rechazado) | 101 · catálogo |
| `OPERACION_EN_PROCESO` | 409 | Otra petición está procesando la misma operación | No se muestra (el registro sigue «Enviando» o vuelve a «Pendiente») | Ninguna | — | 101 |
| `TOKEN_VENCIDO` | 401 | El servicio dueño rechazó el token | No se muestra; la app renueva el token. Si no puede, pide iniciar sesión sin perder los pendientes (101, criterio 7) | Iniciar sesión si se pide | App | 101 |
| `TIEMPO_AGOTADO` | 504 | El servicio dueño no respondió en 5 s, o se agotaron los 20 s del lote | No se muestra (vuelve a «Pendiente») | Ninguna | — | 101 |
| `SERVICIO_NO_DISPONIBLE` | 503 | Obras o Materiales fallaron (también en `GET /paquete-datos` y `POST /fotos/url-subida`) | No se muestra en el envío (vuelve a «Pendiente»). En el paquete de datos, la app sigue con los datos guardados: «Sin señal · datos del dd/mm hh:mm» | Ninguna | App | 101 (criterio 3) · texto de la spec |
| `ARCHIVO_DEMASIADO_GRANDE` | 413 | Lote por encima de 256 KB | Ver «Genéricos» | — | App | 101 |
| `FOTO_NO_DISPONIBLE` | — | Código solo de la app (no lo envía ningún servicio): el archivo de la foto ya no está en el celular al ir a subirlo | «La foto no se pudo preparar para el envío.» | Descartarla y tomarla de nuevo | App (Rechazado) | 102 · decisión del equipo |

Si `POST /fotos/url-subida` devuelve un `400`, `403`, `404` o `422` de Obras (por ejemplo `404 OBRA_NO_ENCONTRADA`), la foto queda «Rechazado» con el mensaje de ese código; un `503` o `504` no se muestra y la foto se vuelve a subir más tarde (102).

## IA (capas 4 y 5)

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `OBRA_NO_ENCONTRADA` | 404 | Predicción o consumos atípicos de una obra que el usuario no ve | Ver «Obras» | — | ERP | 402, 403 |
| `DEMASIADAS_OBRAS` | 400 | Se pidieron predicciones o resumen de atípicos de más de 100 obras (el gateway parte en lotes de 100, así que no debería pasar) | En el tablero: «—» con «Datos de IA no disponibles» | Ninguna (avisar a soporte) | ERP · Supervisión | 402, 403 · texto de la spec (402, criterio 12) |
| `MODELO_NO_DISPONIBLE` | 503 | No hay modelo de riesgo cargado | «El modelo de riesgo no está disponible por el momento.» | Intentar más tarde | ERP · Supervisión («Sobre el modelo») | 402 · catálogo |
| `CONSUMO_ATIPICO_NO_ENCONTRADO` | 404 | Se revisa un consumo atípico que no existe | «No encontramos ese consumo atípico.» | Recargar la lista | ERP · Obras | 403 · catálogo |
| `REVISION_YA_REGISTRADA` | 409 | El consumo atípico ya fue revisado | «Este consumo ya fue revisado» | La lista se recarga sola | ERP · Obras | 403 (criterio 8) · texto de la spec |
| `COMENTARIO_INVALIDO` | 422 | 403: «Confirmar problema» sin comentario o fuera de 5 a 300 caracteres. 502: comentario al aprobar de más de 300. La regla concreta llega en `errores[].mensaje` (`campo` = `comentario`) | Arriba: «Revisa el comentario.» Junto al campo: el `mensaje` de `errores[]` | Ajustar el texto | ERP · Obras, Materiales, Supervisión | 403, 502 · catálogo |
| `AGENTE_INVALIDO` | 400 | Se pide ejecutar un agente que no existe | «Ese agente no existe.» | Recargar la vista | ERP · Supervisión | 502 · catálogo |
| `EJECUCION_EN_CURSO` | 409 | Ya hay una ejecución en curso del mismo agente | «El agente ya se está ejecutando» | Esperar a que termine | ERP · Supervisión | 502 (criterio 3) · texto de la spec |
| `EJECUCION_NO_ENCONTRADA` | 404 | Se pide el detalle de una ejecución que no existe | «No encontramos esa ejecución.» | Volver al historial | ERP · Supervisión | 502 · catálogo |
| `SUGERENCIA_NO_ENCONTRADA` | 404 | La sugerencia no existe o el usuario no puede verla (residente: obra ajena o Control de cobros) | «No encontramos esa sugerencia o no tienes acceso a ella.» | Recargar la lista | ERP (las tres áreas) | 502 · catálogo |
| `SUGERENCIA_YA_DECIDIDA` | 409 | Otra persona ya aprobó o rechazó la sugerencia | «Esta sugerencia ya fue aprobada o rechazada. Recarga la lista.» | Recargar | ERP (las tres áreas) | 502 (criterio 14) · catálogo |
| `MOTIVO_INVALIDO` | 422 | Rechazo de sugerencia con motivo fuera de 10 a 500 caracteres | Ver «Obras» | — | ERP | 502 |
| `TEXTO_INVALIDO` | 400 | Pedido de reporte por voz con menos de 3 o más de 500 caracteres | «El pedido debe tener entre 3 y 500 caracteres.» | Ajustar el texto | ERP · Supervisión | 503 (criterio 4) · catálogo |
| `INTENCION_NO_RECONOCIDA` | 422 | El pedido no corresponde a ningún reporte de la lista | «No encontré un reporte para tu pedido» (con la lista de reportes y ejemplos) | Reformular con un ejemplo | ERP · Supervisión | 503 (criterio 6) · texto de la spec |
| `FILTROS_INVALIDOS` | 422 | La intención trae filtros que el reporte no acepta o valores fuera de rango | «No encontré un reporte para tu pedido» (con la lista de reportes y ejemplos) | Reformular con un ejemplo | ERP · Supervisión | 503 (criterio 7) · texto de la spec |
| `DEMASIADAS_CONSULTAS` | 429 | Más de 10 consultas por minuto del mismo usuario | «Demasiadas consultas; espera un momento» | Esperar un minuto | ERP · Supervisión | 503 (criterio 15) · texto de la spec |
| `LLM_NO_DISPONIBLE` | 503 | El modelo de lenguaje no responde al interpretar el pedido | «El servicio de reportes no está disponible; intenta de nuevo» | Reintentar | ERP · Supervisión | 503 (diseño) · texto de la spec |
| `REPORTES_NO_DISPONIBLES` | 503 | No responde la base de reportes (o la consulta pasa de 5 s) | «El servicio de reportes no está disponible; intenta de nuevo» | Reintentar | ERP · Supervisión | 503 (diseño) · texto de la spec |
| `SERVICIO_NO_DISPONIBLE` | 503 | Materiales no responde y el pedido filtra por material | «El servicio de reportes no está disponible; intenta de nuevo» | Reintentar o pedir sin material | ERP · Supervisión | 503 (diseño) · texto de la spec |
| `TIEMPO_AGOTADO` | 504 | El reporte por voz tardó más de 50 s dentro de IA | «El reporte tardó demasiado; intenta de nuevo» | Reintentar | ERP · Supervisión | 503 (criterio 11) · texto de la spec |

### Errores de la ejecución de un agente

No son respuestas HTTP: son el `error.codigo` de una ejecución `FALLIDA` o el `error` de un paso (502). Se ven en el historial y el detalle de ejecuciones (solo `admin` y `gerente`).

| Código | Dónde | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Origen |
|---|---|---|---|---|---|
| `SIN_HERRAMIENTAS` | Ejecución | Ningún servidor MCP respondió | «Sin herramientas disponibles» | Volver a ejecutar más tarde | 502 (criterio 7) · texto de la spec |
| `REPORTE_INVALIDO` | Ejecución | El modelo no armó un reporte válido en dos intentos | «El agente no logró armar un reporte válido.» | Volver a ejecutar | 502 · catálogo |
| `EJECUCION_TIEMPO_AGOTADO` | Ejecución | La ejecución pasó los 3 minutos | «El agente superó el tiempo máximo de 3 minutos.» | Volver a ejecutar | 502 · catálogo |
| `INTERRUMPIDA` | Ejecución | El servicio se reinició con la ejecución en curso | «La ejecución se interrumpió porque el servicio se reinició.» | Volver a ejecutar | 502 · catálogo |
| `HERRAMIENTA_NO_PERMITIDA` | Paso | El modelo pidió una herramienta que no es de ese agente | «El agente pidió una herramienta que no le corresponde; se ignoró.» | Ninguna | 502, 504 · catálogo |
| `ARGUMENTO_INVALIDO` | Paso (y error de herramienta MCP) | El modelo pidió datos con parámetros no válidos | «El agente pidió datos con parámetros no válidos; se ignoró.» | Ninguna | 501, 502 · catálogo |
| `OBRA_NO_ENCONTRADA` | Paso (error de herramienta MCP) | La herramienta no encontró la obra pedida | «La obra pedida no existe.» | Ninguna | 501 · catálogo |
| `ERROR_INTERNO` | Paso (error de herramienta MCP) | La herramienta falló en el servicio | «La consulta falló en el servicio.» | Volver a ejecutar si el reporte quedó incompleto | 501 · catálogo |

## Notificaciones (010)

| Código | HTTP | Cuándo ocurre | Mensaje para el usuario | Acción sugerida | Se ve en | Origen |
|---|---|---|---|---|---|---|
| `NOTIFICACION_NO_ENCONTRADA` | 404 | Se marca como leída una notificación que no existe o es de otro usuario | «Ese aviso ya no está disponible.» | Recargar la bandeja | ERP (shell), portal, app | 010 · catálogo |
| `SERVICIO_NO_DISPONIBLE` | 503 | El servicio de notificaciones no responde | «No disponible por el momento · Reintentar» (la campana queda sin número; el resto de la aplicación sigue igual) | «Reintentar» | ERP (shell), portal, app | 010 (criterio 16) · texto de la spec |

## Avisos y mensajes que no son errores

Textos exactos de los requisitos y diseños (marcadores entre llaves donde la spec usa un valor de ejemplo). Los que la spec menciona sin texto quedan definidos aquí («catálogo»).

### Consultar obra (006)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Ninguna obra coincide con la búsqueda.» (con «Quitar filtros») | ERP · Obras · lista | Los filtros no dejan ninguna obra | 006 · catálogo |
| «No hay material previsto ni usado en este periodo.» | ERP · detalle · Material | El periodo no tiene previsto ni consumos | 006 · catálogo |
| «Aún no hay fotos de avance.» · «Cargar más fotos» | ERP · detalle · Fotos | Sin fotos · hay más páginas | 006 · catálogo |
| «Aún no hay planillas.» | ERP · detalle · Planillas | La obra no tiene planillas | 006 · catálogo |
| «Aún no hay cobros.» | ERP · detalle · Cobros | La obra no tiene cobros | 006 · catálogo |
| «Saldo y total cobrado: No disponible por el momento.» | ERP · detalle · Contrato | Finanzas no respondió | 006 · catálogo |
| Etiquetas de estado: «Borrador», «Presentada», «En aprobación», «Aprobada», «Observada», «Pendiente», «Vencido», «Excedido», «En riesgo» | ERP (chips) | Estados de planilla, cobro, consumo y obra | 006 · catálogo |

### Tablero (009)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Tablero de obras» | ERP · Supervisión · título | Siempre | 009 · catálogo |
| «Obras en ejecución» · «Obras en riesgo» · «Materiales bajos» · «Cobros vencidos» | ERP · Supervisión · tarjetas | Siempre (la de cobros solo para `admin` y `gerente`) | 009 · catálogo |
| «Aún no hay obras en ejecución.» | ERP · Supervisión · tabla | No hay obras en ejecución visibles | 009 · catálogo |
| «Sin planillas» | ERP · Supervisión · tabla, columna última planilla | La obra todavía no tiene planillas | 009 · catálogo |
| «—» con «Datos de {servicio} no disponibles» | ERP · Supervisión · tarjeta o celda | Ese servicio no respondió (respuesta parcial) | 009 |

### Materiales y fotos (003, 005)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Aún no hay materiales.» | ERP · Materiales · Catálogo | El catálogo está vacío | 003 · catálogo |
| «Elige una obra para ver su stock.» | ERP · Materiales · Stock | Todavía no se eligió una obra | 003 · catálogo |
| «Esta obra todavía no tiene materiales con movimientos ni mínimo definido.» | ERP · Materiales · Stock | La obra no tiene filas de stock | 003 · catálogo |
| «Foto enviada.» | App · Foto de avance | La foto se subió y quedó registrada (también si el registro ya existía) | 005 · catálogo |
| «Para tomar la foto, permite el uso de la cámara en los ajustes del celular.» | App · Foto de avance | El usuario negó el permiso de la cámara | 005 · catálogo |
| «Esta obra no tiene partidas.» | App · Foto de avance | La obra no tiene partidas para elegir | 005 · catálogo |

### Sesión y acceso (001)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «No tienes acceso a esta aplicación» (con el nombre del usuario y el botón «Cerrar sesión») | ERP, portal, app | El usuario no tiene un rol permitido en esa aplicación (app: sin `maestro` ni `almacenero`) | 001 (criterio 3) · texto de la spec |
| «Abre esta pantalla desde el ERP» | Microfrontends | Microfrontend abierto solo, sin el shell | 001 (diseño) · texto de la spec |
| «Esta sección no está disponible por el momento. Intenta recargar la página.» | ERP · shell (espacio del microfrontend) | Un microfrontend no carga | fase 1 (tarea 1.8), 104 · catálogo |
| «Aplicaciones» con «Portal del cliente» | ERP · shell | Solo si el usuario tiene también el rol `cliente` | 001 (criterio 10) · texto de la spec |

### Obras, planillas y portal (002, 006, 007, 008)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Registrando contrato» (etiqueta en la lista) · «Registrando contrato…» (detalle) | ERP · Obras | Obra `SIN_CONTRATO` sin motivo de rechazo | 002 (criterio 7; diseño) · texto de la spec |
| Selector «Zona» con «Sin zona» y las cinco zonas (Norte, Sur, Este, Oeste, Centro) | ERP · Obras (registro de obra, paso de datos) | Siempre; empieza en «Sin zona» (opcional) | 401 (criterio 1; diseño) · catálogo |
| «Zona {Norte\|Sur\|Este\|Oeste\|Centro}» · «Sin zona» | ERP · Obras (lista y encabezado del detalle) | Zona de la obra, o sin zona | 401 (criterio 2; diseño) · catálogo |
| «En riesgo» | ERP · Obras y Supervisión | Plazo transcurrido − avance > 10 puntos | 006, 009 · texto de la spec |
| «Sin planilla en este periodo» | ERP · Obras (pestaña «Material») | No hay planilla en el periodo elegido | 006 (criterio 5) · texto de la spec |
| «No disponible por el momento» | ERP · Obras (cada pestaña) | El servicio de esa sección no responde | 006 (criterio 4) · texto de la spec |
| «¿Aprobar la planilla N.º {numero} por Bs {neto}? Se emitirá el cobro.» con «Aprobar» y «Cancelar» | Portal | Al pulsar «Aprobar» | 008 (criterio 5) · catálogo |
| «Observar» con el contador «{n} / 500» (mínimo 10) | Portal | Al pulsar «Observar» | 008 (criterio 4; diseño) · catálogo |
| «En aprobación…» | Portal | Planilla `APROBANDO` (consulta cada 2 s, hasta 4 minutos) | 008 (criterio 5) · texto de la spec |
| «La aprobación está tardando más de lo normal; puedes cerrar esta pantalla, el resultado aparecerá aquí» | Portal | Pasan 90 s en `APROBANDO` sin resultado | 008 (criterio 5) · texto de la spec |
| «Planilla aprobada» con «Número de cobro: {cobroNumero}» | Portal · planilla | Planilla `APROBADA` | 008 (criterio 6) · catálogo |
| «Planilla observada» con el motivo debajo | Portal · planilla | Planilla `OBSERVADA` (por el cliente o por la saga) | 008 (criterio 6) · catálogo |
| «Detalle de la planilla» · «Fotos de respaldo» · «Fotos de la obra» · «Volver a mis obras» | Portal | Títulos y enlace de las pantallas | 008 · catálogo |
| «Esta planilla no tiene fotos de respaldo.» | Portal · planilla | La planilla no tiene fotos adjuntas | 008 · catálogo |
| «Aprobando…» · «Enviando…» | Portal | Botón mientras se envía la aprobación o la observación | 008 · catálogo |
| «Actualizar» | Portal · planilla | Pasaron 4 minutos en `APROBANDO` y se dejó de consultar | 008 (criterio 5) · catálogo |
| «Cobro {numero}» y columna «Cobro» («—» sin cobro) | ERP · Obras (editor y pestaña «Planillas») | Planilla `APROBADA` | 008 (criterio 14) · catálogo |
| «Los rostros se difuminan para proteger la privacidad del personal» | Portal | Bajo la galería de la obra y de la planilla | 303 (criterio 11) · texto de la spec |

### Materiales y compras (003, 004, 201)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Registrado» | App | El servidor confirmó el movimiento | 004 (criterio 4) · texto de la spec |
| «La salida supera el stock registrado (stock: {stock}). Queda como alerta para revisión» | App | Salida mayor al stock (`superaStock`) | 004 (criterio 5), 101 (criterio 10) · texto de la spec |
| «Sin proveedor habitual: no se generarán órdenes automáticas» | ERP · Materiales (catálogo) | Material sin proveedor habitual | 201 (criterio 3) · texto de la spec |
| «Correo no enviado» (ámbar) · `ENVIADA` (azul) · `RECIBIDA` (verde) | ERP · Materiales (órdenes de compra) | Estado de la orden | 201 (criterio 11; diseño) · texto de la spec |
| «Todavía no hay órdenes de compra» | ERP · Materiales | Lista vacía | 201 (diseño) · texto de la spec |
| «Orden de compra (opcional)» con «{numero} · {proveedor} · {cantidad} {unidadPlural}» | App (ingreso) | Hay órdenes pendientes del material | 201 (diseño) · texto de la spec |

### App sin señal (005, 101, 102, 103)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «No se pudo enviar la foto. Puedes reintentar sin volver a tomarla.» con «Reintentar» | App (005, antes de la capa 1) | Falla la subida de la foto | 005 (criterio 5) · catálogo |
| «Sin señal · datos del dd/mm hh:mm» | App | No hay conexión | 101 (criterio 3) · texto de la spec |
| «Necesitas señal la primera vez para descargar tus obras» | App | Primer uso sin señal | 101 (criterio 4) · texto de la spec |
| «Guardado en el celular · se enviará cuando haya señal» | App | El servidor no confirmó en 5 s | 101 (criterio 8) · texto de la spec |
| «Incluye {N} movimientos sin enviar» | App (stock) | Hay movimientos pendientes | 101 (criterio 9) · texto de la spec |
| «Incluye 1 movimiento sin enviar» | App (stock) | Hay un solo movimiento pendiente (forma en singular) | 101 · decisión del equipo |
| `Pendiente` · `Enviando` · `Enviado` · `Rechazado` (con el motivo) | App («Pendientes de envío») | Estado de cada registro | 101 (criterio 16) · texto de la spec |
| «Salida · 12,5 bolsas de Cemento IP-30 · P-01» (formato: «{tipo} · {cantidad} {unidad} de {material} · {partida}») | App («Pendientes de envío») | Descripción de un movimiento | 101 (criterio 16) · texto de la spec |
| «¿Descartar este registro? No se enviará y no se podrá recuperar.» con «Descartar» y «Cancelar» | App | Al descartar un registro | 101 (criterio 17) · catálogo |
| «No hay registros pendientes de envío.» | App («Pendientes de envío») | El usuario no tiene registros en el celular | 101 · decisión del equipo |
| «Tienes {N} registros sin enviar; se enviarán cuando vuelvas a iniciar sesión con este usuario» | App | Cerrar sesión con pendientes | 101 (criterio 18) · texto de la spec |
| «Hay {N} registros de {nombre} sin enviar; se enviarán cuando esa persona vuelva a iniciar sesión» | App («Pendientes de envío») | Hay registros sin enviar de otro usuario en el celular | 101 (criterio 15) · texto de la spec |
| «1 registro» en lugar de «{N} registros» en los dos avisos anteriores («Tienes 1 registro sin enviar…», «Hay 1 registro de {nombre} sin enviar…») | App | Hay un solo registro (forma en singular) | 101 · decisión del equipo |
| «Subiendo foto…» | App («Pendientes de envío») | El archivo de la foto se está subiendo | 102 (criterio 7) · texto de la spec |
| «Tienes {N} fotos sin enviar; busca señal para enviarlas» | App (foto de avance) | Hay más de 100 fotos sin enviar en el celular (no impide tomar más) | 102 (criterio 3) · texto de la spec |
| «Ya registraste el diario del dd/mm» | App (diario) | Ya hay entrada ese día en el celular o el paquete | 103 (criterio 4) · texto de la spec |
| «Sin enviar» · «Rechazada» | App (diario) | Estado de la entrada | 103 (criterio 7) · texto de la spec |
| «Diario · 15/11 · Lluvia leve» (formato: «Diario · dd/mm · {clima}») | App («Pendientes de envío») | Descripción de una entrada | 103 (diseño) · texto de la spec |
| «Aún no hay entradas del diario en los últimos 30 días.» | App (diario) | La obra no tiene entradas en el paquete ni en la cola | 103 · decisión del equipo |
| «Elige el clima.» | App (diario, formulario) | Se guarda sin elegir el clima | 103 · decisión del equipo |
| «Elige la fecha.» | App (diario, formulario) | Se guarda sin elegir la fecha | 103 · decisión del equipo |
| «Escribe al menos 10 caracteres.» · «Escribe hasta 2000 caracteres.» | App (diario, formulario) | El texto tiene menos de 10 o más de 2000 caracteres (sin contar los espacios de los costados) | 103 · decisión del equipo |
| «Corrigiendo la entrada del dd/mm» | App (diario, formulario) | Se está corrigiendo una entrada sin enviar | 103 · decisión del equipo |
| «Esta entrada ya se está enviando y no se puede corregir.» | App (diario) | Se pulsa «Corregir» en una entrada que pasó a `ENVIANDO` | 103 · decisión del equipo |

### ERP sin conexión (104)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Conéctate a internet para iniciar sesión» | ERP | Sin conexión y sin sesión de las últimas 24 h | 104 (criterio 3) · texto de la spec |
| «Iniciar sesión» (botón) | ERP | Vuelve la conexión y la sesión de Keycloak ya no está vigente | 104 (criterio 4) · texto de la spec |
| «Hay una versión nueva · Recargar» | ERP | Hay una versión nueva del ERP | 104 (criterio 5) · texto de la spec |
| «Sin conexión» | ERP (barra superior) | No hay conexión | 104 (criterio 6) · texto de la spec |
| «Borradores sin enviar ({N})» | ERP (barra superior) | Hay borradores de planilla locales | 104 (criterio 6) · texto de la spec |
| «Sin conexión · datos del dd/mm/aaaa hh:mm» | ERP (pantallas con respaldo) | Se muestran datos guardados | 104 (criterio 8) · texto de la spec |
| «No hay datos guardados de esta pantalla» | ERP | Sin conexión y la pantalla nunca se abrió | 104 (criterio 8) · texto de la spec |
| «Requiere conexión» | ERP (botones de escritura) | Sin conexión | 104 (criterio 9) · texto de la spec |
| «Guardado en este equipo; se enviará al volver la conexión» | ERP · Obras (planilla) | «Guardar» sin conexión o con fallo de red | 104 (criterio 10) · texto de la spec |
| «Borrador local sin enviar (guardado dd/mm hh:mm)» | ERP · Obras (planilla) | Se abre una planilla con borrador local | 104 (criterio 12) · texto de la spec |
| «Borrador de la planilla N.º {numero} enviado» | ERP · Obras | El borrador se envió solo | 104 (criterio 13) · texto de la spec |
| «La planilla cambió en el servidor» · «Aplicar mi borrador sobre la última versión» · «Descartar mi borrador» | ERP · Obras | `VERSION_DESACTUALIZADA` al enviar el borrador | 104 (criterio 14) · texto de la spec |
| «La planilla ya no se puede editar (estado {estado})» | ERP · Obras | `PLANILLA_NO_EDITABLE` al enviar el borrador | 104 (criterio 15) · texto de la spec |
| «Tienes {N} borradores de planilla sin enviar. Si cierras sesión se borrarán de este equipo» | ERP | Cerrar sesión con borradores | 104 (diseño) · texto de la spec |
| «Tienes 1 borrador de planilla sin enviar. Si cierras sesión se borrará de este equipo» (diálogo con título «Cerrar sesión») | ERP | Cerrar sesión con un solo borrador | 104 · singular del texto anterior (decisión del equipo) |

### IA en el dispositivo y en el navegador (301, 302, 303)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Analizando…» | App (foto) | Mientras corre el modelo | 301 (diseño) · texto de la spec |
| «Personas: {N} · Sin casco: {M} · Sin chaleco: {K}» | App (foto) | Terminó el análisis | 301 (criterio 1) · texto de la spec |
| «Hay personas sin equipo de protección. Recuerda el uso de casco y chaleco.» | App (foto) | Al menos una persona sin casco o chaleco | 301 (criterio 2) · texto de la spec |
| «No se detectaron personas» | App (foto) | Ninguna persona | 301 (criterio 4) · texto de la spec |
| «No se pudo analizar la foto» | App (foto) | Falla o tarda más de 5 s | 301 (criterio 5) · texto de la spec |
| «{N} sin casco · {M} sin chaleco» · «Sin alertas de EPP» | ERP · Obras (fotos) | Foto analizada | 301 (criterio 9) · texto de la spec |
| «Detectado en el celular con el modelo {versionModelo}» | ERP · Obras (ayuda al pasar el cursor) | Foto analizada | 301 (diseño) · texto de la spec |
| «Grabando…» (con el tiempo) · «Transcribiendo…» | ERP · Supervisión (dictado) | Grabación y transcripción | 302 (criterios 1 y 2) · texto de la spec |
| «Preparando el dictado: {porcentaje} %» | ERP · Supervisión | Primera descarga del modelo | 302 (criterio 5) · texto de la spec |
| «Sin permiso para usar el micrófono» | ERP · Supervisión | Permiso negado | 302 (criterio 7) · texto de la spec |
| «El dictado no está disponible en este navegador; puedes escribir el texto.» (ayuda del micrófono desactivado) | ERP · Supervisión | Navegador sin micrófono, WebAssembly o Web Workers | 302 (criterio 8) · catálogo |
| «No se pudo descargar el modelo de dictado; puedes escribir el texto.» (ayuda del micrófono desactivado) | ERP · Supervisión | El modelo no se puede descargar | 302 (criterio 8) · catálogo |
| «No se entendió el audio, intenta de nuevo» | ERP · Supervisión | Grabación < 1 s o sin texto | 302 (criterio 9) · texto de la spec |
| «Preparando fotos para el cliente: {X} de {Y}» | ERP · Obras (presentar) | Preparación de versiones para el cliente | 303 (criterio 1) · texto de la spec |
| «No se pudo cargar el detector de rostros. Reintenta o quita las fotos de la planilla.» | ERP · Obras | El modelo de rostros no carga | 303 (criterio 8) · catálogo |
| «No se pudo preparar esta foto para el cliente. Reintenta o quítala de la planilla.» | ERP · Obras (en la foto) | Una foto no se puede procesar | 303 (criterio 8) · catálogo |

### Predicciones y agentes (402, 403, 502)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Riesgo alto (modelo)» | ERP · Supervisión (tarjeta) | Siempre | 402 (criterio 6) · texto de la spec |
| «Riesgo de retraso (modelo): {NIVEL} · {porcentaje} %» · «Sin datos suficientes» | ERP · Obras (encabezado) | Con o sin predicción; los factores van en un *tooltip* | 402 (criterios 2 y 10) · texto de la spec |
| Columna «Riesgo (modelo)» con chip «Bajo», «Medio», «Alto» o «Sin datos» y el porcentaje | ERP · Supervisión (tablero y «Riesgo de retraso») | Siempre (ordenable) | 402 (diseño) · catálogo |
| «Riesgo de retraso» (menú interno) · «Riesgo de retraso por obra» (lista) · «Sobre el modelo» (panel) | ERP · Supervisión | Pantalla `/supervision/riesgo` | 402 (diseño) · catálogo |
| «Datos sintéticos · {N} filas de entrenamiento» (o «Datos reales · …») · «Medio desde {X} % · Alto desde {Y} %» | ERP · Supervisión («Sobre el modelo») | Siempre | 402 (criterio 9) · catálogo |
| «Estas métricas muestran que el modelo aprende las relaciones simuladas; no prueban que acierte con obras reales.» | ERP · Supervisión («Sobre el modelo») | Siempre | 402 (diseño, «Métricas mínimas») · texto de la spec |
| «Datos de IA no disponibles» (con «—») | ERP · Supervisión y Obras | IA no responde | 402 (criterio 12), 403 (criterio 12) · texto de la spec |
| «Modelo entrenado con datos sintéticos; es una estimación de apoyo, no reemplaza la revisión de la obra» (con un modelo reentrenado con datos reales: «Modelo entrenado con datos reales; …») | ERP · Supervisión («Riesgo de retraso») | Siempre; el texto depende de `datos` (`SINTETICOS` o `REALES`) | 402 (criterio 9) · texto de la spec |
| «Consumos atípicos por revisar» (tarjeta) · columna «Atípicos» (pendientes por obra) | ERP · Supervisión (tablero) | Siempre | 403 (criterio 10) · texto de la spec |
| «Detectado por comparación con el consumo habitual; es distinto de "excedido sobre lo previsto"» | ERP · Obras (pestaña «Material») | Ayuda de la sección | 403 (diseño) · texto de la spec |
| «Consumos atípicos» (sección, con filtro «Estado», por defecto «Pendiente») · «No hay consumos atípicos con este estado.» | ERP · Obras (pestaña «Material») | Siempre · sin consumos con ese estado | 403 (diseño) · catálogo |
| «Es normal» · «Confirmar problema» (diálogo con comentario: obligatorio al confirmar, contador de 5 a 300) | ERP · Obras (pestaña «Material») | Solo `residente` asignado y `admin`, y solo en `PENDIENTE` | 403 (criterios 7 y 9; diseño) · texto de la spec |
| Motivos de un consumo atípico (los arma IA, de 1 a 3): «La cantidad es X veces la habitual de este material en la obra» · «… en todas las obras» · «El consumo del mes ya es X veces el promedio mensual» · «Se registró fuera del horario habitual (HH:MM)» · «Se registró en domingo» · «Salió más material del que había en stock» · «Hubo X salidas de este material en la última hora» · «Hubo X salidas de este material el mismo día» · «Salida muy seguida de la anterior (X minutos)» · «Combinación poco habitual de cantidad, horario y frecuencia» | ERP · Obras (columna «Motivos») | Cada consumo atípico | 403 (diseño, «Motivos») · texto de la spec |
| «En curso…» | ERP · Supervisión (agentes) | Ejecución en curso (consulta cada 3 s, máx. 5 min) | 502 (criterio 2) · texto de la spec |
| «No disponible por el momento» | ERP (secciones de agentes) | IA no responde | 502 (criterio 21) · texto de la spec |

### Reportes por voz (503)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| «Preparando el reporte…» | ERP · Supervisión | Mientras se consulta (hasta 60 s) | 503 (criterio 11) · texto de la spec |
| «Se muestran las primeras 100 filas» | ERP · Supervisión | Resultado truncado | 503 (criterio 8) · texto de la spec |
| «Nombres de materiales no disponibles» | ERP · Supervisión (avisos) | Materiales no responde y no se filtró por material | 503 (criterio 8) · texto de la spec |
| «Se encontraron {N} filas para el reporte «{título}» con los filtros: {filtros}.» | ERP · Supervisión | La redacción con el modelo falla o tarda | 503 (diseño) · texto de la spec |

### Notificaciones (010)

| Texto | Dónde | Cuándo | Origen |
|---|---|---|---|
| Número sobre la campana; «9+» si son más de 9; sin número si no hay sin leer | ERP, portal, app («Avisos») | Siempre | 010 (criterio 9) · texto de la spec |
| «No tienes notificaciones» | Bandeja | Sin avisos | 010 (criterio 10) · texto de la spec |
| «Ver más» · «Marcar todas como leídas» | Bandeja | Siempre | 010 (criterios 10 y 12) · texto de la spec |
| «Activar avisos en este navegador» | Bandeja (ERP, portal) | Permiso del navegador sin decidir y Firebase configurado | 010 (criterio 17) · texto de la spec |
| «Los avisos están bloqueados en este navegador» | Bandeja (ERP, portal) | Permiso bloqueado | 010 (criterio 18) · texto de la spec |
| Mensaje breve con el título del aviso y «Ver» | ERP, portal, app | Llega un aviso con la aplicación abierta | 010 (criterio 19; diseño) · texto de la spec |
| «Sin señal · no se pueden cargar los avisos» | App («Avisos») | Sin señal | 010 (diseño) · texto de la spec |

Títulos y mensajes de los avisos (los redacta el servicio Notificaciones; ejemplos con valores de la spec):

| Aviso | Título | Mensaje | Origen |
|---|---|---|---|
| Planilla presentada | «Planilla para revisar» (si se corrigió: «Planilla corregida para revisar») | «Se presentó la planilla N.º {numero} ({periodo}) de {obra} por Bs {neto}. Revísala para aprobarla u observarla.» (corregida: «Se corrigió y volvió a presentar la planilla N.º {numero} …») | 010 (diseño) · texto de la spec |
| Planilla aprobada | «Planilla aprobada» | «Se aprobó la planilla N.º {numero} ({periodo}) de {obra}. Neto: Bs {neto}.» | 010 (diseño) · texto de la spec |
| Planilla observada por el cliente | «Planilla observada» | «El cliente observó la planilla N.º {numero} ({periodo}) de {obra}: «{motivo}».» | 010 (diseño) · texto de la spec |
| Planilla observada por la saga | «No se pudo aprobar la planilla» | «La aprobación de la planilla N.º {numero} ({periodo}) de {obra} falló y quedó observada: {motivo}.» (motivos en «Motivos de observación que pone la saga») | 010 (diseño) · texto de la spec |
| Stock bajo | «Stock bajo: {material}» (sin datos del material: «Stock bajo») | «En {obra} quedan {cantidad} {unidadPlural} de {material} (mínimo {minimo}).» (sin datos: «En {obra} un material quedó por debajo del mínimo») | 010 (diseño) · texto de la spec |
| Cobro vencido | «Cobro vencido {numero}» | «El cobro {numero} de {obra} por Bs {monto} venció el {fecha}.» | 010 (diseño) · texto de la spec |
| Contrato rechazado | «Contrato rechazado» | «Finanzas rechazó el contrato de {obra}: {motivo}.» (motivos en «Motivos de rechazo del contrato») | 010 (diseño) · texto de la spec |

## Inconsistencias encontradas

Las que se encontraron al armar este catálogo quedaron resueltas en las specs, los contratos y `convenciones.md` (28/10/2026):

1. **`TIEMPO_AGOTADO` tenía tres significados.** Ahora es siempre `504` cuando un servicio no recibe respuesta de otro (101, 102, 503 y convenciones); el error de una ejecución de agente pasó a `EJECUCION_TIEMPO_AGOTADO` (502, 504). En el gateway, un campo cuyo servicio no respondió sigue llegando con `SERVICIO_NO_DISPONIBLE` (convenciones, «Errores GraphQL»).
2. **`MOTIVO_INVALIDO` tenía dos rangos.** Ahora es de 10 a 500 caracteres en todas partes (502: requisitos y diseño).
3. **`COMENTARIO_INVALIDO` tenía dos reglas.** Se mantienen (son casos distintos), pero la regla concreta viaja en `errores[].mensaje` (403 y 502, convenciones).
4. **El reporte por voz tenía dos textos para `TIEMPO_AGOTADO`.** Manda el requisito: «El reporte tardó demasiado; intenta de nuevo» (503, diseño corregido).
5. **`ORDEN_COMPRA_NO_PENDIENTE` tenía dos textos.** Manda el requisito (201, diseño corregido).
6. **La app mostraba el `detail` ante un código desconocido.** Ahora muestra el genérico del estado HTTP (101, diseño).
7. **Los errores genéricos no tenían código y faltaba el motivo de `ContratoRechazado`.** Códigos genéricos en `convenciones.md` (`DATOS_INVALIDOS`, `NO_AUTENTICADO`, `SIN_PERMISO`, `ARCHIVO_DEMASIADO_GRANDE`, `DEMASIADAS_PETICIONES`, `ERROR_INTERNO`, `SERVICIO_NO_DISPONIBLE`); motivos del contrato en la 002 (diseño).
8. **Faltaban los textos de `CierreFallido` y `CobroFallido`, y el portal dejaba de consultar a los 90 s.** Textos en la 008 (diseño); el portal consulta hasta 4 minutos y a los 90 s muestra el aviso de espera (008: requisitos, diseño y tareas del portal).
9. **La detección de EPP no viajaba por Sincronización.** La 301 agrega, en «Cambios a contratos y datos», `deteccion` a los `datos` de `FOTO_AVANCE` de la 102.
10. **No estaba definido qué hacer con `SUBIDA_DISTINTA`.** La app descarta la subida y empieza otra con un `idSubida` nuevo y el mismo `fotoId` (102: diseño y tareas de la app). Ya no aplica: la 102 se simplificó el 30/10/2026 y no tiene subida por partes.
11. **El tablero podía pasar el límite de 100 obras de IA.** El gateway parte las llamadas en lotes de 100 (402 y 403: diseño y tareas del gateway).
12. **Faltaban textos de interfaz y `PERIODO_INVALIDO` cubría dos causas.** Los textos están en este catálogo; el código se separó en `PERIODO_NO_POSTERIOR` y `PERIODO_FUTURO` (007: requisitos y diseño; contratos de Obras).

Resuelto: una `deteccion` inválida ya no rechaza la foto; se guarda sin detección con el aviso `DETECCION_DESCARTADA` (301).
