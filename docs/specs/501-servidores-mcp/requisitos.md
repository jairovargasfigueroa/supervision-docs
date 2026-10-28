# 501 · Servidores MCP de solo lectura

**Estado:** borrador para aprobar · **Capa:** 5 (puntos 15 y 16) · **Proyectos:** services/obras, services/materiales, services/finanzas, services/ia, infra

## Historia

Como **equipo de la plataforma** queremos que cada microservicio publique sus datos de seguimiento como herramientas MCP de solo lectura, para que los agentes del servicio de IA (502) los consulten con un protocolo estándar, sin leer la base de otro servicio y sin poder modificar nada.

## Criterios de aceptación

### Publicación

1. Obras, Materiales y Finanzas exponen cada uno un servidor MCP en la ruta `/mcp` de su propio puerto (8081, 8082, 8083), con el transporte HTTP «streamable» del estándar MCP.
2. CUANDO un cliente MCP pide la lista de herramientas (`tools/list`), ENTONCES recibe solo estas, cada una con su descripción, su esquema de entrada y su esquema de salida:
   - Obras: `avance_obra`, `buscar_diario`, `planillas_estado`.
   - Materiales: `consumos_partida`, `stock_obra`.
   - Finanzas: `cobros_por_vencer`.
3. Ninguna herramienta crea, modifica ni borra datos. Los servidores no publican recursos (*resources*) ni plantillas (*prompts*) MCP.
4. `asistencia_obra` **no** se publica: el control de asistencia está fuera del alcance (las tablas `trabajador` y `asistencia` son opcionales y no existen).

### Acceso

5. SI la llamada a `/mcp` llega sin token o con un token inválido, ENTONCES el servicio responde `401`.
6. SI el token es válido pero no tiene el rol `agente_ia`, ENTONCES responde `403`. Solo la *service account* del cliente confidencial `ia-agentes` tiene ese rol; ningún usuario humano lo tiene.
7. Con el rol `agente_ia`, las herramientas ven todas las obras (igual que `gerente`). El rol `agente_ia` no da acceso a ningún endpoint REST.

### Comportamiento de las herramientas

8. CUANDO una herramienta recibe argumentos que no cumplen su esquema (tipo, formato, rango o campos de más), ENTONCES devuelve un resultado de error MCP (`isError: true`) con `codigo = "ARGUMENTO_INVALIDO"` y no consulta la base.
9. SI se pide una obra que no existe, ENTONCES devuelve un resultado de error con `codigo = "OBRA_NO_ENCONTRADA"`.
10. Cada herramienta devuelve como máximo el número de filas indicado en su esquema y recorta los textos largos (marca `truncado: true`).
11. Las cifras que devuelven las herramientas salen de las mismas reglas que el sistema base (avance, plazo, riesgo, stock, estado del stock, vencimiento de cobros), con los mismos redondeos.
12. Cada llamada a una herramienta queda registrada en el log del servicio con el nombre de la herramienta, los argumentos, la cantidad de filas devueltas, la duración y el `X-Request-Id` (igual al id de la ejecución del agente).

### Cliente en el servicio de IA

13. El servicio de IA obtiene el token con *client credentials* del cliente `ia-agentes`, lo reutiliza hasta 30 s antes de que venza y descubre las herramientas con `tools/list` al iniciar cada ejecución de agente.
14. SI un servidor MCP no responde en 10 segundos, ENTONCES la llamada cuenta como fallida, se registra en el paso de la ejecución y el agente sigue con las demás herramientas (502).

## Fuera del alcance

Herramientas que escriben, herramientas de asistencia, recursos y *prompts* MCP, acceso de clientes MCP externos (por ejemplo, un asistente de escritorio) y el servidor MCP de Sincronización.
