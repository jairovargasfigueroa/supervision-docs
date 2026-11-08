# 601 · Diseño

## Las tres etapas

```
1. EMPAQUETAR (esta spec)      2. ENSAYAR (esta spec)                 3. SUBIR (602, después)
servicio ─Dockerfile─> imagen  imágenes + compose por grupo           crear recursos en cada nube,
frontend ─build─> archivos     (6 imágenes + 5 frontends estáticos)         (azure / google / aws) en la laptop,   copiar el compose de cada grupo,
                               HTTPS y TLS entre grupos, datos de     cambiar las variables y correr
                               demo y prueba de humo                  la misma prueba de humo
```

- **Imagen:** el servicio ya empaquetado; no cambia según dónde se despliegue. Los frontends no llevan imagen: son archivos estáticos.
- **Compose:** qué imágenes corren juntas en un servidor y con qué variables. Cambiar el reparto entre nubes es mover bloques de un compose a otro y cambiar variables.

## Imágenes

### Reglas comunes

- Imágenes base oficiales con versión fija al menos hasta *major.minor*, publicadas hace al menos dos semanas; se verifican en Docker Hub al implementar (las del borrador anterior eran: `eclipse-temurin:21-jre-alpine`, `node:24-alpine`, `python:3.12-slim`, `dunglas/frankenphp:1-php8.3`, `nginxinc/nginx-unprivileged:1.29-alpine`).
- Dos etapas: `construir` (dependencias y compilación) y `final` (solo lo necesario para correr).
- Usuario sin privilegios (`USER` numérico, por ejemplo `10001`, o el que trae la imagen: `node`, `nginx`).
- `EXPOSE` con el puerto de `convenciones.md`; el proceso lee el puerto de su variable.
- `HEALTHCHECK` contra `GET /salud`.
- Etiqueta OCI `org.opencontainers.image.source` con la URL del repositorio (GHCR la usa para enlazar el paquete).
- `.dockerignore`: `.git`, `node_modules`, `vendor`, `target`, `dist`, `.env*`, `*.log`, `coverage`, `.venv`, `android`, `datos`.
- Las pruebas no corren dentro del `docker build`: corren antes, en el workflow.

### Imagen por proyecto

| Proyecto | Etapa de construcción | Imagen final y comando | Puerto |
|---|---|---|---|
| services/obras | JDK 21: `./mvnw -B package -DskipTests` | JRE 21: `java -XX:MaxRAMPercentage=75 -jar app.jar` con el perfil `prod` | 8081 |
| services/materiales | Node 24: `npm ci`, `npm run build`, `npm prune --omit=dev` | Node 24: `node dist/main.js`, usuario `node` | 8082 |
| services/finanzas | `composer install --no-dev --optimize-autoloader` | FrankenPHP con PHP 8.4 (Symfony 8.1, en el `composer.lock`, pide PHP 8.4.1 o más; encontrado al implementar) y las extensiones `pdo_pgsql`, `bcmath`, `sockets`, `opcache`; `php artisan migrate --force` y después `frankenphp php-server` sobre `public/` (decisión del equipo: un solo proceso, sin nginx + php-fpm). **La misma imagen** corre los procesos en segundo plano cambiando el comando: `mensajeria:consumir`, `mensajeria:publicar` y `schedule:work` | 8083 |
| services/ia | Python 3.12 con `uv sync --frozen --no-dev` (entorno en `/app/.venv`) | Python 3.12 con el entorno copiado y `modelos/` (402 y 403); sin `entrenamiento/` ni `ml/`. **Una imagen, dos comandos:** `ia-api` (aplica `alembic upgrade head` y atiende en 8085) e `ia-worker`. La carga inicial (`ia-carga-inicial`) es un tercer comando de la misma imagen | 8085 |
| services/sincronizacion | como Materiales | Node 24: `node dist/main.js`. Sin adaptador de Lambda: si la 602 la pone en Lambda, lo agrega allá | 8084 |
| gateway | como Materiales | Node 24: `node dist/main.js` | 4000 |

### Frontends: archivos estáticos con configuración al publicar

Los frontends no llevan imagen (decisión de Jairo): se compilan una vez (`npm run build`) y se publican como archivos estáticos, como en Amplify. En el ensayo local los sirve Caddy desde las carpetas compiladas; en la nube, un *hosting* de estáticos (602). Al **publicar**, un script escribe con las variables del entorno los archivos que dependen de él:

| Proyecto | Archivo generado | Variables |
|---|---|---|
| erp-shell | `configuracion.json` (`keycloakUrl`, `keycloakRealm`, `gatewayUrl`, `portalUrl`) y `federation.manifest.json` (dirección de cada remoto) | `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `GATEWAY_URL`, `PORTAL_URL`, `MF_OBRAS_URL`, `MF_MATERIALES_URL`, `MF_SUPERVISION_URL` |
| portal | `configuracion.json` (`keycloakUrl`, `keycloakRealm`, `obrasUrl`, `erpUrl`) | `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `OBRAS_URL`, `ERP_URL` |
| mf-obras, mf-materiales, mf-supervision | ninguno: leen la configuración que publica el shell en `window.plataforma.configuracion` (ya es así en mf-materiales y mf-supervision; mf-obras se alinea) | — |

- El shell y el portal cargan `configuracion.json` **antes** de iniciar (inicializador de Angular en el shell; antes de montar React en el portal). En desarrollo, si el archivo no está, usan los valores de desarrollo de hoy.
- Reglas del servidor de estáticos (Caddy en el ensayo; el *hosting* en la nube): SPA (si no existe el archivo, `index.html`), CORS en `remoteEntry.json` y `.js` de los microfrontends para el origen del shell, y sin caché en `index.html`, `configuracion.json`, `federation.manifest.json`, `ngsw.json` y `ngsw-worker.js`.
- El script `infra/produccion-local/publicar-frontends.(ps1|sh)` compila (o toma) la carpeta `dist` de cada frontend, la copia al volumen de Caddy y escribe los dos archivos con `envsubst`; la 602 hace lo mismo hacia el *hosting* de la nube.

## Configuración por variables

Fuente de los nombres actuales: `docs/entorno-local.md` («Variables de entorno por proyecto») y el `.env.example` de cada proyecto. Esta spec **revisa que no quede ninguna dirección fija** y agrega solo lo que falta para producción:

| Proyecto | Agrega (si no existe ya) |
|---|---|
| Obras | `OBRAS_DB_SSLMODE`, `OBRAS_RABBITMQ_SSL`, `OBRAS_CORS_ORIGENES` (si faltara), perfil `prod` (`SPRING_PROFILES_ACTIVE`) |
| Materiales | TLS en `MONGODB_URI` y `RABBITMQ_URL` (`amqps://`) por la propia URL; `CORS_ORIGENES` si atiende al navegador; `NODE_ENV` |
| Finanzas | `DB_SSLMODE`, `RABBITMQ_SSL`, `APP_ENV`, `APP_DEBUG`, `LOG_CHANNEL=stderr`, `EMPRESA_NOMBRE` (201) |
| IA | TLS por las URL (`IA_RABBITMQ_URL` con `amqps://`, `IA_MONGO_URL`, `sslmode` en las de PostgreSQL); `IA_CA_EXTRA` opcional (ruta de una CA adicional, para el ensayo local) |
| Sincronización | `NODE_ENV`; las direcciones de Obras y Materiales ya son variables (101) |
| Gateway | `CORS_ORIGENES`, `NODE_ENV` |
| Frontends | las de la tabla anterior (al publicar) |
| app-obra | `EXPO_PUBLIC_KEYCLOAK_URL`, `EXPO_PUBLIC_SINCRONIZACION_URL` (al compilar; hoy están en `app.json` → `extra`). El APK lo genera Jairo más adelante |
| Keycloak (infra) | `ERP_URL`, `PORTAL_URL` (direcciones de regreso y orígenes de los clientes `erp` y `portal`), `USUARIOS_PRUEBA_CLAVE` (contraseña de los usuarios de prueba al importar; por defecto `Prueba123!` solo en desarrollo), `KC_HOSTNAME` (dirección pública de Keycloak, para que el emisor de los tokens sea el mismo para todos), secretos de los clientes (ya por variable) |

- **Una CA extra para el ensayo local:** en la «producción local» los certificados los firma una autoridad local de Caddy. Cada imagen acepta una CA adicional por variable sin cambiar el código: Java (`JAVA_TOOL_OPTIONS` con un *truststore*), Node (`NODE_EXTRA_CA_CERTS`), Python (`SSL_CERT_FILE` o `IA_CA_EXTRA`) y PHP (`curl.cainfo` y `openssl.cafile`). En la nube no hace falta: los certificados son públicos.

## Datos de demostración

- Guarda nueva común a la semilla de Obras, Finanzas y Materiales y a los scripts de `infra`: con `SEMILLA_DEMO=si`, la semilla **carga** (idempotente) aunque el servicio esté en modo producción o la base no sea local; el **vaciado** sigue prohibido fuera de desarrollo (sin excepción).
- Fotos de prueba: al bucket o al S3 compatible configurado (`S3_BUCKET` y su *endpoint*); la guarda del prefijo `supervision-dev-` se cambia por «`supervision-dev-` o `SEMILLA_DEMO=si`».
- Después de la semilla, la carga inicial de reportes (401) con el comando `ia-carga-inicial` de la imagen de IA.

## CI en GitHub

Workflow `.github/workflows/ci.yml` en cada repositorio. Versiones de las acciones (mayores, verificadas al implementar): `actions/checkout`, `actions/setup-node`, `actions/setup-java`, `astral-sh/setup-uv` (o `pip install uv`), `shivammathur/setup-php`, `docker/setup-buildx-action`, `docker/login-action`, `docker/build-push-action`.

```yaml
name: ci
on:
  pull_request: { branches: [develop, main] }
  push: { branches: [main] }
permissions: { contents: read, packages: write }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  prueba:   # dependencias con caché, lint, tipos, pruebas, compilación
  imagen:   # solo servicios · needs: prueba · en PR: build sin push · en push a main: build + push a GHCR (sha-<7> y main)
  archivos: # solo frontends · needs: prueba · en push a main: sube la carpeta compilada como artefacto (actions/upload-artifact)
```

| Proyecto | Job `prueba` |
|---|---|
| Obras | Java 21: `./mvnw -B verify` (Testcontainers con el Docker del runner) |
| Finanzas | PHP 8.4 con `pdo_pgsql`, `bcmath` y `sockets`: `composer install`, `vendor/bin/pint --test`, `vendor/bin/phpstan analyse`, `php artisan test` |
| Materiales, Sincronización y gateway | Node 24: `npm ci` y los scripts de lint, pruebas (unitarias y e2e) y compilación de cada proyecto; Materiales con MongoDB en *replica set* y Sincronización con DynamoDB Local como servicios del job |
| IA | uv con Python 3.12: `uv sync --frozen`, `ruff check`, `ruff format --check`, `mypy`, `pytest` (Testcontainers) |
| erp-shell, mf-obras | `npm ci`, pruebas y `npm run build` |
| mf-materiales, mf-supervision | `npm ci`, `npm run typecheck`, pruebas y `npm run build` |
| portal | `npm ci`, lint, pruebas y `npm run build` |
| app-obra | `npm ci`, `npx tsc --noEmit` y `npx jest` (sin imagen) |
| infra | `docker compose config -q` (todos los perfiles), JSON del realm, definiciones de RabbitMQ y flujos de n8n bien formados |

- Imagen publicada: `ghcr.io/jairovargasfigueroa/supervision-<repo>:sha-<7>` y `:main`. Caché de capas con `type=gha`.
- Los repositorios son públicos: GitHub Actions y GHCR no tienen costo.

## Ensayo local («producción local»)

Carpeta nueva `infra/produccion-local/`:

```
produccion-local/
  compose.azure.yml    keycloak (KC_HOSTNAME), rabbitmq (TLS 5671), n8n, mailpit, postgres (obras_db, finanzas_db, keycloak_db),
                       obras, finanzas-api, finanzas-trabajos (consumidor, publicador y schedule), gateway y caddy, que además
                       sirve los 5 frontends compilados (erp, mf-obras, mf-materiales, mf-supervision y portal)
  compose.google.yml   ia-api, ia-worker, postgres de reportes, mongo (replica set), materiales, ollama (perfil opcional,
                       reusa el volumen del modelo), caddy
  compose.aws.yml      sincronizacion, dynamodb-local, minio (S3), caddy
  caddy/               un Caddyfile por grupo (tls internal) y la CA local compartida
  certificados.ps1/.sh genera la CA local y el certificado de RabbitMQ (openssl en un contenedor)
  .env.example         todas las variables de los tres grupos, sin secretos
  publicar-frontends.ps1/.sh  compila los 5 frontends, los copia al volumen de Caddy y escribe su configuración
  levantar.ps1/.sh     construye o descarga las imágenes, publica los frontends, genera certificados y levanta los tres grupos
  bajar.ps1/.sh
```

- **Nombres:** cada grupo publica sus servicios en `https://<servicio>.<grupo>.localhost` (por ejemplo `https://keycloak.azure.localhost`, `https://ia.google.localhost`); `*.localhost` resuelve a la máquina en el navegador sin tocar el archivo `hosts`. Dentro de los contenedores, esos nombres apuntan a la máquina con `extra_hosts` (`host-gateway`), así las llamadas entre grupos salen y entran por Caddy con HTTPS, como entre nubes.
- **Puertos en la máquina:** 443 compartido no es posible para tres Caddy; cada grupo usa el suyo (por ejemplo 8443 azure, 9443 google y 10443 aws) y las direcciones los llevan (`https://keycloak.azure.localhost:8443`). Se eligen para no chocar con los de desarrollo (`convenciones.md`).
- **Navegador:** acepta la CA local una vez (instalarla en Windows es opcional y necesita permisos de administrador; si no, el navegador muestra el aviso de certificado una vez por dirección).
- **Imágenes:** por defecto se **construyen** desde las carpetas de cada proyecto (sin depender de GHCR); con `--desde-ghcr` se descargan las publicadas.
- **Datos:** `levantar` termina con la semilla en modo demostración y la carga inicial de reportes.
- **Recursos:** el ensayo completo corre unos 20 contenedores; si la laptop no alcanza, se levanta **por grupos** (primero `azure`, el centro, y después los otros). El desarrollo diario no cambia: sigue con los servidores de desarrollo; con 16 GB de RAM se levanta sin Ollama por defecto (reportes y agentes con el modelo apagado, o con el Ollama de desarrollo).

## Prueba de humo

`infra/pruebas/humo-despliegue.mjs` (Node 24, sin dependencias), con un archivo de direcciones (`--entorno produccion-local/.env` o, en la 602, el de la nube):

1. `GET /salud` de Obras, Materiales, Finanzas, IA, Sincronización y el gateway; la página inicial de cada frontend y su `configuracion.json`.
2. Keycloak: token de un usuario de prueba (`ERP_URL` como origen) y de los clientes de servicio (`gateway`, `ia-reportes`, `ia-agentes`, `n8n`), con el emisor esperado.
3. Gateway: una consulta con el token del gerente.
4. `/mcp` de los cuatro servicios: `401` sin token.
5. RabbitMQ: colas de la plataforma y de n8n, por TLS.
6. n8n (flujos publicados) y Mailpit.
7. Con `--completa`: presentar y aprobar una planilla, esperar el cobro y la nota de cobro en Mailpit (reusa la lógica de `pruebas/cobranza.mjs`).

Salida: una línea por comprobación y un resumen; código distinto de 0 si algo falla.

## App

- `app.config.js` toma `EXPO_PUBLIC_KEYCLOAK_URL` y `EXPO_PUBLIC_SINCRONIZACION_URL` (por defecto, las de desarrollo). Generar y distribuir el APK queda fuera de esta spec (lo hace Jairo).

## Pruebas

- Cada servicio: `docker build` y `docker run` con variables de prueba responden `/salud`, el proceso no corre como `root` (`id -u` distinto de 0) y `docker history` no muestra `.env` ni herramientas de compilación.
- IA: la misma imagen arranca con `ia-api` (responde `/salud`) y con `ia-worker` (se conecta a RabbitMQ).
- Finanzas: la misma imagen corre la API y los tres procesos en segundo plano.
- Workflows: un PR con una prueba rota queda en rojo; un *push* a `main` publica `sha-…` y `main`.
- Ensayo local: `levantar` deja los tres grupos sanos y `humo-despliegue.mjs --completa` pasa entero; mover un servicio de grupo solo cambia los *compose* y las variables.

## Cambios a contratos y datos

### `docs/convenciones.md`

Sección nueva «Contenedores y CI»: un `Dockerfile` por servicio y un `ci.yml` por repositorio; imagen en dos etapas, sin `root`, configuración por variables; etiquetas `sha-<7>` y `main` en GHCR; frontends como archivos estáticos con `configuracion.json` escrito al publicar; puertos del ensayo local.

### `docs/entorno-local.md`

- Variables nuevas de la tabla «Configuración por variables».
- Sección «Producción local»: qué levanta, cómo, puertos, la CA local y cuánto ocupa.

### `docs/datos-prueba.md`

Guardas: la excepción `SEMILLA_DEMO=si` (solo carga, nunca vaciado).

### `docs/arquitectura.md`

«Los 4 niveles → Despliegue»: imagen por repositorio publicada por GitHub Actions; IA con una imagen y sus procesos; frontends como archivos estáticos compilados una vez con la configuración escrita al publicar; ensayo local en tres grupos.

### `docs/stack.md`

Imágenes base, Caddy, MinIO y las acciones de GitHub, con sus versiones.

### `docs/specs/602-despliegue-tres-nubes/`

Queda en borrador y se reescribe al desplegar, partiendo de esta spec (imágenes, *compose* por grupo, variables y prueba de humo).

### Repos con tareas del borrador anterior

Reemplazar `docs/specs/601-contenedores-ci/tareas.md` en cada repo por las tareas nuevas (y borrar las de la raíz `tareas-ia.md` y `tareas-sincronizacion.md`, reemplazadas por las nuevas).
