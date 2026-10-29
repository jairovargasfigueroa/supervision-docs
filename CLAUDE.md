# Plataforma de supervisión de obras

Plataforma de una empresa constructora para controlar sus obras: preparar la obra (contrato y presupuesto), registrar en campo el avance y el material, controlar avance y consumo, y cobrar al cliente con planillas de avance. Proyecto de Ingeniería de Software II (UAGRM). Equipo de 3 personas; el código lo escribe la IA a partir de la especificación.

Esta carpeta es el repo **`supervision-docs`**: contiene este archivo, `docs/` (especificación de todo el proyecto), `scripts/` y el prototipo. Cada proyecto de adentro es **su propio repositorio** (está en el `.gitignore` de este). Quien se suma al equipo empieza por `docs/preparar-maquina.md`.

**Estado actual:** fase 1 (entorno y esqueleto que camina). La siguiente tarea está en `docs/plan.md`. No implementes una funcionalidad del negocio sin su especificación aprobada (`requisitos.md`, `diseno.md`, `tareas.md`).

## Mapa de proyectos

| Carpeta | Tecnología | Qué es | Etapa |
|---|---|---|---|
| `services/obras` | Java 21 · Spring Boot 4.1 · PostgreSQL | Obras, presupuesto, avance, planillas; orquesta la saga | Base |
| `services/materiales` | NestJS 12 · TypeScript · MongoDB | Catálogo, stock, ingresos y salidas | Base |
| `services/finanzas` | PHP 8.3 · Laravel 13 · PostgreSQL | Contratos, cobros, órdenes de compra, cuentas por pagar | Base |
| `gateway` | NestJS 12 · GraphQL (Apollo Server 5) | Única entrada del ERP (BFF) | Base |
| `frontend/erp-shell` | Angular 22 · Native Federation (host) | Contenedor del ERP: sesión, menú, carga microfrontends | Base |
| `frontend/mf-obras` | Angular 22 · Native Federation (remoto) | Microfrontend de Obras | Base |
| `frontend/mf-materiales` | React 19 · Native Federation (adaptador esbuild) | Microfrontend de Materiales | Base |
| `frontend/mf-supervision` | React 19 · Native Federation (adaptador esbuild) | Tablero, agentes y voz | Base (tablero) y capa 5 |
| `frontend/portal` | React 19 · Vite 8 | Portal del cliente | Base |
| `mobile/app-obra` | Expo SDK 58 · React Native 0.88 | App de obra (maestro de obra y almacenero) | Base y capa 1 |
| `infra` | Docker Compose · realm de Keycloak | Entorno de desarrollo (RabbitMQ, Keycloak, bases) y pruebas de punta a punta | Fase 1 (todavía no existe) |
| `services/notificaciones` | NestJS · MongoDB · Firebase | Notificaciones *push* y bandeja | Funcionalidad 010 (todavía no existe) |
| `services/sincronizacion` | NestJS · DynamoDB | Recibe lo del celular sin duplicar | Capa 1 (todavía no existe) |
| `services/ia` | Python · FastAPI | Agentes, ML, reportes por voz, base de reportes | Capas 3 a 5 (todavía no existe) |

Repositorios (públicos): `https://github.com/jairovargasfigueroa/supervision-<nombre>`, con `ms-obras`, `ms-materiales`, `ms-finanzas`, `gateway`, `erp-shell`, `mf-obras`, `mf-materiales`, `mf-supervision`, `portal` y `app-obra` (y `infra`, `ms-sincronizacion`, `ms-ia` y `ms-notificaciones` cuando se creen), más `supervision-docs` para esta carpeta. Ramas `main` (estable) y `develop` (integración), protegidas: todo entra por *pull request* (Git Flow, `docs/flujo-trabajo.md`). Al ser públicos, revisa que nada con contraseñas entre en un commit.

Herramientas: **Node 24 LTS** para todos los proyectos JavaScript (activar con `nvm use 24`; en la terminal Bash de esta máquina aparece primero un Node 20 viejo de `~/.nvm`: antepón `export PATH="/c/nvm4w/nodejs:$PATH"` o usa PowerShell, y comprueba con `node -v`), Java 21, PHP 8.5 de Herd (ejecutar Laravel desde PowerShell; el PHP 8.2 de XAMPP no sirve). Las versiones elegidas y el porqué están en `docs/arquitectura.md` («Versiones»).

## Documentos transversales (`docs/`)

- `docs/producto.md`: qué es la plataforma, usuarios, aplicaciones, sistema base, capas y qué queda fuera.
- `docs/puntos.md`: los puntos que pidió el ingeniero, dónde y cómo se aplica cada uno.
- `docs/arquitectura.md`: piezas, conexiones, protocolos y despliegue en 3 nubes.
- `docs/reglas-negocio.md`: reglas que cruzan proyectos (planilla, estados, stock, contrato).
- `docs/convenciones.md`: lo que todos los proyectos hacen igual (token, errores, idempotencia, outbox, nombres).
- `docs/stack.md`: librerías de cada proyecto y por qué (no agregar otras para lo mismo).
- `docs/diseno-visual.md`: colores, tipografía, estados y tema común (Angular Material, MUI y React Native Paper).
- `docs/flujo-trabajo.md`: ramas, commits, *pull requests*, protección de `main`, quién hace qué y **definición de terminado**.
- `docs/preparar-maquina.md` y `docs/entorno-local.md`: herramientas, clonado, Docker Compose (versiones de imágenes), variables de entorno y orden de arranque.
- `docs/permisos.md`: matriz única de qué puede hacer cada rol.
- `docs/mensajes.md`: texto que ve el usuario para cada código de error y aviso.
- `docs/datos-prueba.md`: datos de prueba con ids fijos.
- `docs/contratos/`: cómo se hablan los proyectos (GraphQL del ERP, REST, eventos y saga).
- `docs/specs/`: funcionalidades que cruzan varios proyectos.
- `docs/plan.md`: orden de trabajo y estado. **Empieza siempre por aquí.**

Cada proyecto tiene además su `CLAUDE.md` y su `docs/` (con `estructura.md`, obligatorio antes de programar): los servicios con `servicio.md`, `datos.md`, `contratos.md` y `specs/`; el gateway, los frontends y la app con `app.md`, `contratos.md` y `specs/`.

## Principios

1. **No inventes reglas del negocio, endpoints, eventos ni campos.** Si algo no está en la especificación, pregunta antes de seguir.
2. **Lee la especificación antes de programar:** `docs/plan.md`, la spec de la funcionalidad y los contratos del proyecto.
3. **Los contratos mandan.** Un proyecto no cambia lo que expone o consume sin actualizar `docs/contratos/` y el `docs/contratos.md` de cada proyecto afectado.
4. **Cada servicio es dueño de sus datos.** Nadie lee la base de otro servicio; se pide por su API o se escucha su evento.
5. **Una tarea a la vez**, con sus pruebas, y se marca en `tareas.md` al terminar.
6. **Si una decisión cambia, actualiza la documentación** en el mismo trabajo.
7. **Usa nombres del dominio en español** (obra, partida, planilla, cobro) en código, tablas y endpoints.

## Cómo trabajar en cada chat

Las especificaciones están escritas: las del sistema base (fase 1 y 001–011) están **aprobadas**; las de las capas (101–602) están en **borrador** hasta que Jairo las revise. No hay que volver a planificar lo aprobado: se implementa.

1. Lee `docs/plan.md` y toma la **siguiente tarea `pendiente`** (fase 1) o la **siguiente funcionalidad `pendiente`** (fases 2 en adelante).
2. Para una funcionalidad, lee su `docs/specs/NNN-nombre/requisitos.md` y `diseno.md`, los contratos y datos de cada proyecto afectado, y sus `tareas.md` (`<proyecto>/docs/specs/NNN-nombre/tareas.md`; las de proyectos que todavía no existen están en `docs/specs/NNN-nombre/tareas-<proyecto>.md`).
3. Antes de programar: en cada repo que toca, crea la rama `feat/NNN-nombre` desde `develop` actualizado. Nunca trabajes ni hagas *push* en `main` ni en `develop`.
4. Implementa **tarea por tarea**, en el orden de los proyectos que indica el diseño (servicios → gateway → frontends → app). Cada tarea cumple la **definición de terminado** de `docs/flujo-trabajo.md` (pruebas, lint, tipos, docs).
5. Al terminar cada tarea: marca `- [x]` en su `tareas.md`, haz **un commit** en la rama (Conventional Commits en español) y `git push`.
6. Al terminar la funcionalidad: actualiza `docs/plan.md` en una rama de `supervision-docs`, sube todas las ramas y entrega al usuario, por cada repo, el **título y la descripción del PR** (plantilla completa, enlaces entre repos, orden de fusión) y qué debe probar a mano (sección «Pruebas» del diseño). **El usuario crea y fusiona los PR desde GitHub**; el agente no los crea ni los fusiona.
7. Si algo de la especificación es imposible o contradictorio, no lo inventes: detente, explícalo y propone el cambio; si el usuario lo aprueba, actualiza la spec y los contratos en el mismo trabajo.

Un chat avanza una funcionalidad (o varias tareas de la fase 1). Cuando el chat se hace largo, el usuario abre otro y este vuelve a empezar por el paso 1: el estado vive en `docs/plan.md` y en las casillas de los `tareas.md`.

GitHub CLI está en `C:\Program Files\GitHub CLI\gh.exe` (con sesión iniciada); úsalo para crear los repos nuevos como públicos (`supervision-infra`, `supervision-ms-sincronizacion`, `supervision-ms-ia`, `supervision-ms-notificaciones`), agregarlos a `scripts/repos.ps1`, y configurarlos con `scripts/configurar-repos.ps1`.

En las capas, cada `diseno.md` termina con «Cambios a contratos y datos»: aplícalos como primera tarea de esa funcionalidad, antes de programar.

## Reglas transversales clave

- GraphQL **solo** entre el ERP y el gateway; todo lo demás es REST o eventos.
- Las acciones de un solo servicio van por REST; la saga y la automatización van por eventos (RabbitMQ).
- Saga principal: **aprobar planilla** (Obras orquesta; Finanzas reserva saldo y emite cobro; Materiales cierra consumos).
- Todo registro creado en el celular lleva un identificador único generado en el celular; el servidor no lo procesa dos veces.
- Los eventos se publican con el patrón outbox y se procesan una sola vez (tabla de mensajes procesados).
- La autenticación es con Keycloak (OIDC). Los roles viajan en el token; las reglas finas (qué obras ve cada usuario) las valida cada servicio.
- La IA nunca escribe SQL ni ejecuta acciones: elige reportes de una lista y propone acciones que una persona aprueba.

## Commits

- Formato *Conventional Commits*, **en español**, en modo imperativo: `tipo(alcance): descripción`.
- Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`, `style`, `perf`.
- Ejemplos: `feat(planillas): agrega cálculo del neto a cobrar`, `docs: agrega reglas de la planilla`, `chore: configura estructura hexagonal`.
- Los commits van a nombre del usuario configurado en git. **No agregues coautoría ni firmas de la IA** en los mensajes.
- Nunca subas `.env`, `.env.properties` ni otros archivos con contraseñas.

## Fuera del alcance

Registro de usuarios (se gestionan en el panel de Keycloak), alta de trabajadores y proveedores (vienen como datos iniciales), registro de pagos, aprobación de compras de monto alto, incidentes, planos, órdenes de cambio, contabilidad y facturación ante Impuestos Nacionales.
