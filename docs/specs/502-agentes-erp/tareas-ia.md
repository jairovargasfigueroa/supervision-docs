# 502 · Agentes en el ERP · tareas de `services/ia`

Requisitos y diseño: `docs/specs/502-agentes-erp/` de la carpeta que agrupa los proyectos. Requiere 401 (procesos `ia-api` e `ia-worker`, conexión a `ia_db`, visibilidad), 402 y 403 (repositorios de predicciones y consumos atípicos) y 501 (cliente MCP).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Agregar `ollama` 0.6; variables `IA_OLLAMA_URL`, `IA_OLLAMA_MODELO`, `IA_AGENTES_CRON`, `IA_AGENTES_PROGRAMADOS_ACTIVOS` en `config.py` (Mongo y APScheduler ya vienen de la 401)
- [ ] Repositorios de `ejecucion_agente` y `sugerencia` en `ia_db` con sus índices (incluido el único parcial de sugerencias pendientes)
- [ ] `src/ia/agentes/dominio/definiciones.py`: los tres agentes (misión, herramientas MCP y locales, pasos iniciales, tipos de hallazgo, acciones con su texto)
- [ ] Herramientas locales `riesgo_retraso` (repositorio de `prediccion`, 402) y `consumos_atipicos` (repositorio de `consumo_atipico`, 403), de solo lectura
- [ ] `src/ia/agentes/dominio/reporte.py`: modelos Pydantic del reporte, generación del JSON Schema por agente y validación adicional (obras vistas, evidencias, índices)
- [ ] Puerto `ModeloLenguaje` con adaptador Ollama y un adaptador simulado para pruebas
- [ ] Ejecutor: pasos iniciales, bucle con herramientas (lista permitida, esquema de argumentos, delimitación de resultados), límites de 8 llamadas y 3 minutos, reporte con un reintento
- [ ] En `ia-worker`: toma de ejecuciones desde `ejecucion_agente` (`tomada_en`, una a la vez), programación diaria sin repetir y recuperación de ejecuciones `EN_CURSO` al iniciar
- [ ] Filtros de visibilidad del residente con la utilidad de la 401 (`rpt_obra_resumen.residente_id`) y exclusión de `CONTROL_COBROS`
- [ ] Endpoints en `ia-api`: `GET /agentes`, `POST /agentes/{agente}/ejecuciones`, `GET /ejecuciones`, `GET /ejecuciones/{id}`, `GET /hallazgos`, `GET /sugerencias`, `POST /sugerencias/{id}/aprobar` y `/rechazar`, con roles y errores
- [ ] Pruebas del diseño con el LLM simulado; prueba manual con el modelo real documentada en el README
