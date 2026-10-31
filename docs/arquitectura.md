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
| IA | Microservicio (capas 3 a 5) | FastAPI (procesos `ia-api` e `ia-worker`); ML clásico en la capa 4; el modelo de lenguaje se decide en la capa 5 | PostgreSQL `reportes_db` (modelo de lectura, CQRS) y MongoDB `ia_db` (predicciones, consumos atípicos y, en la capa 5, agentes) |
| RabbitMQ | Mensajería | RabbitMQ | — |
| n8n | Automatización (capa 2) | n8n | — |
| Almacenamiento de objetos | Fotos y notas de remisión | Amazon S3 (también en desarrollo, con un bucket propio) | — |

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
| RabbitMQ | n8n (capa 2) | AMQP / webhook | Eventos «stock bajo» e «ingreso» |
| n8n | Finanzas, correo | REST, SMTP | Crear orden de compra y cuenta por pagar; avisar al proveedor |
| IA | Obras, Materiales, Finanzas | **MCP** (HTTP, solo lectura) | Herramientas para los agentes |
| IA | Ollama | HTTP | Modelo de lenguaje local (capa 5; se decide en esa capa) |

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
| Finanzas | Laravel 13 · PHP 8.3 o superior | Ya creado |

## Los 4 niveles

- **Backend:** microservicios por área del negocio. DDD en todos; Hexagonal en Obras y Finanzas; Clean en Materiales.
- **Frontend:** shell + microfrontends en el ERP; portal y app como aplicaciones separadas.
- **Datos:** una base por servicio; sin JOIN entre servicios. Para los reportes que cruzan servicios (el ingeniero pidió «algún mecanismo», no un microservicio), **CQRS: modelo de lectura alimentado por eventos**, solo para lo que cruza servicios: cada microservicio sigue escribiendo y leyendo lo suyo, y las proyecciones de sus eventos de RabbitMQ arman `reportes_db` (tablas `rpt_*`) dentro del servicio de IA, que es quien lo usa (predicciones de la capa 4 y reportes por voz de la capa 5). Sin *event sourcing*. Lo que existía antes se trae una vez con una carga inicial por REST (401). Decisión de Jairo, 31/10/2026.
- **Despliegue:** cada proyecto produce su propia imagen de contenedor y se despliega por separado.

## Resiliencia

- Las pantallas del ERP se arman por secciones; si un servicio cae, solo su sección muestra «no disponible».
- El gateway devuelve respuestas parciales y corta a los pocos segundos.
- La mayoría de las escrituras tocan un solo servicio. Solo la saga y la automatización involucran a varios.
- Cada servicio guarda una copia de lo poco que necesita de otros (por ejemplo, Obras guarda el anticipo y la retención del contrato).

## Despliegue (propuesta, capa 6)

| Nube | Qué aloja | Por qué |
|---|---|---|
| AWS | Sincronización, DynamoDB, S3 | DynamoDB es de AWS |
| Google Cloud | IA + Ollama (máquina virtual), Materiales, MongoDB, PostgreSQL de reportes | El modelo de lenguaje necesita memoria |
| Azure | Gateway, Obras, Finanzas, Keycloak, RabbitMQ, n8n, apps web, PostgreSQL de Obras y Finanzas | Obras y Finanzas comparten la saga |

En desarrollo todo corre con Docker Compose (DynamoDB Local en lugar de AWS); las fotos van a un bucket S3 real de desarrollo.
