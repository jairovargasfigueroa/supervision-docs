# Entorno local

Lo que corre en Docker para desarrollar, con versiones fijas (revisadas el 28 de octubre de 2026 en Docker Hub y Quay). Vive en el repo `supervision-infra` (se crea en la tarea 1.1).

## Servicios de Docker Compose (`infra/docker-compose.yml`)

| Servicio | Imagen | Puertos | Notas |
|---|---|---|---|
| `postgres` | `postgres:17` | 5433 → 5432 | Bases `obras_db`, `finanzas_db` (y `reportes_db` en la capa 4), creadas por `infra/postgres/init.sql`. **Perfil `bases`** (opcional). |
| `mongo` | `mongo:8.0` | 27017 | Arranca como *replica set* de un nodo (`--replSet rs0`) y un servicio `mongo-init` ejecuta `rs.initiate()`. Bases `materiales_db` (y `notificaciones_db`, `ia_db` en sus funcionalidades). **Perfil `bases`** (opcional). |
| `rabbitmq` | `rabbitmq:4.4-management` | 5672, 15672 (panel) | Importa `infra/rabbitmq/definiciones.json`: exchange `plataforma` (topic), colas `obras`, `materiales`, `finanzas`, `notificaciones`, `ia`, `plataforma.fallidos` y sus enlaces. Usuario por servicio. Las colas `ia` (con sus 6 enlaces de la 401) y `notificaciones` (010) se declaran desde la fase 1, aunque esos servicios todavía no existan, para que ningún evento se pierda. |
| `keycloak` | `quay.io/keycloak/keycloak:26.8.1` | 8080 | `start-dev --import-realm` con `infra/keycloak/realm-supervision.json` y el tema `infra/keycloak/temas/supervision`. Usa su propia base H2 en desarrollo. |
| `almacen` (S3) | `rustfs/rustfs:1.0.4` | 9000 (API S3), 9001 (consola) | Reemplaza a MinIO, que dejó de publicar imágenes. Un servicio `almacen-init` crea el bucket `supervision` y su regla CORS. |
| `mailpit` | `axllent/mailpit:v1.32` | 1025 (SMTP), 8025 (web) | Solo desde la 201. Perfil `automatizacion`. |
| `dynamodb` | `amazon/dynamodb-local:3.3.2` | 8000 | Solo desde la 101. Perfil `sin-senal`. |
| `n8n` | según la spec 201 | 5678 | Solo desde la 201. Perfil `automatizacion`. |

- Todos con *healthcheck* y volúmenes con nombre (`datos-postgres`, `datos-mongo`, `datos-rabbitmq`, `datos-almacen`).
- **Perfiles:** sin perfil se levantan RabbitMQ, Keycloak y el almacén S3. `--profile bases` suma PostgreSQL y MongoDB (para quien no los tiene instalados). Las capas suman sus perfiles.
- En la máquina de Jairo PostgreSQL (5433) y MongoDB (27017) ya están instalados: no usar el perfil `bases`. **MongoDB local debe configurarse como *replica set*** (tarea 1.3: `replication.replSetName: rs0` en `mongod.cfg` y `rs.initiate()`).
- Contraseñas de desarrollo en `infra/.env` (copiado de `infra/.env.example`); nunca en el repo.

## Scripts (`infra/scripts/`, en PowerShell y Bash)

| Script | Qué hace |
|---|---|
| `levantar.ps1` / `.sh` | `docker compose up -d` con los perfiles indicados y espera a que todo esté sano |
| `estado.ps1` / `.sh` | Muestra qué contenedor está sano y llama `GET /salud` de cada servicio que esté corriendo |
| `bajar.ps1` / `.sh` | `docker compose down` (conserva datos) |
| `reiniciar-datos.ps1` / `.sh` | Borra volúmenes y vuelve a levantar todo vacío (pide confirmación) |
| `semilla.ps1` / `.sh` | Carga los datos de prueba (011) |

## Orden para levantar todo

1. `infra`: `./scripts/levantar.ps1`
2. Servicios (cada uno en su terminal): Obras `./mvnw spring-boot:run` → Materiales `npm run start:dev` → Finanzas `php artisan serve --port=8083` y `php artisan mensajeria:consumir` → (capas: Sincronización, IA, Notificaciones).
3. Gateway: `npm run start:dev`.
4. Frontends: mf-obras `npm start`, mf-materiales `npm start`, mf-supervision `npm start`, shell `npm start`; portal `npm run dev`.
5. App: `npx expo start`.

## Variables de entorno por proyecto (`.env.example` de cada repo)

| Proyecto | Variables |
|---|---|
| Obras (`.env.properties`) | `OBRAS_PORT=8081`, `OBRAS_DB_HOST=localhost`, `OBRAS_DB_PORT=5433`, `OBRAS_DB_NAME=obras_db`, `OBRAS_DB_USER`, `OBRAS_DB_PASSWORD`, `OBRAS_KEYCLOAK_ISSUER=http://localhost:8080/realms/supervision`, `OBRAS_RABBITMQ_HOST=localhost`, `OBRAS_RABBITMQ_PORT=5672`, `OBRAS_RABBITMQ_USER`, `OBRAS_RABBITMQ_PASSWORD`, `OBRAS_S3_ENDPOINT=http://localhost:9000`, `OBRAS_S3_ACCESS_KEY`, `OBRAS_S3_SECRET_KEY`, `OBRAS_S3_BUCKET=supervision`, `OBRAS_CORS_ORIGENES=http://localhost:4300` |
| Materiales (`.env`) | `PORT=8082`, `MONGODB_URI=mongodb://localhost:27017/materiales_db?replicaSet=rs0`, `KEYCLOAK_URL=http://localhost:8080`, `KEYCLOAK_REALM=supervision`, `AUDIENCIA=plataforma-api`, `RABBITMQ_URL=amqp://usuario:clave@localhost:5672`, `MATERIALES_S3_*` (desde la 102), `CORS_ORIGENES=` (vacío: solo la llaman servicios y la app) |
| Finanzas (`.env`) | Las de Laravel con `DB_CONNECTION=pgsql`, `DB_HOST=localhost`, `DB_PORT=5433`, `DB_DATABASE=finanzas_db`, `DB_USERNAME`, `DB_PASSWORD`, `APP_TIMEZONE=America/La_Paz`, `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `KEYCLOAK_ISSUER=http://localhost:8080/realms/supervision`, `KEYCLOAK_AUDIENCIA=plataforma-api` |
| Gateway (`.env`) | `PORT=4000`, `OBRAS_URL=http://localhost:8081`, `MATERIALES_URL=http://localhost:8082`, `FINANZAS_URL=http://localhost:8083`, `IA_URL=http://localhost:8085` (capa 4), `NOTIFICACIONES_URL=http://localhost:8086` (010), `KEYCLOAK_URL=http://localhost:8080`, `KEYCLOAK_REALM=supervision`, `KEYCLOAK_GATEWAY_CLIENT_ID=gateway`, `KEYCLOAK_GATEWAY_CLIENT_SECRET`, `CORS_ORIGENES=http://localhost:4200,http://localhost:4201,http://localhost:4202,http://localhost:4203` |
| Shell y mf-obras | `src/environments/environment.ts` (no secretos): `keycloakUrl`, `realm`, `clientId: 'erp'`, `gatewayUrl: 'http://localhost:4000/graphql'`, `portalUrl: 'http://localhost:4300'` |
| mf-materiales y mf-supervision | `src/nucleo/configuracion.ts`: `gatewayUrl` (se lee de `window.plataforma.configuracion` que publica el shell, con valor por defecto para desarrollo) |
| Portal (`.env`) | `VITE_KEYCLOAK_URL=http://localhost:8080`, `VITE_KEYCLOAK_REALM=supervision`, `VITE_KEYCLOAK_CLIENT_ID=portal`, `VITE_OBRAS_URL=http://localhost:8081` |
| App (`app.json` → `extra`) | `keycloakUrl`, `realm`, `clientId: 'app-obra'`, `obrasUrl`, `materialesUrl` (en el celular, la IP de la computadora en la red local, no `localhost`) |

Los secretos de desarrollo (contraseñas de bases y RabbitMQ, secreto del cliente `gateway`) se fijan una vez en `infra/.env` y se copian a los `.env` de cada proyecto. El realm de desarrollo trae el secreto del cliente `gateway` fijo **solo para desarrollo**.
