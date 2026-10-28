# 601 · Contenedores y CI/CD · tareas de `services/ia`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Requiere el proyecto de la 401, que ya crea un `Dockerfile` con los comandos `ia-api` e `ia-worker`. Cuando el repositorio exista, este archivo se copia a `services/ia/docs/specs/601-contenedores-ci/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] `.env.example` completo con todas las variables `IA_*` de la tabla del diseño (401, 402, 403, 501, 502, 503)
- [ ] Completar el `Dockerfile` de la 401: `python:3.12-slim` en dos etapas con `uv sync --frozen --no-dev`, usuario sin privilegios, `modelos/` incluido, `entrenamiento/` y `ml/` excluidos; `alembic upgrade head` al iniciar `ia-api`; `.dockerignore`
- [ ] `.github/workflows/ci-cd.yml`: `uv sync --frozen`, `ruff` y `pytest` (con PostgreSQL de servicio e incluidas las pruebas de seguridad de la 504), imagen en Artifact Registry, despliegue de `ia-api` e `ia-worker` en la VM por `gcloud compute ssh --tunnel-through-iap`
- [ ] Comprobar: la misma imagen arranca como `ia-api` (`/salud` responde) y como `ia-worker` (se conecta a RabbitMQ), sin `root`
