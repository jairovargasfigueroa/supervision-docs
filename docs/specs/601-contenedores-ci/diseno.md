# 601 · Diseño

> **Ajuste pendiente por la evaluación de la capa 1 (30/10/2026):** la 102 se simplificó. La app sube la foto completa y directo a S3 con la URL firmada de Obras (pedida a Sincronización), y ya no existen la subida por partes (`/subidas`), la tabla `subida_archivo`, el prefijo `temporal/subidas/`, el acceso de Sincronización a S3 ni la foto de la nota de remisión (`notas-remision/`, variables `MATERIALES_S3_*`). Al evaluar esta capa, quitar esas menciones de este documento.

## Reglas comunes de los Dockerfile

- Imágenes base oficiales, con versión fija al menos hasta *major.minor* (verificadas en Docker Hub el 28/10/2026): `eclipse-temurin:21-jre-alpine`, `node:24-alpine`, `python:3.12-slim`, `dunglas/frankenphp:1-php8.3`, `nginxinc/nginx-unprivileged:1.29-alpine`.
- Varias etapas: `construir` (dependencias y compilación) y `final` (solo lo necesario para correr).
- Usuario sin privilegios (`USER` numérico, por ejemplo `10001`, o el usuario que trae la imagen: `node`, `nginx`).
- `EXPOSE` con el puerto de `convenciones.md`; el proceso lee el puerto de su variable.
- `HEALTHCHECK` contra `GET /salud` (lo usa Docker Compose; en la nube se configuran las sondas propias de cada servicio).
- Etiqueta OCI `org.opencontainers.image.source` con la URL del repositorio (GHCR la usa para enlazar el paquete).
- `.dockerignore`: `.git`, `node_modules`, `vendor`, `target`, `dist`, `.env*`, `*.log`, `coverage`, `.venv`.
- Las pruebas **no** corren dentro del `docker build`: corren antes, en el job `prueba` del workflow.

## Imagen por proyecto

| Proyecto | Etapa de construcción | Imagen final y comando | Puerto | Registro (602) |
|---|---|---|---|---|
| services/obras | `eclipse-temurin:21-jdk-alpine`, `./mvnw -B package -DskipTests` | `eclipse-temurin:21-jre-alpine`, `java -XX:MaxRAMPercentage=75 -jar app.jar` | 8081 (`OBRAS_PORT`) | GHCR |
| services/materiales | `node:24-alpine`, `npm ci`, `npm run build`, `npm prune --omit=dev` | `node:24-alpine`, `node dist/main.js`, usuario `node` | 8082 (`PORT`) | Artifact Registry (Google) |
| services/finanzas | `composer:2` para `composer install --no-dev --optimize-autoloader` | `dunglas/frankenphp:1-php8.3` con extensiones `pdo_pgsql`, `bcmath`, `sockets`, `opcache`; `frankenphp php-server` sobre `public/` **(decisión del equipo:** FrankenPHP evita armar nginx + php-fpm en dos procesos) | 8083 | GHCR |
| services/ia | `python:3.12-slim` con `uv` (`uv sync --frozen --no-dev` a partir de `pyproject.toml` y `uv.lock`, entorno en `/app/.venv`), como pide la 401 | `python:3.12-slim` con el entorno copiado. **Una imagen, dos comandos** (401): `ia-api` (FastAPI con Uvicorn en `IA_PUERTO`, 8085) e `ia-worker` (consumidor de RabbitMQ y tareas programadas, incluidos los agentes de la 502). Incluye `modelos/` (artefactos de la 402 y la 403); **no** incluye `entrenamiento/` (TensorFlow, 301) ni `ml/` | 8085 | Artifact Registry (Google) |
| services/sincronizacion | `node:24-alpine` como Materiales | `node:24-alpine`, `node dist/main.js`, usuario `node`, más la extensión **AWS Lambda Web Adapter** `1.1.0`: `COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.1.0 /lambda-adapter /opt/extensions/lambda-adapter` (línea documentada en el repositorio `aws/aws-lambda-web-adapter`). Fuera de Lambda la extensión no se activa y la imagen corre igual | 8084 (`PORT`) | ECR (AWS) |
| gateway | como Materiales | `node:24-alpine`, `node dist/main.js` | 4000 (`PORT`) | GHCR |
| frontend/erp-shell, mf-obras | `node:24-alpine`, `npm ci`, `npm run build` (Angular: `dist/<proyecto>/browser`) | `nginxinc/nginx-unprivileged:1.29-alpine` con `nginx.conf` propio (SPA: `try_files … /index.html`; CORS en `remoteEntry.json` y archivos `.js` para los remotos; sin caché en `index.html`, `ngsw.json`, `ngsw-worker.js` y `federation.manifest.json`) | 8080 en el contenedor | GHCR |
| frontend/mf-materiales, mf-supervision | `node:24-alpine`, `npm ci`, `npm run build` (`dist/`) | igual que arriba | 8080 | GHCR |
| frontend/portal | `node:24-alpine`, `npm ci`, `npm run build` (`dist/`) | igual que arriba | 8080 | GHCR |

- **IA:** la 401 ya crea el `Dockerfile` con los dos comandos; esta spec lo completa (etapas, usuario sin privilegios, `HEALTHCHECK` solo en `ia-api`, `.dockerignore`). Si la 401 define los comandos como *scripts* de `pyproject.toml` (`ia-api`, `ia-worker`), el contenedor los ejecuta tal cual; si no, `uvicorn ia.main:app --host 0.0.0.0 --port ${IA_PUERTO}` y `python -m ia.worker`.
- **Finanzas** usa la **misma imagen** para la API y para los procesos en segundo plano de 008 y 201 (consumidor de RabbitMQ, publicador del outbox y `schedule:work`); cambia solo el comando (602).
- Obras, Materiales y Finanzas corren sus migraciones al iniciar (Flyway en Obras; en Finanzas, `php artisan migrate --force` antes de la API). IA corre `alembic upgrade head` al iniciar `ia-api` (las migraciones de `reportes_db` de la 401 y los permisos de la 503). **(decisión del equipo)**
- Frontends: la configuración se fija **al compilar** con variables del entorno de GitHub (`vars`), porque los sitios estáticos no leen variables en tiempo de ejecución. Angular (shell, mf-obras) usa `environment.ts` / `environment.prod.ts` (001); los React con esbuild (mf-materiales, mf-supervision) reciben los valores con `define` en `build.mjs`; el portal usa variables `VITE_*`. En el shell, `public/federation.manifest.json` se genera en el workflow con las URL de producción de los remotos. **(decisión del equipo)**

## Configuración por variables de entorno

Nombres que ya figuran en las specs o en los proyectos; los que todavía no existen se marcan *(propuesto)* y siguen el prefijo que usa cada proyecto. Cada proyecto deja en su `.env.example` el valor de desarrollo.

| Proyecto | Variables (fuente) |
|---|---|
| Obras | `OBRAS_PORT`, `OBRAS_DB_HOST`, `OBRAS_DB_PORT`, `OBRAS_DB_NAME`, `OBRAS_DB_USER`, `OBRAS_DB_PASSWORD` (`application.yml`); `OBRAS_S3_ENDPOINT`, `OBRAS_S3_ACCESS_KEY`, `OBRAS_S3_SECRET_KEY`, `OBRAS_S3_BUCKET` (005); *(propuesto)* `OBRAS_DB_SSLMODE`, `OBRAS_S3_REGION`, `OBRAS_KEYCLOAK_ISSUER`, `OBRAS_RABBITMQ_HOST`, `OBRAS_RABBITMQ_PORT`, `OBRAS_RABBITMQ_USER`, `OBRAS_RABBITMQ_PASSWORD`, `OBRAS_RABBITMQ_SSL`, `OBRAS_CORS_ORIGENES` |
| Materiales | `PORT`, `MONGODB_URI` (`.env.example`); `MATERIALES_S3_ENDPOINT`, `MATERIALES_S3_ACCESS_KEY`, `MATERIALES_S3_SECRET_KEY`, `MATERIALES_S3_BUCKET` (102); `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `AUDIENCIA` (los mismos nombres que la 101 usa «igual que Materiales»); *(propuesto)* `MATERIALES_S3_REGION`, `RABBITMQ_URL` |
| Finanzas | `APP_KEY`, `APP_ENV`, `APP_DEBUG`, `LOG_CHANNEL`, `DB_CONNECTION=pgsql`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` (Laravel); *(propuesto)* `DB_SSLMODE`, `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `AUDIENCIA`, `RABBITMQ_HOST`, `RABBITMQ_PORT`, `RABBITMQ_USER`, `RABBITMQ_PASSWORD`, `RABBITMQ_SSL` |
| IA (`ia-api` e `ia-worker`) | 401: `IA_PUERTO`, `IA_REPORTES_DB_URL`, `IA_MONGO_URL`, `IA_MONGO_DB`, `IA_RABBITMQ_URL`, `IA_KEYCLOAK_ISSUER`, `IA_AUDIENCIA`, `IA_ZONA_HORARIA`; 402 y 403: `IA_MODELO_RIESGO_VERSION`, `IA_MODELO_ATIPICOS_VERSION` (opcionales); 501: `IA_AGENTES_CLIENT_ID`, `IA_AGENTES_CLIENT_SECRET`, `IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`; 502: `IA_OLLAMA_URL`, `IA_OLLAMA_MODELO`, `IA_AGENTES_CRON`, `IA_AGENTES_PROGRAMADOS_ACTIVOS`; 503: `IA_REPORTES_DB_URL_LECTURA`, `IA_MATERIALES_URL` |
| Sincronización | 101: `PORT`, `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `AUDIENCIA`, `OBRAS_URL`, `MATERIALES_URL`, `DYNAMODB_ENDPOINT`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DYNAMODB_CREAR_TABLAS`, `TIEMPO_MAXIMO_LLAMADA_MS`, `TIEMPO_MAXIMO_LOTE_MS`; 102: `SINC_S3_ENDPOINT`, `SINC_S3_ACCESS_KEY`, `SINC_S3_SECRET_KEY`, `SINC_S3_BUCKET` |
| Gateway | `PORT`, `OBRAS_URL`, `MATERIALES_URL`, `FINANZAS_URL`, `KEYCLOAK_URL`, `KEYCLOAK_GATEWAY_CLIENT_ID`, `KEYCLOAK_GATEWAY_CLIENT_SECRET` (contrato del gateway); `IA_URL` (402); *(propuesto)* `KEYCLOAK_REALM`, `AUDIENCIA`, `CORS_ORIGENES` |
| erp-shell (al compilar) | `environment.prod.ts`: URL de Keycloak, del gateway y del portal (001); `federation.manifest.json` con las URL de los remotos |
| mf-obras (al compilar) | `environment.prod.ts`: URL del gateway |
| mf-materiales, mf-supervision (al compilar) | *(propuesto)* `GATEWAY_URL`; mf-supervision además `DICTADO_MODELO_URL` (302, opcional) |
| portal (al compilar) | `VITE_OBRAS_URL` (008); *(propuesto)* `VITE_KEYCLOAK_URL` |
| app-obra (al compilar) | *(propuesto)* `EXPO_PUBLIC_KEYCLOAK_URL`, `EXPO_PUBLIC_SINCRONIZACION_URL` (desde la 101 y la 102 la app solo llama a Keycloak y a Sincronización) |
| n8n (infra) | 201: `GENERIC_TIMEZONE`, `N8N_ENCRYPTION_KEY`, y las variables de los flujos `FINANZAS_URL`, `COMPRAS_CORREO_REMITENTE`, `EMPRESA_NOMBRE` |

- En Lambda, `AWS_REGION`, `AWS_ACCESS_KEY_ID` y `AWS_SECRET_ACCESS_KEY` los pone el propio entorno de ejecución con las credenciales del rol: no se definen a mano. `SINC_S3_ACCESS_KEY` y `SINC_S3_SECRET_KEY` quedan vacías y el cliente S3 usa la cadena de credenciales por defecto del AWS SDK (tarea de Sincronización: no pasar credenciales al cliente si las variables están vacías). Lo mismo con `DYNAMODB_ENDPOINT` vacío (usa el DynamoDB real de la región).

## Workflow `ci-cd.yml`

Versiones mayores de las acciones (verificadas en GitHub el 28/10/2026): `actions/checkout@v7`, `actions/setup-node@v7`, `actions/setup-java@v6`, `actions/setup-python@v7`, `shivammathur/setup-php@v2`, `docker/setup-buildx-action@v4`, `docker/login-action@v4`, `docker/build-push-action@v7`, `azure/login@v3`, `google-github-actions/auth@v3`, `google-github-actions/deploy-cloudrun@v3`, `aws-actions/configure-aws-credentials@v6`, `aws-actions/amazon-ecr-login@v2`, `Azure/static-web-apps-deploy@v1`.

### Estructura común

```yaml
name: ci-cd
on:
  pull_request: { branches: [main] }
  push: { branches: [main] }
  workflow_dispatch:
    inputs:
      etiqueta: { description: "Etiqueta a desplegar (vacío = este commit)", required: false }
permissions:
  contents: read
  packages: write      # GHCR
  id-token: write      # OIDC hacia la nube
concurrency: { group: ci-cd-${{ github.ref }}, cancel-in-progress: true }
jobs:
  prueba:     # siempre: dependencias con caché, lint, pruebas, compilación
  imagen:     # needs: prueba · en PR: build sin push · en main: build + push con etiquetas sha-<7> y main
  desplegar:  # needs: imagen · solo en main o a mano · environment: produccion · login OIDC y despliegue de sha-<7> (o de la etiqueta pedida)
```

- Caché de capas con `cache-from/cache-to: type=gha`.
- El job `desplegar` usa el entorno de GitHub `produccion` (secretos y variables de producción; opcionalmente, aprobación manual de un integrante). **(decisión del equipo)**

### Ejemplo: Obras (Azure Container Apps)

```yaml
  prueba:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-java@v6
        with: { distribution: temurin, java-version: '21', cache: maven }
      - run: ./mvnw -B verify
  imagen:
    needs: prueba
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - id: etiqueta
        run: echo "sha=sha-${GITHUB_SHA::7}" >> "$GITHUB_OUTPUT"
      - uses: docker/setup-buildx-action@v4
      - if: github.event_name != 'pull_request'
        uses: docker/login-action@v4
        with: { registry: ghcr.io, username: ${{ github.actor }}, password: ${{ secrets.GITHUB_TOKEN }} }
      - uses: docker/build-push-action@v7
        with:
          push: ${{ github.event_name != 'pull_request' }}
          tags: |
            ghcr.io/jairovargasfigueroa/supervision-ms-obras:${{ steps.etiqueta.outputs.sha }}
            ghcr.io/jairovargasfigueroa/supervision-ms-obras:main
          cache-from: type=gha
          cache-to: type=gha,mode=max
  desplegar:
    if: github.ref == 'refs/heads/main'
    needs: imagen
    runs-on: ubuntu-latest
    environment: produccion
    steps:
      - uses: azure/login@v3
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      - run: >
          az containerapp update --name obras --resource-group rg-supervision
          --image ghcr.io/jairovargasfigueroa/supervision-ms-obras:sha-${GITHUB_SHA::7}
```

### Diferencias por proyecto

| Proyecto | Job `prueba` | Despliegue |
|---|---|---|
| Obras | `./mvnw -B verify` (Java 21) | `az containerapp update` (app `obras`) |
| Finanzas | PHP 8.3 con `shivammathur/setup-php@v2` (extensiones `pdo_pgsql`, `bcmath`, `sockets`), `composer install`, `php artisan test` con PostgreSQL de servicio | `az containerapp update` de `finanzas-api` y `finanzas-worker` con la misma imagen |
| Gateway | Node 24: `npm ci`, `npm run lint`, `npm test`, `npm run test:e2e`, `npm run build` | `az containerapp update` (app `gateway`) |
| Materiales | Node 24 y MongoDB de servicio en modo *replica set* para las pruebas de outbox | Artifact Registry + `google-github-actions/deploy-cloudrun@v3` (servicio `materiales`) |
| IA | `astral-sh/setup-uv` (o `pip install uv`) con Python 3.12: `uv sync --frozen`, `uv run ruff check`, `uv run pytest` con PostgreSQL de servicio (proyecciones de la 401) e incluidas las pruebas de seguridad de la 504 | Artifact Registry + `gcloud compute ssh vm-ia --tunnel-through-iap --command "cd /opt/supervision && sudo docker compose pull ia-api ia-worker && sudo docker compose up -d ia-api ia-worker"` |
| Sincronización | Node 24 con DynamoDB Local de servicio y un doble de S3 (101 y 102) | ECR + `aws lambda update-function-code --function-name sincronizacion --image-uri <ecr>/supervision-ms-sincronizacion:sha-…` y espera a `LastUpdateStatus = Successful` |
| erp-shell, mf-obras | `npm ci`, `npm test`, `npm run build` con la configuración de producción; el shell genera `federation.manifest.json` | `Azure/static-web-apps-deploy@v1` con `skip_app_build: true` y la carpeta `dist/…/browser`; la imagen nginx se publica en GHCR |
| mf-materiales, mf-supervision | `npm ci`, `npm run typecheck`, pruebas, `npm run build` | igual (carpeta `dist/`) |
| portal | `npm ci`, `npm run lint`, `npm run build` | igual (carpeta `dist/`) |
| app-obra | `npx tsc --noEmit`, pruebas, `npx expo-doctor` (sin imagen ni despliegue) | Workflow aparte `version-instalable.yml` (`workflow_dispatch`) con `eas build --platform android --profile preview` y el secreto `EXPO_TOKEN` **(decisión del equipo:** APK de distribución interna; requiere cuenta gratuita de Expo; la 301 ya exige *development build* por `react-native-fast-tflite`) |
| infra | Valida los `docker-compose*.yml` (`docker compose config`), el JSON del realm y las definiciones de RabbitMQ (colas `ia`, `n8n.stock-bajo`, `n8n.compra-recibida`, `plataforma.fallidos`); valida los flujos de n8n de `n8n/flujos/` (JSON bien formado) | `az vm run-command invoke` (VM de Azure) y `gcloud compute ssh` (VM de Google) para `docker compose pull && docker compose up -d` |

- `astral-sh/setup-uv`: la versión mayor se fija al implementar (no se verificó en esta spec); alternativa sin acción externa: `pip install uv`.
- Las imágenes que van a Azure Container Apps se publican en **GHCR** (gratuito para estos repositorios; Container Apps puede descargar de cualquier registro). Las de Google van a **Artifact Registry** y la de AWS a **ECR**, porque Cloud Run y Lambda descargan de su propio registro. **(decisión del equipo)**
- Los frontends también construyen y publican su imagen nginx en GHCR (sirve para Docker Compose y como alternativa de despliegue), pero en la nube se publican los archivos estáticos. **(decisión del equipo)**

## Secretos de GitHub (entorno `produccion`)

| Secreto | Repos |
|---|---|
| `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` (identidad federada, sin contraseña) | obras, finanzas, gateway, infra |
| `AZURE_SWA_TOKEN` (token de despliegue de cada Static Web App) | erp-shell, mf-obras, mf-materiales, mf-supervision, portal |
| `GCP_WORKLOAD_IDENTITY_PROVIDER`, `GCP_SERVICE_ACCOUNT` | materiales, ia, infra |
| `AWS_ROLE_ARN` (rol con confianza OIDC para el repositorio) | sincronizacion |
| `EXPO_TOKEN` | app-obra |

- Los secretos de la **aplicación** (contraseñas de bases, de RabbitMQ, secretos de los clientes de Keycloak, clave de cifrado de n8n) no los usa el workflow: viven en el gestor de cada nube y se cargan en el servicio (602). El workflow solo cambia la imagen.

## Pruebas

- Cada proyecto: `docker build` local y `docker run` con variables de prueba responden `GET /salud` (o la página inicial en los frontends) y el proceso no corre como `root` (`docker run … id -u` distinto de 0).
- IA: la misma imagen arranca con `ia-api` (responde `/salud`) y con `ia-worker` (se conecta a RabbitMQ y registra la cola `ia`).
- Sincronización: la imagen responde `/salud` con `docker run` (la extensión de Lambda no interfiere fuera de Lambda).
- Workflow: un PR de prueba con una prueba rota queda en rojo y no publica imagen; un *push* a `main` publica `sha-…` y `main` y despliega.
- `docker history` de la imagen final no muestra `.env` ni herramientas de compilación.

## Cambios a contratos y datos

### `docs/convenciones.md`

Nueva sección «Contenedores y CI/CD»:
- Un `Dockerfile` y un `ci-cd.yml` por repositorio; imagen *multi-stage*, sin `root`, configuración por variables de entorno.
- Etiquetas `sha-<7>` (la que se despliega) y `main`.
- Registros: GHCR (`ghcr.io/jairovargasfigueroa/supervision-<repo>`) para lo que va a Azure; Artifact Registry para Google; ECR para AWS.
- Autenticación de los workflows con OIDC; secretos de despliegue en GitHub Secrets (entorno `produccion`).
- Tabla de variables de entorno por proyecto de este diseño (incluidas las *propuestas*, para que cada proyecto las agregue a su `.env.example`).

### `docs/arquitectura.md`

- «Los 4 niveles → Despliegue»: agregar «imagen por repositorio publicada por GitHub Actions; IA con una imagen y dos procesos (`ia-api`, `ia-worker`); frontends como sitios estáticos».
- «Versiones»: imágenes base (`eclipse-temurin:21`, `node:24-alpine`, `python:3.12-slim`, `dunglas/frankenphp:1-php8.3`, `nginx-unprivileged:1.29`) y AWS Lambda Web Adapter 1.1.0.
