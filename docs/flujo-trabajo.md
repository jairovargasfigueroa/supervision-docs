# Flujo de trabajo con Git y GitHub

Por ahora trabaja una sola persona (Jairo, con el agente); más adelante pueden sumarse colaboradores. Se sigue **Git Flow** con *pull requests*: nada se sube directo a `main` ni a `develop`.

## Repositorios

- `supervision-docs`: esta carpeta raíz (CLAUDE.md, `docs/`, `scripts/`, prototipo). Las carpetas de los proyectos están en su `.gitignore`.
- Un repo por proyecto: `supervision-ms-obras`, `supervision-ms-materiales`, `supervision-ms-finanzas`, `supervision-gateway`, `supervision-erp-shell`, `supervision-mf-obras`, `supervision-mf-materiales`, `supervision-mf-supervision`, `supervision-portal`, `supervision-app-obra`, y los que se creen (`supervision-infra`, `supervision-ms-sincronizacion`, `supervision-ms-ia`, `supervision-ms-notificaciones`). Los nombres están en `scripts/repos.ps1`.

## Ramas

| Rama | Para qué | Sale de | Entra a |
|---|---|---|---|
| `main` | Versión estable, la que se entrega o despliega. Cada fusión lleva una etiqueta de versión | — | — |
| `develop` | Integración: lo terminado que todavía no se publicó. Es la rama por defecto en GitHub | `main` (una vez) | `main` por `release/*` |
| `feat/<nº>-<descripcion>` | Una funcionalidad o tarea de la fase 1 | `develop` | `develop` |
| `fix/<nº>-<descripcion>` | Corrección de algo ya fusionado en `develop` | `develop` | `develop` |
| `docs/`, `chore/`, `refactor/`, `test/`, `ci/` `<descripcion>` | Cambios de ese tipo que no son una funcionalidad | `develop` | `develop` |
| `release/<versión>` | Preparar una entrega: último ajuste, versión y notas | `develop` | `main` (y de vuelta a `develop`) |
| `hotfix/<versión>-<descripcion>` | Corrección urgente de algo ya publicado en `main` | `main` | `main` y `develop` |

Ejemplos: `feat/002-registrar-obra`, `feat/1.2-docker-compose`, `fix/007-redondeo-neto`, `docs/flujo-git`, `release/0.2.0`, `hotfix/0.2.1-login-portal`.

- Nombres en minúsculas, con guiones y sin tildes.
- **Una funcionalidad que toca varios repos usa el mismo nombre de rama en cada uno.** Por ejemplo, la 002 crea `feat/002-registrar-obra` en ms-obras, ms-finanzas, ms-materiales, gateway y mf-obras.
- Se crea desde `develop` actualizado: `git switch develop && git pull && git switch -c feat/002-registrar-obra`.
- Si `develop` avanza mientras se trabaja, se trae con `git merge develop` dentro de la rama (no se reescribe historia ya subida).
- Las ramas se borran al fusionarse.

## Commits

- *Conventional Commits* en español e imperativo: `feat(planillas): agrega cálculo del neto a cobrar`. Tipos: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `build`, `ci`, `style`, `perf`.
- **Un commit por tarea** del `tareas.md`, con su casilla marcada en el mismo commit. En el cuerpo, la referencia: `Tarea: 007 · services/obras · 2`.
- A nombre de quien trabaja (`user.name`/`user.email` de git). Sin coautoría ni firmas de la IA.
- Nunca `git push --force` a ramas compartidas; nunca commits con secretos.

## Pull requests

- **Los crea y fusiona el agente** con GitHub CLI (`gh pr create` y `gh pr merge --squash --delete-branch`), uno por repo y rama, hacia `develop`, cuando la rama cumple la definición de terminado (todas las pruebas pasan). Jairo no tiene que hacer nada en GitHub; revisa el resultado probando en el navegador.
- Hacia `main` (ramas `release/*` y `hotfix/*`) **solo cuando Jairo lo pide** («haz el release de la fase 1»).
- Título = commit que quedará al fusionar: `feat(obras): registra obra con contrato y presupuesto (002)`.
- Descripción con la plantilla `.github/pull_request_template.md` (cada repo la tiene): qué cambia, funcionalidad, tareas, PR relacionados en otros repos, cómo probar y la lista de terminado.
- **Forma de fusionar:**
  - `feat/*`, `fix/*` y demás → `develop`: ***squash and merge*** (un commit limpio por rama).
  - `release/*` y `hotfix/*` → `main`: ***merge commit*** (conserva el historial de `develop`); después se fusiona `main` en `develop`.
- Orden de fusión cuando una funcionalidad toca varios repos: **servicios → gateway → frontends → app**.
- Mientras trabaje una sola persona no se exige aprobación; cuando se sumen colaboradores se sube a 1 aprobación (cambiando `scripts/configurar-repos.ps1`) y el agente deja los PR abiertos para revisión en vez de fusionarlos.

## Protección de ramas (en todos los repos)

- `main` y `develop`: sin *push* directo ni *force push*, sin borrado; todo por PR (también para el dueño); aprobaciones requeridas: 0 por ahora; conversaciones resueltas antes de fusionar; cuando exista CI (601), los checks deben pasar.
- Métodos de fusión permitidos: *squash* y *merge commit* (sin *rebase*). Borrar la rama al fusionar.
- Se aplica con `scripts/configurar-repos.ps1` (tarea 1.0), que también crea `develop` y la deja como rama por defecto.

## Versiones y entregas

- *Semver* por repo. Al cerrar cada fase: `release/x.y.0` desde `develop` → PR a `main` → etiqueta `vx.y.0` en `main` → `main` de vuelta a `develop`.
  - `v0.1.0` fase 1 · `v0.2.0` sistema base · `v0.3.0` … una por capa · `v1.0.0` despliegue final.
- `git tag -a v0.2.0 -m "Sistema base" && git push origin v0.2.0`.

## Definición de terminado

**Una tarea** está terminada cuando:

1. Hace lo que dice su `tareas.md` y cumple el diseño.
2. Tiene sus pruebas y **todas las pruebas del proyecto pasan** (`./mvnw verify`, `npm test`, `php artisan test`, etc.).
3. Pasan el lint, el formato y la revisión de tipos del proyecto (comandos en su `CLAUDE.md`).
4. Si cambió un contrato, un dato o una regla, la documentación está actualizada en el mismo commit.
5. No hay secretos en el commit ni mensajes de depuración (`console.log`, `print`).
6. Su casilla está marcada en `tareas.md`.

**Una funcionalidad** está terminada cuando:

1. Todas sus tareas, en todos sus repos, están terminadas y sus PR fusionados en `develop`.
2. Cada criterio de aceptación de `requisitos.md` se comprobó (automático o a mano) y se anotó cómo en el PR.
3. La prueba manual de la sección «Pruebas» del diseño se hizo con los datos de prueba.
4. Su estado está en `hecho` en `docs/plan.md`.
