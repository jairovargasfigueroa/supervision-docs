# 010 · Notificaciones · tareas de `services/notificaciones`

Requisitos y diseño: `docs/specs/010-notificaciones/` de la carpeta que agrupa los proyectos. El proyecto todavía no existe: la primera tarea lo crea. Cuando exista, este archivo se copia a `services/notificaciones/docs/specs/010-notificaciones/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Crear el proyecto `services/notificaciones` con NestJS 12 (módulos ES, Vitest, oxlint, Prettier, como Materiales), puerto `8086`, `.env.example` (variables del diseño, `FIREBASE_CUENTA_SERVICIO_RUTA` vacía) y `.gitignore` con `.env`, `.env.*`, `!.env.example`, `secretos/` y `*-firebase-adminsdk-*.json`; crear el repositorio público con GitHub CLI (`& "C:\Program Files\GitHub CLI\gh.exe" repo create jairovargasfigueroa/supervision-ms-notificaciones --public --source . --remote origin --push`), rama `main`
- [ ] `CLAUDE.md` del proyecto y `docs/` (`servicio.md`, `datos.md`, `contratos.md`, `estructura.md`, `specs/README.md`) a partir del diseño de la 010
- [ ] Aplicar «Cambios a contratos y datos» del diseño a los documentos compartidos (`docs/contratos/`, `convenciones.md`, `reglas-negocio.md`, `stack.md`, `arquitectura.md`, `producto.md`, `diseno-visual.md`, `CLAUDE.md` general, `plan.md`) y a los `docs/` de los proyectos afectados
- [ ] Estructura Clean (`compartido`, `acceso-obra`, `usuarios`, `dispositivos`, `notificaciones`) y `GET /salud`
- [ ] Validación del token con `jose` (JWKS, emisor, audiencia `plataforma-api`), `X-Request-Id`, errores Problem Details y CORS con `CORS_ORIGENES`
- [ ] `usuario_conocido` con su interceptor (*upsert* con nombre y roles del token; no reescribe antes de 10 min salvo cambio de roles); pruebas
- [ ] Mensajería: conexión `amqplib`, cola `notificaciones` con sus 7 enlaces, inbox `mensaje_procesado` (TTL 30 días) en transacción, reintentos con `x-intentos` y `plataforma.fallidos`; consumidor de `ObraRegistrada` → `obra_acceso`; pruebas
- [ ] Dominio: `destinatarios.ts` (tabla del diseño, deduplicación, roles con `visto_en` de 90 días) y `redaccion.ts` (textos, montos es-BO, fechas y periodos en La Paz, campos opcionales); pruebas unitarias
- [ ] Colección `notificacion` (índices, único por `evento_id` + `usuario_id`, TTL 90 días) y caso de uso `NotificarEvento` con los manejadores de `PlanillaPresentada`, `PlanillaAprobada`, `PlanillaObservada`, `StockBajo`, `CobroVencido` y `ContratoRechazado`; pruebas con mensajes repetidos y obra desconocida
- [ ] REST de la bandeja: `GET /notificaciones` (paginado con `antesDe`, `soloNoLeidas`), `GET /notificaciones/no-leidas`, `POST /notificaciones/{id}/leida`, `POST /notificaciones/leidas`; Swagger en `/docs` (desarrollo); pruebas e2e
- [ ] Dispositivos: colección `dispositivo` (TTL 60 días), `POST /dispositivos` (*upsert* por token, reasignación de usuario, límite de 10) y `POST /dispositivos/baja` (204 siempre); pruebas e2e
- [ ] Instalar `firebase-admin` 14; `firebase.proveedor.ts` (sin ruta o archivo inválido → aviso una vez y `EnviadorPushDesactivado`; archivo válido → app de Firebase), `enviador-push.firebase.ts` (mensajes Android y web, `sendEach`, borrado de tokens inválidos, estados del *push*) y `reintentador-push.ts` (cada 60 s, 3 intentos, última hora); pruebas con FCM simulado
- [ ] Pruebas de la spec completas y README con cómo levantar el servicio y cómo activar Firebase (enlace a la sección del diseño)
