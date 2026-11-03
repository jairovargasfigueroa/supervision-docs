# 601 · Preparar el despliegue · tareas de `frontend/mf-supervision`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `frontend/mf-supervision/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] Revisar que la dirección del gateway solo salga de `window.plataforma.configuracion` (respaldo de desarrollo); el modelo de Whisper sigue bajando de Hugging Face
- [ ] `Dockerfile` (compilación + `nginx-unprivileged`, con el *worker* de Whisper) y `nginx.conf` con CORS para el shell; prueba con `docker run`
- [ ] `.github/workflows/ci.yml`: job `prueba` (tipos, pruebas y compilación) y job `imagen` (build en PR; *push* a GHCR con `sha-<7>` y `main` en `main`)
