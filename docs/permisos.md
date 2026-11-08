# Matriz de permisos

Quién puede hacer qué en cada aplicación y en cada servicio. Se arma **solo** con lo que dicen las especificaciones (`docs/specs/*`), los contratos (`docs/contratos/*`, `services/*/docs/contratos.md`, `gateway/docs/contratos.md`) y `docs/convenciones.md`. Las contradicciones que había entre esas fuentes se resolvieron y se listan al final («Inconsistencias encontradas»).

Si una especificación cambia un permiso, se actualiza esta matriz en el mismo trabajo.

**Leyenda**

| Marca | Significado |
|---|---|
| ✔ | Puede, en todas las obras que ve según su rol (`admin` y `gerente` ven todas) |
| propias | Solo en sus obras: las asignadas (`residente`, `maestro`, `almacenero`) o las suyas como cliente (`cliente`) |
| (vacío) | No puede: el botón no se muestra y el servicio responde `403 SIN_PERMISO` (o `404` si el rol sí puede pero no ve esa obra; ver «Reglas de visibilidad») |

La columna **Origen** es la funcionalidad que define la fila (`002`, `201`…). `fase 1` = tarea técnica de `docs/plan.md`.

## Roles

### Roles de personas (realm `supervision`)

| Rol | Quién es | Aplicación en la que entra (001, criterio 3) |
|---|---|---|
| `admin` | Administración de la constructora | ERP |
| `residente` | Residente (ingeniero) de obra | ERP |
| `gerente` | Gerencia | ERP |
| `maestro` | Maestro de obra | App de obra |
| `almacenero` | Almacenero de la obra | App de obra |
| `cliente` | Cliente dueño de la obra | Portal |

Un usuario sin un rol permitido en esa aplicación ve «No tienes acceso a esta aplicación» (001). Un usuario puede tener más de un rol: el usuario de prueba `demo1` tiene `residente` y `cliente` para demostrar el paso entre el ERP y el portal (001).

### Roles y clientes técnicos (no los tiene ninguna persona; se crean con su capa)

| Rol o permiso | Lo tiene | Para qué | Origen |
|---|---|---|---|
| `view-users` y `view-realm` (roles del cliente `realm-management`, solo lectura) | *Service account* del cliente confidencial `gateway` | Listar usuarios por rol para los formularios de asignación (`view-realm` lo exige Keycloak para `GET /roles/{rol}/users`) y resolver nombres | convenciones, 002, 006 |
| `automatizacion` (rol de realm) | *Service account* del cliente confidencial `n8n` | Solo las rutas de Finanzas que llama n8n (recordatorios, envíos y nota de cobro) | 201 |
| `gerente` (rol de realm de personas) y `view-users` (rol del cliente `realm-management`, solo lectura) | *Service account* del cliente confidencial `n8n` (solo *client credentials*) | Leer con los endpoints que ya existen (Obras `GET /obras/{id}` y `GET /planillas/{id}`, Finanzas `GET /cobros/{id}`; desde la 010, también Obras `GET /obras` y `GET /obras/{obraId}/diario` y Materiales `GET /materiales`), igual que `ia-reportes`, y el nombre y el correo del cliente (`GET /admin/realms/supervision/users/{id}`): segunda excepción a «ningún otro proyecto llama a la API de administración de Keycloak», junto al gateway | 201, 010 |
| `agente_ia` (rol de realm) | *Service account* del cliente confidencial `ia-agentes` (la usa `ia-worker`, host de los agentes) | Solo `POST /mcp` de Obras, Materiales, Finanzas e IA (herramientas de solo lectura); ve todas las obras como `gerente`; ningún endpoint REST lo acepta | 501 |
| `gerente` (rol de realm de personas, asignado también a una *service account*) | *Service account* del cliente confidencial `ia-reportes` (solo *client credentials*) | Carga inicial del modelo de lectura: solo `GET` a Obras (`/obras`, `/obras/{id}`, `/obras/{obraId}/planillas`, `/planillas/{id}`), Materiales (`/materiales`, `/obras/{obraId}/movimientos`) y Finanzas (`/cobros`); ve todas las obras como cualquier `gerente`. Se eligió un rol existente para no cambiar los tres servicios; el secreto solo lo usa el comando de carga | 401 |

Sincronización (capa 1) no tiene cliente propio: reenvía el token del usuario a Obras y Materiales.

## Reglas de visibilidad de obras

Resumen de `docs/convenciones.md` («Autenticación y permisos»):

- `admin` y `gerente` ven todas las obras; `residente`, `maestro` y `almacenero`, las que tienen asignadas; `cliente`, las suyas; `agente_ia`, todas, solo por `/mcp`.
- Cada servicio valida sus reglas. Obras es dueño de las asignaciones; Materiales guarda una copia en `obra_acceso` (evento `ObraRegistrada`); IA usa `rpt_obra_resumen.residente_id` (401). Finanzas no guarda asignaciones: por eso sus endpoints son solo para `admin` y `gerente` (el número de cobro que ve el residente lo guarda Obras, 008).
- Respuestas, en este orden:
  - `401 NO_AUTENTICADO`: no hay token válido.
  - `403 SIN_PERMISO`: el rol no permite esa acción (se comprueba primero, en el guardia del endpoint).
  - `404` con el código de «no encontrado» (por ejemplo `404 OBRA_NO_ENCONTRADA`): el rol sí puede, pero el usuario no ve esa obra. Se responde igual que si no existiera, para no revelar que existe; vale para lecturas y escrituras.
- Para el `cliente`: no recibe planillas `BORRADOR` (`404` si pide una), solo recibe fotos publicadas (versión con rostros difuminados desde la 303) y nunca los datos de detección de EPP (301).
- Campos de Finanzas en el ERP (`Obra.finanzas`, `Obra.cobros`, `IndicadoresTablero.cobrosVencidos` y el detalle de `Planilla.cobro`): llegan en `null` **sin error** si el rol no es `admin` ni `gerente`.
- Residente en los agentes (502): solo hallazgos y sugerencias de sus obras y nunca los del agente Control de cobros.
- Avisos (010): cada aviso va solo al almacenero, al maestro o al cliente de esa obra (ver «Avisos que recibe cada rol»).

## Permisos por aplicación

### Acceso a las aplicaciones

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Entrar al ERP (shell y microfrontends) | ✔ | ✔ | ✔ | | | | 001 |
| Entrar al portal del cliente | | | | | | ✔ | 001 |
| Entrar a la app de obra | | | | ✔ | ✔ | | 001 |
| Pasar a otra aplicación para la que tiene rol sin volver a escribir la contraseña (SSO) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 001 |
| Cerrar sesión | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | 001 |

### ERP · Shell

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Menú Obras, Materiales y Supervisión | ✔ | ✔ | ✔ | | | | 001 |
| Menú «Aplicaciones → Portal del cliente» (solo si el usuario también tiene `cliente`, como `demo1`; si no, la opción no aparece) | ✔ | ✔ | ✔ | | | | 001 |
| Instalar el ERP como aplicación (PWA) y abrirlo sin conexión | ✔ | ✔ | ✔ | | | | 104 |
| Entrar en «modo sin conexión» (sesión de las últimas 24 h) | ✔ | ✔ | ✔ | | | | 104 |
| Indicador «Borradores sin enviar (N)» | | propias | | | | | 104 |

### ERP · Obras (mf-obras)

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Ver la lista de obras (filtro por estado, búsqueda por nombre, etiqueta «En riesgo») | ✔ | propias | ✔ | | | | 006 |
| Ver la zona de la obra en la lista y el detalle | ✔ | propias | ✔ | | | | 401 |
| Botón «Nueva obra» y formulario de 3 pasos (datos, contrato, presupuesto) | ✔ | | | | | | 002 |
| Elegir la zona al registrar la obra | ✔ | | | | | | 401 |
| Ver el detalle de la obra (encabezado, indicadores, contrato, partidas, motivo de rechazo del contrato) | ✔ | propias | ✔ | | | | 002, 006 |
| Ver saldo disponible y total cobrado del contrato | ✔ | | ✔ | | | | 006 |
| Pestaña «Material» (previsto, usado y diferencia por periodo) | ✔ | propias | ✔ | | | | 006 |
| Pestaña «Fotos» (galería por partida) | ✔ | propias | ✔ | | | | 005, 006 |
| Ver la etiqueta de casco y chaleco en cada foto | ✔ | propias | ✔ | | | | 301 |
| Pestaña «Planillas» (número, periodo, estado, neto, número de cobro) | ✔ | propias | ✔ | | | | 006, 007, 008 |
| Pestaña «Cobros» | ✔ | | ✔ | | | | 006 |
| Ver en «Cobros» el estado `PAGADO` con la fecha y el comprobante, y los correos enviados de cada cobro («Nota enviada», recordatorios, «Constancia enviada», «Nota sin enviar») | ✔ | | ✔ | | | | 201 |
| «Registrar pago» de un cobro `PENDIENTE` o `VENCIDO` (fecha de pago y n.º de comprobante) | ✔ | | | | | | 201 |
| Ver el riesgo de retraso del modelo en el encabezado | ✔ | propias | ✔ | | | | 402 |
| Ver la sección «Consumos atípicos» (pestaña «Material») | ✔ | propias | ✔ | | | | 403 |
| «Es normal» / «Confirmar problema» en un consumo atípico `PENDIENTE` | ✔ | propias | | | | | 403 |
| Pestaña «Agentes»: hallazgos y sugerencias de Seguimiento de obras | ✔ | propias | ✔ | | | | 502 |
| Pestaña «Agentes»: hallazgos y sugerencias de Control de cobros | ✔ | | ✔ | | | | 502 |
| «Aprobar» / «Rechazar» una sugerencia de Seguimiento de obras | ✔ | propias | ✔ | | | | 502 |
| «Aprobar» / «Rechazar» una sugerencia de Control de cobros | ✔ | | ✔ | | | | 502 |
| «Nueva planilla» (elegir periodo) | | propias | | | | | 007 |
| Editar cantidades, adjuntar fotos del periodo y «Guardar» | | propias | | | | | 007 |
| «Presentar» la planilla | | propias | | | | | 007 |
| Corregir una planilla `OBSERVADA` y volver a presentarla | | propias | | | | | 007, 008 |
| Ver una planilla en modo lectura (estado, observación, número de cobro) | ✔ | propias | ✔ | | | | 007, 008 |
| Ver el detalle del cobro de una planilla (monto, emisión, vencimiento, estado) | ✔ | | ✔ | | | | 008 |
| Preparar la versión para el cliente de las fotos (difuminar rostros, marcar zonas, «Volver a preparar», «Quitar de la planilla», «Confirmar y presentar») | | propias | | | | | 303 |
| Guardar el borrador de la planilla sin conexión y enviarlo al volver | | propias | | | | | 104 |

### ERP · Materiales (mf-materiales)

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Ver el catálogo de materiales (búsqueda por código o nombre) | ✔ | ✔ | ✔ | | | | 003 |
| «Nuevo material», «Editar», «Activar/Desactivar» | ✔ | | | | | | 003 |
| Ver el stock por obra (cantidad, mínimo, estado con color) | ✔ | propias | ✔ | | | | 003 |
| «Fijar mínimo» y «Agregar material» a la obra | ✔ | | | | | | 003 |
| Panel «Control de materiales»: hallazgos y sugerencias de la obra | ✔ | propias | ✔ | | | | 502 |
| «Aprobar» / «Rechazar» una sugerencia de Control de materiales | ✔ | propias | ✔ | | | | 502 |

Ningún rol del ERP registra ingresos ni salidas: eso lo hace solo el almacenero desde la app (004). Sin conexión (104) se deshabilitan todas las acciones que escriben, salvo guardar el borrador de planilla.

### ERP · Supervisión (mf-supervision)

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Ver el tablero: obras en ejecución, obras en riesgo, materiales bajos y tabla de obras | ✔ | propias | ✔ | | | | 009 |
| Indicador «Cobros vencidos» (cantidad y monto) | ✔ | | ✔ | | | | 009 |
| Ordenar la tabla, «Actualizar» y abrir el detalle de una obra | ✔ | propias | ✔ | | | | 009 |
| Indicador «Riesgo alto (modelo)» y columna «Riesgo (modelo)» | ✔ | propias | ✔ | | | | 402 |
| Pantalla «Riesgo de retraso» (lista, historial, «Sobre el modelo») | ✔ | propias | ✔ | | | | 402 |
| Indicador «Consumos atípicos por revisar» y columna «Atípicos» | ✔ | propias | ✔ | | | | 403 |
| Vista «Agentes»: tarjetas de agentes y lista de sugerencias | ✔ | propias (sin Control de cobros) | ✔ | | | | 502 |
| «Ejecutar ahora» un agente | ✔ | | ✔ | | | | 502 |
| Historial de ejecuciones y detalle de pasos | ✔ | | ✔ | | | | 502 |
| «Aprobar» / «Rechazar» sugerencias | ✔ | propias (sin Control de cobros) | ✔ | | | | 502 |
| «Reportes»: dictar o escribir, «Consultar», reportes comunes (atajos), ver historial de sus consultas | ✔ | | ✔ | | | | 503 |
| «Exportar a Excel» y «Exportar a CSV» | ✔ | | ✔ | | | | 503 |

### Portal del cliente

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| Ver «Mis obras» (nombre, ubicación, avance %, plazo %) | | | | | | propias | 008 |
| Ver el detalle de la obra: avance por partida y fotos publicadas (con rostros difuminados desde la 303) | | | | | | propias | 008, 303 |
| Ver la lista de planillas presentadas y anteriores (sin borradores) | | | | | | propias | 008 |
| Ver una planilla (líneas, totales, fotos de respaldo) | | | | | | propias | 008 |
| «Aprobar» una planilla `PRESENTADA` | | | | | | propias | 008 |
| «Observar» una planilla `PRESENTADA` (motivo de 10 a 500 caracteres) | | | | | | propias | 008 |

El cliente no ve los datos de detección de EPP (301), ni el riesgo de retraso (402), ni el diario de obra (103).

### App de obra

| Acción | admin | residente | gerente | maestro | almacenero | cliente | Origen |
|---|---|---|---|---|---|---|---|
| «Mis obras» | | | | propias | propias | | 001, 004 |
| «Foto de avance» (partida, cámara o galería, «Enviar») | | | | propias | | | 005 |
| Ver el aviso de casco y chaleco antes de enviar la foto | | | | propias | | | 301 |
| «Ingreso» de material (con número de nota de remisión opcional) | | | | | propias | | 004 |
| «Salida» de material (con partida de destino) | | | | | propias | | 004 |
| «Stock» de la obra (también al abrirlo desde un aviso de stock bajo) | | | | | propias | | 004, 010 |
| «Diario de obra» (registrar y corregir mientras no se envía; también al abrirlo desde el recordatorio del diario) | | | | propias | | | 103, 010 |
| Trabajar sin señal con los datos guardados en el celular | | | | propias | propias | | 101 |
| «Pendientes de envío» (ver, «Enviar ahora», «Descartar», «Actualizar datos») | | | | propias | propias | | 101 |
| Recibir avisos *push* de sus obras asignadas (permiso de notificaciones de Android la primera vez con señal; sin bandeja): recordatorio del diario (maestro) y stock bajo (almacenero) | | | | propias | propias | | 010 |

### Avisos que recibe cada rol (010)

Los envía n8n; sin bandeja ni historial. Cada aviso va solo al usuario asignado a la obra con ese rol.

| Aviso | Canal | admin | residente | gerente | maestro | almacenero | cliente |
|---|---|---|---|---|---|---|---|
| Stock bajo (al cruzar el mínimo) | *Push* al celular (tema `obra-{obraId}-almacenero`) | | | | | propias | |
| Diario pendiente (18:00 de La Paz, sin diario de hoy) | *Push* al celular (tema `obra-{obraId}-maestro`) | | | | propias | | |
| Planilla para revisar (presentada o corregida) | Correo | | | | | | propias |

La app se suscribe solo a los temas de las obras asignadas del paquete de datos (101) y los quita al cerrar sesión; el servidor no verifica la suscripción (consecuencia aceptada en la 010: una app modificada podría recibir avisos de stock o de diario de otra obra, que no tienen datos sensibles). Los demás avisos (planilla aprobada u observada, cobro vencido, contrato rechazado) quedan fuera del alcance (010).

## Permisos por servicio

Todas las rutas exigen token salvo `GET /salud`. En la columna **Regla** se indica la visibilidad que aplica el servicio además del rol. Un rol que no figura recibe `403 SIN_PERMISO`.

### Obras (puerto 8081)

| Método y ruta | Origen | Roles | Regla |
|---|---|---|---|
| `GET /salud` | fase 1 | sin token | — |
| `POST /obras` | 002, 401 | `admin` | — |
| `GET /obras?estado=&busqueda=` | 006, 009, 401, 010 | todos (`admin`, `residente`, `gerente`, `maestro`, `almacenero`, `cliente`) | Filtra por visibilidad de obras |
| `GET /obras/{id}` | 002, 004, 006, 008, 401, 201, 010 | los que pueden ver la obra | `404 OBRA_NO_ENCONTRADA` si no la ve |
| `GET /obras/{id}/material-previsto?periodo=` | 006 | `admin`, `gerente`, `residente` | Residente asignado; si no ve la obra, `404 OBRA_NO_ENCONTRADA` |
| `POST /obras/{obraId}/fotos/url-subida` | 005, 102 | `maestro`, `residente` | Asignados a la obra |
| `POST /obras/{obraId}/fotos` | 005, 102, 301 | `maestro`, `residente` | Asignados a la obra |
| `GET /obras/{obraId}/fotos?partidaId=&desde=&hasta=` | 005, 006, 007, 008, 301, 303 | los que pueden ver la obra | `cliente`: solo publicadas, `urlDescarga` de la versión para el cliente, `deteccion: null`. Internos: además `urlDescargaCliente` y `rostrosDifuminados` |
| `POST /obras/{obraId}/fotos/{fotoId}/url-subida-cliente` | 303 | `residente` | Asignado a la obra |
| `PUT /obras/{obraId}/fotos/{fotoId}/version-cliente` | 303 | `residente` | Asignado a la obra |
| `POST /obras/{obraId}/planillas` | 007 | `residente` | Asignado a la obra |
| `GET /obras/{obraId}/planillas` | 006, 007, 008, 401 | los que pueden ver la obra | `cliente` no recibe `BORRADOR`; incluye `cobroNumero` |
| `GET /planillas/{id}` | 007, 008, 401, 201, 010 | los que pueden ver la obra | `cliente` recibe `404` si es `BORRADOR`; incluye `cobroNumero` |
| `PUT /planillas/{id}` | 007 | `residente` | Asignado a la obra |
| `POST /planillas/{id}/presentar` | 007, 303, 010 | `residente` | Asignado a la obra (publica `PlanillaPresentada`, 010) |
| `POST /planillas/{id}/aprobar` | 008 | `cliente` | Dueño de la obra |
| `POST /planillas/{id}/observar` | 008 | `cliente` | Dueño de la obra |
| `POST /obras/{obraId}/diario` | 103 | `maestro` | Asignado; otro rol que ve la obra → `403 SIN_PERMISO`; maestro no asignado → `404` |
| `GET /obras/{obraId}/diario?desde=&hasta=` | 103, 010 | `maestro`, `residente` asignados; `admin`, `gerente` | `cliente` → `404 OBRA_NO_ENCONTRADA` |
| `POST /mcp` (MCP) | 501 | `agente_ia` | Ve todas las obras |

Quién llama: gateway (ERP), portal (`GET /obras`, `GET /obras/{id}`, fotos, planillas, aprobar, observar), Sincronización con el token del usuario (101, 102, 103), el servicio de IA en la carga inicial con el token de `ia-reportes` (`gerente`; solo los `GET` marcados con 401), n8n con el token de su *service account* (`gerente`; solo `GET /obras/{id}` y `GET /planillas/{id}`, 201, y desde la 010 también `GET /obras` y `GET /obras/{obraId}/diario`) y el servicio de IA por MCP (501).

### Materiales (puerto 8082)

| Método y ruta | Origen | Roles | Regla |
|---|---|---|---|
| `GET /salud` | fase 1 | sin token | — |
| `GET /materiales?busqueda=&soloActivos=` | 002, 003, 006, 401, 503, 010 | `admin`, `residente`, `gerente`, `maestro`, `almacenero` | — (también lo llaman Sincronización e IA con el token del usuario, la carga inicial de IA con el token de `ia-reportes` y n8n con su `gerente`, 010) |
| `POST /materiales` | 003 | `admin` | — |
| `PUT /materiales/{id}` | 003 | `admin` | — |
| `GET /obras/{obraId}/stock` | 003, 004 | internos que pueden ver la obra | Según `obra_acceso`; `404 OBRA_NO_ENCONTRADA` si no la ve |
| `PUT /obras/{obraId}/stock/{materialId}/minimo` | 003 | `admin` | — |
| `POST /movimientos` | 004 | `almacenero` | Asignado (`obra_acceso`); si no ve la obra, `404 OBRA_NO_ENCONTRADA` |
| `GET /obras/{obraId}/movimientos?periodo=` | 004, 102, 401 | internos que pueden ver la obra | Según `obra_acceso` (la carga inicial de IA, como `gerente`, ve todas) |
| `GET /obras/{obraId}/consumos?periodo=` | 006 | `admin`, `gerente`, `residente` | Residente asignado; si no ve la obra, `404 OBRA_NO_ENCONTRADA` |
| `GET /stock/resumen?obraIds=` | 009 | `admin`, `residente`, `gerente` | Solo devuelve obras visibles |
| `POST /mcp` (MCP) | 501 | `agente_ia` | Tratado como `gerente` (todas las obras) |

### Finanzas (puerto 8083)

Finanzas no guarda asignaciones de obras: sus endpoints de consulta son solo para `admin` y `gerente`.

| Método y ruta | Origen | Roles | Regla |
|---|---|---|---|
| `GET /salud` | fase 1 | sin token | — |
| `GET /contratos?obraId=` | 006, 201 | `admin`, `gerente` | — (`totalCobrado` incluye los `PAGADO`) |
| `GET /cobros?obraId=&estado=` | 006, 008, 401, 201 | `admin`, `gerente` | — (también la carga inicial de IA con el token de `ia-reportes`) |
| `GET /cobros/{id}` | 008, 201 | `admin`, `gerente` | — (el residente ve solo el número del cobro, que guarda Obras; también n8n con su `gerente`) |
| `GET /cobros/resumen` | 009 | `admin`, `gerente` | — |
| `POST /cobros/{id}/pago` | 201 | `admin` | — (lo llama el gateway con el token del usuario) |
| `GET /cobros/recordatorios` | 201 | `automatizacion` | Solo n8n |
| `POST /cobros/{id}/envios` | 201 | `automatizacion` | Solo n8n |
| `POST /cobros/{id}/nota-cobro` | 201 | `automatizacion` | Solo n8n |
| `POST /mcp` (MCP) | 501 | `agente_ia` | Todas las obras |

### Sincronización (puerto 8084, capa 1)

Todas las rutas, salvo `/salud`, piden además el encabezado `X-Dispositivo-Id`. Solo la llama la app de obra, así que acepta solo los roles de la app.

| Método y ruta | Origen | Roles | Regla |
|---|---|---|---|
| `GET /salud` | 101 | sin token | — |
| `GET /paquete-datos?obraActivaId=` | 101, 103 | `maestro`, `almacenero` | Los datos los filtran Obras y Materiales con el token del usuario. El diario por obra solo se agrega si el token tiene `maestro` (103) |
| `POST /lotes` | 101, 102, 103 | `maestro`, `almacenero` | Cada operación se reenvía con el token del usuario; una operación guardada por otro usuario → `OPERACION_AJENA` |
| `POST /fotos/url-subida` | 102 | `maestro` | La reenvía a Obras `POST /obras/{obraId}/fotos/url-subida` con el token del usuario; Obras aplica sus reglas (asignado) |

### IA (puerto 8085, capas 4 y 5)

Atiende solo al ERP: `maestro`, `almacenero`, `cliente`, `automatizacion` y `agente_ia` reciben `403 SIN_PERMISO` en todas las rutas REST (401). Excepción: `POST /mcp` (501) acepta **solo** `agente_ia`. Visibilidad del residente: `rpt_obra_resumen.residente_id = sub` (401); la cola `ia` existe desde la fase 1 y la carga inicial (401) trae lo que ya existía, así que la base de reportes conoce todas las obras. El servicio de IA **llama** a Obras, Materiales y Finanzas solo en la carga inicial (cliente `ia-reportes`).

| Método y ruta | Origen | Roles | Regla |
|---|---|---|---|
| `GET /salud` | 401 | sin token | — |
| `GET /reportes/estado` | 401 | `admin` | — (no se expone por GraphQL) |
| `GET /predicciones?obraIds=` | 402 | `admin`, `gerente`, `residente` | Solo obras visibles; las demás se omiten; hasta 100 ids |
| `GET /obras/{obraId}/prediccion?historial=` | 402 | `admin`, `gerente`, `residente` | `404 OBRA_NO_ENCONTRADA` si no la ve |
| `GET /modelos/riesgo-retraso` | 402 | `admin`, `gerente`, `residente` | — |
| `GET /consumos-atipicos?obraId=&estado=&desde=&hasta=` | 403 | `admin`, `gerente`, `residente` | Obras visibles; `404 OBRA_NO_ENCONTRADA` si pide una que no ve |
| `GET /consumos-atipicos/resumen?obraIds=` | 403 | `admin`, `gerente`, `residente` | Solo obras visibles; hasta 100 ids |
| `PUT /consumos-atipicos/{id}/revision` | 403 | `admin`, `residente` | Residente asignado a la obra (si no, `404 CONSUMO_ATIPICO_NO_ENCONTRADO`); `gerente` recibe `403` |
| `GET /agentes` | 502 | `admin`, `gerente`, `residente` | Residente: sin `CONTROL_COBROS`; pendientes solo de sus obras |
| `POST /agentes/{agente}/ejecuciones` | 502 | `admin`, `gerente` | — |
| `GET /ejecuciones?agente=&estado=&limite=` | 502 | `admin`, `gerente` | — |
| `GET /ejecuciones/{id}` | 502 | `admin`, `gerente` | Residente → `403` (504, G10) |
| `GET /hallazgos?agente=&obraId=` | 502 | `admin`, `gerente`, `residente` | Residente: sus obras, sin `CONTROL_COBROS` |
| `GET /sugerencias?estado=&agente=&obraId=&limite=` | 502 | `admin`, `gerente`, `residente` | Residente: sus obras, sin `CONTROL_COBROS` |
| `POST /sugerencias/{id}/aprobar` | 502 | `admin`, `gerente`, `residente` | Residente: sus obras, sin `CONTROL_COBROS` (si no, `404 SUGERENCIA_NO_ENCONTRADA`) |
| `POST /sugerencias/{id}/rechazar` | 502 | `admin`, `gerente`, `residente` | Ídem |
| `POST /consultas-reporte` | 503 | `admin`, `gerente` | Residente → `403`; 10 por minuto por usuario |
| `GET /consultas-reporte?limite=` | 503 | `admin`, `gerente` | Solo las consultas del usuario del token |
| `GET /catalogo-reportes` | 503 | `admin`, `gerente` | — |
| `POST /mcp` (MCP) | 501 | `agente_ia` | Todas las obras; personas → `403` |

### Herramientas MCP (capa 5, solo lectura)

Ruta `POST /mcp` de Obras, Materiales, Finanzas e IA. Rol único: `agente_ia` (*service account* de `ia-agentes`; el host es `ia-worker`). Un token de `gerente` o `admin` recibe `403`; el token de `agente_ia` en un endpoint REST (también los de IA) recibe `403` (504, M2 y M6).

| Herramienta | Servicio | Origen | La usa el agente |
|---|---|---|---|
| `avance_obra` | Obras | 501 | Seguimiento de obras, Control de materiales |
| `buscar_diario` | Obras | 501 | Seguimiento de obras |
| `planillas_estado` | Obras | 501 | Seguimiento de obras, Control de cobros |
| `stock_obra` | Materiales | 501 | Control de materiales |
| `consumos_partida` | Materiales | 501 | Control de materiales |
| `cobros_por_vencer` | Finanzas | 501 | Control de cobros |
| `riesgo_retraso` | IA | 501 | Seguimiento de obras |
| `consumos_atipicos` | IA | 501 | Control de materiales |
| `consultar_reporte` | IA | 501, 503 | Los tres, cada uno con sus conjuntos: Seguimiento de obras `OBRAS` y `PLANILLAS`; Control de materiales `CONSUMO_MATERIAL` y `MOVIMIENTOS`; Control de cobros `COBROS` y `PLANILLAS` |

Cada agente solo ve y usa las suyas (mínimo privilegio, lo aplica el host, 502); otra herramienta → `HERRAMIENTA_NO_PERMITIDA`; otro conjunto en `consultar_reporte` → `ARGUMENTO_INVALIDO`.

### Gateway · GraphQL del ERP (puerto 4000)

El gateway valida el token y el rol con `RolesGuard` (001); cada servicio vuelve a aplicar su visibilidad. Los roles están anotados en el SDL de `gateway/docs/contratos.md` y de cada spec de capa. Solo atiende al ERP (`admin`, `residente`, `gerente`).

**Consultas**

| Operación | Origen | Roles | Regla |
|---|---|---|---|
| `salud` | fase 1, 104 | sin token | — |
| `usuarios(rol)` | 002 | `admin` | Keycloak con el cliente `gateway` |
| `obras(estado, busqueda)` | 006, 401 | `admin`, `gerente`, `residente` | Residente: sus obras |
| `obra(id)` | 006 | `admin`, `gerente`, `residente` | `404 OBRA_NO_ENCONTRADA` si no la ve |
| `Obra.finanzas`, `Obra.cobros` (con `pagadoEn`, `comprobante` y `envios`, 201) | 006, 201 | `admin`, `gerente` | `null` sin error para otros roles |
| `Obra.materialComparado(periodo)` | 006 | `admin`, `gerente`, `residente` | Residente: sus obras |
| `Obra.fotos(partidaId)` (con `deteccion`, `urlDescargaCliente`, `rostrosDifuminados`) | 005, 301, 303 | `admin`, `gerente`, `residente` | Visibilidad de Obras |
| `Obra.planillas` | 007 | `admin`, `gerente`, `residente` | Visibilidad de Obras |
| `Obra.riesgoRetraso`, `Obra.historialRiesgo` | 402 | `admin`, `gerente`, `residente` | Visibilidad de IA |
| `Obra.consumosAtipicos(estado)` | 403 | `admin`, `gerente`, `residente` | Visibilidad de IA |
| `Obra.hallazgos(agente)`, `Obra.sugerencias(estado)` | 502 | `admin`, `gerente`, `residente` | Residente: sin `CONTROL_COBROS` |
| `planilla(id)` | 007 | `admin`, `gerente`, `residente` | Residente: sus obras |
| `Planilla.cobro` → `id` y `numero` | 008 | `admin`, `gerente`, `residente` | Desde Obras (`cobroId`, `cobroNumero`) |
| `Planilla.cobro` → `montoNeto`, `emitidoEn`, `venceEn`, `estado` | 008 | `admin`, `gerente` | Finanzas `GET /cobros/{id}`; `null` sin error para el residente |
| `materiales(...)` | 003 | `admin`, `gerente`, `residente` | — |
| `stockObra(obraId)` | 003 | `admin`, `gerente`, `residente` | Residente: sus obras |
| `tablero` | 009 | `admin`, `gerente`, `residente` | Residente: sus obras |
| `IndicadoresTablero.cobrosVencidos` | 009 | `admin`, `gerente` | `null` sin error para otros roles |
| `FilaTablero.riesgoRetraso`, `IndicadoresTablero.obrasRiesgoAlto` | 402 | `admin`, `gerente`, `residente` | Visibilidad de IA; lotes de 100 obras |
| `FilaTablero.consumosAtipicosPendientes`, `IndicadoresTablero.consumosAtipicosPendientes` | 403 | `admin`, `gerente`, `residente` | Visibilidad de IA; lotes de 100 obras |
| `modeloRiesgo` | 402 | `admin`, `gerente`, `residente` | — |
| `agentes` | 502 | `admin`, `gerente`, `residente` | Residente: sin `CONTROL_COBROS` |
| `ejecucionesAgente(...)`, `ejecucionAgente(id)` | 502 | `admin`, `gerente` | — |
| `hallazgos(agente, obraId)`, `sugerencias(...)` | 502 | `admin`, `gerente`, `residente` | Residente: sus obras, sin `CONTROL_COBROS` |
| `catalogoReportes`, `consultasReporte(limite)` | 503 | `admin`, `gerente` | Solo las consultas del usuario |

**Mutaciones**

| Operación | Origen | Roles | Regla |
|---|---|---|---|
| `registrarObra(entrada)` | 002, 401 | `admin` | — |
| `crearMaterial(entrada)`, `actualizarMaterial(id, entrada)` | 003 | `admin` | — |
| `definirStockMinimo(obraId, materialId, minimo)` | 003 | `admin` | — |
| `crearPlanilla(obraId, periodo)` | 007 | `residente` | Asignado a la obra |
| `guardarPlanilla(id, entrada)` | 007, 104 | `residente` | Asignado a la obra |
| `presentarPlanilla(id, version)` | 007, 303 | `residente` | Asignado a la obra |
| `prepararSubidaFotoCliente(obraId, fotoId)` | 303 | `residente` | Asignado a la obra |
| `registrarFotoCliente(obraId, fotoId, claveArchivoCliente, rostrosDifuminados)` | 303 | `residente` | Asignado a la obra |
| `registrarPagoCobro(cobroId, pagadoEn, comprobante)` | 201 | `admin` | Finanzas `POST /cobros/{id}/pago` con el token del usuario |
| `revisarConsumoAtipico(id, estado, comentario)` | 403 | `admin`, `residente` | Residente asignado a la obra |
| `ejecutarAgente(agente)` | 502 | `admin`, `gerente` | — |
| `aprobarSugerencia(id, comentario)`, `rechazarSugerencia(id, motivo)` | 502 | `admin`, `gerente`, `residente` | Residente: sus obras, sin `CONTROL_COBROS` |
| `consultarReporte(texto, atajo)` | 503 | `admin`, `gerente` | El gateway agrega el directorio de clientes |

### Paneles técnicos (602)

El panel de RabbitMQ, n8n, la interfaz de Mailpit y la consola de administración de Keycloak no tienen roles de la plataforma: en producción se abren solo por HTTPS y con usuario y contraseña propios (602, criterio 5). La gestión de usuarios y roles se hace en el panel de Keycloak (fuera del alcance de las aplicaciones).

## Inconsistencias encontradas

Todas las que se encontraron al armar esta matriz quedaron resueltas en las specs y los contratos (28/10/2026). Se dejan aquí para saber qué se decidió:

1. **Sincronización aceptaba `residente`, que no entra a la app.** Ahora solo `maestro` y `almacenero` (101, 102 y 103: diseño y tareas de Sincronización; el diario del paquete solo para `maestro`).
2. **Los `app.md` de mf-obras, mf-materiales y mf-supervision no coincidían con las specs.** Se corrigieron con los roles de las specs (también se quitó de mf-materiales la pantalla «usado frente a previsto», que es la pestaña «Material» de mf-obras).
3. **No estaba escrita la regla de `404` frente a `403`.** Ahora está en `convenciones.md` («Autenticación y permisos»): rol sin permiso → `403 SIN_PERMISO`; rol con permiso pero obra que no ve → `404 OBRA_NO_ENCONTRADA`. Se alinearon las pruebas de 004, 005, 102, 103 y 303.
4. **`GET /cobros/{id}` aceptaba `residente` sin regla de visibilidad.** Ahora es solo para `admin` y `gerente`; Obras guarda `planilla.cobro_numero` al recibir `CobroEmitido` y el gateway resuelve `Planilla.cobro.numero` desde Obras (008: diseño y tareas de Obras y del gateway; datos y contratos de Obras; contratos de Finanzas y del gateway).
5. **`material-previsto` y `consumos` no decían «residente asignado».** Ahora lo dicen los contratos y la 006.
6. **El enlace al portal desde el ERP llevaba a «No tienes acceso».** «Aplicaciones» muestra solo las aplicaciones web para las que el usuario tiene rol; el usuario de prueba `demo1` (`residente` y `cliente`) sirve para demostrar el SSO (001: requisitos, diseño, tareas del shell y de infra). Sus obras las asigna la 011.
7. **La visibilidad del residente en IA dependía de la carga de la base de reportes.** La cola `ia` y sus enlaces se declaran desde la fase 1 (`docs/entorno-local.md`, 401); los datos de prueba de las tablas `rpt_*` los trae la carga inicial de la 401 desde lo que cargó la 011 (31/10/2026; antes, una semilla propia de IA).
8. **El SDL del gateway no anotaba el rol de todas las operaciones.** Ahora sí (`gateway/docs/contratos.md`, `docs/contratos/graphql-erp.md`, 402 y 502).
9. **No se decía si `{ salud }` exigía token.** No lo exige (`convenciones.md`, SDL).
10. **Faltaban los roles técnicos en las convenciones.** `automatizacion` (201) y `agente_ia` (501) figuran como «se crean con su capa».
11. **`admin` podía registrar movimientos sin tener dónde.** `POST /movimientos` es solo para el `almacenero` asignado (004, contratos de Materiales); por coherencia, también los dos endpoints de la nota de remisión que tenía la 102 (quitados al simplificarla el 30/10/2026).

12. **Capa 5 (31/10/2026): las «herramientas locales» de IA no pasaban por MCP ni por su validación.** Ahora `riesgo_retraso`, `consumos_atipicos` y `consultar_reporte` son herramientas del servidor MCP de IA (`POST /mcp`, solo `agente_ia`), y el host limita por agente las herramientas y los conjuntos de `consultar_reporte` (501, 502). Las rutas de reportes pasaron a `/consultas-reporte` y `/catalogo-reportes` (503).

13. **La 201 dejó de ser la compra automática (01/11/2026).** Pasó a ser la cobranza automática: se quitaron las filas de proveedores, órdenes de compra y cuentas por pagar (catálogo, ingreso en la app, Materiales, Finanzas y gateway); `automatizacion` queda solo en las rutas de cobranza de Finanzas que llama n8n, y se agregaron el registro de pago (`admin`) y la lectura de n8n con `gerente` y `view-users`.

14. **La 010 se rehízo (02/11/2026).** Ya no hay servicio de notificaciones, bandeja, campana ni *push* web: se quitaron el servicio Notificaciones (8086), sus filas del ERP, el portal y la app, y sus operaciones GraphQL. Quedan tres avisos que envía n8n (stock bajo y diario por *push* al celular; «planilla para revisar» por correo), con la lectura de n8n (`gerente`) ampliada a `GET /obras`, `GET /obras/{obraId}/diario` y `GET /materiales`.

Pendiente de aplicar, sin contradicción: los cambios a contratos de la 010 se integran en `docs/contratos/` como primera tarea (`docs/plan.md`); esta matriz ya los incluye. Los de la capa 5 (501, 502, 503 y 504) y los de la 201 ya están en `docs/contratos/` (01/11/2026). Ya no vale para la 010 (02/11/2026): se rehízo y sus cambios ya están en `docs/contratos/` y en esta matriz.
