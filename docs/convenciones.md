# Convenciones

Lo que todos los proyectos hacen igual.

## Nombres

- Dominio en español: `obra`, `partida`, `planilla`, `cobro`, `material`, `movimiento`.
- Tablas, columnas y campos de MongoDB en `snake_case`.
- JSON de las APIs (REST y GraphQL) en `camelCase`. Cada servicio traduce entre ambos.
- Rutas REST en español, en plural y en minúsculas con guiones: `/obras/{id}/planillas`, `/cuentas-por-pagar`.
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
| Notificaciones (010) | 8086 |
| ERP: shell · mf-obras · mf-materiales · mf-supervision | 4200 · 4201 · 4202 · 4203 |
| Portal | 4300 |
| PostgreSQL · MongoDB · RabbitMQ (AMQP / panel) | 5433 · 27017 · 5672 / 15672 |

- PostgreSQL usa el 5433 (no el 5432) porque así está configurado Obras y es el puerto de la instalación local de Jairo. Una sola instancia con una base por servicio: `obras_db`, `finanzas_db` y, en la capa 4, `reportes_db`.
- En la máquina de Jairo, PostgreSQL (5433) y MongoDB (27017) ya están instalados como servicios de Windows; ahí Docker Compose levanta solo RabbitMQ y Keycloak. Quien no los tenga instalados levanta también los contenedores de las bases.

## Autenticación y permisos (Keycloak)

- Realm `supervision`. Keycloak emite tokens JWT (OIDC).
- Roles del realm: `admin`, `residente`, `gerente`, `maestro`, `almacenero`, `cliente`.
- Roles técnicos (se crean con su capa; ninguna persona los tiene): `automatizacion` (201, *service account* del cliente confidencial `n8n`; solo en las rutas de Finanzas que llama n8n) y `agente_ia` (501, *service account* del cliente confidencial `ia-agentes`; solo en `POST /mcp`, donde ve todas las obras como `gerente`; ningún endpoint REST lo acepta).
- Clientes públicos con PKCE: `erp` (shell y microfrontends), `portal`, `app-obra`.
- Cliente confidencial `gateway` con *service account* y los roles `view-users` y `view-realm` de `realm-management`: el gateway los usa para listar usuarios por rol (formularios de asignación) y resolver nombres. `view-realm` hace falta porque Keycloak 26 exige ver los roles del realm para responder `GET /roles/{rol}/users`; es de solo lectura. Ningún otro proyecto llama a la API de administración de Keycloak.
- Capa 5: cliente confidencial `ia-agentes` con *service account* para que el servicio de IA llame a las herramientas MCP.
- Todos los tokens llevan la audiencia `plataforma-api` (mapper de audiencia en Keycloak).
- Cada servicio valida firma (JWKS del realm), vencimiento, emisor y audiencia `plataforma-api`.
- Los roles van en el token (`realm_access.roles`); el id del usuario es el `sub` del token.
- Las reglas finas (qué obras puede ver el usuario) las valida cada servicio. Obras es dueño de las asignaciones; Materiales guarda una copia (`obra_acceso`) que recibe con el evento `ObraRegistrada`.
- Visibilidad de obras: `admin` y `gerente` ven todas; `residente`, `maestro` y `almacenero` ven las que tienen asignadas; `cliente` ve las suyas.
- **Usuario con varios roles** (por ejemplo `demo1`, residente y cliente): cada servicio aplica solo los roles de la aplicación desde la que se inició sesión, que viene en el campo `azp` del token. Con `azp = portal` cuentan solo las reglas de `cliente`; con `azp = erp` o `app-obra`, solo las de los roles internos. Las llamadas de servicio a servicio usan el `azp` de su propio cliente (`gateway`, `ia-agentes`, `n8n`).
- Respuestas de permiso:
  - `401 NO_AUTENTICADO`: no hay token válido.
  - `403 SIN_PERMISO`: el rol del usuario no permite esa acción (no figura en los roles del endpoint, o figura con una condición que no cumple, por ejemplo `residente` en una acción solo de `admin`). Se comprueba primero, en el guardia de cada endpoint.
  - `404` con el código de «no encontrado» del recurso (por ejemplo `404 OBRA_NO_ENCONTRADA`): el rol sí puede hacer la acción, pero el usuario no ve esa obra (no está asignado o no es su cliente). Se responde igual que si no existiera, para no revelar que existe; vale para lecturas y escrituras.
- La matriz completa de quién puede qué está en `docs/permisos.md`.
- Librerías: Spring Security OAuth2 Resource Server (Obras), `jose` (NestJS: gateway, Materiales), `firebase/php-jwt` con JWKS (Finanzas), keycloak-angular 22 + keycloak-js 26 (shell), react-oidc-context + oidc-client-ts (portal), `expo-auth-session` (app).

## Sesión dentro del ERP

- El shell es el único que inicia sesión. Publica la sesión en `window.plataforma.sesion` con:
  - `usuario`: `{ id, nombre, roles }`
  - `obtenerToken(): Promise<string>`: devuelve un token vigente (lo renueva si hace falta)
  - `cerrarSesion(): void`
- Cuando la sesión cambia, el shell emite el evento `plataforma:sesion` en `window`.
- El shell publica también `window.plataforma.configuracion` con `{ gatewayUrl }`, para que los microfrontends no repitan configuración.
- Los microfrontends (Angular y React) solo leen ese objeto; nunca hablan con Keycloak.
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
- `504 TIEMPO_AGOTADO`: el servicio llamó a otro servicio (o a un componente externo, como Ollama) y no recibió respuesta en su tiempo máximo. Es el mismo código y estado en todos los servicios. El error de una ejecución de agente por pasar su límite de tiempo es otro: `EJECUCION_TIEMPO_AGOTADO` (502).
- El texto que ve el usuario por cada `codigo` está en `docs/mensajes.md`; un código que el frontend no conoce se muestra con el mensaje genérico de su estado HTTP.

## Errores GraphQL (gateway)

- Cada error va en `errors[]` con `extensions.codigo` (el mismo `codigo` del servicio) y `extensions.servicio`.
- Si un servicio no responde, solo los campos que dependen de él vuelven en `null` con `extensions.codigo = "SERVICIO_NO_DISPONIBLE"`; el resto de la respuesta llega.
- Tiempo máximo por llamada del gateway a un servicio: **3 segundos**. Las consultas se reintentan una vez; las mutaciones no se reintentan.

## Idempotencia

- Toda operación que crea algo desde el celular o desde un evento usa un identificador de operación (el UUID del registro).
- El servicio guarda los identificadores ya procesados y, si llega uno repetido, devuelve `200` con el registro existente en lugar de crearlo otra vez.

## Eventos y comandos (RabbitMQ)

- Un *exchange* tipo `topic` llamado `plataforma`.
- Clave de enrutamiento: `evento.<origen>.<Tipo>` para eventos (algo que pasó) y `comando.<destino>.<Tipo>` para órdenes de la saga. Ejemplos: `evento.obras.ObraRegistrada`, `comando.finanzas.ReservarSaldo`.
- Cada servicio tiene su propia cola durable (`obras`, `materiales`, `finanzas`, `ia`) y se suscribe a las claves que le interesan.
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
- Mensajes que fallan 3 veces van a la cola `plataforma.fallidos` para revisión.
- Librerías: Spring AMQP (Obras), `amqplib` / `@nestjs/microservices` (Materiales), `php-amqplib` 3 (Finanzas).

## Seguridad

- **CORS:** cada servicio acepta solo los orígenes de su variable `CORS_ORIGENES` (ver `docs/entorno-local.md`): el gateway, los del ERP; Obras, el portal; Materiales, Finanzas e IA, ninguno (los llama el gateway o la app, que no usa CORS). Nunca `*` con credenciales.
- **Tamaños máximos:** cuerpo JSON 1 MB; fotos 5 MB (la app las comprime antes, ver «Archivos»); las URL firmadas de subida aceptan solo `image/jpeg` y hasta 5 MB.
- **GraphQL:** profundidad máxima 8 y complejidad máxima 1000 por consulta; introspección y Apollo Sandbox solo en desarrollo.
- **Límite de peticiones:** 120 por minuto por usuario en el gateway y en los endpoints del portal en Obras; 10 por minuto en la consulta por voz (503). Al superar: `429 DEMASIADAS_PETICIONES` con `Retry-After`.
- **Encabezados:** `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer` y, en producción, HSTS.
- **Keycloak:** política de contraseñas «mínimo 8 caracteres, 1 mayúscula, 1 número, distinta del usuario»; protección contra fuerza bruta activada (bloqueo temporal tras 5 intentos); idioma por defecto **español** y único habilitado; tema propio `supervision` (colores y logo de `docs/diseno-visual.md`) para la pantalla de inicio de sesión, en `infra/keycloak/temas/supervision` (extiende el tema `keycloak.v2`).
- **Datos sensibles en registros:** nunca se registran tokens, contraseñas ni el cuerpo completo de las peticiones.

## Registros y salud

- Cada servicio expone `GET /salud` sin token, que responde `200 {"estado":"ok"}`. El gateway responde además la consulta GraphQL `{ salud }`, que tampoco exige token (el ERP la usa para saber si volvió la conexión, también sin sesión; 104).
- Encabezado `X-Request-Id`: el gateway lo crea si no viene y lo reenvía a cada servicio; todos los registros lo incluyen. En los eventos se usa `correlacionId`.
- Registros en formato JSON en producción y texto legible en desarrollo.

## Archivos (fotos y notas de remisión)

- Se guardan en **Amazon S3**: en desarrollo, un bucket propio (`supervision-dev-<sufijo>`, ver `docs/entorno-local.md`); en producción, el bucket de la capa 6. El código es el mismo; solo cambian las variables.
- Las pruebas automáticas **no usan S3**: usan un doble del puerto de almacenamiento (por ejemplo `AlmacenArchivos` en memoria).
- La app sube el archivo con una URL firmada que entrega el servicio dueño; el servicio guarda solo la clave (`clave_archivo`).
- Fotos comprimidas en el celular a un máximo de 1600 px de lado y calidad JPEG 80 antes de subirse.

## Git

- Un repositorio por proyecto más `supervision-docs`. Ramas, commits, *pull requests* y definición de terminado: `docs/flujo-trabajo.md`.
- Nunca se suben archivos `.env` ni contraseñas; cada proyecto tiene un `.env.example`.
