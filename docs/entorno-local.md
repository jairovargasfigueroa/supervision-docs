# Entorno local

Lo que corre en Docker para desarrollar, con versiones fijas (revisadas el 28 de octubre de 2026 en Docker Hub y Quay). Vive en el repo `supervision-infra` (carpeta `infra/`).

## Servicios de Docker Compose (`infra/docker-compose.yml`)

| Servicio | Imagen | Puertos | Notas |
|---|---|---|---|
| `postgres` | `postgres:17` | 5433 → 5432 | Bases `obras_db` y `finanzas_db` (`infra/postgres/init.sql`) y, desde la 401, el usuario `ia` y la base `reportes_db`, dueña de ese usuario (`infra/postgres/init-reportes.sh`, con `POSTGRES_IA_CLAVE`). Los scripts corren solo con el volumen vacío. **Perfil `bases`** (opcional). |
| `mongo` | `mongo:8.0` | 27017 | Arranca como *replica set* de un nodo (`--replSet rs0`) y un servicio `mongo-init` ejecuta `rs.initiate()`. Bases `materiales_db`, `ia_db` (402, 403; aparece cuando `ia-api` o `ia-worker` aseguran sus índices al arrancar) y, en la 010, `notificaciones_db`. **Perfil `bases`** (opcional). |
| `rabbitmq` | `rabbitmq:4.4-management` | 5672, 15672 (panel) | `rabbitmq-init` le importa `infra/rabbitmq/definiciones.json`: exchange `plataforma` (topic), colas `obras`, `materiales`, `finanzas`, `notificaciones`, `ia`, `plataforma.fallidos` y sus enlaces. Usuario por servicio (los crea `rabbitmq-init`). Las colas `ia` (con sus 6 enlaces de la 401) y `notificaciones` (010) se declaran desde la fase 1, aunque esos servicios todavía no existan, para que ningún evento se pierda. |
| `keycloak` | `quay.io/keycloak/keycloak:26.8.1` | 8080 | `start-dev --import-realm` con `infra/keycloak/realm-supervision.json` y el tema `infra/keycloak/temas/supervision`. Usa su propia base H2 en desarrollo. Sin volumen: al recrear el contenedor el realm se vuelve a importar. |
| `rabbitmq-init` | `curlimages/curl:8.17.0` | — | Corre una vez al levantar, por la API del panel: importa `infra/rabbitmq/definiciones.json` y crea un usuario por servicio (`obras`, `materiales`, `finanzas`, `ia`, `notificaciones`) con las contraseñas de `infra/.env`; termina. (Si RabbitMQ cargara las definiciones al arrancar, no crearía el administrador de `.env`.) |
| `s3-cli` | `amazon/aws-cli:2.38.0` | — | Solo para la semilla (011). Perfil `herramientas`: sube y borra las fotos de prueba en el bucket S3 de desarrollo (`S3_BUCKET`, que debe empezar con `supervision-dev-`) con las credenciales del usuario IAM de desarrollo de `infra/.env`. |
| `ia-api` | `supervision-ia:dev` (se construye desde `services/ia`, carpeta `IA_DIR`) | 8085 | API del servicio de IA (401). Aplica `alembic upgrade head` de `reportes_db` antes de atender. **Perfil `ia`** (opcional: el servicio también se corre con `uv`). |
| `ia-worker` | `supervision-ia:dev` | — | Consumidor de la cola `ia` y tareas programadas (401–403). Espera a que `ia-api` esté sano (base migrada). **Perfil `ia`**. |
| `ia-carga-inicial` | `supervision-ia:dev` | — | Carga inicial de `reportes_db` por REST (401): corre una vez y termina (código 0 si cargó todo). Es el único proceso que recibe `IA_REPORTES_CLIENT_SECRET`. Llega a Obras, Materiales y Finanzas por `host.docker.internal`. **Perfil `ia-carga`**: `docker compose --profile ia-carga run --rm ia-carga-inicial`. |
| `psql-cli` | `postgres:17` | — | Herramienta de una sola vez para vaciar `reportes_db` en `recargar` (usuario `ia`, `host.docker.internal:5433`). **Perfil `herramientas`**. |
| `mailpit` | `axllent/mailpit:v1.32` | 1025 (SMTP), 8025 (web) | Solo desde la 201. Perfil `automatizacion`. |
| `dynamodb` | `amazon/dynamodb-local:3.3.2` | 8000 | DynamoDB Local para Sincronización (desde la 101). Sin perfil: se levanta siempre. Con `-sharedDb` (una sola base para cualquier credencial y región) y el volumen `datos-dynamodb`. Las tablas (`operacion_procesada`, `estado_dispositivo`) las crea Sincronización al iniciar con `DYNAMODB_CREAR_TABLAS=true`. |
| `n8n` | según la spec 201 | 5678 | Solo desde la 201. Perfil `automatizacion`. |

- Todos con *healthcheck* y volúmenes con nombre (`datos-postgres`, `datos-mongo`, `datos-rabbitmq`, `datos-dynamodb`).
- Los scripts esperan a que cada servicio esté sano y a que los de una sola vez (`rabbitmq-init`, `mongo-init`) terminen bien; no usan `docker compose up --wait`, que toma como fallo a los que terminan.
- **Perfiles:** sin perfil se levantan RabbitMQ, Keycloak y DynamoDB Local. `--profile bases` suma PostgreSQL y MongoDB (para quien no los tiene instalados). Las capas suman sus perfiles: `ia` (`ia-api` e `ia-worker`, 401) e `ia-carga` (`ia-carga-inicial`, 401); `herramientas` tiene `s3-cli` y `psql-cli`.
- Los contenedores de IA no usan el `.env` de `services/ia`: sus variables están en `infra/docker-compose.yml` (`x-ia-entorno`) con las claves de `infra/.env`, y buscan PostgreSQL (5433) y MongoDB en la máquina (`host.docker.internal`), así sirven la instalación local y el perfil `bases`. No levantes a la vez el servicio de IA con `uv` y en contenedor (los dos usan el 8085 y la cola `ia`).
- En la máquina de Jairo PostgreSQL (5433) y MongoDB (27017) ya están instalados: no usar el perfil `bases`. **MongoDB local debe configurarse como *replica set*** (tarea 1.3): una vez, en PowerShell como administrador, `infra/scripts/mongo-local-replica.ps1` (agrega `replication.replSetName: rs0` a `mongod.cfg`, reinicia el servicio y ejecuta `rs.initiate()`).
- Contraseñas de desarrollo en `infra/.env` (copiado de `infra/.env.example`); nunca en el repo. Desde la 401: `POSTGRES_IA_CLAVE` (usuario `ia` de `reportes_db`), `RABBITMQ_IA_CLAVE` (usuario `ia` de RabbitMQ), `IA_REPORTES_CLIENT_SECRET` (secreto del cliente `ia-reportes`, que el realm toma de aquí; el de desarrollo viene en `.env.example`) e `IA_DIR` (carpeta de `services/ia`, por defecto `../services/ia`).
- **Base de reportes en la instalación local de PostgreSQL** (401): el contenedor la crea solo, pero en un PostgreSQL instalado (el 5433 de Jairo) se crea una vez a mano, como `postgres`, con la misma `POSTGRES_IA_CLAVE` de `infra/.env`: `CREATE ROLE ia LOGIN PASSWORD '…';` y `CREATE DATABASE reportes_db OWNER ia;`. Lo mismo si el volumen del contenedor es de antes de la 401 (`docker compose exec postgres psql -U postgres`). Las tablas las crea el servicio con `alembic upgrade head`.

## Archivos en desarrollo: S3 real

Las fotos y notas de remisión van a **Amazon S3 también en desarrollo** (no hay imitador en Docker). Lo crea Jairo una vez en la consola de AWS (tarea 1.5):

1. Bucket privado `supervision-dev-<sufijo>` en `sa-east-1` (São Paulo), con «Bloquear todo el acceso público» activado.
2. Regla CORS del bucket: métodos `GET` y `PUT`, orígenes `http://localhost:4200`, `http://localhost:4201` y `http://localhost:4300`, encabezados `*`.
3. Regla de ciclo de vida del prefijo `temporal/`: ya no hace falta (la 102 se simplificó el 30/10/2026: la foto se sube completa a `fotos/` con la URL firmada de Obras y no usa `temporal/`).
4. Usuario IAM `supervision-dev` con una política que solo permite `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` y `s3:ListBucket` sobre ese bucket; sus claves van en los `.env` (nunca en el repo).
5. Alerta de presupuesto de AWS (por ejemplo 5 USD) para enterarse de cualquier gasto.

Con pocas fotos el costo es mínimo, pero depende de la cuenta (capa gratuita o créditos): revísalo en la consola. Las **pruebas automáticas no usan S3**: usan un doble del almacenamiento en memoria. La app en el celular sube a S3 por internet con la URL firmada, así que no necesita estar en la misma red que la computadora para las fotos.

## Scripts (`infra/scripts/`, en PowerShell y Bash)

| Script | Qué hace |
|---|---|
| `levantar.ps1` / `.sh` | `docker compose up -d` con los perfiles indicados y espera a que todo esté sano |
| `estado.ps1` / `.sh` | Muestra qué contenedor está sano y llama `GET /salud` de cada servicio que esté corriendo |
| `bajar.ps1` / `.sh` | `docker compose down` (conserva datos) |
| `reiniciar-datos.ps1` / `.sh` | Borra volúmenes y vuelve a levantar todo vacío (pide confirmación) |

Datos de prueba (011), en `infra/semilla/`: `semilla.ps1` / `.sh` cargan los datos de `docs/datos-prueba.md` sin duplicar y `recargar.ps1` / `.sh` (con `-Si` / `--si`) vacían bases (también `reportes_db`, 401), colas y fotos y vuelven a cargar; después se corre otra vez la carga inicial de la base de reportes. Detalle en el README de infra.

## Orden para levantar todo

1. `infra`: `./scripts/levantar.ps1` (para el servicio de IA en contenedor, además `docker compose --profile ia up -d --build`)
2. Servicios (cada uno en su terminal): Obras `./mvnw spring-boot:run` → Materiales `npm run start:dev` → Finanzas `php artisan serve --port=8083`, `php artisan mensajeria:consumir` y `php artisan mensajeria:publicar` (sin este último sus eventos y respuestas de la saga no salen; `php artisan schedule:work` para la tarea diaria de cobros vencidos) → Sincronización (capa 1, puerto 8084; necesita DynamoDB Local, Obras y Materiales) `npm run start:dev` → IA (capa 4, puerto 8085), en `services/ia`: `uv run alembic upgrade head` (la primera vez y con cada migración nueva), `uv run ia-api` y `uv run ia-worker` (o el perfil `ia` de infra) → (Notificaciones, en la 010).
   - **Carga inicial de la base de reportes (401):** después de levantar IA por primera vez y después de cada `recargar` de los datos de prueba, con Obras, Materiales y Finanzas levantados: `uv run ia-carga-inicial` en `services/ia` (o `docker compose --profile ia-carga run --rm ia-carga-inicial` en `infra`). Termina con código 0 si cargó todo; se puede repetir sin duplicar.
3. Gateway: `npm run start:dev`.
4. Frontends: mf-obras `npm start`, mf-materiales `npm start`, mf-supervision `npm start`, shell `npm start`; portal `npm run dev`.
5. App: celular Android con depuración USB (o inalámbrica) → `infra/scripts/celular.ps1` (hace `adb reverse` de 8080, 8081, 8082, 8084 y 8090) → en `mobile/app-obra`, `npm start` (Metro en el **8090**, porque el 8081 es de Obras) y abrir en Expo Go.

## Variables de entorno por proyecto (`.env.example` de cada repo)

| Proyecto | Variables |
|---|---|
| Obras (`.env.properties`) | `OBRAS_PORT=8081`, `OBRAS_DB_HOST=localhost`, `OBRAS_DB_PORT=5433`, `OBRAS_DB_NAME=obras_db`, `OBRAS_DB_USER`, `OBRAS_DB_PASSWORD`, `OBRAS_KEYCLOAK_ISSUER=http://localhost:8080/realms/supervision`, `OBRAS_RABBITMQ_HOST=localhost`, `OBRAS_RABBITMQ_PORT=5672`, `OBRAS_RABBITMQ_USER`, `OBRAS_RABBITMQ_PASSWORD`, `OBRAS_S3_REGION=sa-east-1`, `OBRAS_S3_ACCESS_KEY`, `OBRAS_S3_SECRET_KEY`, `OBRAS_S3_BUCKET=supervision-dev-<sufijo>`, `OBRAS_CORS_ORIGENES=http://localhost:4300` |
| Materiales (`.env`) | `PORT=8082`, `MONGODB_URI=mongodb://localhost:27017/materiales_db?replicaSet=rs0`, `KEYCLOAK_URL=http://localhost:8080`, `KEYCLOAK_REALM=supervision`, `AUDIENCIA=plataforma-api`, `RABBITMQ_URL=amqp://usuario:clave@localhost:5672`, `CORS_ORIGENES=` (vacío: solo la llaman servicios y la app) |
| Finanzas (`.env`) | Las de Laravel con `DB_CONNECTION=pgsql`, `DB_HOST=localhost`, `DB_PORT=5433`, `DB_DATABASE=finanzas_db`, `DB_USERNAME`, `DB_PASSWORD`, `APP_TIMEZONE=America/La_Paz`, `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `KEYCLOAK_ISSUER=http://localhost:8080/realms/supervision`, `KEYCLOAK_AUDIENCIA=plataforma-api` |
| Sincronización (`.env`, desde la 101) | `PORT=8084`, `KEYCLOAK_URL=http://localhost:8080`, `KEYCLOAK_REALM=supervision`, `AUDIENCIA=plataforma-api`, `OBRAS_URL=http://localhost:8081`, `MATERIALES_URL=http://localhost:8082`, `DYNAMODB_ENDPOINT=http://localhost:8000` (vacío en AWS), `AWS_REGION=sa-east-1`, `AWS_ACCESS_KEY_ID=local` y `AWS_SECRET_ACCESS_KEY=local` (valores de prueba: DynamoDB Local acepta cualquiera), `DYNAMODB_CREAR_TABLAS=true` (solo en desarrollo), `TIEMPO_MAXIMO_LLAMADA_MS=5000`, `TIEMPO_MAXIMO_LOTE_MS=20000` |
| IA (`.env`, desde la 401) | `IA_ENTORNO=desarrollo`, `IA_PUERTO=8085`, `IA_REPORTES_DB_URL=postgresql+psycopg://ia:<POSTGRES_IA_CLAVE>@localhost:5433/reportes_db`, `IA_MONGO_URL=mongodb://localhost:27017`, `IA_MONGO_DB=ia_db`, `IA_RABBITMQ_URL=amqp://ia:<RABBITMQ_IA_CLAVE>@localhost:5672/`, `IA_KEYCLOAK_ISSUER=http://localhost:8080/realms/supervision`, `IA_AUDIENCIA=plataforma-api`, `IA_ZONA_HORARIA=America/La_Paz`, `IA_MODELOS_DIR=modelos`, `IA_MODELO_RIESGO_VERSION=` y `IA_MODELO_ATIPICOS_VERSION=` (vacías: la versión de `actual.txt`), y solo para la carga inicial `IA_OBRAS_URL=http://localhost:8081`, `IA_MATERIALES_URL=http://localhost:8082`, `IA_FINANZAS_URL=http://localhost:8083`, `IA_REPORTES_CLIENT_ID=ia-reportes`, `IA_REPORTES_CLIENT_SECRET` (el de `infra/.env`) |
| Gateway (`.env`) | `PORT=4000`, `OBRAS_URL=http://localhost:8081`, `MATERIALES_URL=http://localhost:8082`, `FINANZAS_URL=http://localhost:8083`, `IA_URL=http://localhost:8085` (capa 4), `NOTIFICACIONES_URL=http://localhost:8086` (010), `KEYCLOAK_URL=http://localhost:8080`, `KEYCLOAK_REALM=supervision`, `KEYCLOAK_GATEWAY_CLIENT_ID=gateway`, `KEYCLOAK_GATEWAY_CLIENT_SECRET`, `CORS_ORIGENES=http://localhost:4200,http://localhost:4201,http://localhost:4202,http://localhost:4203` |
| Shell y mf-obras | `src/environments/environment.ts` (no secretos): `keycloakUrl`, `realm`, `clientId: 'erp'`, `gatewayUrl: 'http://localhost:4000/graphql'`, `portalUrl: 'http://localhost:4300'` |
| mf-materiales y mf-supervision | `src/nucleo/configuracion.ts`: `gatewayUrl` (se lee de `window.plataforma.configuracion` que publica el shell, con valor por defecto para desarrollo) |
| Portal (`.env`) | `VITE_KEYCLOAK_URL=http://localhost:8080`, `VITE_KEYCLOAK_REALM=supervision`, `VITE_KEYCLOAK_CLIENT_ID=portal`, `VITE_OBRAS_URL=http://localhost:8081` |
| App (`app.json` → `extra`) | `keycloakUrl`, `realm`, `clientId: 'app-obra'`, `obrasUrl`, `materialesUrl`, `sincronizacionUrl` (desde la 101): todas con `localhost` (`http://localhost:8080`, `:8081`, `:8082`, `:8084`). El celular llega a la computadora con `adb reverse` (`infra/scripts/celular.ps1`), así el token sale con el mismo emisor `http://localhost:8080/realms/supervision` que validan los servicios; con la IP de la red local, Keycloak pondría otro emisor y los servicios rechazarían el token. |

Los secretos de desarrollo (contraseñas de bases y RabbitMQ, secretos de los clientes `gateway` e `ia-reportes`) se fijan una vez en `infra/.env` y se copian a los `.env` de cada proyecto. El realm de desarrollo trae el secreto del cliente `gateway` fijo **solo para desarrollo**: `gateway-secreto-solo-desarrollo` (va en `KEYCLOAK_GATEWAY_CLIENT_SECRET` del gateway).
