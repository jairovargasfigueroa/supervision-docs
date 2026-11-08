# 501 · Diseño

## Arquitectura (decisión de Jairo, 31/10/2026)

```
                     servicio de IA = HOST de los agentes
        ┌────────────────────────────────────────────────────────────┐
        │ ia-worker: agentes (502) + ModeloLenguaje (503) + cliente MCP │
        └───────┬─────────────┬─────────────┬────────────────┬─────────┘
   token ia-agentes (agente_ia) · HTTP «streamable» sin estado · POST /mcp · privados
                │             │             │                │
        Obras :8081/mcp  Materiales :8082/mcp  Finanzas :8083/mcp  IA (ia-api) :8085/mcp
        avance_obra      stock_obra          cobros_por_vencer    consultar_reporte (motor de la 503)
        buscar_diario    consumos_partida                         riesgo_retraso (402)
        planillas_estado                                          consumos_atipicos (403)
```

- **Host:** el servicio de IA. El proceso `ia-worker` ejecuta los agentes y es el único cliente MCP.
- **Servidores:** privados, internos y remotos; viven dentro de cada servicio (misma aplicación, mismo puerto) y reutilizan sus casos de uso de lectura. No pasan por el gateway (GraphQL es solo para el ERP) y solo los llama el servicio de IA con el token de `ia-agentes`: en desarrollo, por la red local; en el despliegue, entre nubes por HTTPS (602).
- **IA también es servidor:** sus herramientas leen lo que solo IA sabe (base de reportes y `ia_db`). El worker las llama por HTTP al `/mcp` de `ia-api`, igual que a los demás: así todos los agentes usan un solo mecanismo y la misma validación de argumentos. **(decisión del equipo:** reemplaza las «herramientas locales» del borrador de la 502.)
- **Personas por REST, agentes por MCP:** los reportes de las personas siguen `ERP → gateway → IA (REST, 503)`; `consultar_reporte` publica el mismo `MotorReportes` para los agentes.

## Versiones (verificadas el 31/10/2026)

| Pieza | Versión | Fuente y nota |
|---|---|---|
| Especificación MCP | **2026-07-28** (vigente) | modelcontextprotocol.io/specification (esquema `schema/2026-07-28`). Peticiones sin estado y negociación por petición |
| Versión común de esta plataforma | **2025-11-25** | Es la más nueva que soportan los cuatro SDK (los de Java y TypeScript todavía no anuncian la 2026-07-28). El cliente de Python negocia solo (modo `auto`: prueba la 2026-07-28 y, si el servidor es anterior, cae al saludo `initialize`) |
| Obras · Java 21 / Spring Boot 4.1 | Spring AI **2.0.2** (`spring-ai-bom`, `spring-ai-starter-mcp-server-webmvc`), que trae el **SDK oficial de MCP para Java** `io.modelcontextprotocol.sdk:mcp` **2.1.0** | Maven Central. El starter 2.0.2 declara `spring-boot-starter-web` 4.1.2, la misma versión de Obras. La 2.1.0-RC1 de Spring AI y la 2.2.0-M1 del SDK no son estables (no se usan). El SDK 2.1.0 soporta hasta la 2025-11-25 |
| Materiales · NestJS 12 | **SDK oficial de MCP para TypeScript** v2: `@modelcontextprotocol/server` **2.4.0** | npm. Implementación: se usa el transporte `WebStandardStreamableHTTPServerTransport` del mismo paquete; el adaptador `@modelcontextprotocol/express` 2.0.2 no hizo falta (`docs/estructura.md` de Materiales). Requiere `zod` ^4.2 y Node ≥ 20; el adaptador acepta Express 4 o 5. El paquete único `@modelcontextprotocol/sdk` sigue en 1.x (1.32.2) y no se usa. Soporta hasta la 2025-11-25 |
| Finanzas · Laravel 13 | `laravel/mcp` **1.1.2** (paquete oficial de **Laravel**) | Packagist. Declara PHP ^8.2 e `illuminate/*` ^13.0; soporta la 2026-07-28 y la 2025-11-25. El SDK oficial de MCP para PHP (`mcp/sdk`, de la organización MCP) existe pero sigue en **0.9.0** (antes de 1.0); se prefiere `laravel/mcp` por estar integrado con Laravel **(decisión del equipo)** |
| IA · Python 3.12 (servidor y cliente) | **SDK oficial de MCP para Python** `mcp` **2.3.0** | PyPI (pide Python ≥ 3.10). Servidor `MCPServer` montado en FastAPI con `streamable_http_app()`; cliente `Client(url)`. Soporta la 2026-07-28 y las anteriores hasta la 2025-11-25 |

Si un SDK de Java o TypeScript pasa a soportar la 2026-07-28, se puede actualizar sin cambiar las herramientas.

## Decisiones comunes a los cuatro servidores

- **Transporte:** HTTP «streamable» en `POST /mcp`, **sin estado** (no se guarda sesión entre llamadas) y con respuestas JSON (sin flujo SSE; un `GET /mcp` responde `405`). Cada ejecución de agente abre un cliente nuevo. **(decisión del equipo)**
- **Seguridad:** `/mcp` pasa por la misma validación de token del servicio (firma, vencimiento, emisor, audiencia `plataforma-api`) y exige el rol de realm `agente_ia` (roles efectivos con `azp = ia-agentes`). Las reglas de visibilidad tratan a `agente_ia` como `gerente` (ve todas las obras). Ningún endpoint REST acepta `agente_ia`.
- **Solo lectura:** cada herramienta llama únicamente a casos de uso de consulta. En Obras son `@Transactional(readOnly = true)`; en Materiales y Finanzas solo se llaman métodos de consulta; en IA, las lecturas de la 402 y la 403 y el `MotorReportes` (usuario `ia_reportes_lector`, 503). Cada herramienta se anuncia con `annotations: { readOnlyHint: true, openWorldHint: false }`. Prueba obligatoria: la lista de herramientas es exactamente la del contrato.
- **Esquemas estrictos:** entrada y salida como JSON Schema con `additionalProperties: false`; `structuredContent` cumple el `outputSchema` y, por compatibilidad, el mismo JSON va como texto en `content`.
- **Respuestas compactas:** filas máximas por herramienta (abajo) y `truncado: true` cuando hay más; textos libres recortados (con su propio `truncado` donde se indica); tiempo máximo de consulta 5 s.
- **Errores como resultado:** los errores de negocio no son errores del protocolo; se devuelven con `isError: true` y contenido de texto JSON `{"codigo": "...", "mensaje": "..."}`. Códigos: `ARGUMENTO_INVALIDO`, `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`. Una herramienta que no existe sí es un error del protocolo.
- **Registro:** una línea JSON por llamada: `herramienta`, `argumentos`, `filas`, `duracionMs`, `requestId` (encabezado `X-Request-Id`). Nunca el token.
- **Descripciones:** en español, cortas, empiezan con «Devuelve…», dicen cuándo conviene usar la herramienta y no traen instrucciones para el modelo (el LLM las lee).

## Herramientas

Formato: JSON Schema simplificado. `uuid` = string con formato uuid; `periodo` = string `^\d{4}-(0[1-9]|1[0-2])$`; `fecha` = string `AAAA-MM-DD`. Todas las entradas con `additionalProperties: false`.

### Obras · `avance_obra`

Descripción: «Devuelve el avance físico y el plazo transcurrido de las obras, al día. Sin obraId devuelve las obras en ejecución ordenadas de la más atrasada a la menos. Con obraId devuelve además sus partidas y, si se indica periodo, el material previsto de ese periodo.»

Entrada:

```json
{
  "obraId": "uuid (opcional)",
  "periodo": "periodo (opcional; solo junto con obraId)"
}
```

Salida:

```json
{
  "generadoEn": "2027-03-10T10:00:00Z",
  "obras": [{
    "obraId": "uuid", "nombre": "Edificio Las Palmas", "estado": "EN_EJECUCION",
    "fechaInicio": "2026-11-01", "plazoDias": 300,
    "avancePct": 32.5, "plazoPct": 41.0, "diferencia": 8.5, "enRiesgo": false,
    "ultimaPlanilla": { "periodo": "2027-02", "estado": "APROBADA" },
    "partidas": [{
      "partidaId": "uuid", "codigo": "P-01", "nombre": "Losa de hormigón armado", "unidad": "m2",
      "cantidadContratada": 850, "ejecutadaAcumulada": 300, "avancePct": 35.29,
      "materialPrevisto": [{ "materialId": "id", "cantidadPrevista": 55.0 }]
    }]
  }],
  "hayPlanillaEnPeriodo": true,
  "truncado": false
}
```

- Sin `obraId`: obras `EN_EJECUCION`, sin `partidas`, máximo 50, ordenadas por `diferencia` descendente.
- Con `obraId`: una sola obra (en cualquier estado) con `partidas` (máximo 200). `materialPrevisto` y `hayPlanillaEnPeriodo` solo si viene `periodo`; reutiliza el cálculo de `GET /obras/{id}/material-previsto` (006). Se agrega aquí porque el agente de Control de materiales necesita comparar lo usado con lo previsto y Materiales no conoce lo previsto. **(decisión del equipo)**
- `diferencia` = `plazoPct − avancePct`; `enRiesgo` según «Avance y plazo» de las reglas del negocio.
- Errores: `ARGUMENTO_INVALIDO` (por ejemplo, `periodo` sin `obraId`), `OBRA_NO_ENCONTRADA`.

### Obras · `buscar_diario`

Descripción: «Devuelve las entradas del diario de obra (clima y texto) de una obra en un rango de fechas, opcionalmente filtradas por una palabra. Sirve para buscar la causa de un atraso.»

Entrada:

```json
{
  "obraId": "uuid (obligatorio)",
  "desde": "fecha (opcional; por defecto hoy − 14 días)",
  "hasta": "fecha (opcional; por defecto hoy)",
  "texto": "string 2 a 50 caracteres (opcional)",
  "limite": "entero 1 a 30 (opcional; por defecto 14)"
}
```

Salida:

```json
{
  "obraId": "uuid",
  "entradas": [{ "fecha": "2027-03-08", "clima": "LLUVIA_FUERTE", "texto": "Se suspendió el vaciado…", "truncado": false }],
  "total": 1,
  "truncado": false
}
```

- `hoy` se calcula en `America/La_Paz`. Rango máximo 62 días; si `desde > hasta` o el rango es mayor, `ARGUMENTO_INVALIDO`. `texto` de cada entrada recortado a 1000 caracteres.
- `texto` busca sin distinguir mayúsculas (`ILIKE` con parámetro; los caracteres `%`, `_` y `\` del usuario se escapan).
- Orden: fecha descendente. Usa la tabla `entrada_diario` de la 103; si no hay entradas, `entradas: []`.
- El texto del diario lo escriben personas: para el agente es **dato no confiable** (504).

### Obras · `planillas_estado`

Descripción: «Devuelve las planillas de avance, al día, con su estado, neto, observación y días desde que se presentaron. Sirve para detectar planillas pendientes o sin respuesta del cliente.»

Entrada:

```json
{
  "obraId": "uuid (opcional)",
  "estados": ["BORRADOR | PRESENTADA | APROBANDO | APROBADA | OBSERVADA (opcional; por defecto todos menos APROBADA)"],
  "desdePeriodo": "periodo (opcional)",
  "limite": "entero 1 a 50 (opcional; por defecto 30)"
}
```

Salida:

```json
{
  "planillas": [{
    "planillaId": "uuid", "obraId": "uuid", "obraNombre": "Edificio Las Palmas",
    "numero": 3, "periodo": "2027-03", "estado": "PRESENTADA", "neto": 41881.80,
    "observacion": null, "presentadaEn": "2027-04-01T15:00:00Z", "diasDesdePresentacion": 9,
    "cobroId": null
  }],
  "truncado": false
}
```

- `presentadaEn`: nueva columna `planilla.presentada_en` que se llena cada vez que la planilla pasa a `PRESENTADA` (007). Para planillas anteriores a la migración queda `null`. La necesita el agente de Control de cobros para detectar planillas sin respuesta del cliente. **(decisión del equipo)**
- `diasDesdePresentacion`: días calendario en `America/La_Paz` desde `presentadaEn` hasta hoy, solo si el estado es `PRESENTADA`; si no, `null`.
- `observacion` recortada a 500 caracteres. Orden: periodo descendente.

### Materiales · `stock_obra`

Descripción: «Devuelve el stock de materiales por obra, al día, con su mínimo y su estado (BAJO, JUSTO, OK), primero los más críticos.»

Entrada:

```json
{
  "obraId": "string (opcional)",
  "estados": ["BAJO | JUSTO | OK (opcional; por defecto los tres)"],
  "limite": "entero 1 a 100 (opcional; por defecto 100)"
}
```

Salida:

```json
{
  "filas": [{
    "obraId": "uuid", "obraNombre": "Edificio Las Palmas",
    "materialId": "id", "codigo": "CEM-IP30", "nombre": "Cemento IP-30", "unidad": "bolsa",
    "cantidad": 80.0, "minimo": 100.0, "estado": "BAJO"
  }],
  "total": 1,
  "truncado": false
}
```

- `obraNombre` sale de `obra_acceso.nombre`. Estado del stock según las reglas del negocio. Orden: `BAJO`, `JUSTO`, `OK` y luego por nombre de obra. `total` = filas que cumplen el filtro (antes de recortar).
- Error: `OBRA_NO_ENCONTRADA` si `obraId` no está en `obra_acceso`.

### Materiales · `consumos_partida`

Descripción: «Devuelve el material usado (suma de salidas) por partida y material de una obra en un periodo, con las salidas que superaron el stock. Sirve para comparar con lo previsto de avance_obra.»

Entrada:

```json
{
  "obraId": "string (obligatorio)",
  "periodo": "periodo (obligatorio)",
  "partidaId": "string (opcional)"
}
```

Salida:

```json
{
  "obraId": "uuid", "periodo": "2027-03", "cerrado": false,
  "filas": [{
    "partidaId": "uuid", "materialId": "id", "codigo": "CEM-IP30", "nombre": "Cemento IP-30", "unidad": "bolsa",
    "usado": 64.0, "salidas": 5, "salidasSuperanStock": 1
  }],
  "truncado": false
}
```

- `usado` = suma de salidas (misma agregación que `GET /obras/{obraId}/consumos`, 006). `cerrado` = existe `cierre_periodo` `CERRADO` para la obra y el periodo. Máximo 200 filas.

### Finanzas · `cobros_por_vencer`

Descripción: «Devuelve los cobros pendientes que vencen en los próximos días y, si se pide, los vencidos, al día, con totales.»

Entrada:

```json
{
  "dias": "entero 1 a 90 (opcional; por defecto 15)",
  "incluirVencidos": "booleano (opcional; por defecto true)",
  "obraId": "uuid (opcional)"
}
```

Salida:

```json
{
  "hoy": "2027-04-20",
  "cobros": [{
    "cobroId": "uuid", "numero": "COB-2027-0003", "obraId": "uuid", "planillaId": "uuid",
    "montoNeto": 41881.80, "emitidoEn": "2027-04-02", "venceEn": "2027-05-02",
    "estado": "PENDIENTE", "diasParaVencer": 12
  }],
  "totales": {
    "vencidos": { "cantidad": 1, "monto": 20000.00 },
    "porVencer": { "cantidad": 1, "monto": 41881.80 }
  },
  "truncado": false
}
```

- `hoy` en `America/La_Paz`. `diasParaVencer` = `venceEn − hoy` (negativo si venció). Máximo 50 cobros, ordenados por `venceEn`; los totales cuentan todos (no solo los 50).
- Finanzas no guarda el nombre de la obra; el agente lo obtiene de `planillas_estado` o `avance_obra`.

### IA · `riesgo_retraso`

Descripción: «Devuelve la última predicción de riesgo de retraso (modelo de la 402) de las obras en ejecución: probabilidad, nivel y hasta 3 factores. Sirve para encontrar obras que pueden atrasarse aunque hoy no lo estén.»

Entrada:

```json
{
  "obraIds": ["uuid (opcional; 1 a 50)"],
  "niveles": ["BAJO | MEDIO | ALTO | SIN_DATOS (opcional; por defecto los cuatro)"],
  "limite": "entero 1 a 50 (opcional; por defecto 50)"
}
```

Salida:

```json
{
  "generadoEn": "2027-04-20T10:00:00Z",
  "predicciones": [{
    "obraId": "uuid", "obraNombre": "Edificio Las Palmas", "probabilidad": 0.72, "nivel": "ALTO",
    "factores": [{ "variable": "relacion_ritmo", "descripcion": "El ritmo de avance de los últimos meses es menor al necesario para terminar a tiempo", "peso": 0.81 }],
    "versionModelo": "rr-1.0.0", "calculadaEn": "2027-04-20T05:00:00Z"
  }],
  "total": 1,
  "truncado": false
}
```

- Obras `EN_EJECUCION` de `rpt_obra_resumen` (nombre de ahí) con su última predicción de `ia_db.prediccion`, con el mismo repositorio de `GET /predicciones` (402). Orden: probabilidad descendente (las `SIN_DATOS` al final). Las predicciones diarias corren a las 01:00, antes que los agentes.
- Sin modelo o sin predicciones: `predicciones: []` (no es error).
- Error: `OBRA_NO_ENCONTRADA` si un id de `obraIds` no está en `rpt_obra_resumen`.

### IA · `consumos_atipicos`

Descripción: «Devuelve las salidas de material que el modelo de la 403 marcó como atípicas, con su puntaje y motivos. Por defecto, las pendientes de revisión de los últimos 30 días. Solo lectura: la revisión la hace una persona.»

Entrada:

```json
{
  "obraId": "uuid (opcional)",
  "estados": ["PENDIENTE | NORMAL | CONFIRMADO (opcional; por defecto [PENDIENTE])"],
  "dias": "entero 1 a 90 (opcional; por defecto 30)",
  "limite": "entero 1 a 50 (opcional; por defecto 50)"
}
```

Salida:

```json
{
  "consumos": [{
    "movimientoId": "uuid", "obraId": "uuid", "obraNombre": "Edificio Las Palmas",
    "materialId": "id", "partidaId": "uuid", "cantidad": 120.0, "periodo": "2027-04",
    "registradoEn": "2027-04-15T02:40:00Z", "puntaje": 0.71,
    "motivos": ["La cantidad es 4,2 veces la habitual de este material en la obra"],
    "estadoRevision": "PENDIENTE"
  }],
  "total": 1,
  "truncado": false
}
```

- Lee `ia_db.consumo_atipico` con el mismo repositorio de `GET /consumos-atipicos` (403); `registradoEn` dentro de los últimos `dias` (La Paz). Orden: puntaje descendente. Cada motivo recortado a 200 caracteres. Los motivos son texto: para el agente son datos (504).
- Error: `OBRA_NO_ENCONTRADA` si `obraId` no está en `rpt_obra_resumen`.

### IA · `consultar_reporte`

Descripción: «Devuelve un reporte de datos históricos que cruzan servicios (obras, material usado, movimientos, cobros, planillas aprobadas u observadas, consumos atípicos), armado con una receta del catálogo. Los datos pueden ir hasta un día atrasados; para el dato de hoy usa las otras herramientas.»

Entrada: la receta de la 503 en **modo `MCP`**, con sus campos en el primer nivel:

```json
{
  "conjunto": "OBRAS | CONSUMO_MATERIAL | MOVIMIENTOS | COBROS | PLANILLAS | CONSUMOS_ATIPICOS",
  "columnas": ["…"], "filtros": [{ "campo": "…", "operador": "…", "valor": "…" }],
  "agruparPor": ["…"], "metricas": [{ "funcion": "…", "campo": "…" }],
  "orden": [{ "por": "…", "direccion": "ASC | DESC" }],
  "limite": "entero 1 a 50 (por defecto 20)"
}
```

- Mismo catálogo y misma `validar_receta` de la 503, modo `MCP`: filtros `obraId`, `materialId` y `clienteId` (ids) en lugar de `material` y `cliente` por nombre; las columnas `material` y `cliente` devuelven el id. Sin `NINGUNO`. Límite máximo 50 (respuesta compacta). **(decisión del equipo)**
- El host (502) le muestra a cada agente un esquema con `conjunto` limitado a sus conjuntos y rechaza otro antes de llamar.

Salida:

```json
{
  "conjunto": "COBROS", "titulo": "Cobros",
  "aplicado": [{ "nombre": "Estado", "valor": "VENCIDO" }],
  "columnas": [{ "clave": "numero", "titulo": "Número", "tipo": "TEXTO" }],
  "filas": [["COB-2027-0001"]],
  "totalFilas": 1, "truncado": false, "avisos": []
}
```

- Errores: `ARGUMENTO_INVALIDO` (receta que no cumple el esquema o el catálogo; `mensaje` con hasta 5 problemas, cada uno con su ruta), `ERROR_INTERNO` (base de reportes o `ia_db` no responden, o la consulta pasa de 5 s).

## Obras (Spring Boot)

- Dependencia `spring-ai-starter-mcp-server-webmvc` con el BOM `spring-ai-bom` 2.0.2 (trae el SDK de MCP para Java 2.1.0 y `spring-ai-mcp-annotations`). Modo sin estado con `spring.ai.mcp.server.protocol=STATELESS` (documentación de Spring AI 2.0.2, verificada el 31/10/2026); ruta por defecto `/mcp`.
- Paquete `com.constructora.obras.mcp` como **adaptador de entrada** (al lado de `infraestructura/web`): clase `HerramientasMcpObras` con un método `@McpTool` por herramienta (parámetros con `@McpToolParam`), que llama a los casos de uso de `aplicacion` (consulta de obras, detalle, material previsto, diario, planillas). Los DTO de salida son *records* propios del adaptador (de ellos sale el `outputSchema`).
- Validación de argumentos en el adaptador (formato uuid, periodo, rangos) antes de llamar al caso de uso.
- Seguridad: la cadena de Spring Security agrega `requestMatchers("/mcp/**").hasRole("agente_ia")`. Los demás controladores no cambian.
- Migración Flyway: `planilla.presentada_en timestamptz null`. El caso de uso «presentar planilla» (007) la llena con la hora actual.
- Repositorio nuevo de lectura para `entrada_diario` (por obra, rango de fechas y texto).

## Materiales (NestJS)

- Módulo `src/mcp/` (capa `presentacion`): `McpController` con `@Post('mcp')` protegido por el `RolesGuard` con `@Roles('agente_ia')`; crea el servidor con `@modelcontextprotocol/server` 2.4, registra las dos herramientas con esquemas `zod` 4 (entrada y salida) y atiende la petición con el transporte `WebStandardStreamableHTTPServerTransport` del mismo paquete (implementación; el borrador decía el adaptador `@modelcontextprotocol/express` 2.0) en modo sin estado y respuesta JSON (los nombres exactos de las opciones se toman de la documentación del SDK al implementar).
- `zod` 4 se usa **solo** en `src/mcp/` (lo exige el SDK); el resto del servicio sigue con `class-validator`.
- Las herramientas llaman a los casos de uso de `aplicacion` (stock por obra, consumos por periodo) y a una consulta nueva de lectura que cuenta `salidas` y `salidasSuperanStock`.
- La visibilidad de `obra_acceso` trata a `agente_ia` como `gerente`.

## Finanzas (Laravel)

- `composer require laravel/mcp:^1.1`. Servidor `app/Cobros/Infraestructura/Mcp/ServidorMcpFinanzas.php` con la herramienta `CobrosPorVencerHerramienta` (esquemas de entrada y salida con el constructor de esquemas del paquete, validación propia de rangos y anotación de solo lectura).
- Ruta en `routes/ai.php`: `Mcp::web('/mcp', ServidorMcpFinanzas::class)->middleware(['token', 'rol:agente_ia'])` (los *middleware* de 001).
- La herramienta llama a un caso de uso de `Aplicacion` (`ConsultarCobrosPorVencer`) que reutiliza el cálculo del resumen de cobros (009).

## IA: servidor MCP (`ia-api`)

- Módulo `src/ia/mcp/servidor/` (adaptador de entrada):
  - `servidor.py`: `MCPServer("ia")` del SDK `mcp` 2.3, con las tres herramientas; cada una devuelve un modelo Pydantic (de él sale el `outputSchema` y el `structuredContent`). Se monta en la app de FastAPI de `ia.main.crear_app` con `app.mount("/mcp", mcp.streamable_http_app(...))` y `streamable_http_path="/"`; el *lifespan* de FastAPI entra en `mcp.session_manager.run()` (al montarlo, el SDK no corre su propio *lifespan*; documentación del SDK, verificada el 31/10/2026). Modo sin estado y respuestas JSON (nombres exactos de las opciones según la documentación del SDK al implementar) y lista de hosts permitidos (`transport_security`), porque con un nombre de host real el SDK responde `421` si no está en la lista. Variable `IA_MCP_HOSTS_PERMITIDOS` (por defecto `localhost:8085,127.0.0.1:8085`). **Implementación:** se registra como ruta exacta `POST /mcp` (no con `app.mount`, que respondía `307` a `POST /mcp`); otro método da `405` y el administrador de sesiones corre en una tarea propia del *lifespan* (`docs/estructura.md` de IA).
  - `seguridad.py`: *middleware* ASGI delante del montaje: token válido (validador de la 401) y rol `agente_ia`; si no, `401` o `403` como Problem Details. Excepción a la regla de la 401 «solo `admin`, `gerente` y `residente`»: `/mcp` acepta **solo** `agente_ia`, y las rutas REST siguen sin aceptarlo.
  - `herramientas.py`: `riesgo_retraso` (repositorios de la 402 y `rpt_obra_resumen`), `consumos_atipicos` (repositorio de la 403) y `consultar_reporte` (`validar_receta` modo `MCP` + `MotorReportes` de la 503). Los errores de negocio se convierten en resultado con `isError: true` y el JSON `{codigo, mensaje}`.

## IA: cliente MCP del host (`ia-worker`)

- Módulo `src/ia/mcp/cliente/` (adaptador de salida):
  - `token.py`: *client credentials* contra `{IA_KEYCLOAK_ISSUER}/protocol/openid-connect/token` con `IA_AGENTES_CLIENT_ID` y `IA_AGENTES_CLIENT_SECRET`; caché en memoria hasta 30 s antes del vencimiento. El secreto solo lo lee `ia-worker`.
  - `cliente.py`: `ClienteMcp(nombre_servidor)` con `Client(url)` del SDK `mcp` 2.3 (modo de versión `auto`) y los encabezados `Authorization: Bearer …` y `X-Request-Id: <ejecucionId>`; métodos `listar_herramientas()` y `llamar(nombre, argumentos)` con tiempo máximo de 10 s.
  - `catalogo.py`: mapa herramienta → servidor (`IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`, `IA_PROPIO_MCP_URL`) y los esquemas de entrada esperados, para comparar con lo que devuelve `tools/list` (si un servidor publica una herramienta distinta o con otro esquema, se ignora y se registra una advertencia).

## Infra

- Realm `supervision`: rol de realm `agente_ia`; cliente confidencial `ia-agentes` con *service account* habilitada, sin *standard flow* ni *direct access grants*, con el rol `agente_ia` asignado a su *service account* y el mapper de audiencia `plataforma-api`. Duración del token: 5 minutos (como los demás).
- `x-ia-entorno` de Compose y `.env.example` de IA: `IA_AGENTES_CLIENT_ID=ia-agentes`, `IA_AGENTES_CLIENT_SECRET=` (el valor real solo en el `.env` local o en el gestor de secretos, 602), `IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`, `IA_PROPIO_MCP_URL` (en Compose, `http://ia-api:8085/mcp`) e `IA_MCP_HOSTS_PERMITIDOS` (en Compose, incluye `ia-api:8085`).

## Pruebas

- Cada uno de los cuatro servicios:
  - `/mcp` sin token → 401; con token de `gerente` → 403; con token de `agente_ia` → 200.
  - `tools/list` devuelve exactamente las herramientas del contrato, con sus esquemas y la anotación de solo lectura.
  - Cada herramienta con datos de prueba: cifras iguales a las del endpoint REST equivalente (avance y plazo, stock y estado, consumos, cobros y días para vencer, predicciones, consumos atípicos) y `truncado` cuando hay más filas que el límite.
  - Argumentos inválidos (uuid mal formado, `"x' OR 1=1"`, periodo `2027-13`, `limite` 1000, campo de más) → `isError` con `ARGUMENTO_INVALIDO` y sin consulta a la base.
  - Obra inexistente → `OBRA_NO_ENCONTRADA`.
  - Prueba de «solo lectura»: después de llamar todas las herramientas, ninguna tabla o colección cambió (conteo y suma de verificación de filas).
- Obras: `presentada_en` se llena al presentar y al volver a presentar una planilla observada; `buscar_diario` escapa `%` y `_`.
- IA (servidor): `consultar_reporte` con una receta de cada conjunto da las mismas cifras que `POST /consultas-reporte` (503); filtros por nombre (`material`, `cliente`) → `ARGUMENTO_INVALIDO`; token de `agente_ia` en una ruta REST de IA → `403`.
- IA (cliente): contra un servidor MCP de prueba hecho con el mismo SDK: token en caché, reintento de token vencido, tiempo máximo de 10 s, herramienta desconocida ignorada, servidor caído.

## Cambios a contratos y datos

### `docs/contratos/rest.md` y `docs/contratos.md` de Obras, Materiales, Finanzas e IA

Reemplazar «Herramientas MCP (capa 5, solo lectura) … Se especifican en la capa 5» (y agregar la sección en IA) por:

```
## Herramientas MCP (capa 5, solo lectura) · 501
Ruta: POST /mcp (MCP, HTTP «streamable», sin estado, respuestas JSON; versión común 2025-11-25) · Rol: agente_ia (service account de ia-agentes) · Solo lo llama el servicio de IA
```

- Obras: `avance_obra {obraId?, periodo?}`, `buscar_diario {obraId, desde?, hasta?, texto?, limite?}`, `planillas_estado {obraId?, estados?, desdePeriodo?, limite?}`, con las salidas de este diseño. Quitar la mención a `asistencia_obra`.
- Materiales: `stock_obra {obraId?, estados?, limite?}`, `consumos_partida {obraId, periodo, partidaId?}`.
- Finanzas: `cobros_por_vencer {dias?, incluirVencidos?, obraId?}`.
- IA: `riesgo_retraso {obraIds?, niveles?, limite?}`, `consumos_atipicos {obraId?, estados?, dias?, limite?}`, `consultar_reporte {receta en modo MCP}`. En la sección «IA (puerto 8085)» de `rest.md`: «`/mcp` acepta solo `agente_ia`; las rutas REST no lo aceptan».
- Errores de herramienta: `ARGUMENTO_INVALIDO`, `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO` (resultado con `isError: true`).

### `docs/convenciones.md` (Autenticación y permisos)

- Rol `agente_ia` (ya está): agregar que también lo acepta `POST /mcp` del servicio de IA.
- «Librerías»: Spring AI 2.0 (SDK de MCP para Java 2.1, servidor en Obras), `@modelcontextprotocol/server` 2 + `zod` 4 (Materiales), `laravel/mcp` 1 (Finanzas), `mcp` 2 (servidor y cliente en IA). Versión común del protocolo: 2025-11-25.

### `docs/arquitectura.md`

- Ya aplicado en esta aprobación (host, servidores MCP de los cuatro servicios, versiones).

### `services/obras/docs/datos.md`

- Tabla `planilla`: agregar `presentada_en | timestamptz | última vez que pasó a PRESENTADA (501); nulo en planillas anteriores`.

### `services/ia/docs/contratos.md`, `docs/estructura.md` y `docs/servicio.md`

- «Expone (MCP)»: las tres herramientas de IA.
- «Consume (MCP)»: las seis herramientas de Obras, Materiales y Finanzas y las tres propias, con `IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`, `IA_PROPIO_MCP_URL`.
- Módulo `src/ia/mcp/` (`servidor/` y `cliente/`); librería `mcp` 2; la regla «solo `admin`, `gerente` y `residente`» con la excepción de `/mcp`.

### Proyectos de Materiales y Obras

- `services/materiales/docs/estructura.md` y `docs/stack.md`: `zod` 4 solo en `src/mcp/`.
