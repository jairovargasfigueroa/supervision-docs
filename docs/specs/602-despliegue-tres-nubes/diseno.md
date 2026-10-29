# 602 · Diseño

## Criterios para elegir servicios

1. **Costo bajo para estudiantes:** niveles gratuitos, créditos de estudiante y escalar a cero cuando se pueda. Los montos de créditos y niveles gratuitos cambian; el equipo los revisa en la página de cada nube antes de crear los recursos.
2. **Contenedores** para todo lo que es nuestro (601); servicios administrados solo donde ahorran trabajo (bases de datos, sitios estáticos).
3. **Procesos permanentes fuera de lo serverless:** lo que debe estar siempre encendido y no tiene un servicio barato (Keycloak, RabbitMQ, n8n, Mailpit, `ia-worker`, Ollama) va en máquinas virtuales con Docker Compose.
4. Una región por nube, la más cercana a Bolivia que tenga todos los servicios usados: Azure `Brazil South`, Google `southamerica-east1` (São Paulo), AWS `sa-east-1` (São Paulo). **(decisión del equipo; si un servicio o nivel gratuito no está en esa región, se usa `us-east`)**

## Mapa del despliegue

| Pieza | Nube | Servicio | Tamaño o plan | URL pública |
|---|---|---|---|---|
| Shell, mf-obras, mf-materiales, mf-supervision, portal | Azure | **Static Web Apps** (una por proyecto) | Plan gratuito | `https://<nombre>.azurestaticapps.net` |
| Gateway | Azure | **Container Apps** (entorno de consumo `cae-supervision`) | 0,5 vCPU / 1 GiB; réplicas 0 a 2 | `https://gateway.<entorno>.azurecontainerapps.io` |
| Obras | Azure | Container Apps | 0,5 vCPU / 1 GiB; mínimo 1 réplica (consumidor de la saga y tarea de vencimientos cada 10 s) | `https://obras.<entorno>.azurecontainerapps.io` |
| Finanzas API | Azure | Container Apps | 0,25 vCPU / 0,5 GiB; réplicas 0 a 2 | `https://finanzas-api.<entorno>.azurecontainerapps.io` |
| Finanzas en segundo plano | Azure | Container Apps (sin ingreso HTTP) | 0,25 vCPU / 0,5 GiB; exactamente 1 réplica | — |
| Keycloak, RabbitMQ, n8n, Mailpit | Azure | **Máquina virtual** `vm-plataforma` (Ubuntu LTS, tamaño B2s: 2 vCPU, 4 GiB) con Docker Compose y **Caddy** (HTTPS automático) | Disco de 32 GiB | `https://<etiqueta>.brazilsouth.cloudapp.azure.com` (etiqueta DNS gratuita de la IP pública) |
| PostgreSQL de Obras, Finanzas y Keycloak | Azure | **Azure Database for PostgreSQL – Flexible Server** | Nivel *Burstable* B1ms, 32 GiB; bases `obras_db`, `finanzas_db`, `keycloak_db` | solo por TLS |
| IA (`ia-api` + `ia-worker`), Ollama, PostgreSQL de reportes | Google | **Compute Engine** `vm-ia` (`e2-standard-4`: 4 vCPU, 16 GB) con Docker Compose y Caddy | Disco balanceado de 50 GB; IP externa estática | `https://ia.<ip-con-guiones>.sslip.io` o subdominio propio |
| Materiales | Google | **Cloud Run** | 1 vCPU / 512 MiB; mínimo 1 instancia con CPU siempre asignada (consumidores de RabbitMQ y outbox cada segundo) | `https://materiales-<hash>.run.app` |
| MongoDB (`materiales_db`, `ia_db`) | Google (vía MongoDB Atlas) | **MongoDB Atlas**, clúster gratuito M0 alojado en Google Cloud | Replica set de 3 nodos (lo exige el outbox de Materiales) | cadena `mongodb+srv://` con TLS |
| Sincronización | AWS | **Lambda** con imagen de contenedor (ECR), **AWS Lambda Web Adapter** 1.1.0 y **URL de función** | 1024 MB, tiempo máximo 60 s | `https://<id>.lambda-url.sa-east-1.on.aws` |
| DynamoDB | AWS | DynamoDB, capacidad bajo demanda | Tablas `operacion_procesada`, `estado_dispositivo` (101) y `subida_archivo` (102) | — |
| Archivos | AWS | **S3**, bucket privado `supervision-<sufijo>` | Bloqueo de acceso público; acceso solo por URL firmada o por el rol de Sincronización | — |

Decisiones marcadas **(decisión del equipo)**:

- **Apps web en Static Web Apps** en lugar de contenedores: son archivos estáticos y el plan gratuito incluye HTTPS. El `Dockerfile` nginx queda para Docker Compose.
- **Keycloak, RabbitMQ, n8n y Mailpit en una VM de Azure:** RabbitMQ necesita un puerto TCP (AMQPS) abierto a Google, y Keycloak y n8n necesitan estar siempre encendidos; en una sola VM cuesta menos que varios servicios siempre encendidos. Alternativa si la VM da problemas: RabbitMQ administrado de CloudAMQP en una región de Azure.
- **IA en una VM de Google con 16 GB, sin serverless:** `ia-worker` es permanente (consumidor de la cola `ia`, tareas programadas de la 401 y la 402, agentes de la 502) y debe estar junto a Ollama; `qwen3:8b` necesita unos 5,2 GB solo para el modelo. `ia-api` va en la misma VM (la usa el gateway y llama a Ollama para los reportes por voz). Sin GPU (más barato; por eso los tiempos de la 503). La PostgreSQL de reportes va en la misma VM en un contenedor con volumen: Cloud SQL costaría más y solo la usa la IA.
- **MongoDB en Atlas M0 sobre Google:** gratuito y ya es *replica set* con TLS. Si el espacio del nivel gratuito no alcanza, se pasa a una VM o a un nivel pagado.
- **Materiales en Cloud Run con 1 instancia mínima:** necesita procesos permanentes (consumidores y outbox). Si los créditos no alcanzan, se mueve a `vm-ia` como un contenedor más.
- **Sincronización en Lambda** (App Runner no acepta clientes nuevos desde el 30/04/2026, documentación de AWS). Revisión contra la 101 y la 102:

| Necesidad (101, 102) | Límite de Lambda con URL de función (cuotas de Lambda, documentación de AWS) | ¿Alcanza? |
|---|---|---|
| `POST /lotes` hasta 256 KB; `PUT /subidas/{id}/partes/{n}` hasta 300 KB binarios | Carga de invocación síncrona: 6 MB de petición y 6 MB de respuesta. El cuerpo binario llega en base64 (≈ 400 KB por parte) | Sí, con margen |
| Lote con presupuesto de 20 s (`TIEMPO_MAXIMO_LOTE_MS`) + llamada en curso de hasta 5 s; `completar` con 5 s (URL firmada) + 15 s (`PUT` a S3); la app espera 30 s | Tiempo máximo de la función: hasta 900 s. Se configura **60 s** | Sí |
| Armar y verificar archivos de hasta 5 MB | 1024 MB de memoria; `/tmp` desde 512 MB (no se usa: se arma en memoria) | Sí |
| Procesos en segundo plano | No hay: el `PROCESANDO` abandonado se resuelve en la siguiente petición (60 s), la expiración la hacen el TTL de DynamoDB y la regla de ciclo de vida de S3 | Sí |
| Dos lotes a la vez con el mismo `idOperacion` | Varias instancias en paralelo; la exclusión la da el *conditional put* de DynamoDB | Sí |
| Compresión gzip (`compression`) | El adaptador pasa la respuesta tal cual (modo con búfer) | Sí |

  - Variables del adaptador: `AWS_LWA_PORT=8084`, `AWS_LWA_READINESS_CHECK_PATH=/salud`. URL de función con autenticación `NONE` (el servicio valida el token de Keycloak).
  - **Punto a comprobar:** el README del adaptador documenta la codificación de respuestas binarias, pero no dice explícitamente cómo trata los **cuerpos binarios de entrada** (`application/octet-stream`). La prueba de humo sube una parte binaria y comprueba su SHA-256 al completar. **Si falla, Sincronización se pasa a Amazon ECS Express Mode** (lo que AWS recomienda en lugar de App Runner), con la misma imagen y sin cambiar código. **(decisión del equipo)**

## Diagrama

```
                    Internet (navegador, app)
       ┌────────────────────┬───────────────────────────┬───────────────────────┐
       ▼                    ▼                           ▼                       ▼
AZURE                                                GOOGLE CLOUD            AWS
 Static Web Apps (shell, mf-*, portal)                Cloud Run: Materiales   Lambda (URL): Sincronización
 Container Apps: gateway ──REST/HTTPS──────────────→  Materiales               │   │   │
                 obras ←──REST/HTTPS (portal, Sincronización)                  │   │   └→ S3 temporal/ (rol)
                 finanzas-api ←── n8n (token de servicio)                      │   └→ DynamoDB (3 tablas)
                 finanzas-worker                       vm-ia (Caddy):          └→ Obras, Materiales (token del usuario)
 vm-plataforma (Caddy):                                  ia-api ──MCP/HTTPS──→ Obras, Finanzas (Azure), Materiales
   Keycloak ←──OIDC/JWKS (todos)                         ia-worker (permanente)
   RabbitMQ ←──AMQPS 5671── Obras, Finanzas, Materiales, ia-worker            S3 ←─ URL firmada (Obras, Materiales,
   n8n ── cola n8n.* ── SMTP ──→ Mailpit                  Ollama (interno)            Sincronización, navegador del ERP)
 PostgreSQL Flexible (obras_db, finanzas_db, keycloak_db) PostgreSQL reportes (interno)
                                                     MongoDB Atlas (sobre Google): materiales_db, ia_db
```

## Comunicación entre nubes

| Desde | Hacia | Protocolo | Autenticación | Variable |
|---|---|---|---|---|
| Navegador / app | Keycloak (Azure VM) | OIDC sobre HTTPS | — | configuración al compilar |
| ERP | Gateway (Azure) | GraphQL sobre HTTPS | token del usuario | configuración al compilar |
| Gateway | Obras, Finanzas (Azure), Materiales, IA (Google) | REST sobre HTTPS | token del usuario reenviado | `OBRAS_URL`, `FINANZAS_URL`, `MATERIALES_URL`, `IA_URL` |
| Portal | Obras | REST sobre HTTPS | token del cliente | `VITE_OBRAS_URL` |
| App | Sincronización (AWS) | REST sobre HTTPS | token del usuario + `X-Dispositivo-Id` | `EXPO_PUBLIC_SINCRONIZACION_URL` |
| Sincronización | Obras, Materiales | REST sobre HTTPS | token del usuario reenviado | `OBRAS_URL`, `MATERIALES_URL` |
| Sincronización | S3 | HTTPS | rol IAM de la función (prefijo `temporal/`) y URL firmadas de Obras y Materiales | `SINC_S3_BUCKET` |
| Navegador del ERP (303) | S3 | HTTPS con URL firmadas (`GET` y `PUT`) | firma de Obras | regla CORS del bucket |
| Obras, Finanzas, Materiales, `ia-worker`, n8n | RabbitMQ (Azure VM) | **AMQPS 5671** (n8n, en la misma VM, por la red interna) | usuario y contraseña por servicio | variables de RabbitMQ de cada proyecto, `IA_RABBITMQ_URL` |
| n8n | Finanzas | REST sobre HTTPS | token de la *service account* del cliente `n8n` (rol `automatizacion`) | `FINANZAS_URL` |
| n8n | Mailpit | SMTP (red interna) | — | credencial SMTP de n8n |
| IA | Obras, Finanzas, Materiales | MCP (HTTP streamable) sobre HTTPS | token de `ia-agentes` | `IA_*_MCP_URL` |
| IA | Materiales | REST sobre HTTPS | token del usuario (nombres de materiales, 503) | `IA_MATERIALES_URL` |
| Todos los servicios | Keycloak | HTTPS (JWKS) | — | `KEYCLOAK_URL` + `KEYCLOAK_REALM`, `IA_KEYCLOAK_ISSUER`, `OBRAS_KEYCLOAK_ISSUER` |
| Obras, Materiales | S3 | HTTPS (URL firmadas, `HeadObject` en 303) | usuario IAM con permiso solo sobre sus prefijos | `OBRAS_S3_*`, `MATERIALES_S3_*` |
| Materiales, IA | MongoDB Atlas | TLS | usuario por base | `MONGODB_URI`, `IA_MONGO_URL` |

- **Emisor único:** Keycloak publica `https://<host-azure>/auth/realms/supervision`. Keycloak corre con `KC_HOSTNAME=https://<host-azure>/auth`, `KC_HTTP_RELATIVE_PATH=/auth`, `KC_PROXY_HEADERS=xforwarded` y HTTP solo hacia Caddy. En los proyectos que usan `KEYCLOAK_URL` + `KEYCLOAK_REALM`, `KEYCLOAK_URL=https://<host-azure>/auth`. **(decisión del equipo)**
- **CORS:** el gateway acepta el origen del shell (los microfrontends corren dentro de la página del shell); Obras acepta el origen del portal; los remotos (`mf-*`) envían `Access-Control-Allow-Origin` del shell para sus archivos (`staticwebapp.config.json`); el bucket S3 acepta `GET` y `PUT` desde el origen del shell (303).
- **Listas de IP:** Container Apps (consumo), Cloud Run y Lambda no tienen IP de salida fija sin pagar NAT; por eso RabbitMQ (5671), Atlas y PostgreSQL Flexible aceptan conexiones de internet **solo con TLS y contraseña fuerte por servicio**. PostgreSQL Flexible permite además «servicios de Azure» y la IP de `vm-plataforma`. **(decisión del equipo; riesgo aceptado y documentado)**

## HTTPS y nombres

- Container Apps, Static Web Apps, Cloud Run y URL de Lambda: HTTPS y certificado incluidos en su dominio.
- `vm-plataforma`: etiqueta DNS de la IP pública de Azure y Caddy con Let's Encrypt. Rutas: `/auth/` → Keycloak, `/n8n/` → n8n (`N8N_PATH=/n8n/` y la URL pública del editor; confirmar las variables en la documentación de la versión fijada de n8n), `/rabbitmq/` → panel de RabbitMQ (`management.path_prefix = /rabbitmq`), `/mailpit/` → interfaz de Mailpit (`MP_WEBROOT=mailpit`) con autenticación básica de Caddy. RabbitMQ escucha AMQPS en 5671 con el mismo certificado (Caddy lo obtiene; se monta en solo lectura en RabbitMQ y un *script* reinicia RabbitMQ cuando se renueva). **(decisión del equipo)**
- `vm-ia`: IP estática y nombre `ia.<ip-con-guiones>.sslip.io` (servicio gratuito que resuelve el nombre a la IP) con Caddy y Let's Encrypt; si el equipo tiene un dominio, se usa un subdominio. Caddy solo publica `ia-api`. **(decisión del equipo)**
- Reglas de red: `vm-plataforma` abre 80, 443 y 5671; `vm-ia` abre 80 y 443; SSH solo por la consola de cada nube (Azure: `az vm run-command`; Google: IAP). No se publican fuera de Docker: Ollama (11434) y PostgreSQL (5432) en `vm-ia`; RabbitMQ 5672, n8n 5678 y Mailpit SMTP 1025 en `vm-plataforma`.

## Correo en producción (201)

- **Mailpit también en producción** como servidor SMTP de n8n, en `vm-plataforma`: los proveedores son datos de prueba con correos `.test` (seeder de la 201), así que un SMTP real rebotaría. Los correos quedan visibles en `/mailpit/` para la demostración. **(decisión del equipo)**
- Si el equipo quiere enviar correos reales, se cambia solo la credencial SMTP de n8n a un proveedor de correo transaccional con plan gratuito, con su contraseña en Key Vault, y se cargan proveedores con correos reales. No cambia ningún flujo.

## Secretos

| Nube | Gestor | Qué guarda | Cómo llega al servicio |
|---|---|---|---|
| Azure | Secretos de Container Apps, cargados desde **Azure Key Vault** (`kv-supervision`) con identidad administrada | Contraseñas de PostgreSQL y RabbitMQ de Obras y Finanzas, `APP_KEY` de Finanzas, secreto del cliente `gateway`, claves IAM de S3 de Obras | Referencia de Key Vault en la variable de entorno de la app |
| Azure (VM) | Key Vault | Administración de Keycloak, contraseñas de RabbitMQ (todos los usuarios), de `keycloak_db`, `N8N_ENCRYPTION_KEY`, secreto del cliente `n8n`, usuario y contraseña de la interfaz de Mailpit | Un *script* de arranque de la VM (identidad administrada + `az keyvault secret show`) escribe el `.env` de Compose con permisos `600` |
| Google | **Secret Manager** | `MONGODB_URI` de Materiales, `IA_MONGO_URL`, contraseñas de RabbitMQ de Materiales e IA, `IA_AGENTES_CLIENT_SECRET`, claves IAM de S3 de Materiales, contraseñas de `reportes_db` (`ia` e `ia_reportes_lector`) | Cloud Run: `--set-secrets`; `vm-ia`: *script* de arranque con la cuenta de servicio de la VM que escribe el `.env` (`600`) |
| AWS | **SSM Parameter Store** (`SecureString`, nivel estándar) | Nada sensible por ahora: la Lambda usa su rol IAM para DynamoDB y S3; parámetros con las URL | Variables de la función (cifradas con KMS por defecto) |
| GitHub | **GitHub Secrets** (entorno `produccion`) | Solo lo que necesita el workflow (601) | — |

- Contraseñas generadas al azar (32 caracteres), una por servicio y por base. Los usuarios de prueba de Keycloak (`Prueba123!`) **no** se importan en producción: se crean usuarios de demostración con otras contraseñas.

## Configuración por proyecto en producción

Nombres de variables de 601.

| Proyecto | Valores clave |
|---|---|
| Obras | `OBRAS_DB_HOST=<servidor>.postgres.database.azure.com`, `OBRAS_DB_PORT=5432`, `OBRAS_DB_SSLMODE=require`, `OBRAS_RABBITMQ_HOST=<host-azure>`, `OBRAS_RABBITMQ_PORT=5671`, `OBRAS_RABBITMQ_SSL=true`, `OBRAS_S3_ENDPOINT` vacío, `OBRAS_S3_REGION=sa-east-1`, `OBRAS_S3_BUCKET=supervision-<sufijo>`, `OBRAS_KEYCLOAK_ISSUER`, `OBRAS_CORS_ORIGENES=<portal>` |
| Finanzas | `DB_HOST`, `DB_PORT=5432`, `DB_SSLMODE=require`, `RABBITMQ_HOST=<host-azure>`, `RABBITMQ_PORT=5671`, `RABBITMQ_SSL=true`, `APP_ENV=production`, `APP_DEBUG=false`, `LOG_CHANNEL=stderr`; `finanzas-worker` con el comando de los procesos en segundo plano |
| Gateway | `OBRAS_URL`, `FINANZAS_URL`, `MATERIALES_URL`, `IA_URL` públicas; `KEYCLOAK_URL=https://<host-azure>/auth`; `CORS_ORIGENES=<shell>` |
| Materiales | `MONGODB_URI=mongodb+srv://…/materiales_db`, `RABBITMQ_URL=amqps://materiales:…@<host-azure>:5671`, `MATERIALES_S3_ENDPOINT` vacío, `MATERIALES_S3_REGION=sa-east-1`, `MATERIALES_S3_BUCKET=supervision-<sufijo>`, `KEYCLOAK_URL` |
| IA (`ia-api` e `ia-worker`) | `IA_REPORTES_DB_URL=postgresql+psycopg://ia:…@postgres-reportes:5432/reportes_db` (red interna), `IA_REPORTES_DB_URL_LECTURA` (usuario `ia_reportes_lector`), `IA_MONGO_URL=mongodb+srv://…`, `IA_MONGO_DB=ia_db`, `IA_RABBITMQ_URL=amqps://ia:…@<host-azure>:5671/`, `IA_KEYCLOAK_ISSUER=https://<host-azure>/auth/realms/supervision`, `IA_OLLAMA_URL=http://ollama:11434`, `IA_OLLAMA_MODELO=qwen3:8b`, `IA_*_MCP_URL` públicas (`…/mcp`), `IA_MATERIALES_URL` |
| Sincronización | `PORT=8084`, `KEYCLOAK_URL`, `KEYCLOAK_REALM=supervision`, `AUDIENCIA=plataforma-api`, `OBRAS_URL`, `MATERIALES_URL`, `DYNAMODB_ENDPOINT` vacío, `DYNAMODB_CREAR_TABLAS=false`, `TIEMPO_MAXIMO_LLAMADA_MS=5000`, `TIEMPO_MAXIMO_LOTE_MS=20000`, `SINC_S3_ENDPOINT` vacío, `SINC_S3_BUCKET=supervision-<sufijo>`, `SINC_S3_ACCESS_KEY` y `SINC_S3_SECRET_KEY` vacías (rol), `AWS_LWA_PORT=8084`, `AWS_LWA_READINESS_CHECK_PATH=/salud` |
| n8n | `GENERIC_TIMEZONE=America/La_Paz`, `N8N_ENCRYPTION_KEY`, `N8N_PATH=/n8n/`, `FINANZAS_URL` (pública), `COMPRAS_CORREO_REMITENTE`, `EMPRESA_NOMBRE`; credenciales de n8n (RabbitMQ `n8n`, OAuth2 con el cliente `n8n` y la URL de token pública, SMTP Mailpit) creadas desde su panel como indica el README de la 201 |
| Frontends | shell: Keycloak, gateway, portal y remotos de producción; mf-supervision: `DICTADO_MODELO_URL` vacío (el modelo Whisper se descarga de Hugging Face, como la 302 por defecto) **(decisión del equipo)** |
| App | `EXPO_PUBLIC_KEYCLOAK_URL`, `EXPO_PUBLIC_SINCRONIZACION_URL` (URL de la función) |
| Keycloak (realm) | Roles de realm del sistema base más `agente_ia` (501) y `automatizacion` (201). Clientes `erp` y `portal` con *redirect URIs* y *web origins* de las Static Web Apps; `app-obra` igual; confidenciales `gateway`, `ia-agentes` y `n8n` con secretos nuevos. El realm de producción se importa desde el mismo JSON con marcadores `${…}` sustituidos por variables de entorno (comprobar el soporte en la documentación de Keycloak 26; si no, un JSON aparte `realm-supervision-produccion.json` sin usuarios de prueba) |

## Static Web Apps (`staticwebapp.config.json`)

- `navigationFallback` a `index.html` (rutas de cada aplicación).
- Encabezados: `Access-Control-Allow-Origin: <shell>` en los remotos; `Cache-Control: no-cache` en `index.html`, `ngsw.json`, `ngsw-worker.js` (service worker de la 104) y `federation.manifest.json`, para que una versión nueva se tome al recargar.

## RabbitMQ en producción

- Exchange `plataforma` y colas durables desde el archivo de definiciones de infra: `obras`, `materiales`, `finanzas`, `ia` (401), `n8n.stock-bajo` y `n8n.compra-recibida` (201) y `plataforma.fallidos`, con sus enlaces.
- Un usuario por servicio (`obras`, `finanzas`, `materiales`, `ia`, `n8n`) con permisos solo sobre sus colas y el exchange `plataforma` (`n8n`: leer `n8n.*`). Se elimina el usuario `guest`.
- Puerto 5672 sin TLS cerrado hacia afuera (solo en la red de Docker para n8n); 5671 con TLS abierto.
- Si `vm-ia` está apagada, los eventos se acumulan en la cola `ia` y `ia-worker` los procesa al volver (401, criterio 13).

## Bases de datos y archivos

- **PostgreSQL Flexible (Azure):** bases `obras_db`, `finanzas_db`, `keycloak_db`; usuarios `obras`, `finanzas`, `keycloak`, cada uno dueño solo de su base; `require_secure_transport = on`. Copias automáticas del servicio (retención por defecto).
- **Atlas M0:** bases `materiales_db` (usuario `materiales`) e `ia_db` (usuario `ia`), cada usuario con `readWrite` solo en su base.
- **reportes_db (vm-ia):** contenedor PostgreSQL 16 con volumen; usuario `ia` (401, escribe) e `ia_reportes_lector` (503, solo lectura). Copia diaria con `pg_dump` a un bucket de Cloud Storage (opcional, si sobra crédito).
- **DynamoDB:** `operacion_procesada` (clave `id_operacion`, TTL en `expira_en`), `estado_dispositivo` (clave `id_dispositivo`) y `subida_archivo` (clave `id_subida`, TTL en `expira_en`), las tres bajo demanda y creadas por los *scripts* de infra (en producción `DYNAMODB_CREAR_TABLAS=false`).
- **S3:** bucket privado y cifrado por defecto, con los prefijos de las specs: `fotos/` (005), `fotos-cliente/` (303), `notas-remision/` (102) y `temporal/subidas/` (102) con regla de ciclo de vida que borra a los 7 días. Regla CORS: `GET` y `PUT` desde el origen del shell.
- **Permisos IAM:**

| Identidad | Permisos |
|---|---|
| Usuario `obras-s3` (claves en Key Vault) | `s3:PutObject`, `s3:GetObject` en `fotos/*` y `fotos-cliente/*`; `HeadObject` (303) |
| Usuario `materiales-s3` (claves en Secret Manager) | `s3:PutObject`, `s3:GetObject` en `notas-remision/*` |
| Rol de la función `sincronizacion` | `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` en `temporal/*`; `dynamodb:PutItem`, `GetItem`, `UpdateItem`, `DeleteItem` en las tres tablas; registros en CloudWatch |

## Orden para levantar todo

1. Cuentas, créditos, grupo de recursos `rg-supervision` (Azure), proyecto `supervision-obras` (Google), cuenta AWS; **alertas de presupuesto** en las tres (Azure Cost Management, Google Billing Budgets, AWS Budgets) con aviso al 50 %, 80 % y 100 % del monto que decida el equipo.
2. Identidades OIDC para GitHub (601).
3. Datos: PostgreSQL Flexible, Atlas, S3 (bucket, ciclo de vida, CORS), DynamoDB (tres tablas), Key Vault, Secret Manager.
4. `vm-plataforma`: Docker, Compose de producción (Caddy, Keycloak, RabbitMQ, n8n, Mailpit), realm de producción, definiciones de RabbitMQ, importación de los flujos de n8n (201) y creación de sus credenciales.
5. `vm-ia`: Docker, Compose de producción (Caddy, `ia-api`, `ia-worker`, Ollama, PostgreSQL de reportes) y `ollama pull qwen3:8b`.
6. Registros (Artifact Registry `supervision`, ECR `supervision-ms-sincronizacion`), entorno de Container Apps, servicio de Cloud Run, función Lambda con su URL y las cinco Static Web Apps.
7. Primer despliegue de cada repositorio con su workflow (601).
8. Prueba de humo y prueba de punta a punta.

Todo lo creado a mano se anota como comandos `az`, `gcloud` y `aws` en `infra/nube/` (*scripts* versionados, ejecutables de nuevo). Terraform queda fuera por tiempo. **(decisión del equipo)**

## Ahorro y operación

- `infra/nube/apagar.sh` y `encender.sh`: detienen y arrancan `vm-plataforma` y `vm-ia`, ponen el mínimo de réplicas de Obras y `finanzas-worker` en 0 (y de vuelta en 1) y Materiales en 0 instancias mínimas. Con todo apagado no se pierden eventos: las colas son durables.
- Registros: Container Apps → Log Analytics; Cloud Run y VM de Google → Cloud Logging (agente de operaciones en `vm-ia`); Lambda → CloudWatch Logs con retención de 7 días.
- Volver atrás: ejecutar el workflow del repositorio con la etiqueta anterior (`workflow_dispatch`, entrada `etiqueta`) o, en Container Apps, activar la revisión anterior.

## Prueba de humo (`infra/nube/prueba-humo.sh`)

1. `GET /salud` de Obras, Finanzas, Materiales, IA (`ia-api`) y Sincronización → `200`.
2. `POST /graphql { salud }` al gateway → `200`.
3. Tokens por *client credentials* de `ia-agentes` (contiene `agente_ia`) y de `n8n` (contiene `automatizacion`).
4. `POST /mcp` de Obras, Materiales y Finanzas sin token → `401`; con el token de `ia-agentes`, `tools/list` → las herramientas de la 501.
5. Página inicial del shell y del portal → `200`; `remoteEntry.json` de cada remoto con el encabezado CORS del shell.
6. Conexión AMQPS a 5671 con el usuario de prueba de humo → TLS válido; las colas `ia`, `n8n.stock-bajo` y `n8n.compra-recibida` existen.
7. Sincronización con un usuario de demostración `maestro`: `POST /subidas` de un archivo de prueba de 300 KB (2 partes), `PUT` de las dos partes binarias y `GET /subidas/{id}` con `partesRecibidas = [0, 1]`; la prueba de punta a punta completa la subida y comprueba la huella (punto a comprobar del adaptador de Lambda).

## Pruebas

- Prueba de humo en verde después de cada despliegue completo.
- Prueba manual de punta a punta, con capturas para el documento del proyecto: ERP (lista de obras, registrar obra, tablero), portal con aprobación de planilla (saga entre Azure y Google), app con un movimiento y una foto sin señal que llegan una sola vez (101, 102), compra automática por stock bajo con el correo visible en Mailpit y la cuenta por pagar creada (201), reporte por voz y una ejecución de agente (capa 5).
- Revisión de seguridad: `nmap` desde fuera a las dos VM (solo 80, 443 y 5671 en `vm-plataforma`; 80 y 443 en `vm-ia`); intento de conexión a 5672, 5678, 1025, 11434 y 5432 desde internet → rechazado; búsqueda de secretos en las imágenes (`docker history`, `docker run … env`).

## Cambios a contratos y datos

### `docs/arquitectura.md` («Despliegue»)

Reemplazar la tabla «Despliegue (propuesta, capa 6)» por el «Mapa del despliegue» de este diseño (servicio concreto, tamaño y URL por pieza), con la tabla de límites de Lambda frente a la 101 y la 102, y agregar la tabla «Comunicación entre nubes». Agregar las notas: «App Runner no admite clientes nuevos desde el 30/04/2026; Sincronización usa Lambda con imagen de contenedor y AWS Lambda Web Adapter (plan B: ECS Express Mode)» y «IA: `ia-api` e `ia-worker` en una VM junto a Ollama».

### `docs/convenciones.md`

- «Autenticación y permisos»: emisor público de producción `https://<host-azure>/auth/realms/supervision`.
- «Eventos y comandos»: en producción, AMQPS en 5671 y un usuario de RabbitMQ por servicio (incluidos `ia` y `n8n`).
- «Archivos»: en producción, bucket S3 `supervision-<sufijo>` en `sa-east-1`, privado, con los prefijos `fotos/`, `fotos-cliente/`, `notas-remision/` y `temporal/subidas/` (7 días) y CORS para el shell; en desarrollo se usa el bucket `supervision-dev-<sufijo>` (`docs/entorno-local.md`).
- Nueva sección «Secretos en producción»: tabla de gestores por nube de este diseño.

### `docs/reglas-negocio.md` («Compras automáticas (capa 2)»)

- Agregar: «En producción el correo al proveedor se captura en Mailpit (los proveedores de prueba tienen correos `.test`); enviar correos reales es una decisión del equipo que solo cambia la credencial SMTP de n8n».

### `docs/puntos.md` (fila «Despliegue en 3 nubes»)

- «Cómo»: AWS (Lambda + DynamoDB + S3), Google Cloud (VM con IA —`ia-api`, `ia-worker`— y Ollama, Cloud Run con Materiales, MongoDB Atlas), Azure (Container Apps con gateway, Obras y Finanzas; VM con Keycloak, RabbitMQ, n8n y Mailpit; Static Web Apps; PostgreSQL Flexible). Quitar «Reparto propuesto».

### `infra/docs/contratos.md` (cuando exista)

- Puertos públicos de las VM, rutas de Caddy (`/auth/`, `/n8n/`, `/rabbitmq/`, `/mailpit/`), usuarios de RabbitMQ y bases por servicio, tablas de DynamoDB y prefijos del bucket.
