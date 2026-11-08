# Convenciones

Lo que todos los proyectos hacen igual.

## Nombres

- Dominio en español: `obra`, `partida`, `planilla`, `cobro`, `material`, `movimiento`.
- Tablas, columnas y campos de MongoDB en `snake_case`.
- JSON de las APIs (REST y GraphQL) en `camelCase`. Cada servicio traduce entre ambos.
- Rutas REST en español, en plural y en minúsculas con guiones: `/obras/{id}/planillas`, `/cobros/{id}/nota-cobro`.
- Identificadores: UUID. Los registros creados en el celular traen su UUID desde el celular.
- Fechas en UTC con formato ISO 8601 (`2026-10-28T14:30:00Z`); fechas sin hora como `2026-10-28`; periodos como `2026-10`.
- Montos en bolivianos, en JSON como número con 2 decimales; en la base, `numeric(14,2)`. Cantidades con 3 decimales (`numeric(14,3)`). Los cálculos redondean a 2 decimales al final, con redondeo «mitad hacia arriba».
- Zona horaria del negocio: `America/La_Paz` (UTC−4). El periodo de un registro (`AAAA-MM`) se calcula con la fecha en esa zona.

## Puertos en desarrollo

| Pieza | Puerto |
|---|---|
| Keycloak | 8080 |
| Obras | 8081 |
| Materiales | 8082 |
| Finanzas | 8083 |
| Sincronización (capa 1) | 8084 |
| IA (capas 4 y 5) | 8085 |
| Gateway | 4000 |
| ERP: shell · mf-obras · mf-materiales · mf-supervision | 4200 · 4201 · 4202 · 4203 |
| Portal | 4300 |
| Metro de Expo (app en desarrollo; el 8081 es de Obras) | 8090 |
| PostgreSQL · MongoDB · RabbitMQ (AMQP / panel) | 5433 · 27017 · 5672 / 15672 |
| DynamoDB Local (Sincronización, capa 1) | 8000 |
| Ollama (modelo de lenguaje local, capa 5, perfil `ollama`; solo en `127.0.0.1`) | 11434 |
| n8n (201 y 010, perfil `automatizacion`) | 5678 |
| Mailpit (correo de prueba, 201 y 010, perfil `automatizacion`): SMTP / interfaz y API | 1025 / 8025 |

- PostgreSQL usa el 5433 (no el 5432) porque así está configurado Obras y es el puerto de la instalación local de Jairo. Una sola instancia con una base por servicio: `obras_db`, `finanzas_db` y, en la capa 4, `reportes_db` (modelo de lectura del servicio de IA, 401), con su usuario propio `ia`, dueño de la base (`POSTGRES_IA_CLAVE` de `infra/.env`), y desde la 503 el rol de solo lectura `ia_reportes_lector` (`POSTGRES_IA_LECTOR_CLAVE`; `SELECT` solo sobre las tablas `rpt_*` que lee el constructor de reportes). El servicio de IA usa además la base `ia_db` de MongoDB (402, 403 y, en la capa 5, agentes, sugerencias, consultas de reportes y límite por minuto).
- En la máquina de Jairo, PostgreSQL (5433) y MongoDB (27017) ya están instalados como servicios de Windows; ahí Docker Compose levanta solo RabbitMQ, Keycloak y DynamoDB Local (101). Quien no los tenga instalados levanta también los contenedores de las bases.
- El ensayo del despliegue («producción local», 601) usa otros puertos (8443, 9443, 10443 y 5671) para no chocar con estos: «Contenedores y CI».

## Datos de prueba (011)

- Los datos de prueba (`docs/datos-prueba.md`) **solo se cargan en desarrollo**: `infra/semilla/semilla.ps1` (o `.sh`) y `recargar` se niegan a correr sin `SEMILLA_PERMITIDA=si` en el `.env` de infra, y cada servicio rechaza su propia semilla en producción (`prod`, `APP_ENV=production`, `NODE_ENV=production`) o con una base que no sea local.
- **Única excepción, datos de demostración (601):** con `SEMILLA_DEMO=si` (solo en el `.env` de la «producción local» o de la nube, nunca en `infra/.env`) la semilla **carga** sin duplicar aunque el servicio esté en modo producción o la base no sea local; el **vaciado** (`recargar` y los comandos de vaciar de cada servicio) sigue prohibido fuera de desarrollo, sin excepción. Detalle en `docs/datos-prueba.md` («Guardas»).
- La semilla no publica eventos ni comandos (no escribe `outbox_evento` ni `mensaje_procesado`) y todos los servicios usan la misma fecha D (`SEMILLA_FECHA`).

## Autenticación y permisos (Keycloak)

- Realm `supervision`. Keycloak emite tokens JWT (OIDC). Emisor: `http://localhost:8080/realms/supervision` en desarrollo y, en la nube (602), `https://keycloak.supervision.workflow-tramites.site/realms/supervision` (`KC_HOSTNAME`).
- Roles del realm: `admin`, `residente`, `gerente`, `maestro`, `almacenero`, `cliente`.
- Roles técnicos (se crean con su capa; ninguna persona los tiene): `automatizacion` (201, *service account* del cliente confidencial `n8n`; solo en las rutas de Finanzas de la 201 que llama n8n: `GET /cobros/recordatorios`, `POST /cobros/{id}/envios` y `POST /cobros/{id}/nota-cobro`) y `agente_ia` (501, *service account* del cliente confidencial `ia-agentes`; solo en `POST /mcp` de Obras, Materiales, Finanzas e IA, donde ve todas las obras como `gerente`; ningún endpoint REST lo acepta).
- Clientes públicos con PKCE: `erp` (shell y microfrontends), `portal`, `app-obra`.
- Cliente confidencial `gateway` con *service account* y los roles `view-users` y `view-realm` de `realm-management`: el gateway los usa para listar usuarios por rol (formularios de asignación) y resolver nombres. `view-realm` hace falta porque Keycloak 26 exige ver los roles del realm para responder `GET /roles/{rol}/users`; es de solo lectura. Ningún otro proyecto llama a la API de administración de Keycloak, salvo n8n (capa 2, abajo).
- Capa 2 (201): cliente confidencial `n8n` (solo *client credentials*, mapper de audiencia `plataforma-api`) con *service account* que tiene `automatizacion` (rutas nuevas de Finanzas), el **rol de realm `gerente`** (para leer con los endpoints que ya existen: Obras `GET /obras/{id}` y `GET /planillas/{id}`, Finanzas `GET /cobros/{id}` y, desde la 010, Obras `GET /obras` y `GET /obras/{obraId}/diario` y Materiales `GET /materiales`, igual que `ia-reportes`, sin cambiar guardias ni visibilidad) y `view-users` de `realm-management` (para leer el nombre y el correo del cliente con `GET /admin/realms/supervision/users/{id}`): es la **segunda excepción** a la API de administración de Keycloak, junto al gateway. El `azp` del token es `n8n` (roles del token tal cual). Su secreto va en `N8N_KEYCLOAK_SECRETO` de `infra/.env` y se inyecta en la credencial de n8n; nunca en el repo.
- Capa 4 (401): cliente confidencial `ia-reportes` con *service account* (solo *client credentials*) y el **rol de realm `gerente`** en su *service account*, para la carga inicial del modelo de lectura: el servicio de IA hace solo `GET` a endpoints que ya aceptan `gerente` (Obras, Materiales y Finanzas; lista en la 401). Se usa `gerente` y no un rol técnico nuevo para no cambiar los guardias ni la visibilidad de los tres servicios. Su secreto solo lo lee el comando de carga inicial (no `ia-api` ni `ia-worker`).
- Capa 5: cliente confidencial `ia-agentes` con *service account* para que el servicio de IA (host de los agentes, `ia-worker`) llame a las herramientas MCP de los cuatro servicios; su secreto solo lo lee `ia-worker`. La clave de la API de Anthropic (`IA_ANTHROPIC_API_KEY`, si se usa ese proveedor) se trata igual: solo en `.env` o en el gestor de secretos.
- Todos los tokens llevan la audiencia `plataforma-api` (mapper de audiencia en Keycloak).
- Cada servicio valida firma (JWKS del realm), vencimiento, emisor y audiencia `plataforma-api`. Si Keycloak no responde al pedir el JWKS, se responde `503 SERVICIO_NO_DISPONIBLE` (en el gateway, `extensions.servicio = "keycloak"`), no `401`: un `401` haría que la aplicación cierre la sesión del usuario por una falla del servidor.
- Los roles van en el token (`realm_access.roles`); el id del usuario es el `sub` del token.
- Las reglas finas (qué obras puede ver el usuario) las valida cada servicio. Obras es dueño de las asignaciones; Materiales guarda una copia (`obra_acceso`) que recibe con el evento `ObraRegistrada`, y el servicio de IA usa `rpt_obra_resumen.residente_id` de su modelo de lectura (401).
- Visibilidad de obras: `admin` y `gerente` ven todas; `residente`, `maestro` y `almacenero` ven las que tienen asignadas; `cliente` ve las suyas.
- **Usuario con varios roles** (por ejemplo `demo1`, residente y cliente): cada servicio aplica solo los roles de la aplicación desde la que se inició sesión, que viene en el campo `azp` del token. Con `azp = portal` cuentan solo las reglas de `cliente`; con `azp = erp` o `app-obra`, solo las de los roles internos. Las llamadas de servicio a servicio usan el `azp` de su propio cliente (`gateway`, `ia-reportes`, `ia-agentes`, `n8n`). Un `azp` que no es `portal`, `erp` ni `app-obra` (clientes de servicio, o un token sin `azp`) usa los roles del token tal cual. Cada servicio lo aplica con una función pura de «roles efectivos» y toda regla por rol (incluida la visibilidad de obras) la usa. Excepción: el menú «Aplicaciones» del ERP mira los roles del token completo, para ofrecer el portal a quien tiene `cliente`.
- Respuestas de permiso:
  - `401 NO_AUTENTICADO`: no hay token válido.
  - `403 SIN_PERMISO`: el rol del usuario no permite esa acción (no figura en los roles del endpoint, o figura con una condición que no cumple, por ejemplo `residente` en una acción solo de `admin`). Se comprueba primero, en el guardia de cada endpoint.
  - `404` con el código de «no encontrado» del recurso (por ejemplo `404 OBRA_NO_ENCONTRADA`): el rol sí puede hacer la acción, pero el usuario no ve esa obra (no está asignado o no es su cliente). Se responde igual que si no existiera, para no revelar que existe; vale para lecturas y escrituras.
- La matriz completa de quién puede qué está en `docs/permisos.md`.
- Servidores MCP (capa 5, 501): `POST /mcp` de Obras, Materiales, Finanzas e IA pasa por la misma validación de token de cada servicio y exige `agente_ia` (roles efectivos con `azp = ia-agentes`); también el `/mcp` del servicio de IA, que en sus rutas REST sigue aceptando solo `admin`, `gerente` y `residente`. Librerías: Spring AI 2.0 (SDK de MCP para Java 2.1, Obras), `@modelcontextprotocol/server` 2 + `zod` 4 (Materiales), `laravel/mcp` 1 (Finanzas) y `mcp` 2 (servidor y cliente, IA). Versión común del protocolo: 2025-11-25. El secreto de `ia-agentes` (`IA_AGENTES_CLIENT_SECRET`) es un secreto como los de los demás clientes confidenciales: solo en `.env` o en el gestor de secretos.
- Librerías: Spring Security OAuth2 Resource Server (Obras), `jose` (NestJS: gateway, Materiales, Sincronización), `firebase/php-jwt` con JWKS (Finanzas), `PyJWT[crypto]` 2 con `PyJWKClient` (IA), keycloak-angular 22 + keycloak-js 26 (shell), react-oidc-context + oidc-client-ts (portal), `expo-auth-session` (app).

## Sesión dentro del ERP

- El shell es el único que inicia sesión. Publica la sesión en `window.plataforma.sesion` con:
  - `usuario`: `{ id, nombre, roles }`
  - `obtenerToken(): Promise<string>`: devuelve un token vigente (lo renueva si hace falta)
  - `cerrarSesion(): void`
- Cuando la sesión cambia, el shell emite el evento `plataforma:sesion` en `window`.
- El shell publica también `window.plataforma.configuracion` con `{ gatewayUrl }`, para que los microfrontends no repitan configuración. Desde la 601 el shell lo toma de su `configuracion.json` (escrito al publicar) y es la **única** fuente de la dirección del gateway para los microfrontends; abiertos solos (desarrollo), usan `http://localhost:4000/graphql`.
- Los microfrontends (Angular y React) solo leen ese objeto; nunca hablan con Keycloak.
- ERP sin conexión (104):
  - `sesion.sinConexion: boolean`; en ese modo `obtenerToken()` rechaza con `Error('SIN_CONEXION')`.
  - `window.plataforma.conexion`: `{ enLinea, reportarFallo() }` y el evento `plataforma:conexion` (`detail: { enLinea }`).
  - `window.plataforma.almacen`: almacén local en IndexedDB (`guardarConsulta`, `leerConsulta`, `guardarBorradorPlanilla`, `leerBorradorPlanilla`, `listarBorradoresPlanilla`, `borrarBorradorPlanilla`), separado por usuario y borrado al cerrar sesión; evento `plataforma:borradores`.
  - Los microfrontends no usan IndexedDB, `localStorage` ni service workers propios: usan lo que publica el shell.
- Rutas del shell: `/obras` (mf-obras), `/materiales` (mf-materiales), `/supervision` (mf-supervision).

## Listas y paginación

- Las listas que pueden crecer se paginan: `GET /materiales`, `GET /obras/{obraId}/movimientos`, `GET /obras/{obraId}/fotos`, `GET /cobros` (y las que cada capa marque como paginadas).
- Parámetros: `pagina` (desde 1, por defecto 1), `tamano` (por defecto 20, máximo 100), `orden` (campo, por ejemplo `registradoEn`) y `direccion` (`asc` o `desc`). Los filtros propios de cada endpoint se suman como parámetros con nombre.
- Respuesta: `{ "items": [...], "total": 134, "pagina": 1, "tamano": 20 }`.
- `tamano` mayor a 100 → `400 PAGINACION_INVALIDA`.
- Las listas cortas por naturaleza (obras, partidas de una obra, planillas de una obra, stock de una obra, contratos) devuelven un arreglo simple.
- GraphQL: los campos paginados reciben `pagina` y `tamano` y devuelven un tipo `XxxPagina { items, total, pagina, tamano }`.

## Errores REST

- Formato estándar **Problem Details (RFC 9457)**, `Content-Type: application/problem+json`, con dos campos propios:

```json
{
  "type": "about:blank",
  "title": "La planilla no está presentada",
  "status": 409,
  "detail": "Solo se puede aprobar una planilla en estado PRESENTADA.",
  "codigo": "PLANILLA_NO_PRESENTADA",
  "errores": [{ "campo": "cantidadPeriodo", "mensaje": "Supera la cantidad contratada" }]
}
```

- `codigo`: identificador estable en `MAYUSCULAS_CON_GUION_BAJO`; el frontend decide qué mostrar según este campo.
- `errores`: en errores de validación (`400` o `422`). Si un mismo `codigo` puede deberse a reglas distintas (por ejemplo `COMENTARIO_INVALIDO`), `errores[]` trae el `campo` y un `mensaje` con la regla concreta; el frontend muestra el mensaje del catálogo y, junto al campo, ese `mensaje`.
- Estados: `400` datos mal formados · `401` sin token · `403` sin permiso · `404` no existe o no lo puede ver · `409` conflicto de estado o versión · `413` cuerpo demasiado grande · `422` regla del negocio incumplida · `429` demasiadas peticiones · `500` error interno · `503` servicio no disponible (se puede reintentar) · `504` tiempo agotado.
- Todo error lleva `codigo`. Si no hay uno propio, se usa el genérico de su estado: `400 DATOS_INVALIDOS`, `401 NO_AUTENTICADO`, `403 SIN_PERMISO`, `413 ARCHIVO_DEMASIADO_GRANDE`, `429 DEMASIADAS_PETICIONES`, `500 ERROR_INTERNO`, `503 SERVICIO_NO_DISPONIBLE`; una ruta que no existe responde `404 RUTA_NO_ENCONTRADA` (solo con token válido: sin token, `401`). En los contratos, un estado escrito sin código (por ejemplo «`400`» o «`403`») significa ese genérico. `404`, `409` y `422` siempre llevan un código propio.
- `504 TIEMPO_AGOTADO`: el servicio llamó a otro servicio (o a un componente externo, como el modelo de lenguaje) y no recibió respuesta en su tiempo máximo. Es el mismo código y estado en todos los servicios. El error de una ejecución de agente por pasar su límite de tiempo es otro: `EJECUCION_TIEMPO_AGOTADO` (502).
- Códigos propios del servicio de IA en la capa 5: `TEXTO_INVALIDO` (`400`), `INTENCION_NO_RECONOCIDA` y `RECETA_INVALIDA` (`422`), `DEMASIADAS_CONSULTAS` (`429`), `LLM_NO_DISPONIBLE` y `REPORTES_NO_DISPONIBLES` (`503`) (503); `AGENTE_INVALIDO` (`400`), `EJECUCION_NO_ENCONTRADA` y `SUGERENCIA_NO_ENCONTRADA` (`404`), `EJECUCION_EN_CURSO` y `SUGERENCIA_YA_DECIDIDA` (`409`), `COMENTARIO_INVALIDO` y `MOTIVO_INVALIDO` (`422`) (502). Los de una ejecución de agente o de una herramienta MCP no son respuestas HTTP (`docs/mensajes.md`, «Errores de la ejecución de un agente»).
- El texto que ve el usuario por cada `codigo` está en `docs/mensajes.md`; un código que el frontend no conoce se muestra con el mensaje genérico de su estado HTTP.

## Errores GraphQL (gateway)

- Cada error va en `errors[]` con `extensions.codigo` (el mismo `codigo` del servicio) y `extensions.servicio`.
- Si un servicio no responde, solo los campos que dependen de él vuelven en `null` con `extensions.codigo = "SERVICIO_NO_DISPONIBLE"`; el resto de la respuesta llega.
- Tiempo máximo por llamada del gateway a un servicio: **3 segundos**. Las consultas se reintentan una vez; las mutaciones no se reintentan.
- **Excepción (503):** `consultarReporte` espera hasta **60 segundos** a IA (interpretar con el modelo de lenguaje, consultar y resumir), sin reintento por ser mutación; si IA no responde en ese tiempo, `SERVICIO_NO_DISPONIBLE`. El resto de las operaciones de IA siguen con 3 s. **(decisión del equipo)**

## Idempotencia

- Toda operación que crea algo desde el celular o desde un evento usa un identificador de operación (el UUID del registro).
- El servicio guarda los identificadores ya procesados y, si llega uno repetido, devuelve `200` con el registro existente en lugar de crearlo otra vez.
- En la capa 1, la primera barrera es Sincronización: guarda cada `idOperacion` en DynamoDB (`operacion_procesada`, «guardar solo si no existe», TTL de 30 días) y devuelve la respuesta guardada si se repite. Los servicios dueños mantienen su propia idempotencia por `id` (101).

## Eventos y comandos (RabbitMQ)

- Un *exchange* tipo `topic` llamado `plataforma`.
- Clave de enrutamiento: `evento.<origen>.<Tipo>` para eventos (algo que pasó) y `comando.<destino>.<Tipo>` para órdenes de la saga. Ejemplos: `evento.obras.ObraRegistrada`, `comando.finanzas.ReservarSaldo`.
- Cada servicio tiene su propia cola durable (`obras`, `materiales`, `finanzas`, `ia`) y se suscribe a las claves que le interesan. n8n (201 y 010) usa una cola durable por flujo, declarada en las definiciones de RabbitMQ de infra: `n8n.cobro-emitido` (`evento.finanzas.CobroEmitido`) y `n8n.cobro-pagado` (`evento.finanzas.CobroPagado`) en la 201; `n8n.stock-bajo` (`evento.materiales.StockBajo`) y `n8n.planilla-presentada` (`evento.obras.PlanillaPresentada`) en la 010. No guarda inbox en una base: confirma el mensaje al terminar la ejecución; en la 201 la idempotencia la da Finanzas (`envio_cobro`, único por cobro y tipo) y en la 010 cada flujo guarda el `id` del sobre en sus datos estáticos (los últimos 500) y descarta los repetidos.
- Sobre común de todo mensaje:

```json
{
  "id": "uuid del mensaje",
  "tipo": "PlanillaAprobacionIniciada",
  "version": 1,
  "ocurridoEn": "2026-10-28T14:30:00Z",
  "origen": "obras",
  "correlacionId": "uuid de la saga o del flujo",
  "datos": { }
}
```

- `tipo` en PascalCase: los eventos en pasado (`ObraRegistrada`), los comandos en infinitivo (`ReservarSaldo`).
- Se publican con el patrón **outbox**: el mensaje se guarda en la misma transacción que el dato y un proceso aparte lo publica (cada segundo).
- Cada consumidor guarda los `id` de mensajes procesados (patrón inbox) y descarta los repetidos.
- Mensajes que fallan 3 veces van a la cola `plataforma.fallidos` para revisión. Cada reintento se vuelve a publicar en la misma cola por el exchange por defecto con el cuerpo original sin tocar y estos encabezados (iguales en todos los servicios): `x-intentos` (intentos ya hechos), `x-error` (texto del error, sin datos sensibles), `x-cola-origen` (cola de donde salió) y `x-clave-origen` (clave de enrutamiento original, que se pierde al pasar por el exchange por defecto).
- Van directo a `plataforma.fallidos`, sin reintentos: un cuerpo que no es JSON, un sobre con `version` distinta de 1, datos incompletos y un `tipo` que la cola recibe pero el servicio todavía no procesa (así no se pierde y se puede reenviar cuando exista su consumidor).
- Librerías: Spring AMQP (Obras), `amqplib` / `@nestjs/microservices` (Materiales), `php-amqplib` 3 (Finanzas), `aio-pika` 10 (IA; solo consume en la capa 4).

## Seguridad

- **CORS:** cada servicio acepta solo los orígenes de su variable `CORS_ORIGENES` (ver `docs/entorno-local.md`): el gateway, los del ERP; Obras, el portal; Materiales, Finanzas e IA, ninguno (los llama el gateway o la app, que no usa CORS). Nunca `*` con credenciales.
- **Tamaños máximos:** cuerpo JSON 1 MB; fotos 5 MB (la app las comprime antes, ver «Archivos»); las URL firmadas de subida aceptan solo `image/jpeg` y hasta 5 MB.
- **GraphQL:** profundidad máxima 8 y complejidad máxima 1000 por consulta (complejidad = cantidad de campos pedidos, contando fragmentos); si se pasa, `DATOS_INVALIDOS`. Introspección y Apollo Sandbox solo en desarrollo.
- **Límite de peticiones:** 120 por minuto por usuario en el gateway y en los endpoints del portal en Obras (al superar: `429 DEMASIADAS_PETICIONES` con `Retry-After`); 10 por minuto en las consultas de reportes (503, contadas en `ia_db`; al superar: `429 DEMASIADAS_CONSULTAS` con `Retry-After`).
- **Encabezados:** `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` y, en producción, HSTS.
- **Keycloak:** política de contraseñas «mínimo 8 caracteres, 1 mayúscula, 1 número, distinta del usuario»; protección contra fuerza bruta activada (bloqueo temporal tras 5 intentos); idioma por defecto **español** y único habilitado; tema propio `supervision` (colores y logo de `docs/diseno-visual.md`) para la pantalla de inicio de sesión, en `infra/keycloak/temas/supervision` (extiende el tema `keycloak.v2`).
- **Datos sensibles en registros:** nunca se registran tokens, contraseñas ni el cuerpo completo de las peticiones.

### IA segura (capa 5, 504)

- El modelo de lenguaje nunca escribe SQL ni filtros de base de datos ni ejecuta acciones: entrega una **receta** que el código valida contra el catálogo (503); el SQL lo arma el código con nombres del catálogo y valores enlazados (usuario `ia_reportes_lector`, transacción `READ ONLY`, 5 s). Todo dato externo (resultados de herramientas, filas de reportes, texto del usuario) llega al modelo solo por `como_dato` (delimitado con etiquetas y con `<` y `>` escapados).
- Toda salida del modelo se valida con esquema estricto (Pydantic, `extra="forbid"`) y listas permitidas antes de usarse, con cualquier proveedor (Ollama o Anthropic). Los agentes solo usan sus herramientas MCP de solo lectura y solo sugieren acciones de su lista; una persona decide (502).
- Los frontends muestran el texto de la IA como texto (prohibido `dangerouslySetInnerHTML` e `innerHTML`); el Excel y el CSV anteponen un apóstrofo a los textos que empiezan con `=`, `+`, `-` o `@`.
- No se registran tokens, la clave de la API del modelo (`IA_ANTHROPIC_API_KEY`) ni secretos; tampoco el texto completo de los mensajes al modelo.
- Las pruebas de `services/ia/tests/seguridad/` (entradas maliciosas con `ModeloSimulado` y prueba de arquitectura) corren con las pruebas normales del servicio de IA (`uv run pytest`).
- Librerías del modelo de lenguaje: `ollama` 0.6 y `anthropic` 2 (IA, solo en `src/ia/lenguaje/`). Exportación a Excel y CSV: SheetJS 0.20.3 desde `cdn.sheetjs.com` (mf-supervision). Detalle en `docs/stack.md`.

## Registros y salud

- Cada servicio expone `GET /salud` sin token, que responde `200 {"estado":"ok"}`; desde la 601 también el gateway (lo usan el `HEALTHCHECK` de su imagen y la prueba de humo). El gateway responde además la consulta GraphQL `{ salud }`, que tampoco exige token (el ERP la usa para saber si volvió la conexión, también sin sesión; 104).
- Encabezado `X-Request-Id`: el gateway lo crea si no viene y lo reenvía a cada servicio; todos los registros lo incluyen. En los eventos se usa `correlacionId`.
- Encabezado `X-Dispositivo-Id` (UUID del celular, generado por la app al instalarse): obligatorio en las llamadas de la app a Sincronización, salvo `GET /salud`; sin él, `400 DISPOSITIVO_REQUERIDO` (101).
- Registros en formato JSON en producción y texto legible en desarrollo.

## Avisos al celular (010)

- *Push* con **Firebase Cloud Messaging por temas**: la app de obra suscribe el celular a `obra-{obraId}-maestro` u `obra-{obraId}-almacenero` (según su rol) por cada obra asignada del paquete de datos (101), quita los de las obras que ya no tiene al actualizar los datos y todos al cerrar sesión. Ningún servicio guarda tokens de dispositivos.
- Los envía solo n8n, con la API v1 de FCM. Cada mensaje lleva `notification { title, body }` (Android lo muestra con la app cerrada) y `data { tipo, obraId }` (`tipo`: `STOCK_BAJO` o `DIARIO`) para abrir el stock o el diario de la obra al tocarlo.
- La cuenta de servicio de Firebase (en `infra/.env`) y el `google-services.json` de la app nunca van al repo. Sin Firebase configurado, los flujos de *push* no se publican y el resto funciona igual.

## Correo (201, 010 y 602)

- Los correos los envía solo n8n, por SMTP con las variables `SMTP_HOST`, `SMTP_PUERTO`, `SMTP_SEGURO`, `SMTP_USUARIO` y `SMTP_CLAVE`. Por defecto es Mailpit (desarrollo y ensayo local, sin TLS ni usuario). En la nube es el Gmail de la plataforma (587 con STARTTLS y contraseña de aplicación), con Mailpit desplegado como respaldo.
- El destinatario de los avisos al cliente es el correo de su usuario en Keycloak.

## Archivos (fotos y notas de remisión)

- Se guardan en **Amazon S3**: en desarrollo, un bucket propio (`supervision-dev-<sufijo>`, ver `docs/entorno-local.md`); en producción (602), el bucket privado `supervision-obras-<sufijo>` en `us-east-2`, con el prefijo `fotos/`; en la «producción local» (601), un S3 compatible (MinIO) con `OBRAS_S3_ENDPOINT` (rutas de estilo *path*; vacío = Amazon S3). El código es el mismo; solo cambian las variables.
- Las pruebas automáticas **no usan S3**: usan un doble del puerto de almacenamiento (por ejemplo `AlmacenArchivos` en memoria).
- La app sube el archivo con una URL firmada que entrega el servicio dueño; el servicio guarda solo la clave (`clave_archivo`).
- Fotos comprimidas en el celular a un máximo de 1600 px de lado y calidad JPEG 80 antes de subirse.
- En la capa 1 la app guarda la foto comprimida (1280 px, calidad 70) en el celular y la sube completa con la URL firmada que pide a Sincronización (que la obtiene del servicio dueño); si falla, la vuelve a subir completa (102).

## Contenedores y CI (601)

- **Una imagen por servicio:** Obras, Materiales, Finanzas, IA, Sincronización y el gateway tienen en su raíz un `Dockerfile` y un `.dockerignore` (`.git`, `node_modules`, `vendor`, `target`, `dist`, `.env*`, `*.log`, `coverage`, `.venv`, `android`, `datos`). Los frontends y la app no llevan imagen.
- **Dos etapas:** `construir` (dependencias y compilación) y `final` (solo lo necesario para correr); las herramientas de compilación no quedan en la imagen final. Las pruebas no corren dentro del `docker build`: corren antes, en el workflow.
- **Sin `root`:** usuario `10001` (Obras, Finanzas, IA) o `node` (Materiales, Sincronización, gateway). `EXPOSE` con el puerto de «Puertos en desarrollo», `HEALTHCHECK` contra `GET /salud` y la etiqueta OCI `org.opencontainers.image.source` con la URL del repositorio.
- **Una imagen, varios procesos:** IA corre `ia-api` (por defecto; aplica antes `alembic upgrade head`), `ia-worker` e `ia-carga-inicial`; Finanzas corre la API (por defecto: `php artisan migrate --force` y FrankenPHP sobre `public/` en `PORT`) y, cambiando el comando, `mensajeria:consumir`, `mensajeria:publicar` y `schedule:work`. Obras aplica sus migraciones de Flyway al iniciar.
- **Configuración solo por variables:** la imagen no lleva `.env`, claves, contraseñas ni direcciones de otros servicios; todo entra por variables al arrancar, con el valor de desarrollo en el `.env.example` de cada proyecto (lista en `docs/entorno-local.md`). El gateway y Sincronización exigen las direcciones de los servicios que llaman (sin valor por defecto en el código: si falta una, no arrancan). La imagen trae el modo producción: `SPRING_PROFILES_ACTIVE=prod` (Obras), `APP_ENV=production`, `APP_DEBUG=false` y `LOG_CHANNEL=stderr` (Finanzas), `NODE_ENV=production` (Node) e `IA_ENTORNO=produccion` (IA): registros en la salida estándar, en JSON, y errores sin trazas para el usuario.
- **TLS cuando se configura:** Obras con `OBRAS_DB_SSLMODE` y `OBRAS_RABBITMQ_SSL`, Finanzas con `DB_SSLMODE` y `RABBITMQ_SSL`, y Materiales, Sincronización, gateway e IA por la propia URL (`https://`, `amqps://`, `tls=true` o `mongodb+srv://`, `sslmode=` en PostgreSQL). Una CA adicional (solo la del ensayo local; en la nube los certificados son públicos) entra por variable sin cambiar la imagen: Java `JAVA_TOOL_OPTIONS` con un *truststore*, Node `NODE_EXTRA_CA_CERTS`, IA `IA_CA_EXTRA` y PHP un `.ini` con `curl.cainfo` y `openssl.cafile`.
- **CI:** un workflow `.github/workflows/ci.yml` por repositorio. En cada *pull request* hacia `develop` o `main`: job `prueba` (dependencias con caché, lint, tipos, pruebas y compilación) y, en los servicios, job `imagen` que la construye sin publicarla; si algo falla, el PR queda en rojo. En cada *push* a `main` (un *release*): cada servicio publica su imagen en GitHub Container Registry, `ghcr.io/jairovargasfigueroa/supervision-<repo>` (por ejemplo `supervision-ms-obras`, `supervision-gateway`), con las etiquetas `sha-<7 caracteres>` y `main` (caché de capas `type=gha`), y cada frontend guarda su carpeta compilada como artefacto del workflow. La app corre tipos y pruebas; infra valida los *compose*, el realm, las definiciones de RabbitMQ y los flujos de n8n. Los workflows no usan secretos de la aplicación: solo `GITHUB_TOKEN`.
- **Frontends como archivos estáticos:** se compilan **una vez** (`npm run build`) y se publican tal cual. Al publicar, un script escribe con las variables del entorno (todas sin `/` final), desde las plantillas `*.plantilla` de cada repo, `configuracion.json` del shell (`keycloakUrl`, `keycloakRealm`, `gatewayUrl`, `portalUrl`) y del portal (`keycloakUrl`, `keycloakRealm`, `obrasUrl`, `erpUrl`) y el `federation.manifest.json` del shell (dirección de cada remoto). El shell y el portal lo leen antes de iniciar; sin el archivo (desarrollo), usan los valores de desarrollo. Los microfrontends no escriben nada: leen `window.plataforma.configuracion`. Reglas del servidor de estáticos (Caddy en el ensayo; el *hosting* en la nube): SPA (si el archivo no existe, `index.html`), CORS en `remoteEntry.json` y los `.js` de los microfrontends para el origen del shell, y sin caché en `index.html`, `configuracion.json`, `federation.manifest.json`, `ngsw.json` y `ngsw-worker.js`.
- **Ensayo local («producción local», `infra/produccion-local/`):** tres grupos que hacen de las tres nubes, cada uno con su proyecto de Compose, su red y su Caddy (HTTPS con una CA local). Direcciones `https://<pieza>.<grupo>.localhost:<puerto>`; detalle en `docs/entorno-local.md` («Producción local»).

| Grupo (proyecto de Compose) | Puerto en la máquina | Piezas publicadas |
|---|---|---|
| `azure` (`supervision-azure`) | 8443 (HTTPS) | `keycloak`, `gateway`, `obras`, `finanzas`, `n8n`, `mailpit`, `rabbitmq` (panel), `erp`, `mf-obras`, `mf-materiales`, `mf-supervision`, `portal` |
| `azure` (RabbitMQ) | 5671 (AMQPS) | `rabbitmq.azure.localhost:5671`, para los servicios de los tres grupos |
| `google` (`supervision-google`) | 9443 (HTTPS) | `ia`, `materiales` |
| `aws` (`supervision-aws`) | 10443 (HTTPS) | `sincronizacion`, `s3` (MinIO) |

## Despliegue en la nube (602)

- Una máquina por nube con Docker Compose (`infra/nube/`). Nombres `https://<pieza>.supervision.workflow-tramites.site` (los mismos nombres de pieza que el ensayo local), con certificados de Let's Encrypt que saca Caddy.
- Desde internet solo se abren 80 y 443 en las tres máquinas, más 5671 (AMQPS) en la de Azure. El 22 se abre solo para la IP de Jairo y con clave. Bases, RabbitMQ 5672, n8n, SMTP y Ollama no tienen puerto público.
- **Secretos en producción:** todos en `infra/nube/.env` de la PC de Jairo (no se sube). Cada máquina recibe en `/opt/supervision/.env` (permisos `600`) solo las variables de su grupo. No hay secretos en el código, las imágenes ni los registros.
- Imágenes de GHCR con la etiqueta `main` del último *release* o, para volver atrás un servicio, su `sha-<7>` anterior.

## Git

- Un repositorio por proyecto más `supervision-docs`. Ramas, commits, *pull requests* y definición de terminado: `docs/flujo-trabajo.md`.
- Nunca se suben archivos `.env` ni contraseñas; cada proyecto tiene un `.env.example`.
