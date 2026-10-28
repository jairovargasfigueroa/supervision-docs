# Stack por proyecto

Qué librerías usa cada proyecto y para qué. Versiones verificadas el 28 de octubre de 2026 (npm, Maven Central, Packagist). **No agregues otras librerías para lo mismo**: si hace falta algo que no está aquí, propónlo antes de instalarlo y, si se aprueba, agrégalo a esta tabla y al `docs/estructura.md` del proyecto.

Las capas pueden sumar librerías propias (Whisper, MediaPipe, SheetJS, TF Lite, Ollama, etc.); están en sus especificaciones.

## Decisiones generales

- **Interfaz web:** Material Design en todo el ERP y el portal: **Angular Material 22** en Angular y **MUI 9** en React, con el mismo tema (`docs/diseno-visual.md`).
- **App móvil:** **React Native Paper 5** (Material Design 3) con el mismo tema.
- **React:** ecosistema **TanStack** (Router, Table, Form; Query donde se usa REST). Los microfrontends usan **Apollo Client 4** para GraphQL.
- **Formularios en React y en la app:** **TanStack Form + Zod 4** (Zod se conecta directo como *Standard Schema*; no hace falta adaptador).
- **Formularios en Angular:** Reactive Forms tipados con los validadores de Angular.
- **Validación en NestJS:** `class-validator` + `class-transformer` con el `ValidationPipe` global. (`nestjs-zod` todavía no es compatible con NestJS 12.)
- **Documentación de cada API REST:** OpenAPI generado desde el código, publicado en `/docs` (solo en desarrollo).
- **Pruebas de punta a punta:** Playwright 1, en el repo `infra` (carpeta `e2e/`), contra el entorno de Docker Compose.

## services/obras (Java 21 · Spring Boot 4.1)

| Para qué | Librería | Versión |
|---|---|---|
| Web, seguridad, JPA, AMQP, validación, actuator | starters de Spring Boot (ya en el `pom.xml`) | 4.1 |
| Migraciones | Flyway (ya incluido) | la del BOM de Spring Boot |
| Mapeo entre dominio, JPA y DTO | MapStruct | 1.6.3 (estable; no usar la 1.7 beta) |
| DTO y objetos de valor | `record` de Java (sin Lombok) | — |
| OpenAPI y Swagger UI | `springdoc-openapi-starter-webmvc-ui` | 3.2 |
| Fotos en S3/RustFS | AWS SDK for Java v2 (`s3`) | 2.x |
| Pruebas | JUnit 5 + AssertJ (del starter de test), Testcontainers 2 (PostgreSQL, RabbitMQ) | versiones del BOM de Spring Boot |
| Reglas de arquitectura hexagonal | ArchUnit (`archunit-junit5`) | 1.5 |

## services/materiales (NestJS 12 · MongoDB)

| Para qué | Librería | Versión |
|---|---|---|
| Framework, configuración, Mongoose | `@nestjs/*`, `@nestjs/config`, `@nestjs/mongoose`, `mongoose` (ya instalados) | 12 / 9 |
| Validación de DTO | `class-validator` + `class-transformer` | 0.15 / 0.5 |
| OpenAPI | `@nestjs/swagger` | 12 |
| RabbitMQ | `amqplib` (con un módulo propio de mensajería) | última 0.x |
| Validar el token de Keycloak | `jose` | 6 |
| Pruebas | Vitest (ya), `supertest`, `mongodb-memory-server` (con *replica set*) | — / 11 |

## gateway (NestJS 12 · GraphQL)

| Para qué | Librería | Versión |
|---|---|---|
| GraphQL code-first | `@nestjs/graphql` 14 + `@nestjs/apollo` 14 + `@apollo/server` 5 (ya instalados) | — |
| Evitar llamadas repetidas | `dataloader` | 2 |
| Validar el token | `jose` | 6 |
| Llamadas REST | `fetch` nativo de Node 24 con `AbortSignal.timeout(3000)` | — |
| Pruebas | Vitest (ya), `supertest` | — |

## services/finanzas (PHP · Laravel 13)

| Para qué | Librería | Versión |
|---|---|---|
| Entrada y salida HTTP | Form Requests y API Resources de Laravel | — |
| RabbitMQ | `php-amqplib/php-amqplib` | 3 |
| Validar el token | `firebase/php-jwt` (con JWKS) | 7 |
| OpenAPI automático | `dedoc/scramble` | 0.13 |
| Análisis estático | `larastan/larastan` (nivel 6) | 3 |
| Formato | Laravel Pint (ya incluido) | — |
| Pruebas | PHPUnit 12 (ya instalado; no migrar a Pest) | 12 |

## frontend/erp-shell y frontend/mf-obras (Angular 22)

| Para qué | Librería | Versión |
|---|---|---|
| Componentes y diseño | `@angular/material` + `@angular/cdk` | 22 |
| Íconos | Material Symbols (fuente, con `mat-icon`) | — |
| Federación | `@angular-architects/native-federation` (ya instalado) | 22 |
| GraphQL (solo mf-obras; el shell no consulta datos) | `apollo-angular` 14 + `@apollo/client` 4 + `graphql` 16 | — |
| Login (solo el shell) | `keycloak-angular` 22 + `keycloak-js` 26 | — |
| Estado | *signals* de Angular y servicios; sin NgRx | — |
| Formularios | Reactive Forms tipados | — |
| PWA (solo el shell, capa 1) | `@angular/pwa` | 22 |
| Pruebas | Vitest (ya configurado por Angular CLI) | — |

## frontend/mf-materiales y frontend/mf-supervision (React 19 · Native Federation esbuild)

| Para qué | Librería | Versión |
|---|---|---|
| Componentes | `@mui/material` + `@mui/icons-material` + `@emotion/react` + `@emotion/styled` + `@emotion/cache` | 9 / 11 |
| Rutas internas | `@tanstack/react-router` (rutas definidas en código, con `basepath`) | 1 |
| Tablas | `@tanstack/react-table` (lógica) dibujada con la `Table` de MUI | 9 |
| Formularios | `@tanstack/react-form` + `zod` | 1 / 4 |
| GraphQL | `@apollo/client` 4 + `graphql` 16 | — |
| Pruebas | Vitest + `@testing-library/react` + `jsdom` | — / 16 |

## frontend/portal (React 19 · Vite 8)

| Para qué | Librería | Versión |
|---|---|---|
| Componentes | MUI 9 (mismos paquetes que los microfrontends, sin `@emotion/cache` especial) | 9 |
| Rutas | `@tanstack/react-router` + `@tanstack/router-plugin` (rutas por archivos) | 1 |
| Datos REST | `@tanstack/react-query` | 5 |
| Tablas | `@tanstack/react-table` | 9 |
| Formularios | `@tanstack/react-form` + `zod` | 1 / 4 |
| Login | `react-oidc-context` + `oidc-client-ts` | 3 / 3 |
| Pruebas | Vitest + `@testing-library/react` + `jsdom` | — |

## mobile/app-obra (Expo SDK 58)

Instalar **siempre** con `npx expo install <paquete>` (elige la versión compatible con el SDK).

| Para qué | Librería |
|---|---|
| Componentes | `react-native-paper` 5 + `react-native-safe-area-context` + `@expo/vector-icons` (MaterialCommunityIcons) |
| Navegación | `expo-router` |
| Datos REST | `@tanstack/react-query` 5 |
| Formularios | `@tanstack/react-form` + `zod` 4 |
| Login y tokens | `expo-auth-session`, `expo-secure-store`, `expo-crypto` |
| Fotos | `expo-image-picker`, `expo-image-manipulator` |
| Base local (capa 1) | `expo-sqlite` |
| Pruebas | `jest-expo` + `@testing-library/react-native` 14 |

## services/sincronizacion y services/ia

Se crean en las capas 1 y 4; sus librerías están en `docs/specs/101-registro-sin-senal/diseno.md` y `docs/specs/401-base-reportes/diseno.md`.

## infra

Docker Compose, el JSON del realm de Keycloak, las definiciones de RabbitMQ y las pruebas de punta a punta con Playwright (`e2e/`).
