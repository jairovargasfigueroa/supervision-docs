# Plan de trabajo

Orden de trabajo y estado. Estados: `pendiente`, `en curso`, `hecho`. Al terminar una tarea, cambia su estado aquí.

**Siguiente tarea:** la primera `pendiente` de la fase 1.

Ramas, *pull requests* y definición de terminado: `docs/flujo-trabajo.md`. Solo se empieza algo cuyas dependencias están `hecho`.

## Fase 0. Esqueleto y especificación general

| Tarea | Estado |
|---|---|
| Estructura de carpetas y un repositorio por proyecto (10 repos en GitHub) | hecho |
| Repo `supervision-docs` con la carpeta raíz | hecho |
| `CLAUDE.md` y documentos transversales (`docs/`) | hecho |
| `CLAUDE.md` y `docs/` de cada proyecto (servicio, datos, contratos conocidos) | hecho |
| Reglas del negocio fijadas (sin «por confirmar») | hecho |
| Convenciones completas (sin «por definir») | hecho |
| Proyectos generados con sus frameworks y versiones | hecho |

Los contratos detallados (rutas REST exactas, cuerpos, eventos con sus datos, esquema GraphQL) **no se escriben por adelantado**: cada funcionalidad los define en su `diseno.md` y los copia a `docs/contratos/` y al `docs/contratos.md` de cada proyecto afectado.

## Fase 1. Entorno y esqueleto que camina

**Cerrada el 29/10/2026 con el release `v0.1.0`** (etiqueta en `main` de cada repo).

| N.º | Tarea | Proyecto | Estado |
|---|---|---|---|
| 1.0 | Configurar los repos según `docs/flujo-trabajo.md` con `scripts/configurar-repos.ps1`: crear `develop` y dejarla por defecto, proteger `main` y `develop`, solo *merge commit*, borrar ramas al fusionar (plantilla de PR ya copiada en cada repo) | todos | hecho |
| 1.1 | Crear el repo `infra` (carpeta `infra/`, GitHub `supervision-infra`) con su `CLAUDE.md` | infra | hecho |
| 1.2 | Docker Compose: RabbitMQ (con panel), Keycloak 26.8; PostgreSQL 17 y MongoDB 8.0 como perfil opcional; scripts de `infra/scripts/` (todo según `docs/entorno-local.md`) | infra | hecho |
| 1.3 | MongoDB como *replica set* de un nodo (lo necesitan las transacciones del outbox de Materiales), en el contenedor y en la instalación local | infra | hecho |
| 1.4 | Realm `supervision` exportado en JSON e importado al iniciar: roles, clientes `erp`, `portal`, `app-obra`, mapper de audiencia `plataforma-api`, cliente `gateway` con *service account*, usuarios de prueba de la 001 (con `demo1`), política de contraseñas, protección contra fuerza bruta, idioma español y tema `supervision` (`docs/convenciones.md`, «Seguridad») | infra | hecho |
| 1.5 | Bases `obras_db` y `finanzas_db` en PostgreSQL; definiciones de RabbitMQ con el exchange `plataforma` y todas las colas (incluidas `ia` y `notificaciones`) | infra | hecho |
| 1.6 | `GET /salud` en Obras, Materiales y Finanzas, y validación del token de Keycloak en los tres (rechaza sin token, acepta con token válido) | services/* | hecho |
| 1.7 | Gateway: validación del token, reenvío del token y de `X-Request-Id`, tiempo máximo de 3 s | gateway | hecho |
| 1.8 | Shell: login con keycloak-angular, `window.plataforma.sesion`, menú y rutas `/obras`, `/materiales`, `/supervision` cargando cada microfrontend (Angular por `loadRemoteModule`; React como Web Component) con aviso si uno no carga | erp-shell, mf-* | hecho |
| 1.9 | Tema visual y librerías base en shell, microfrontends, portal y app según `docs/diseno-visual.md` y el `docs/estructura.md` de cada uno (tema, fuentes, estados vacío y error, `formato.ts`) | frontends, app-obra | hecho |
| 1.10 | Esqueleto que camina: login en el ERP → consulta GraphQL → Obras devuelve una lista (vacía) de obras → se muestra en mf-obras | todos los del ERP | hecho |

**Preparativos que hace Jairo más adelante (no bloquean la fase 1):**

- **Bucket S3 de desarrollo** (antes de la 005): bucket privado, CORS, expiración de `temporal/` y usuario IAM limitado, según `docs/entorno-local.md`. Hasta entonces las variables `*_S3_*` quedan vacías.
- **Proyecto de Firebase** (antes de la 010): según la sección «Configuración de Firebase» de `docs/specs/010-notificaciones/diseno.md`.

Si una funcionalidad necesita uno de estos preparativos y todavía no está, el agente avisa y espera; no lo inventa ni lo salta.

La fase 1 es técnica: no necesita `requisitos.md` por funcionalidad, pero cada tarea se hace con sus pruebas y su commit.

## Fase 2. Sistema base (una especificación por funcionalidad)

Las especificaciones ya están escritas y aprobadas (la 010 y la 011 terminan con «Cambios a contratos y datos»: aplícalos como primera tarea): `docs/specs/NNN-nombre/requisitos.md` y `diseno.md` en la carpeta general, y `docs/specs/NNN-nombre/tareas.md` en cada proyecto afectado (las de `infra` en `infra/docs/specs/NNN-nombre/tareas.md`). Se implementan en este orden; una funcionalidad está `hecho` cuando todas sus tareas, en todos sus proyectos, están marcadas.

| N.º | Funcionalidad | Proyectos | Depende de | Estado |
|---|---|---|---|---|
| 001 | Iniciar sesión y paso entre aplicaciones | Keycloak, frontends | fase 1 | hecho |
| 002 | Registrar obra (datos, contrato, presupuesto) | obras, finanzas, gateway, mf-obras | 001 | hecho |
| 003 | Gestionar materiales (catálogo y stock mínimo) | materiales, gateway, mf-materiales | 001 | hecho |
| 004 | Registrar ingreso y salida de material | materiales, app-obra | 002, 003 | pendiente |
| 005 | Registrar foto de avance | obras, app-obra | 002 | en curso (Obras y app hechos; la galería del ERP va con la 006; la subida real espera el bucket S3) |
| 006 | Consultar obra (avance vs plazo, material usado vs previsto) | obras, materiales, finanzas, gateway, mf-obras | 002, 003, 004, 005 | pendiente |
| 007 | Elaborar y presentar planilla | obras, gateway, mf-obras | 005, 006 | pendiente |
| 008 | Revisar planilla en el portal (saga aprobar planilla) | obras, finanzas, materiales, portal | 007 | pendiente |
| 009 | Consultar tablero | gateway, mf-supervision | 006 | pendiente |
| 010 | Notificaciones (Firebase: *push* web y Android, bandeja en ERP, portal y app; crea `services/notificaciones`) | notificaciones, obras, finanzas, materiales, gateway, erp-shell, mf-materiales, portal, app-obra, infra | 001, 002, 003, 004, 007, 008 | pospuesta (decisión de Jairo, 29/10/2026: se hace después de la 011) |
| 011 | Datos de prueba (`docs/datos-prueba.md`) | obras, materiales, finanzas, infra | 009 | pendiente |

## Fases 3 a 8. Capas (especificaciones en borrador)

Las specs de las capas están escritas pero en **borrador**: Jairo las revisa (y puede cambiar la forma de aplicar cada punto) antes de empezar cada capa. **No se implementa una funcionalidad de capa mientras su `requisitos.md` diga «borrador»**; al aprobarla se cambia a «aprobado».

Mismo formato que el sistema base. Cada `diseno.md` de capa termina con «Cambios a contratos y datos»: **la primera tarea al implementar la funcionalidad es aplicar esos cambios** a `docs/contratos/`, `docs/convenciones.md` o `docs/reglas-negocio.md` (si los menciona) y a los `docs/contratos.md` y `docs/datos.md` de cada proyecto afectado.

| N.º | Funcionalidad | Capa | Depende de | Estado |
|---|---|---|---|---|
| 101 | Registro de material sin señal y sincronización sin duplicados (crea `services/sincronizacion`) | 1 | 004 | pendiente |
| 102 | Fotos sin señal y envío con mala conexión (incluye foto de la nota de remisión) | 1 | 005, 101 | pendiente |
| 103 | Diario de obra | 1 | 101 | pendiente |
| 104 | ERP como PWA y borrador de planilla sin conexión | 1 | 007 | pendiente |
| 201 | Compra automática por stock bajo (n8n) | 2 | 003, 004, 101 | pendiente |
| 301 | Detección de casco y chaleco en la app (TensorFlow → TF Lite; crea `services/ia` con el entrenamiento) | 3 | 005 | pendiente |
| 302 | Dictado por voz en el navegador (Whisper) | 3 | 009 | pendiente |
| 303 | Rostros difuminados en las fotos del cliente | 3 | 007, 008 | pendiente |
| 401 | Base de reportes (servicio IA con FastAPI) | 4 | 008 | pendiente |
| 402 | Riesgo de retraso (ML supervisado, XGBoost) | 4 | 401 | pendiente |
| 403 | Consumos atípicos (ML no supervisado, Isolation Forest) | 4 | 401 | pendiente |
| 501 | Servidores MCP de solo lectura en cada microservicio | 5 | 401 | pendiente |
| 502 | Agentes del ERP (Seguimiento de obras, Control de materiales, Control de cobros) | 5 | 501, 402, 403 | pendiente |
| 503 | Reportes por voz con exportación a Excel | 5 | 302, 401 | pendiente |
| 504 | Seguridad de la IA (inyección SQL y de instrucciones) | 5 | 502, 503 | pendiente |
| 601 | Contenedores y CI (Dockerfile y GitHub Actions por proyecto) | 6 | — (se puede adelantar) | pendiente |
| 602 | Despliegue en tres nubes (AWS, Google Cloud, Azure) | 6 | 601 | pendiente |
