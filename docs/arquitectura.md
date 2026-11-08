# Arquitectura

## Piezas

| Pieza | Tipo | Tecnología | Base de datos |
|---|---|---|---|
| App de obra | Aplicación móvil | React Native | Base local + cola de envíos (capa 1) |
| Portal del cliente | Aplicación web externa | React | — |
| ERP | Aplicación web interna | Shell Angular + microfrontends (Obras Angular, Materiales React, Supervisión React) con Native Federation | — |
| Keycloak | Identidad y SSO | Keycloak (OIDC) | Propia |
| Gateway GraphQL | BFF del ERP | NestJS | — |
| Obras | Microservicio | Spring Boot | PostgreSQL |
| Materiales | Microservicio | NestJS | MongoDB |
| Finanzas | Microservicio | Laravel | PostgreSQL |
| Sincronización | Microservicio (capa 1) | NestJS | DynamoDB |
| IA | Microservicio (capas 4 y 5) | Python 3.12 · FastAPI: procesos `ia-api` (REST y servidor MCP en `/mcp`, 8085) e `ia-worker` (cola `ia`, tareas programadas y **host de los agentes** con el cliente MCP) y el comando `ia-carga-inicial`, de la misma imagen; ML clásico en la capa 4 (XGBoost e Isolation Forest, en CPU); en la capa 5, **modelo de lenguaje por un puerto** (`ModeloLenguaje`) con dos adaptadores, Ollama local (`qwen3:8b`) o la API de Anthropic (`claude-sonnet-5-5`), elegido con `IA_LLM_PROVEEDOR` | PostgreSQL `reportes_db` (modelo de lectura, CQRS) y MongoDB `ia_db` (predicciones, consumos atípicos y, en la capa 5, ejecuciones de agentes, sugerencias, consultas de reportes y límite por minuto) |
| Ollama | Modelo de lenguaje local (capa 5, opcional) | `ollama/ollama:0.40.4` con `qwen3:8b` (perfil `ollama` de infra; GPU opcional); solo si `IA_LLM_PROVEEDOR=ollama` | — |
| RabbitMQ | Mensajería | RabbitMQ | — |
| n8n | Automatización: cobranza automática (capa 2, 201) y avisos al celular y al cliente (010) | n8n 2.43.7 (`n8nio/n8n`), flujos en `infra/n8n/flujos/`; sin base propia (en la 201 la idempotencia la da Finanzas; en la 010, cada flujo recuerda los últimos 500 `id` de sobre en sus datos estáticos). En desarrollo, el correo llega a Mailpit | — |
| Firebase Cloud Messaging | Avisos *push* a la app de obra (010) | Firebase (plan gratuito *Spark*), envío por **temas** (`obra-{obraId}-maestro`, `obra-{obraId}-almacenero`); ningún servicio guarda tokens de dispositivos. Opcional: sin Firebase configurado, no hay *push* | — |
| Almacenamiento de objetos | Fotos y notas de remisión | Amazon S3 (también en desarrollo, con un bucket propio); en el ensayo local de la 601, un S3 compatible (MinIO) con `OBRAS_S3_ENDPOINT` | — |

## Conexiones

| Desde | Hacia | Protocolo | Para qué |
|---|---|---|---|
| Las 3 aplicaciones | Keycloak | OIDC | Iniciar sesión y obtener el token |
| ERP (todos sus microfrontends) | Gateway | **GraphQL** | Toda la interacción del ERP |
| Gateway | Obras, Materiales, Finanzas, IA | REST | Resolver las consultas y mutaciones |
| Portal | Obras | REST | Ver avance y planillas; aprobar u observar |
| App de obra | Sincronización (capa 1) | REST | `POST /lotes`: enviar lo registrado (movimientos, fotos de avance y diario); desde la 101 la app ya no llama directo a Obras ni a Materiales |
| App de obra | Sincronización (capa 1) | REST | `GET /paquete-datos`: datos para trabajar sin señal |
| App de obra | Sincronización (capa 1) | REST | `POST /fotos/url-subida`: pedir la URL firmada para subir una foto de avance (102) |
| App de obra | Almacenamiento (S3) | HTTPS (`PUT` con URL firmada) | Subir la foto de avance completa, directo del celular (102) |
| Sincronización | Obras, Materiales | REST | Repartir lo recibido sin duplicar, armar el paquete de datos y pedir a Obras la URL firmada de la foto (con el token del usuario) |
| Obras, Materiales, Finanzas | RabbitMQ | AMQP | Eventos y comandos de la saga |
| RabbitMQ | IA (capa 4) | AMQP | Eventos para el modelo de lectura (`reportes_db`, 401) |
| IA (capa 4) | Obras, Materiales, Finanzas | REST (solo `GET`) | Carga inicial del modelo de lectura, una vez, con el cliente `ia-reportes` (401) |
| Gateway | IA (capas 4 y 5) | REST | Riesgo de retraso (402) y consumos atípicos (403), en lotes de hasta 100 obras para el tablero; reportes de las personas (503: con el directorio de clientes) y agentes (502) |
| IA (capa 5) | Materiales | REST (`GET /materiales`, con el token del usuario) | Nombres y unidades de los materiales en los reportes (503) |
| RabbitMQ | n8n (capa 2) | AMQP (colas `n8n.cobro-emitido` y `n8n.cobro-pagado`) | Eventos `CobroEmitido` y `CobroPagado`: enviar la nota de cobro y la constancia de pago (201) |
| n8n (capa 2) | Finanzas, Obras, Keycloak | REST, con el token de la *service account* del cliente `n8n` | Finanzas: recordatorios, nota de cobro en PDF y anotar los envíos; Obras: planilla y obra (`gerente`); Keycloak: nombre y correo del cliente (API de administración, `view-users`) (201) |
| n8n (capa 2) | Correo | SMTP | Nota de cobro, recordatorios, resumen del día y constancia de pago (Mailpit en desarrollo; servidor real en la nube, capa 6) (201) |
| RabbitMQ | n8n (010) | AMQP (colas `n8n.stock-bajo` y `n8n.planilla-presentada`) | Eventos `StockBajo` y `PlanillaPresentada`: aviso de stock bajo al almacenero y correo «planilla para revisar» al cliente (010) |
| n8n (010) | Obras, Materiales, Keycloak | REST, con el token de la *service account* del cliente `n8n` (`gerente`, `view-users`) | Obras: obra, planilla, obras `EN_EJECUCION` y diario de hoy; Materiales: nombre y unidad del material; Keycloak: nombre y correo del cliente (010) |
| n8n (010) | Correo | SMTP | «Planilla para revisar» al cliente, sin copia a cobranzas (Mailpit en desarrollo) (010) |
| n8n (010) | Firebase Cloud Messaging | HTTPS (API v1, `messages:send`, cuenta de servicio de Google) | *Push* al tema de la obra: stock bajo (almacenero) y recordatorio del diario a las 18:00 de La Paz (maestro) (010) |
| App de obra | Firebase Cloud Messaging | SDK de Firebase (`@react-native-firebase/messaging`) | Suscribirse a los temas de sus obras asignadas y recibir los avisos; tocar uno abre el stock o el diario (010) |
| IA (`ia-worker`, host de los agentes) | Obras, Materiales, Finanzas e IA (`ia-api`) | **MCP** (HTTP «streamable» sin estado en `POST /mcp`, solo lectura, token de `ia-agentes`, privados: solo los llama IA; versión común 2025-11-25) | Herramientas para los agentes: el dato al instante de cada dueño y, en IA, `consultar_reporte` (motor de la 503), riesgo de retraso y consumos atípicos (501) |
| IA | Ollama **o** API de Anthropic | HTTP / HTTPS | Modelo de lenguaje de la capa 5 (uno u otro, según `IA_LLM_PROVEEDOR`) |

## Microfrontends del ERP

- Se usa **Native Federation 4** (federación con módulos ES e *import maps*) en todos los microfrontends: un solo mecanismo, sin mezclar con Module Federation de webpack.
- **Shell** (`erp-shell`, puerto 4200): host dinámico; lee la lista de remotos de `public/federation.manifest.json`.
- **mf-obras** (Angular, 4201): remoto con el adaptador oficial de Angular; comparte Angular con el shell.
- **mf-materiales** (React, 4202) y **mf-supervision** (React, 4203): remotos con el adaptador esbuild de Native Federation y su preset oficial de React. Cada uno se publica como **Web Component** (`<mf-materiales>`, `<mf-supervision>`) con Shadow DOM, así el shell los muestra sin depender de React y sus estilos no se mezclan.
- El shell carga `mf-obras` como rutas (`./Routes`) en `/obras` y los React como Web Components (`./Bootstrap`) en `/materiales` y `/supervision`; la sesión les llega por `window.plataforma` (fase 1, 1.8). Si un remoto no carga, su espacio muestra el aviso con «Reintentar».
- Vue queda como tercer framework **opcional**; no se usa salvo que el equipo decida agregarlo.

## Versiones

Elegidas por compatibilidad entre sí y soporte durante el proyecto (revisado el 28 de octubre de 2026).

| Pieza | Versión | Motivo |
|---|---|---|
| Node | 24 LTS | Mantenimiento hasta abril de 2028; lo soportan Angular 22, Vite 8, Expo 58 y NestJS 12 |
| Angular | 22 | Activa hasta junio de 2027 y LTS hasta junio de 2028; Native Federation 22 y keycloak-angular 22 alineados |
| Native Federation | `@angular-architects/native-federation` 22.2 (Angular) · `@softarc/native-federation` 4.7 + `@softarc/native-federation-esbuild` 4.2 (React) | El adaptador esbuild 4.2 pide el núcleo 4.7 |
| React | 19.3 | Estable; lo usan los dos microfrontends y el portal |
| Vite | 8 (solo el portal) | Plantilla oficial `create-vite` con React y TypeScript |
| NestJS | 12 (gateway, Materiales y Sincronización) | Misma versión en todos |
| GraphQL en el gateway | `@nestjs/graphql` 14 + `@nestjs/apollo` 14 + Apollo Server 5 | Versiones declaradas compatibles con NestJS 12 |
| Cliente GraphQL (previsto) | apollo-angular 14 · Apollo Client 4 | Compatibles con Angular 22 y React 19 |
| Login (previsto) | Keycloak 26 · keycloak-angular 22 · react-oidc-context 3 | OIDC estándar |
| App móvil | Expo SDK 58 · React Native 0.88 | Recomendado por la documentación de React Native; TensorFlow Lite (capa 3) con `react-native-fast-tflite` en una *development build* |
| Obras | Spring Boot 4.1 · Java 21 | Ya creado |
| Finanzas | Laravel 13 · PHP 8.4 o superior | Ya creado. El `composer.lock` trae Symfony 8.1, que pide PHP 8.4.1 o más: la imagen y el CI usan PHP 8.4 (601); en la máquina, el PHP 8.5 de Herd |
| IA | Python 3.12 · FastAPI 0.162 · `uv` · XGBoost 3 · scikit-learn 1 | `xgboost` 3 y `numpy` 2.5 exigen Python 3.12; librerías en `docs/stack.md` (401) |
| Capa 5: MCP | Especificación vigente 2026-07-28; versión común 2025-11-25. SDK oficiales: Java `io.modelcontextprotocol.sdk:mcp` 2.1.0 (por Spring AI 2.0.2), TypeScript `@modelcontextprotocol/server` 2.4.0 (con su transporte `WebStandardStreamableHTTPServerTransport`; el adaptador `@modelcontextprotocol/express` no hizo falta), Python `mcp` 2.3.0; PHP: `laravel/mcp` 1.1.2 (oficial de Laravel; el SDK de la organización MCP, `mcp/sdk`, sigue en 0.9) | Verificado el 31/10/2026; detalle en la 501 |
| Capa 5: modelo de lenguaje | `ollama` 0.6.3 (Python) con `qwen3:8b` · `anthropic` 2.3.0 (Python) con `claude-sonnet-5-5` | Verificado el 31/10/2026; detalle en la 503. En desarrollo, imagen `ollama/ollama:0.40.4` (`docs/entorno-local.md`) |
| Capa 5: navegador (mf-supervision) | `@huggingface/transformers` 4 (Whisper `onnx-community/whisper-base` `q8`, 302) · SheetJS `xlsx` 0.20.3 desde `cdn.sheetjs.com` (503) | Detalle en la 302 y la 503; librerías en `docs/stack.md` |

## Los 4 niveles

- **Backend:** microservicios por área del negocio. DDD en todos; Hexagonal en Obras y Finanzas; Clean en Materiales y Sincronización; hexagonal ligera por módulo en IA (`reportes`, `riesgo`, `atipicos` y, en la capa 5, `lenguaje`, `constructor_reportes`, `mcp`, `agentes` y `seguridad`). En la capa 5, MCP: el servicio de IA es el **host** de los agentes y los cuatro servicios (Obras, Materiales, Finanzas e IA) son **servidores MCP** internos de solo lectura; las personas usan REST por el gateway.
- **Frontend:** shell + microfrontends en el ERP; portal y app como aplicaciones separadas.
- **Datos:** una base por servicio; sin JOIN entre servicios. Para los reportes que cruzan servicios (el ingeniero pidió «algún mecanismo», no un microservicio), **CQRS: modelo de lectura alimentado por eventos**, solo para lo que cruza servicios: cada microservicio sigue escribiendo y leyendo lo suyo, y las proyecciones de sus eventos de RabbitMQ arman `reportes_db` (tablas `rpt_*`) dentro del servicio de IA, que es quien lo usa (predicciones de la capa 4 y reportes por voz de la capa 5). Sin *event sourcing*. Lo que existía antes se trae una vez con una carga inicial por REST (401). Decisión de Jairo, 31/10/2026.
- **Despliegue (601):** cada servicio (Obras, Materiales, Finanzas, IA, Sincronización y el gateway) produce **su propia imagen** de contenedor, construida en dos etapas, sin `root` y configurada solo por variables, y la publica GitHub Actions en GitHub Container Registry (`ghcr.io/jairovargasfigueroa/supervision-<repo>`, etiquetas `sha-<7>` y `main`) con cada *push* a `main`; cada pieza se despliega por separado. El servicio de IA tiene **una imagen con sus procesos** (`ia-api`, `ia-worker` e `ia-carga-inicial`, cambiando el comando), igual que Finanzas (API, `mensajeria:consumir`, `mensajeria:publicar` y `schedule:work`). Los **frontends** (shell, 3 microfrontends y portal) no llevan imagen: se **compilan una vez** a archivos estáticos y, al publicarlos, un script escribe su configuración (`configuracion.json` del shell y del portal y `federation.manifest.json` del shell) con las direcciones del entorno, así la misma compilación sirve en la laptop y en cualquier nube. La app no lleva imagen (el APK lo genera Jairo). Antes de subir a las nubes (602) se **ensaya en local** («producción local», `infra/produccion-local/`): las mismas imágenes y los frontends compilados, en **tres grupos** (`azure`, `google` y `aws`, el reparto de abajo), cada uno con su red y su Caddy; entre grupos solo por direcciones públicas con HTTPS (CA local) y RabbitMQ con TLS. Mover un servicio de nube solo cambia los *compose* y las variables, nunca una imagen. Detalle en `docs/convenciones.md` («Contenedores y CI») y `docs/entorno-local.md` («Producción local»).

## Resiliencia

- Las pantallas del ERP se arman por secciones; si un servicio cae, solo su sección muestra «no disponible».
- El gateway devuelve respuestas parciales y corta a los pocos segundos.
- La mayoría de las escrituras tocan un solo servicio. Solo la saga y la automatización involucran a varios.
- Cada servicio guarda una copia de lo poco que necesita de otros (por ejemplo, Obras guarda el anticipo y la retención del contrato).

## Despliegue (capa 6, 602)

Una máquina virtual por nube con Docker Compose (los mismos *compose* del ensayo local de la 601) y Caddy, que da HTTPS con certificados de Let's Encrypt. Las tres cerca de Ohio: AWS en `us-east-2` (la única región que permite la organización de la cuenta), Azure en `northcentralus` (Chicago; la suscripción de prueba no permite máquinas pequeñas en São Paulo ni en Virginia) y Google en `us-east5` (Columbus). Los nombres van bajo `supervision.workflow-tramites.site`. Las máquinas están apagadas salvo para probar y para la presentación, y se manejan con `node infra/nube/nube.mjs` desde la PC de Jairo.

| Nube | Máquina | Qué aloja | Por qué |
|---|---|---|---|
| Azure (`northcentralus`) | `vm-plataforma`, B2als_v2 (4 GiB) | Gateway, Obras, Finanzas, Keycloak, RabbitMQ (AMQPS 5671), n8n, Mailpit, apps web y PostgreSQL de Obras, Finanzas y Keycloak | Obras y Finanzas comparten la saga; Keycloak y RabbitMQ son el centro |
| Google Cloud (`us-east5`) | `vm-ia`, e2-medium (4 GB; 16 GB si se usa Ollama) | IA (`ia-api` e `ia-worker`), Materiales, MongoDB y PostgreSQL de reportes | Materiales e IA comparten MongoDB; el modelo de lenguaje local necesitaría memoria |
| AWS (`us-east-2`) | `vm-sincronizacion`, t3.micro (1 GiB) | Sincronización; además DynamoDB y S3 (fotos) | DynamoDB es de AWS |

Entre nubes: HTTPS con los nombres públicos y el token de Keycloak, y RabbitMQ por AMQPS. Dentro de una máquina, los nombres de sus propias piezas apuntan a su Caddy. Detalle (comunicación, secretos, costos y orden): `docs/specs/602-despliegue-tres-nubes/diseno.md`.

En desarrollo todo corre con Docker Compose (DynamoDB Local en lugar de AWS); las fotos van a un bucket S3 real de desarrollo. El ensayo local de la 601 reproduce este reparto en tres grupos de Docker Compose (MinIO en lugar de S3).
