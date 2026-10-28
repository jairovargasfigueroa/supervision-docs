# Flujo de trabajo con Git y GitHub

Cómo trabajamos los tres (y el agente) sin pisarnos. Sigue **GitHub Flow**: `main` siempre funciona, todo cambio entra por una rama y un *pull request* revisado.

## Repositorios

- `supervision-docs`: esta carpeta raíz (CLAUDE.md, `docs/`, prototipo). Las carpetas de los proyectos están en su `.gitignore`.
- Un repo por proyecto: `supervision-ms-obras`, `supervision-ms-materiales`, `supervision-ms-finanzas`, `supervision-gateway`, `supervision-erp-shell`, `supervision-mf-obras`, `supervision-mf-materiales`, `supervision-mf-supervision`, `supervision-portal`, `supervision-app-obra`, y los que se creen (`supervision-infra`, `supervision-ms-sincronizacion`, `supervision-ms-ia`, `supervision-ms-notificaciones`).

## Protección de `main` (en todos los repos)

- No se permite *push* directo ni *force push* a `main`.
- Todo entra por *pull request* con **1 aprobación** de otra persona del equipo.
- Cuando exista CI (601), los checks deben pasar antes de fusionar.
- Método de fusión permitido: **solo *squash and merge***; la rama se borra al fusionar.
- Se configura con el script `scripts/configurar-repos.ps1` (tarea 1.0 del plan).

## Ramas

- Nombre: `<tipo>/<número>-<descripcion-corta>` en minúsculas con guiones.
  - Funcionalidad: `feat/002-registrar-obra`
  - Tarea técnica de la fase 1: `chore/1.2-docker-compose`
  - Corrección: `fix/007-redondeo-neto`
  - Documentación: `docs/convenciones-paginacion`
- **Una funcionalidad usa el mismo nombre de rama en cada repo que toca.** Por ejemplo, la 002 crea `feat/002-registrar-obra` en ms-obras, ms-finanzas, ms-materiales, gateway y mf-obras.
- Se crea desde `main` actualizado: `git switch main && git pull && git switch -c feat/002-registrar-obra`.
- Ramas cortas: una funcionalidad no debería tardar más de unos días. Si `main` avanza, se trae con `git merge main` (no se reescribe una rama que ya tiene revisión).

## Commits

- *Conventional Commits* en español e imperativo (ver `CLAUDE.md`): `feat(planillas): agrega cálculo del neto a cobrar`.
- **Un commit por tarea** del `tareas.md`, con la casilla marcada en el mismo commit. En el cuerpo, la referencia: `Tarea: 007 · services/obras · 2`.
- A nombre de la persona que trabaja (su `user.name`/`user.email` de git). Sin coautoría ni firmas de la IA.

## Pull requests

- Uno por repo y funcionalidad. Se abre en **borrador** al empezar y se marca listo al terminar todas las tareas de ese repo.
- Título = el commit que quedará en `main` al hacer *squash*: `feat(obras): registra obra con contrato y presupuesto (002)`.
- Descripción con la plantilla `.github/pull_request_template.md` (cada repo la tiene):
  - Qué cambia y funcionalidad (`docs/specs/NNN-...`).
  - Tareas cubiertas.
  - PR relacionados en otros repos (enlaces).
  - Cómo probarlo.
  - Lista de «terminado» (abajo).
- Orden de fusión cuando una funcionalidad toca varios repos: **servicios → gateway → frontends → app**. Así `main` de cada repo nunca depende de algo que todavía no está en el `main` de otro.
- El agente abre los PR con GitHub CLI (`gh pr create`) pero **no los fusiona**: los revisa y fusiona una persona.

## Quién hace qué

- En `docs/plan.md` cada funcionalidad tiene las columnas **Responsable** y **Rama**. Antes de empezar, la persona pone su nombre y la rama, y hace commit en `supervision-docs` (por PR, como todo).
- Se pueden trabajar en paralelo las funcionalidades cuyas dependencias (columna «Depende de») ya están `hecho`.
- Al terminar (todos los PR fusionados), el estado pasa a `hecho` en el mismo PR de `supervision-docs` que marca las tareas.

## Definición de terminado

**Una tarea** está terminada cuando:

1. Hace lo que dice su `tareas.md` y cumple el diseño.
2. Tiene sus pruebas y **todas las pruebas del proyecto pasan** (`./mvnw verify`, `npm test`, `php artisan test`, etc.).
3. Pasan el lint, el formato y la revisión de tipos del proyecto (los comandos están en su `CLAUDE.md`).
4. Si cambió un contrato, un dato o una regla, la documentación está actualizada en el mismo commit.
5. No hay secretos en el commit ni `console.log`/`print` de depuración.
6. Su casilla está marcada en `tareas.md`.

**Una funcionalidad** está terminada cuando:

1. Todas sus tareas, en todos sus repos, están terminadas y sus PR fusionados en `main`.
2. Cada criterio de aceptación de `requisitos.md` se comprobó (automático o a mano) y se anotó cómo en el PR.
3. La prueba manual de la sección «Pruebas» del diseño la hizo una persona del equipo con los datos de prueba.
4. Su estado está en `hecho` en `docs/plan.md`.

## Versiones

- Al cerrar cada fase se etiqueta cada repo con *semver*: `v0.1.0` (fase 1), `v0.2.0` (sistema base), `v0.3.0`, … (cada capa), `v1.0.0` (despliegue final).
- `git tag -a v0.2.0 -m "Sistema base" && git push --tags`.
