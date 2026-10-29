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
| IA | Microservicio (capas 3 a 5) | FastAPI + Ollama | MongoDB (agentes) y PostgreSQL de lectura (reportes) |
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
| App de obra | Sincronización (capa 1) | REST | Enviar lo registrado; en el sistema base, la app llama directo a Obras y Materiales |
| Sincronización | Obras, Materiales | REST | Repartir lo recibido sin duplicar |
| Obras, Materiales, Finanzas | RabbitMQ | AMQP | Eventos y comandos de la saga |
| RabbitMQ | n8n (capa 2) | AMQP / webhook | Eventos «stock bajo» e «ingreso» |
| n8n | Finanzas, correo | REST, SMTP | Crear orden de compra y cuenta por pagar; avisar al proveedor |
| IA | Obras, Materiales, Finanzas | **MCP** (HTTP, solo lectura) | Herramientas para los agentes |
| IA | Ollama | HTTP | Modelo de lenguaje local |

## Microfrontends del ERP

- Se usa **Native Federation 4** (federación con módulos ES e *import maps*) en todos los microfrontends: un solo mecanismo, sin mezclar con Module Federation de webpack.
- **Shell** (`erp-shell`, puerto 4200): host dinámico; lee la lista de remotos de `public/federation.manifest.json`.
- **mf-obras** (Angular, 4201): remoto con el adaptador oficial de Angular; comparte Angular con el shell.
- **mf-materiales** (React, 4202) y **mf-supervision** (React, 4203): remotos con el adaptador esbuild de Native Federation y su preset oficial de React. Cada uno se publica como **Web Component** (`<mf-materiales>`, `<mf-supervision>`) con Shadow DOM, así el shell los muestra sin depender de React y sus estilos no se mezclan.
- Pendiente para la fase 1 («esqueleto que camina»): que el shell cargue cada remoto en su ruta y le pase la sesión.
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
| NestJS | 12 (gateway y Materiales) | Misma versión en ambos |
| GraphQL en el gateway | `@nestjs/graphql` 14 + `@nestjs/apollo` 14 + Apollo Server 5 | Versiones declaradas compatibles con NestJS 12 |
| Cliente GraphQL (previsto) | apollo-angular 14 · Apollo Client 4 | Compatibles con Angular 22 y React 19 |
| Login (previsto) | Keycloak 26 · keycloak-angular 22 · react-oidc-context 3 | OIDC estándar |
| App móvil | Expo SDK 58 · React Native 0.88 | Recomendado por la documentación de React Native; TensorFlow Lite (capa 3) con `react-native-fast-tflite` en una *development build* |
| Obras | Spring Boot 4.1 · Java 21 | Ya creado |
| Finanzas | Laravel 13 · PHP 8.3 o superior | Ya creado |

## Los 4 niveles

- **Backend:** microservicios por área del negocio. DDD en todos; Hexagonal en Obras y Finanzas; Clean en Materiales.
- **Frontend:** shell + microfrontends en el ERP; portal y app como aplicaciones separadas.
- **Datos:** una base por servicio; sin JOIN entre servicios. Los reportes que cruzan servicios leen una base de lectura del servicio de IA, alimentada por eventos.
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
