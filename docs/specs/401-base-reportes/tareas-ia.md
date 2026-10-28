# 401 · Servicio de IA y base de reportes · tareas de `services/ia`

Requisitos y diseño: `docs/specs/401-base-reportes/` de esta carpeta. Si el repositorio `services/ia` ya existe por la 301 (solo con `entrenamiento/`), estas tareas agregan el servicio en el mismo repositorio.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Crear el proyecto y su repositorio si no existen (GitHub `supervision-ms-ia`, rama `main`); `pyproject.toml` con `uv` y Python 3.12, `.env.example`, `.gitignore`, `Dockerfile` (una imagen, dos comandos: `ia-api` e `ia-worker`)
- [ ] `CLAUDE.md` del proyecto y `docs/` (`servicio.md`, `datos.md`, `contratos.md`, `specs/README.md`) con lo de esta spec
- [ ] Esqueleto FastAPI en el puerto 8085: `GET /salud`, Problem Details, `X-Request-Id`, registros JSON/texto; pruebas
- [ ] Validación del token con `PyJWT` (`PyJWKClient`, emisor, audiencia `plataforma-api`), roles y visibilidad por `residente_id`; pruebas con tokens firmados en la prueba
- [ ] Alembic: migración inicial de `reportes_db` (`rpt_obra_resumen`, `rpt_planilla`, `rpt_consumo_material`, `rpt_movimiento`, `rpt_cobro`, `evento_aplicado`) y conexión a `ia_db`
- [ ] Dominio de `reportes`: avance, plazo transcurrido y vencimiento con fechas fijas; pruebas
- [ ] Worker: conexión `aio-pika`, cola `ia` y enlaces, inbox en la misma transacción, reintentos con `x-intentos` y `plataforma.fallidos`; pruebas con canal simulado
- [ ] Proyecciones de los 6 eventos (incluido el orden indistinto de `CobroEmitido` y `PlanillaAprobada`); pruebas con PostgreSQL real
- [ ] Tareas programadas (00:20 cobros vencidos, 00:30 plazo) con `apscheduler`; pruebas de las funciones que llaman
- [ ] `GET /reportes/estado` (rol `admin`); pruebas
