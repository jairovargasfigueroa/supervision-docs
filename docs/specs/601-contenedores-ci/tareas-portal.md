# 601 · Preparar el despliegue · tareas de `frontend/portal`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `frontend/portal/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] Cargar `configuracion.json` antes de montar React (Keycloak, Obras y ERP) con respaldo a los valores de desarrollo; pruebas
- [ ] `Dockerfile` (compilación + `nginx-unprivileged`), `nginx.conf` y script que genera `configuracion.json` con `envsubst`; prueba con `docker run`
- [ ] `.github/workflows/ci.yml`: job `prueba` (lint, pruebas y compilación) y job `imagen` (build en PR; *push* a GHCR con `sha-<7>` y `main` en `main`)
