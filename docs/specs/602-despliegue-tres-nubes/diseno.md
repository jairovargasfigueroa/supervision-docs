# 602 · Diseño

## Criterios

1. **Lo mismo que el ensayo local.** La 601 ya corre la plataforma en tres grupos de Docker Compose con HTTPS y RabbitMQ por TLS (53 de 53 comprobaciones). Cada grupo pasa a una máquina virtual de su nube con los mismos *compose*: solo cambian las direcciones, los certificados y lo que en local reemplazaba a un servicio de AWS (DynamoDB Local y MinIO).
2. **Costo bajo:** una máquina por nube, **apagada** salvo para probar y para la presentación. Con la máquina apagada se paga solo su disco y su IP fija. Sin servicios administrados, que cobran aunque no se usen.
3. **Una región por nube, todas cerca de Ohio** (requisitos, decisión 8): AWS `us-east-2` (Ohio; la organización de la cuenta solo permite esa), Azure `northcentralus` (Chicago; la suscripción de prueba no permite máquinas pequeñas en `brazilsouth` ni en `eastus`) y Google `us-east5` (Columbus).
4. **Todo con *scripts* desde la PC de Jairo** (`infra/nube/`), repetibles y versionados. Nada se crea a mano en las consolas, salvo los registros DNS de Namecheap, el Gmail de la plataforma, Firebase y la clave de Anthropic.

## Mapa del despliegue

| Nube | Máquina | Tamaño | Disco | Puertos públicos | Qué corre |
|---|---|---|---|---|---|
| Azure (`rg-supervision`, `northcentralus`) | `vm-plataforma`, Ubuntu 24.04 LTS | B2als_v2: 2 vCPU, 4 GiB (+ 2 GiB de *swap*) | Standard SSD 32 GiB | 80, 443, 5671 (22 solo desde la IP de Jairo) | `compose.azure.yml`: Caddy (y los 5 frontends), Keycloak, gateway, Obras, `finanzas-api`, `finanzas-trabajos`, RabbitMQ, n8n, Mailpit y PostgreSQL (`obras_db`, `finanzas_db` y `keycloak_db`) |
| AWS (`us-east-2`) | `vm-sincronizacion`, Ubuntu 24.04 LTS | t3.micro: 2 vCPU, 1 GiB (+ 1 GiB de *swap*) | gp3 16 GiB | 80, 443 (22 solo desde la IP de Jairo) | `compose.aws.yml`: Caddy y Sincronización. Además, DynamoDB (tablas `operacion_procesada` y `estado_dispositivo`, bajo demanda) y el bucket S3 `supervision-obras-<sufijo>` |
| Google (proyecto `supervision-obras`, `us-east5`) | `vm-ia`, Ubuntu 24.04 LTS | e2-medium: 2 vCPU, 4 GB (con Anthropic); e2-standard-4 de 16 GB si se elige Ollama | Balanceado 30 GB | 80, 443 (22 solo desde la IP de Jairo) | `compose.google.yml`: Caddy, Materiales, `ia-api`, `ia-worker`, MongoDB (`materiales_db` e `ia_db`) y PostgreSQL de reportes |

- **Memoria medida en la 601:** el grupo de Azure usa ~2,7 GB y el de Google ~1,0 GB sin Ollama. Si la B2als_v2 se queda corta, se cambia a B2as_v2 (8 GiB) en unos minutos: desasignar, cambiar el tamaño y encender.
- Cada máquina tiene una **IP pública fija**: Azure, IP estática Standard; AWS, Elastic IP; Google, dirección externa estática. Así los registros DNS se ponen una sola vez.

## Nombres

Todo va bajo `supervision.workflow-tramites.site`, con los mismos nombres de pieza que el ensayo local (`<pieza>.<grupo>.localhost` → `<pieza>.supervision.workflow-tramites.site`):

| Nube | Nombres |
|---|---|
| Azure | `keycloak`, `gateway`, `obras`, `finanzas`, `erp`, `portal`, `mf-obras`, `mf-materiales`, `mf-supervision`, `n8n`, `mailpit`, `rabbitmq` |
| Google | `materiales`, `ia` |
| AWS | `sincronizacion` |

Registros A en Namecheap («Advanced DNS», TTL 5 min), que pone Jairo cuando existe cada IP. `node nube/nube.mjs dns` le muestra la lista exacta:

- Azure: `*.supervision` → IP de Azure. Si Namecheap no acepta el comodín en un subnivel, se pone un registro por cada uno de los 12 nombres.
- AWS: `sincronizacion.supervision` → IP de AWS.
- Google: `materiales.supervision` e `ia.supervision` → IP de Google. Un registro concreto gana sobre el comodín.

Los registros `api` y `sga-api` del dominio son de otro proyecto y no se tocan.

## Diagrama

```
                         Internet (navegador, app)
        ┌───────────────────────────┬───────────────────────────┬──────────────────────┐
        ▼                           ▼                           ▼                      ▼
AZURE · vm-plataforma            GOOGLE · vm-ia              AWS · vm-sincronizacion   AWS · S3
 Caddy :80/:443 ─ erp, mf-*, portal  Caddy :80/:443              Caddy :80/:443          (fotos, URL firmadas)
   ├ keycloak ◄──── tokens/JWKS ──── materiales ─┐               sincronizacion ──┐        ▲
   ├ gateway ──HTTPS──────────────►  ia-api      │                 │  DynamoDB ◄──┘ (rol)  │
   ├ obras ◄───HTTPS───────────────────────────────────────────────┘                       │
   ├ finanzas-api   finanzas-trabajos│  ia-worker ──HTTPS /mcp──► obras, finanzas          │
   ├ n8n ──SMTP 587──► Gmail         │  mongo, postgres-reportes (sin puerto)              │
   ├ mailpit (respaldo)              │                                                     │
   ├ rabbitmq :5671 ◄──AMQPS─────────┘ (materiales, ia-worker)          obras ─────────────┘
   └ postgres (sin puerto)
```

## Comunicación

| Origen | Destino | Protocolo y credencial |
|---|---|---|
| Navegador | `erp`, `mf-*`, `portal` (Caddy de Azure) | HTTPS |
| Navegador (shell y microfrontends) | `gateway` | HTTPS, GraphQL, token del usuario |
| Navegador (portal) | `obras` | HTTPS, REST, token del usuario |
| Navegador y app | `keycloak` | HTTPS, OIDC |
| Navegador y app | S3 | HTTPS, URL firmada por Obras |
| App | `sincronizacion` | HTTPS, REST, token del usuario |
| Gateway | Obras y Finanzas (misma máquina), Materiales e IA (Google) | HTTPS por nombre público, token reenviado o de servicio |
| Sincronización (AWS) | Obras (Azure) y Materiales (Google) | HTTPS, token reenviado |
| `ia-worker` (Google) | `/mcp` de Obras, Finanzas y Materiales, e `ia-api` por la red interna | HTTPS, token de `ia-agentes` |
| Obras, Finanzas, Materiales e `ia-worker` | RabbitMQ (Azure) | **AMQPS 5671**, un usuario por servicio |
| n8n | RabbitMQ y Mailpit | red interna de Docker (5672 y 1025) |
| n8n | Gmail | SMTP 587 con STARTTLS, contraseña de aplicación |
| n8n | Firebase Cloud Messaging | HTTPS, cuenta de servicio (010) |
| Obras | S3 | HTTPS, claves del usuario IAM `obras-s3` |
| Sincronización | DynamoDB | HTTPS, rol de la máquina (sin claves) |

- **Dentro de una misma máquina**, los nombres públicos de sus propias piezas apuntan al Caddy de la máquina (`extra_hosts: <nombre>:host-gateway`, como en la 601). La llamada usa el mismo nombre y el mismo certificado sin salir a internet. Los nombres de las otras nubes se resuelven por DNS público.

## Qué cambia respecto del ensayo local

Los *compose* de la nube viven en `infra/nube/` y se copian de los de `infra/produccion-local/` con estos cambios (el README de `nube/` los lista):

**En los tres grupos**

- Direcciones: las de «Nombres», en el puerto 443, desde el `.env` de la nube. Los Caddyfile usan las variables de entorno de Caddy (`{$KEYCLOAK_HOST}`…) en lugar de nombres fijos.
- Caddy escucha en 80 y 443 y saca un certificado de **Let's Encrypt** por nombre (desafío HTTP), con el correo de `ACME_CORREO`. Se quitan `local_certs`, la CA local (`pki`) y `disable_redirects`: HTTP redirige a HTTPS.
- Sin CA local: se quitan los montajes de `./certificados` en los servicios, `JAVA_TOOL_OPTIONS`, `NODE_EXTRA_CA_CERTS`, `IA_CA_EXTRA` y `finanzas/ca-local.ini`. `CA_LOCAL` queda vacío.
- Imágenes de GHCR con la etiqueta del release (`IMAGEN_ETIQUETA`, por defecto `main`), sin `build:`. Cada servicio acepta su propia etiqueta (`OBRAS_ETIQUETA`…) para volver atrás solo ese servicio con un `sha-<7>` anterior.
- Registros de Docker con rotación (10 MB × 3 por contenedor, en `daemon.json`) para no llenar el disco.

**Azure**

- Sin `finanzas-reenvio`: era solo por `*.localhost` (libcurl). Con un dominio real, PHP resuelve el nombre por `extra_hosts`.
- RabbitMQ usa el certificado que Caddy obtiene para `rabbitmq.supervision…`: `maquina/certificado-rabbitmq.sh` lo copia del volumen de Caddy a `certificados/rabbitmq.crt` y `.key` (dueño 999, permisos `600`). Su `tls.conf` toma como `cacertfile` las CA del sistema. El certificado vence a los 90 días: el *script* corre al desplegar, al encender y una vez al día (*timer* de systemd), y reinicia RabbitMQ solo si cambió.
- Mailpit queda detrás de autenticación básica en Caddy (`MAILPIT_USUARIO` y `MAILPIT_CLAVE_HASH`).
- n8n: el SMTP sale de variables (sección «Correo») y Firebase de sus tres variables (010). `COBRANZA_REMITENTE` y `COBRANZA_CORREO` son el Gmail de la plataforma.
- Keycloak: `USUARIOS_PRUEBA_CLAVE` es la contraseña nueva de los usuarios de prueba. `CLIENTE1_CORREO`, una variable nueva del realm, es el correo real de `cliente1` en la demostración.
- Obras: `OBRAS_S3_ENDPOINT` vacío (Amazon S3), `OBRAS_S3_REGION=us-east-2`, el bucket y las claves de `obras-s3`.
- Caddy sirve los frontends desde `sitios/`, que se compilan en la PC y se copian al desplegar.

**AWS**

- Sin `dynamodb`, `minio` ni `minio-init`. `s3-cli` (perfil `herramientas`) se queda para subir las fotos de demostración desde la PC.
- Sincronización: `DYNAMODB_ENDPOINT` vacío, `AWS_REGION=us-east-2`, sin claves (el SDK toma el rol de la máquina por IMDSv2, con límite de saltos 2 para que llegue al contenedor) y `DYNAMODB_CREAR_TABLAS=false`.

**Google**

- MongoDB: `MONGO_IMAGEN=mongo:8.0` si el *kernel* de la máquina es menor que 6.19. Si no, `mongo:7.0`, como el CI de IA (pendiente de la 601, SERVER-125742). Se comprueba con `uname -r` al crearla.
- `IA_LLM_PROVEEDOR=anthropic` con `IA_ANTHROPIC_API_KEY`, o el perfil `ollama` si se elige Ollama. `IA_MCP_HOSTS_PERMITIDOS` lleva `ia.supervision.workflow-tramites.site`.

## Carpeta `infra/nube/` y el comando `nube.mjs`

```
nube/
  nube.mjs                 comando único (Node 24, sin dependencias): node nube/nube.mjs <acción> [nube]
  lib/                     comun.mjs, azure.mjs, aws.mjs, google.mjs, ssh.mjs
  compose.azure.yml · compose.google.yml · compose.aws.yml
  caddy/                   Caddyfile por nube, comun.caddy y global.caddy (Let's Encrypt)
  rabbitmq/tls.conf
  maquina/cloud-init.yaml  Docker Engine y su plugin de Compose (repositorio oficial de Docker), swap, rotación de
                           registros, usuario supervision en el grupo docker, carpeta /opt/supervision, timer del certificado
  maquina/certificado-rabbitmq.sh
  .env.example             variables de las tres nubes, sin secretos
  README.md
  .env, sitios/            no se suben (.gitignore)
```

Los *scripts* son de Node y no de PowerShell y Bash duplicados (excepción a la regla de infra): llaman a `az`, `aws`, `gcloud`, `ssh` y `scp`, y Node corre igual en Windows y en Linux.

| Acción | Qué hace |
|---|---|
| `secretos` | Crea `nube/.env` desde `.env.example` y llena los secretos vacíos con valores al azar (32 caracteres; los hashes de n8n y Mailpit, con las imágenes de n8n y Caddy). Nunca cambia uno que ya existe. Crea la clave SSH `~/.ssh/supervision_nube` si no existe |
| `crear <nube> [--datos]` | Crea los recursos de esa nube. Si un recurso ya existe, lo deja. En AWS, `--datos` crea solo el bucket, las tablas y los permisos |
| `desplegar <nube>` | Copia por SSH el *compose*, Caddy y un `.env` **solo con las variables de esa nube** (permisos `600`) a `/opt/supervision`. Después hace `docker compose pull`, levanta Caddy, espera los certificados, levanta el resto y espera a que todo esté sano. En Azure, antes compila y copia los frontends |
| `encender <nube\|todas>` | Enciende la máquina, cambia la regla del 22 a la IP actual de Jairo, renueva la copia del certificado de RabbitMQ y espera a que todo esté sano. `todas`: Azure primero (Keycloak y RabbitMQ), después Google y AWS |
| `apagar <nube\|todas>` | Azure: `az vm deallocate` (detenerla sin desasignar sigue cobrando); AWS y Google: detener la instancia |
| `estado [nube]` | Estado de cada máquina, su IP, sus contenedores y `GET /salud` de cada servicio |
| `registros <nube> [servicio]` | `docker compose logs` en esa máquina |
| `ssh <nube>` | Abre una sesión en la máquina |
| `dns` | Lista los registros A que van en Namecheap, con las IP actuales |
| `contextos` | Crea los contextos de Docker `supervision-azure`, `-google` y `-aws` (`ssh://supervision@<ip>`) para la semilla |

## Qué crea cada nube

**Azure** (`crear azure`)

- Registra los proveedores `Microsoft.Compute`, `Microsoft.Network` y `Microsoft.Storage`: la suscripción es nueva y no los tiene. Revisa la cuota de vCPU en la región.
- Grupo de recursos `rg-supervision`; NSG `nsg-plataforma` (80, 443 y 5671 desde internet; 22 desde la IP de Jairo); IP estática `ip-plataforma`; red `vnet-plataforma`.
- VM `vm-plataforma` (`Canonical:ubuntu-24_04-lts:server:latest`, B2als_v2, disco Standard SSD de 32 GiB), con el usuario `supervision`, la clave SSH y `cloud-init.yaml`.
- Presupuesto mensual de $50 con avisos al 50, 80 y 100 % a `NUBE_ALERTAS_CORREO`. Si la CLI no lo permite en la cuenta de prueba, el README da los pasos en el portal. La suscripción de prueba tiene además el límite de gasto activado: al acabarse el crédito, Azure apaga los recursos en lugar de cobrar.

**AWS** (`crear aws --datos`, después `crear aws`)

- Bucket `supervision-obras-<sufijo>` en `us-east-2`: privado (bloqueo de acceso público), cifrado por defecto, con CORS `GET` y `HEAD` desde `ERP_URL` y `PORTAL_URL` (las galerías piden las fotos con URL firmadas). Solo usa el prefijo `fotos/` (005).
- Tablas `operacion_procesada` (clave `id_operacion`, TTL en `expira_en`) y `estado_dispositivo` (clave `id_dispositivo`), bajo demanda, como las define `tablas.ts` de Sincronización.
- Usuario IAM `obras-s3` con `s3:PutObject` y `s3:GetObject` en `<bucket>/fotos/*`. Su clave de acceso se escribe directo en `nube/.env`.
- Rol `sincronizacion-ec2` (con su perfil de instancia) con `dynamodb:GetItem`, `PutItem`, `UpdateItem` y `DeleteItem` en las dos tablas.
- Presupuesto mensual de $20 con avisos al 50, 80 y 100 % a `NUBE_ALERTAS_CORREO`.
- Máquina: grupo de seguridad `supervision-sincronizacion` (80 y 443; 22 desde la IP de Jairo), par de claves `supervision-nube` (la clave pública de la PC), EC2 t3.micro con la AMI de Ubuntu 24.04 del parámetro público de Canonical en SSM (`/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id`), gp3 de 16 GiB, IMDSv2 obligatorio con límite de saltos 2, el perfil de instancia, `cloud-init.yaml` como *user data* y una Elastic IP asociada.

**Google** (`crear google`, cuando esté la cuenta)

- Proyecto `supervision-obras` con la API de Compute Engine; reglas de *firewall* (80 y 443; 22 desde la IP de Jairo); dirección estática; VM `vm-ia` (familia `ubuntu-2404-lts-amd64` de `ubuntu-os-cloud`, disco balanceado de 30 GB), con la clave SSH y `cloud-init.yaml` en los metadatos; presupuesto.

## Secretos

- Todos en `infra/nube/.env` de la PC de Jairo (no se sube). Ahí están también las contraseñas en claro para entrar a los paneles (`N8N_PROPIETARIO_CLAVE`, `MAILPIT_CLAVE`, `KEYCLOAK_ADMIN_CLAVE`, `RABBITMQ_ADMIN_CLAVE` y `USUARIOS_PRUEBA_CLAVE`), que no se copian a las máquinas cuando no las necesitan.
- **Jairo guarda una copia de `nube/.env`.** Las bases se crean con esas contraseñas: sin el archivo no se puede volver a desplegar sin reiniciar los datos.
- Cada máquina recibe en `/opt/supervision/.env` (permisos `600`) solo las variables de su grupo. La lista por nube está en `lib/comun.mjs`.
- `USUARIOS_PRUEBA_CLAVE` es fácil de escribir en el celular, por ejemplo dos palabras y cuatro dígitos, y distinta de `Prueba123!`. Keycloak la toma solo al importar el realm por primera vez; después se cambia desde la consola de Keycloak.

## Correo

- **Gmail de la plataforma** (lo crea Jairo): verificación en dos pasos y una contraseña de aplicación. Variables nuevas en n8n: `SMTP_HOST=smtp.gmail.com`, `SMTP_PUERTO=587`, `SMTP_SEGURO=false` (STARTTLS), `SMTP_USUARIO=<gmail>` y `SMTP_CLAVE=<contraseña de aplicación>`. En desarrollo y en el ensayo local los valores por defecto son los de Mailpit (`mailpit`, 1025, sin TLS ni usuario).
- La credencial SMTP del repositorio (`n8n/credenciales/smtp-mailpit.json` → `smtp.json`) queda sin esos campos, y `n8n/secretos.sh` los pasa por `CREDENTIALS_OVERWRITE_DATA`, que solo llena los campos vacíos.
- El correo de los avisos al cliente sale de Keycloak (el usuario `cliente` de la obra). En la nube, `CLIENTE1_CORREO` pone ahí un buzón real de Jairo.
- Azure solo bloquea la salida por el puerto 25, así que 587 funciona. Gmail permite unos 500 destinatarios al día, de sobra para la demostración.
- Mailpit queda desplegado como respaldo: para volver a él basta con dejar las variables `SMTP_*` con sus valores por defecto y volver a desplegar Azure.

## App (APK) y Firebase

- **APK que apunta a la nube**, compilado en la PC: `EXPO_PUBLIC_KEYCLOAK_URL=https://keycloak.supervision.workflow-tramites.site`, `EXPO_PUBLIC_SINCRONIZACION_URL=https://sincronizacion.supervision.workflow-tramites.site` y, si existe, `GOOGLE_SERVICES_JSON`. Después, `npx expo prebuild --clean` y `gradlew assembleRelease`.
  - El APK queda firmado con la clave de depuración, que es lo que trae la plantilla de Expo; se comprueba al implementar.
  - Se instala por cable (`adb install -r`) o pasando el archivo. Lo hace `scripts/apk-nube.ps1` de app-obra.
  - Reemplaza a la *development build* del celular (mismo paquete).
- **Firebase** (010, «Configuración de Firebase»): cuando Jairo cree el proyecto, sus tres variables van en `nube/.env` (Azure) y el `google-services.json` se usa al compilar el APK. Ninguno de los dos se sube.

## Imágenes y release

- Antes de desplegar: **release `v1.0.0`** en todos los repositorios, con Git Flow: `release/1.0.0` desde `develop`, PR a `main`, etiqueta y `main` de vuelta a `develop`. Al fusionar en `main`, el CI de la 601 publica en GHCR `sha-<7>` y `main`.
- Los paquetes de GHCR tienen que ser **públicos** para descargarlos sin iniciar sesión (los repositorios lo son). Se revisa al publicar y, si alguno quedó privado, se cambia en GitHub.
- Los frontends se compilan desde `main` de cada uno con `publicar-frontends`, que recibe dos opciones nuevas: `--entorno nube/.env` y `--destino nube/sitios`. El mismo paso ajusta el `ngsw.json` del shell con las direcciones de los remotos de la nube (pendiente de la 601).

## Datos de demostración (con las tres nubes)

- La semilla en modo demostración (601, `SEMILLA_DEMO=si`) corre desde la PC. Para cada servicio usa `docker compose run` con su imagen **dentro de su máquina**, por medio de un contexto de Docker por SSH. Variables nuevas: `SEMILLA_CONTEXTO_OBRAS`, `SEMILLA_CONTEXTO_FINANZAS` y `SEMILLA_CONTEXTO_MATERIALES`; vacías, usa el Docker local, como en la 601. Los servicios de la nube no montan archivos locales, así que el mismo *compose* sirve por SSH.
- Las fotos se suben con `s3-cli` en la PC, contra S3 real, con las claves de `obras-s3` y `AWS_ENDPOINT_URL` vacío.
- Después corre `ia-carga-inicial` en la máquina de Google, también por su contexto.
- Los usuarios de Keycloak salen de la importación del realm, con la contraseña nueva.

## Encender, apagar y costo

- Docker arranca con la máquina y los contenedores tienen `restart: unless-stopped`: al encender todo vuelve solo. Keycloak tarda unos minutos.
- Con las máquinas apagadas, los eventos esperan en las colas durables de RabbitMQ (401, criterio 13).

| Recurso | Precio | Se paga |
|---|---|---|
| Azure B2als_v2 en `northcentralus` | $0,0468/h (precio de lista consultado el 08/11/2026) | encendida |
| AWS t3.micro en `us-east-2` | $0,0104/h (consultado el 08/11/2026) | encendida |
| Google e2-medium en `us-east5` | se confirma al crear | encendida |
| IP pública fija (una por nube) | $0,005/h cada una (~$3,60 al mes) | siempre |
| Discos | unos pocos dólares al mes en total; se confirma al crear | siempre |
| DynamoDB bajo demanda y S3 | centavos con el uso de la demostración | por uso |

Ejemplo: 40 horas encendidas en el mes cuestan unos $2,30 de máquinas (Azure y AWS), más las IP y los discos. Lo cubren el crédito de Azure ($200 hasta el 04/12/2026) y los créditos del plan gratuito de AWS.

## Orden

0. Aprobar esta spec y aplicar «Cambios a contratos y datos».
1. **Preparación (código):** `infra/nube/` completo, los cambios a la semilla, `publicar-frontends`, la prueba de humo, la credencial SMTP de n8n, `CLIENTE1_CORREO` en el realm y el *script* del APK. El ensayo local de la 601 tiene que seguir pasando 53 de 53.
2. **AWS, datos:** `secretos` y `crear aws --datos`.
3. **Release `v1.0.0`** (imágenes en GHCR).
4. **Azure:** `crear azure`, registros DNS (Jairo), `desplegar azure` y la prueba de humo con `--sin-google`.
5. **AWS, máquina:** `crear aws`, registro DNS (Jairo), `desplegar aws` y la prueba de humo.
6. **Google, cuando esté la cuenta:** `crear google`, registros DNS, `desplegar google`, la semilla de demostración, la carga inicial, la prueba de humo `--completa`, el APK y las pruebas manuales.
7. **Firebase, cuando Jairo cree el proyecto:** variables en `nube/.env`, `desplegar azure` y el APK con `google-services.json`.

Al terminar cada sesión de trabajo: `apagar todas`.

**Lo que hace Jairo a mano:** crear el Gmail de la plataforma y su contraseña de aplicación, los registros DNS en Namecheap, el proyecto de Firebase, la cuenta de Google Cloud y la clave de Anthropic con límite de gasto (paso 6), y las pruebas manuales.

## Prueba de humo (cambios a `humo-despliegue.mjs`)

- `--sin-google`: omite las comprobaciones de Materiales e IA y lo dice en el resumen (pasos 4 y 5).
- Mailpit con autenticación básica si están `MAILPIT_USUARIO` y `MAILPIT_CLAVE`.
- Si el SMTP no es Mailpit (`SMTP_HOST` distinto de `mailpit`), `--completa` comprueba el envío `NOTA_COBRO` que n8n registra en Finanzas (los `envios` del cobro, con la misma consulta de la pestaña «Cobros» del ERP por el gateway) en lugar del correo en Mailpit.
- Puertos cerrados: desde la PC, intenta conectarse a los puertos internos de cada máquina (5432, 5672, 15672, 5678, 1025, 8025, 8080, 8081, 8082, 8083, 8084, 8085, 4000, 27017 y 11434) y espera que fallen.

## Pruebas

- Prueba de humo en verde al terminar cada paso del «Orden»: con `--sin-google` en los pasos 4 y 5, y completa en el 6.
- **Pruebas manuales de Jairo** (con las tres nubes y capturas para el documento):
  - ERP: `admin` ve la lista de obras, registra una obra con insumos y abre el tablero; el residente presenta una planilla.
  - Portal: `cliente1` aprueba la planilla. Se emite el cobro y la nota de cobro llega al buzón real.
  - App (APK): el maestro y el almacenero inician sesión. En modo avión registran una salida de material y una foto; al volver la señal llegan una sola vez y la foto se ve en la galería del ERP.
  - Con Firebase: el aviso de stock bajo llega al celular.
  - IA: un reporte por voz y la pestaña «Agentes» de una obra.
  - Al terminar, `apagar todas` y `estado` muestra las máquinas apagadas.
- Ningún secreto en el repositorio: búsqueda de los valores de `nube/.env` en los commits del trabajo antes de cada PR.

## Cambios a contratos y datos

### `docs/arquitectura.md` («Despliegue»)

Reemplazar la tabla «Despliegue (propuesta, capa 6)» por el «Mapa del despliegue» y la tabla «Comunicación» de este diseño. Agregar: una máquina por nube con Docker Compose y Caddy (Let's Encrypt), AWS en Ohio, Azure en Chicago y Google en Columbus, nombres bajo `supervision.workflow-tramites.site`, y las máquinas apagadas fuera de las pruebas.

### `docs/convenciones.md`

- «Autenticación y permisos»: emisor público de producción `https://keycloak.supervision.workflow-tramites.site/realms/supervision`.
- «Archivos»: el bucket de producción es `supervision-obras-<sufijo>` en `us-east-2`, con el prefijo `fotos/`.
- Sección nueva «Secretos en producción»: `infra/nube/.env` en la PC (no se sube) y un `.env` por máquina (`600`) solo con las variables de su grupo.
- «Avisos» o el apartado de correo: SMTP por variables (`SMTP_*`); Gmail de la plataforma en la nube y Mailpit en desarrollo.

### `docs/entorno-local.md`

Variables nuevas (`SMTP_*`, `CLIENTE1_CORREO`, `SEMILLA_CONTEXTO_*`, `MAILPIT_USUARIO` y `MAILPIT_CLAVE_HASH`, `MONGO_IMAGEN` y `ACME_CORREO`) y una sección «Nube» que remite a `infra/nube/README.md`.

### `docs/datos-prueba.md`

En la nube, los usuarios de prueba usan `USUARIOS_PRUEBA_CLAVE` y el correo de `cliente1` es `CLIENTE1_CORREO`.

### `docs/puntos.md` (fila «Despliegue en 3 nubes»)

«Cómo»: Azure (máquina con gateway, Obras, Finanzas, Keycloak, RabbitMQ, n8n y las apps web), Google Cloud (máquina con Materiales e IA, y sus bases) y AWS (máquina con Sincronización, más DynamoDB y S3), cada una con Docker Compose y HTTPS de Let's Encrypt; AWS en Ohio, Azure en Chicago y Google en Columbus. Quitar «Reparto propuesto».

### `docs/stack.md`

Ubuntu 24.04 LTS, Docker Engine del repositorio oficial de Docker y Let's Encrypt por Caddy en la nube.

### `infra` (`docs/contratos.md`, `CLAUDE.md` y README)

Nombres públicos y puertos abiertos de cada máquina, las variables nuevas del realm (`CLIENTE1_CORREO`), la credencial SMTP por variables y la carpeta `nube/` con sus comandos.

### `docs/specs/601-contenedores-ci/` y `docs/plan.md`

- Los «Pendientes para reescribir» que dejó la 601 quedan resueltos aquí:
  - el `ngsw.json`, con `publicar-frontends --entorno`;
  - libcurl y `*.localhost`, que no aplica con un dominio real;
  - MongoDB y el *kernel*, con `MONGO_IMAGEN`;
  - Node y `localhost`, que no aplica: la nube usa nombres públicos.
- Fila de la 602 en el plan.
