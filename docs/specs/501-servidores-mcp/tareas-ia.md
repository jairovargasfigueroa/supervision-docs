# 501 · Servidores MCP · tareas de `services/ia`

Requisitos y diseño: `docs/specs/501-servidores-mcp/` de la carpeta que agrupa los proyectos. Requiere el servicio `services/ia` de la 401 (estructura `src/ia/`, `config.py`, validación del token).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Agregar el paquete `mcp` 2 y las variables `IA_AGENTES_CLIENT_ID`, `IA_AGENTES_CLIENT_SECRET`, `IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL` en `config.py` (con `.env.example`)
- [ ] `src/ia/mcp/token.py`: token por *client credentials* con caché hasta 30 s antes del vencimiento; pruebas con un Keycloak simulado
- [ ] `src/ia/mcp/cliente.py`: `listar_herramientas()` y `llamar()` con `Authorization`, `X-Request-Id` y tiempo máximo de 10 s
- [ ] `src/ia/mcp/catalogo.py`: mapa herramienta → servidor y comparación de esquemas con `tools/list` (herramientas desconocidas se ignoran con advertencia)
- [ ] Pruebas contra un servidor MCP de prueba hecho con el mismo SDK (camino feliz, servidor caído, servidor lento, herramienta desconocida)
