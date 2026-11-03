# 601 · Preparar el despliegue · tareas de `services/obras`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `services/obras/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] Revisar que no quede ninguna dirección fija; agregar `OBRAS_DB_SSLMODE`, `OBRAS_RABBITMQ_SSL` y el perfil `prod` (sin trazas al usuario, registros por la salida estándar)
- [ ] `Dockerfile` en dos etapas y `.dockerignore` (JRE 21, sin `root`, `HEALTHCHECK`, etiqueta OCI); prueba `docker build` + `docker run` con `/salud`
- [ ] Semilla: excepción `SEMILLA_DEMO=si` en la guarda (solo carga; el vaciado sigue prohibido fuera de desarrollo); pruebas
- [ ] `.github/workflows/ci.yml`: job `prueba` (`./mvnw -B verify`) y job `imagen` (build en PR; *push* a GHCR con `sha-<7>` y `main` en `main`)
