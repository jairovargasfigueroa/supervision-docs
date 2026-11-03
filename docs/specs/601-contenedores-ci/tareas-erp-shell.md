# 601 · Preparar el despliegue · tareas de `frontend/erp-shell`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `frontend/erp-shell/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] Cargar `configuracion.json` antes de iniciar (inicializador de Angular) con respaldo a los valores de desarrollo; `federation.manifest.json` con las direcciones de los remotos; pruebas
- [ ] `Dockerfile` (compilación + `nginx-unprivileged`), `nginx.conf` (SPA, sin caché en los archivos de configuración y del *service worker*) y script de `/docker-entrypoint.d/` que genera los dos archivos con `envsubst`; prueba con `docker run`
- [ ] `.github/workflows/ci.yml`: job `prueba` (pruebas y compilación) y job `imagen` (build en PR; *push* a GHCR con `sha-<7>` y `main` en `main`)
