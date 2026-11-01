# 501 · Servidores MCP de solo lectura

**Estado:** aprobado (31/10/2026) · **Capa:** 5 (puntos 15 y 16) · **Proyectos:** services/obras, services/materiales, services/finanzas, services/ia, infra · **Depende de:** 401, 402, 403 y 503 (motor de reportes de `consultar_reporte`)

**Arquitectura decidida por Jairo (31/10/2026):**

- El **host** de los agentes es el servicio de IA: tiene el modelo de lenguaje, la lógica de los agentes (502) y el **cliente MCP**.
- **Servidores MCP privados e internos, remotos** (HTTP «streamable», en la ruta `/mcp`) en **Obras, Materiales y Finanzas**, para el dato al instante de cada dueño, **y también en el servicio de IA**, para lo que solo él sabe: `consultar_reporte` (el mismo motor de la 503), las predicciones de riesgo de la 402 y los consumos atípicos de la 403.
- Los reportes de las personas van por **REST** (gateway → IA, 503); el mismo motor se publica por MCP para los agentes.
- Herramientas **pocas y pensadas por tarea**, con descripciones claras, esquemas estrictos de entrada y salida, respuestas compactas (límite de filas y `truncado`), errores como resultado (`isError`) y **solo lectura**.
- Token técnico del cliente `ia-agentes` (rol `agente_ia`), que solo sirve en `/mcp`. Cada agente solo ve sus herramientas (mínimo privilegio, 502).

## Historia

Como **equipo de la plataforma** queremos que cada microservicio, incluido el de IA, publique sus datos de seguimiento como herramientas MCP de solo lectura, para que los agentes del servicio de IA (502) los consulten con un protocolo estándar, sin leer la base de otro servicio y sin poder modificar nada.

## Criterios de aceptación

### Publicación

1. Obras, Materiales, Finanzas e IA exponen cada uno un servidor MCP en la ruta `/mcp` de su propio puerto (8081, 8082, 8083 y 8085), con el transporte HTTP «streamable» del estándar MCP. Son **privados**: solo los llama el servicio de IA con el token de `ia-agentes`; no pasan por el gateway ni los usan clientes externos. En desarrollo van por la red local; en el despliegue (602), entre nubes por HTTPS.
2. CUANDO un cliente MCP pide la lista de herramientas (`tools/list`), ENTONCES recibe solo estas, cada una con su descripción, su esquema de entrada y su esquema de salida:
   - Obras: `avance_obra`, `buscar_diario`, `planillas_estado`.
   - Materiales: `consumos_partida`, `stock_obra`.
   - Finanzas: `cobros_por_vencer`.
   - IA: `consultar_reporte`, `consumos_atipicos`, `riesgo_retraso`.
3. Ninguna herramienta crea, modifica ni borra datos, y todas se anuncian como de solo lectura. Los servidores no publican recursos (*resources*) ni plantillas (*prompts*) MCP.
4. `asistencia_obra` **no** se publica: el control de asistencia está fuera del alcance (las tablas `trabajador` y `asistencia` son opcionales y no existen).
5. Las descripciones están en español, dicen qué devuelve la herramienta y cuándo conviene usarla, y no contienen instrucciones para el modelo.

### Acceso

6. SI la llamada a `/mcp` llega sin token o con un token inválido, ENTONCES el servicio responde `401`.
7. SI el token es válido pero no tiene el rol `agente_ia`, ENTONCES responde `403`. Solo la *service account* del cliente confidencial `ia-agentes` tiene ese rol; ningún usuario humano lo tiene.
8. Con el rol `agente_ia`, las herramientas ven todas las obras (igual que `gerente`). El rol `agente_ia` no da acceso a ningún endpoint REST (tampoco a los del servicio de IA).

### Comportamiento de las herramientas

9. CUANDO una herramienta recibe argumentos que no cumplen su esquema (tipo, formato, rango o campos de más), ENTONCES devuelve un resultado de error MCP (`isError: true`) con `codigo = "ARGUMENTO_INVALIDO"` y no consulta la base.
10. SI se pide una obra que no existe, ENTONCES devuelve un resultado de error con `codigo = "OBRA_NO_ENCONTRADA"`.
11. Cada herramienta devuelve como máximo el número de filas indicado en su esquema, dice si recortó (`truncado: true`) y recorta los textos largos.
12. Las cifras que devuelven las herramientas salen de las mismas reglas que el sistema base y la capa 4 (avance, plazo, riesgo, stock, estado del stock, vencimiento de cobros, predicciones, consumos atípicos), con los mismos redondeos.
13. `consultar_reporte` recibe una receta del catálogo de la 503 (modo para agentes) y la valida igual que para las personas; una receta inválida es un `ARGUMENTO_INVALIDO` con la lista de problemas.
14. Cada llamada a una herramienta queda registrada en el log del servicio con el nombre de la herramienta, los argumentos, la cantidad de filas devueltas, la duración y el `X-Request-Id` (igual al id de la ejecución del agente).

### Cliente en el servicio de IA (host)

15. El servicio de IA obtiene el token con *client credentials* del cliente `ia-agentes`, lo reutiliza hasta 30 s antes de que venza y descubre las herramientas con `tools/list` de los cuatro servidores al iniciar cada ejecución de agente.
16. SI un servidor MCP no responde en 10 segundos, ENTONCES la llamada cuenta como fallida, se registra en el paso de la ejecución y el agente sigue con las demás herramientas (502).
17. SI un servidor publica una herramienta que no está en el contrato, o con otro esquema, ENTONCES el cliente la ignora y registra una advertencia.

## Fuera del alcance

Herramientas que escriben, herramientas de asistencia, recursos y *prompts* MCP, acceso de clientes MCP externos (por ejemplo, un asistente de escritorio), que otro cliente que no sea el servicio de IA use los servidores MCP y el servidor MCP de Sincronización.
