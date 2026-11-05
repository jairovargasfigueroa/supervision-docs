# Plan de trabajo

Orden de trabajo y estado. Estados: `pendiente`, `en curso`, `hecho`. Al terminar una tarea, cambia su estado aquí.

**Siguiente:** la **602** (se reescribe al desplegar, con las cuentas de las nubes que se consigan). La **601** (preparar el despliegue) se terminó el 05/11/2026 con el ensayo local completo (53 de 53 comprobaciones); el recorrido en el navegador queda para Jairo. También queda mejorar el modelo de lenguaje local (`qwen3:4b`, precarga del modelo). La **201** (cobranza automática con n8n) se terminó el 02/11/2026 y la **301** (casco y chaleco) el 01/11/2026, las dos con sus pruebas manuales pendientes (Jairo). La capa 5 se terminó el 01/11/2026 y la capa 4 el 31/10/2026. La fase 1 y el sistema base están terminados (la 010 se rehízo y terminó el 03/11/2026).

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
| 1.5 | Bases `obras_db` y `finanzas_db` en PostgreSQL; definiciones de RabbitMQ con el exchange `plataforma` y todas las colas (incluidas `ia` y `notificaciones`; la cola `notificaciones` se quitó con la 010) | infra | hecho |
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
| 004 | Registrar ingreso y salida de material | materiales, app-obra | 002, 003 | hecho (falta probar la app en el celular) |
| 005 | Registrar foto de avance | obras, app-obra | 002 | hecho (la subida real a S3 y el celular quedan para cuando exista el bucket) |
| 006 | Consultar obra (avance vs plazo, material usado vs previsto) | obras, materiales, finanzas, gateway, mf-obras | 002, 003, 004, 005 | hecho |
| 007 | Elaborar y presentar planilla | obras, gateway, mf-obras | 005, 006 | hecho (la galería de fotos necesita el bucket S3) |
| 008 | Revisar planilla en el portal (saga aprobar planilla) | obras, finanzas, materiales, gateway, mf-obras, portal, infra | 007 | hecho |
| 009 | Consultar tablero | materiales, finanzas, gateway, mf-supervision | 006 | hecho |
| 010 | Avisos al celular y al cliente: *push* de stock bajo al almacenero y recordatorio del diario al maestro (Firebase, desde n8n), y correo «planilla para revisar» al cliente | obras, app-obra, infra | 003, 004, 007, 103, 201 | hecho (03/11/2026; reemplazó a la versión con servicio de notificaciones y bandeja; pendiente de Jairo: crear el proyecto de Firebase, `node pruebas/avisos.mjs` tras recargar los datos y la prueba del *push* en el celular) |
| 011 | Datos de prueba (`docs/datos-prueba.md`) | obras, materiales, finanzas, infra | 009 | hecho (las fotos se suben al bucket S3 cuando exista: completar `infra/.env` y correr `semilla`) |

### Pendientes conocidos del sistema base

- **Manuales (Jairo):** crear el bucket S3 y poner sus claves en `services/obras/.env.properties` (subida de fotos de la 005, galería de la 007 y fotos del portal de la 008); probar la app en el celular (001, 004, 005); Firebase cuando se haga la 010.
- **Con el bucket:** Obras debe comprobar con `HEAD` que la foto no supere 5 MB al registrarla (la URL firmada de subida no lo limita).
- **Carrera rara en Materiales (004 y 008):** un movimiento registrado en el mismo instante en que `CerrarConsumos` cierra su periodo puede quedar con `cerrado = false`. Se corrige haciendo que el registro del movimiento escriba también en `cierre_periodo` dentro de su transacción.
- **Respuesta tardía entre dos sagas de la misma planilla (008):** un `ConsumosCerrados` tardío de una saga ya compensada envía `ReabrirConsumos` con el mismo `planillaId` y podría reabrir el cierre de una segunda saga en curso. Muy improbable (exige vencimiento, corrección y nueva aprobación dentro de esa ventana).
- **Límite de 120 peticiones por minuto:** lo aplica el gateway; Obras no lo aplica en los endpoints que el portal llama directo.

## Fases 3 a 8. Capas

Las specs de las capas son una **base**: al llegar a cada capa se reevalúan como arquitectura desde lo que pidió el ingeniero, se ajustan y se aprueban (la capa 1 se aprobó el 30/10/2026 y la capa 4 el 31/10/2026, y las dos están hechas; la capa 5 se aprobó el 31/10/2026 y se terminó el 01/11/2026). Las demás están escritas pero en **borrador**: Jairo las revisa (y puede cambiar la forma de aplicar cada punto) antes de empezar cada capa. **No se implementa una funcionalidad de capa mientras su `requisitos.md` diga «borrador»**; al aprobarla se cambia a «aprobado».

**Orden de las capas (decisión de Jairo, 31/10/2026): 4 → 3 → 5 → 2 → 6.** Los números de las funcionalidades no cambian (la 401 sigue siendo la 401); solo cambia el orden en que se hacen. La tabla está en ese orden. Las capas 4 (31/10/2026) y 5 (01/11/2026) están **hechas** y la capa 3 se salta por ahora (abajo), así que **la siguiente es la capa 2.** Dentro de cada capa, se hacen en el orden de la tabla (en la capa 5 el orden sigue las dependencias, no los números).

- Capa 3: **se salta por ahora** (decisión de Jairo, 31/10/2026). El dictado por voz (302) pasa a hacerse en la capa 5, junto a los reportes por voz (503). El deep learning con TensorFlow sobre fotos en el celular (301) se aprobó y se terminó el 01/11/2026: casco y chaleco en la foto de avance y en un «Control de seguridad» de la app (el celular hace de dispositivo de borde). Desde la 301 la app necesita la *development build* (no corre en Expo Go). Los rostros difuminados (303) quedan **opcionales**. El repositorio `services/ia` (`supervision-ms-ia`) ya existe: lo llenó la 401.
- Capa 5 (aprobada el 31/10/2026, decisiones de Jairo): la 302 pasa a esta capa (Whisper base en el navegador, mf-supervision). Reportes con **constructor** (catálogo de conjuntos + receta del LLM validada por el código + SQL parametrizado) y atajos; tabla, resumen y exportación a Excel y CSV (503). **Host** de los agentes = servicio de IA; servidores MCP internos (HTTP «streamable» en `/mcp`) en Obras, Materiales, Finanzas **y en IA** (`consultar_reporte`, `riesgo_retraso`, `consumos_atipicos`) (501). Los 3 agentes como estaban, con herramientas MCP (502). **Modelo de lenguaje por un puerto** con dos adaptadores: Ollama local (`qwen3:8b`) o la API de Anthropic (`claude-sonnet-5-5`), por `IA_LLM_PROVEEDOR`; las pruebas usan un modelo simulado. Todo lo de la capa 5 en MongoDB `ia_db` (sin DynamoDB). Las pruebas maliciosas (504) corren con las pruebas normales de IA (sin CI todavía). Si se usa `anthropic`, Jairo pone la clave en `services/ia/.env` (o `infra/.env`); nunca en el repositorio.
- **Pendientes de la capa 5 (01/11/2026):**
  - **Pruebas manuales con el modelo real** (503, 502 y 504; última tarea de cada una, sin marcar): se omitieron por decisión de Jairo, porque el código está probado con el modelo simulado (544 pruebas) y por una revisión independiente. Mediciones parciales con `qwen3:8b` en el README de `services/ia`.
  - **`qwen3:8b` no alcanza en la práctica:** 2 de 15 recetas válidas (el código rechaza las inválidas), interpretación de 1,7 a 26,8 s (límite 20 s), dos de los tres agentes fallan por pasar los 60 s por llamada y el de materiales no encontró el stock bajo. Es la calidad del modelo, no la velocidad ni el código: con contexto 8192 y sin límite pasa lo mismo. Opciones: usar Anthropic (clave de Jairo) para la demostración, o mejorar las instrucciones con ejemplos para el modelo local. Por decidir.
  - **Calentar el modelo local:** la primera carga de `qwen3:8b` tarda de 135 a 166 s y una consulta en frío se corta a los 20 s; propuesta: calentar al arrancar `ia-api` e `ia-worker` y mandar `keep_alive: 30m` desde el adaptador de Ollama.
  - **Prueba del dictado (302)** con micrófono en Chrome y Edge: la hace Jairo.

Mismo formato que el sistema base. Cada `diseno.md` de capa termina con «Cambios a contratos y datos»: **la primera tarea al implementar la funcionalidad es aplicar esos cambios** a `docs/contratos/`, `docs/convenciones.md` o `docs/reglas-negocio.md` (si los menciona) y a los `docs/contratos.md` y `docs/datos.md` de cada proyecto afectado (lo que la spec marca como «ya aplicado» ya está en los documentos de esta carpeta).

| N.º | Funcionalidad | Capa | Depende de | Estado |
|---|---|---|---|---|
| 101 | Registro de material sin señal y sincronización sin duplicados (crea `services/sincronizacion`) | 1 | 004 | hecho (sincronizacion, app-obra, infra; aprobada el 30/10/2026) |
| 102 | Fotos sin señal y envío con mala conexión (simplificada: foto completa directo a S3, sin nota de remisión) | 1 | 005, 101 | hecho (sincronizacion, app-obra; aprobada el 30/10/2026) |
| 103 | Diario de obra | 1 | 101 | hecho (obras, sincronizacion, app-obra; aprobada el 30/10/2026) |
| 104 | ERP como PWA y borrador de planilla sin conexión | 1 | 007 | hecho (erp-shell, mf-obras, mf-materiales, mf-supervision; aprobada el 30/10/2026) |
| 401 | Base de reportes: CQRS, modelo de lectura alimentado por eventos, con carga inicial por REST (servicio IA con FastAPI; llena `services/ia`) | 4 | 008 | hecho (ia, obras, materiales, infra, gateway, mf-obras; aprobada el 31/10/2026) |
| 402 | Riesgo de retraso (ML supervisado, XGBoost, datos sintéticos) | 4 | 401 | hecho (ia, gateway, mf-obras, mf-supervision; aprobada el 31/10/2026) |
| 403 | Consumos atípicos (ML no supervisado, Isolation Forest, datos sintéticos) | 4 | 401 (402 opcional: recálculo del riesgo) | hecho (ia, gateway, mf-obras, mf-supervision; aprobada el 31/10/2026) |
| 301 | Detección de casco y chaleco en la app (TensorFlow → TF Lite): en la foto de avance y en el «Control de seguridad» | 3 | 005, 102, 401 (repositorio `services/ia`) | hecho (01/11/2026; modelo `epp-1.0.0`: sin casco sensibilidad 0,88 y precisión 0,93, sin chaleco 0,91 y 0,95; falta la prueba manual en un Android de gama media, que hace Jairo: tiempo ≤ 2 s con 5 personas y 5 fotos de referencia) |
| 303 | Rostros difuminados en las fotos del cliente (**opcional**) | 3 | 007, 008 | pendiente (opcional) |
| 302 | Dictado por voz en el navegador (Whisper base, `q8`, en mf-supervision) | 5 (antes 3) | 009 | hecho (mf-supervision; aprobada el 31/10/2026; falta la prueba manual con micrófono de Jairo) |
| 503 | Reportes generativos por voz: constructor de reportes (catálogo + receta validada), atajos, tabla, resumen y exportación a Excel y CSV; crea el puerto `ModeloLenguaje` (Ollama o Anthropic) | 5 | 302, 401, 402, 403 | hecho (ia, infra, gateway, mf-supervision; aprobada el 31/10/2026; prueba manual con el modelo real pendiente) |
| 501 | Servidores MCP de solo lectura en Obras, Materiales, Finanzas e IA; cliente MCP en el host (IA) | 5 | 401, 402, 403, 503 | hecho (obras, materiales, finanzas, ia, infra; aprobada el 31/10/2026) |
| 502 | Agentes del ERP (Seguimiento de obras, Control de materiales, Control de cobros) | 5 | 501, 402, 403, 503 | hecho (ia, infra, gateway, mf-supervision, mf-obras, mf-materiales; aprobada el 31/10/2026; prueba manual con el modelo real pendiente) |
| 504 | Seguridad de la IA (inyección SQL y de instrucciones; pruebas con las de IA, sin CI) | 5 | 501, 502, 503 | hecho (ia; aprobada el 31/10/2026; prueba manual con el modelo real pendiente) |
| 201 | Cobranza automática (n8n): nota de cobro al cliente, recordatorios, registro de pago y constancia | 2 | 006, 008, 401 | hecho (02/11/2026; finanzas, ia, gateway, mf-obras, infra; falta la prueba de punta a punta de Jairo con n8n y Mailpit: variables del `.env`, recrear Keycloak, perfil `automatizacion`, `pruebas/cobranza.mjs`) |
| 601 | Preparar el despliegue: imágenes Docker de los 6 servicios, configuración de producción por variables, frontends estáticos con configuración al publicar, datos de demostración, CI en GitHub (pruebas y publicación en GHCR), ensayo local en tres grupos con HTTPS y prueba de humo | 6 | — | hecho (05/11/2026; los 6 servicios, gateway, 5 frontends, app e infra; ensayo local con 53 de 53 comprobaciones; falta el recorrido en el navegador de Jairo) |
| 602 | Despliegue en tres nubes (AWS, Google Cloud, Azure): se reescribe al momento de desplegar, con las cuentas disponibles, a partir de la 601 | 6 | 601 | pendiente (borrador viejo; se reescribe al desplegar) |
