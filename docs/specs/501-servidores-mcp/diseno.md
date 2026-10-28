# 501 · Diseño

## Decisiones comunes a los tres servidores

- **Transporte:** HTTP «streamable» del estándar MCP en `POST /mcp`, en modo **sin estado** (*stateless*: no se guarda sesión entre llamadas) y respuestas JSON (sin flujo SSE). Cada ejecución de agente abre un cliente nuevo; no hace falta sesión. **(decisión del equipo)**
- **Misma aplicación, mismo puerto:** el servidor MCP vive dentro del servicio (no es un proceso aparte) y reutiliza sus casos de uso de lectura. No se agrega ninguna consulta nueva a la base que salte las reglas del dominio.
- **Seguridad:** `/mcp` pasa por la misma validación de token del servicio (firma, vencimiento, emisor, audiencia `plataforma-api`) y exige el rol de realm `agente_ia` **(decisión del equipo: nombre del rol)**. Las reglas de visibilidad tratan a `agente_ia` como `gerente` (ve todas las obras). Los endpoints REST no aceptan `agente_ia` (no figura en ninguna lista de roles).
- **Solo lectura:** cada herramienta llama únicamente a casos de uso de consulta. En Obras los casos de uso que usa MCP son `@Transactional(readOnly = true)`; en Finanzas y Materiales solo se llaman métodos de consulta de los repositorios. Prueba obligatoria: la lista de herramientas es exactamente la del contrato.
- **Errores:** los errores de negocio no son errores del protocolo; se devuelven como resultado de herramienta con `isError: true` y contenido de texto JSON `{"codigo": "...", "mensaje": "..."}`. Códigos: `ARGUMENTO_INVALIDO`, `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO`.
- **Salida:** cada resultado trae `structuredContent` (objeto que cumple el `outputSchema`) y, por compatibilidad, el mismo JSON como texto en `content`.
- **Límites:** filas máximas por herramienta (abajo), textos libres recortados a 1000 caracteres con `truncado: true`, tiempo máximo de consulta 5 s.
- **Registro:** una línea JSON por llamada: `herramienta`, `argumentos`, `filas`, `duracionMs`, `requestId` (encabezado `X-Request-Id`).
- **Descripciones:** las descripciones de las herramientas se escriben en español, cortas y sin instrucciones para el modelo («Devuelve…»), porque el LLM las lee.

## Librerías (verificadas el 28/10/2026)

| Proyecto | Librería | Versión mayor | Nota |
|---|---|---|---|
| Obras (Spring Boot 4.1) | Spring AI `spring-ai-starter-mcp-server-webmvc` (BOM `spring-ai-bom`) | 2 (2.0.2) | La 2.0.2 declara `spring-boot-starter-web` 4.1.2, la misma versión de Obras. Usa el SDK oficial de MCP para Java (`io.modelcontextprotocol.sdk`, versión mayor 2) y las anotaciones `@McpTool` / `@McpToolParam`. Modo sin estado con `spring.ai.mcp.server.protocol=STATELESS` (confirmar el nombre exacto de la propiedad en la documentación de Spring AI 2.0). |
| Materiales (NestJS 12) | SDK oficial de MCP para TypeScript `@modelcontextprotocol/server` + adaptador `@modelcontextprotocol/express` | 2 (2.4.0 y 2.0.2) | Desde la versión 2 el SDK oficial se publica en paquetes separados (el paquete único `@modelcontextprotocol/sdk` sigue en 1.x). Requiere `zod` 4. Se monta en un controlador de NestJS sobre Express. Alternativa comunitaria: `@rekog/mcp-nest` 2 (no oficial; no se usa). |
| Finanzas (Laravel 13) | `laravel/mcp` (paquete oficial de Laravel) | 1 (1.1.2) | Declara compatibilidad con Laravel 13 y PHP ≥ 8.2. Se registra un servidor web con `Mcp::web('/mcp', ...)` y el *middleware* de token. El SDK oficial de MCP para PHP (`mcp/sdk`) existe pero sigue en 0.x (0.9.0); se prefiere `laravel/mcp` por estar integrado con Laravel. **(decisión del equipo)** |
| IA (cliente) | SDK oficial de MCP para Python `mcp` | 2 (2.3.0) | Cliente con transporte HTTP «streamable» (`Client(url)`), con el encabezado `Authorization`. |

## Herramientas

Formato: entrada y salida como JSON Schema simplificado. `uuid` = string con formato uuid; `periodo` = string `^\d{4}-(0[1-9]|1[0-2])$`; `fecha` = string `AAAA-MM-DD`. Todas las entradas usan `additionalProperties: false`.

### Obras · `avance_obra`

Descripción: «Devuelve el avance físico y el plazo transcurrido de las obras. Sin obraId devuelve las obras en ejecución. Con obraId devuelve además sus partidas y, si se indica periodo, el material previsto de ese periodo.»

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
  "hayPlanillaEnPeriodo": true
}
```

- Sin `obraId`: obras `EN_EJECUCION`, sin `partidas`, máximo 50, ordenadas por `diferencia` descendente.
- Con `obraId`: una sola obra (en cualquier estado) con `partidas` (máximo 200). `materialPrevisto` y `hayPlanillaEnPeriodo` solo si viene `periodo`; reutiliza el cálculo de `GET /obras/{id}/material-previsto` (006). Se agrega aquí porque el agente de Control de materiales necesita comparar lo usado con lo previsto y Materiales no conoce lo previsto. **(decisión del equipo)**
- `diferencia` = `plazoPct − avancePct`; `enRiesgo` según «Avance y plazo» de las reglas del negocio.
- Errores: `ARGUMENTO_INVALIDO` (por ejemplo, `periodo` sin `obraId`), `OBRA_NO_ENCONTRADA`.

### Obras · `buscar_diario`

Descripción: «Devuelve las entradas del diario de obra (clima y texto) de una obra en un rango de fechas, opcionalmente filtradas por una palabra.»

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
  "entradas": [{ "fecha": "2027-03-08", "clima": "Lluvia", "texto": "Se suspendió el vaciado…", "truncado": false }],
  "total": 1
}
```

- `hoy` se calcula en `America/La_Paz`. Rango máximo 62 días; si `desde > hasta` o el rango es mayor, `ARGUMENTO_INVALIDO`.
- `texto` busca sin distinguir mayúsculas (`ILIKE` con parámetro; los caracteres `%`, `_` y `\` del usuario se escapan).
- Orden: fecha descendente. Usa la tabla `entrada_diario` de la capa 1; si la capa 1 todavía no registró entradas, devuelve `entradas: []`.
- El texto del diario lo escriben personas: para el agente es **dato no confiable** (504).

### Obras · `planillas_estado`

Descripción: «Devuelve las planillas de avance con su estado, neto, observación y fecha de presentación.»

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
  }]
}
```

- `presentadaEn`: nueva columna `planilla.presentada_en` que se llena cada vez que la planilla pasa a `PRESENTADA` (007). Para planillas anteriores a la migración queda `null`. La necesita el agente de Control de cobros para detectar planillas sin respuesta del cliente. **(decisión del equipo)**
- `diasDesdePresentacion`: días calendario en `America/La_Paz` desde `presentadaEn` hasta hoy, solo si el estado es `PRESENTADA`; si no, `null`.
- `observacion` recortada a 500 caracteres. Orden: periodo descendente.

### Materiales · `stock_obra`

Descripción: «Devuelve el stock de materiales por obra con su mínimo y su estado (BAJO, JUSTO, OK).»

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
  "total": 1
}
```

- `obraNombre` sale de `obra_acceso.nombre`. Estado del stock según las reglas del negocio. Orden: `BAJO`, `JUSTO`, `OK` y luego por nombre de obra.
- Error: `OBRA_NO_ENCONTRADA` si `obraId` no está en `obra_acceso`.

### Materiales · `consumos_partida`

Descripción: «Devuelve el material usado (suma de salidas) por partida y material de una obra en un periodo, con las salidas que superaron el stock.»

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
  }]
}
```

- `usado` = suma de salidas (misma agregación que `GET /obras/{obraId}/consumos`, 006). `cerrado` = existe `cierre_periodo` `CERRADO` para la obra y el periodo. Máximo 200 filas.

### Finanzas · `cobros_por_vencer`

Descripción: «Devuelve los cobros pendientes que vencen en los próximos días y, si se pide, los vencidos, con totales.»

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
  }
}
```

- `hoy` en `America/La_Paz`. `diasParaVencer` = `venceEn − hoy` (negativo si venció). Máximo 50 cobros, ordenados por `venceEn`.
- Finanzas no guarda el nombre de la obra; el agente lo obtiene de `planillas_estado` o `avance_obra`.

## Obras (Spring Boot)

- Dependencia `spring-ai-starter-mcp-server-webmvc` con el BOM `spring-ai-bom` 2.0.x.
- Paquete `com.constructora.obras.mcp` como **adaptador de entrada** (al lado de `infraestructura/web`): clase `HerramientasMcpObras` con un método `@McpTool` por herramienta, que llama a los casos de uso de `aplicacion` (consulta de obras, detalle, material previsto, diario, planillas). Los DTO de salida son *records* propios del adaptador.
- Validación de argumentos en el adaptador (formato uuid, periodo, rangos) antes de llamar al caso de uso.
- Seguridad: la cadena de Spring Security agrega `requestMatchers("/mcp/**").hasRole("agente_ia")`. Los demás controladores no cambian.
- Migración Flyway: `planilla.presentada_en timestamptz null`. El caso de uso «presentar planilla» (007) la llena con la hora actual.
- Repositorio nuevo de lectura para `entrada_diario` (por obra, rango de fechas y texto).

## Materiales (NestJS)

- Módulo `src/mcp/` (capa `presentacion`): `McpController` con `@Post('mcp')` protegido por el `RolesGuard` con `@Roles('agente_ia')`; crea el servidor con `@modelcontextprotocol/server`, registra las dos herramientas con esquemas `zod` 4 (entrada y salida) y atiende la petición con el transporte del adaptador `@modelcontextprotocol/express` en modo sin estado.
- Las herramientas llaman a los casos de uso de `aplicacion` (stock por obra, consumos por periodo) y a una consulta nueva de lectura que cuenta `salidas` y `salidasSuperanStock`.
- La visibilidad de `obra_acceso` trata a `agente_ia` como `gerente`.

## Finanzas (Laravel)

- `composer require laravel/mcp`. Servidor `app/Cobros/Infraestructura/Mcp/ServidorMcpFinanzas.php` con la herramienta `CobrosPorVencerHerramienta` (esquema de entrada con el constructor de esquemas del paquete y validación propia de rangos).
- Ruta en `routes/ai.php`: `Mcp::web('/mcp', ServidorMcpFinanzas::class)->middleware(['token', 'rol:agente_ia'])` (los *middleware* de 001).
- La herramienta llama a un caso de uso de `Aplicacion` (`ConsultarCobrosPorVencer`) que reutiliza el cálculo del resumen de cobros (009).

## IA (cliente MCP)

- Módulo `src/ia/mcp/` (adaptador de salida, dentro de la estructura de la 401):
  - `token.py`: *client credentials* contra `{IA_KEYCLOAK_ISSUER}/protocol/openid-connect/token` (emisor de la 401) con `IA_AGENTES_CLIENT_ID` y `IA_AGENTES_CLIENT_SECRET`; caché en memoria hasta 30 s antes del vencimiento.
  - `cliente.py`: `ClienteMcp(nombre_servidor)` con `Client(url)` del SDK `mcp` 2 y los encabezados `Authorization: Bearer …` y `X-Request-Id: <ejecucionId>`; métodos `listar_herramientas()` y `llamar(nombre, argumentos)` con tiempo máximo de 10 s.
  - `catalogo.py`: mapa herramienta → servidor (`IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`) y los esquemas de entrada esperados, para comparar con lo que devuelve `tools/list` (si un servidor publica una herramienta distinta o con otro esquema, se ignora y se registra una advertencia).

## Infra

- Realm `supervision`: rol de realm `agente_ia`; cliente confidencial `ia-agentes` con *service account* habilitada, sin *standard flow* ni *direct access grants*, con el rol `agente_ia` asignado a su *service account* y el mapper de audiencia `plataforma-api`. Duración del token: 5 minutos (como los demás).
- `.env.example` de IA: `IA_AGENTES_CLIENT_ID=ia-agentes`, `IA_AGENTES_CLIENT_SECRET=` (el valor real solo en el `.env` local o en el gestor de secretos, 602).

## Pruebas

- Cada servicio:
  - `/mcp` sin token → 401; con token de `gerente` → 403; con token de `agente_ia` → 200.
  - `tools/list` devuelve exactamente las herramientas del contrato, con sus esquemas.
  - Cada herramienta con datos de prueba: cifras iguales a las del endpoint REST equivalente (avance y plazo, stock y estado, consumos, cobros y días para vencer).
  - Argumentos inválidos (uuid mal formado, `"x' OR 1=1"`, periodo `2027-13`, `limite` 1000, campo de más) → `isError` con `ARGUMENTO_INVALIDO` y sin consulta a la base.
  - Obra inexistente → `OBRA_NO_ENCONTRADA`.
  - Prueba de «solo lectura»: después de llamar todas las herramientas, ninguna tabla o colección cambió (conteo y suma de verificación de filas).
- Obras: `presentada_en` se llena al presentar y al volver a presentar una planilla observada; `buscar_diario` escapa `%` y `_`.
- IA: cliente contra un servidor MCP de prueba (SDK `mcp` en modo servidor): token en caché, reintento de token vencido, tiempo máximo de 10 s, herramienta desconocida ignorada.

## Cambios a contratos y datos

### `docs/contratos/rest.md` y `docs/contratos.md` de Obras, Materiales y Finanzas

Reemplazar «Herramientas MCP (capa 5, solo lectura) … Se especifican en la capa 5» por:

```
## Herramientas MCP (capa 5, solo lectura) · 501
Ruta: POST /mcp (MCP, HTTP «streamable», sin estado) · Rol: agente_ia (service account de ia-agentes)
```

- Obras: `avance_obra {obraId?, periodo?}`, `buscar_diario {obraId, desde?, hasta?, texto?, limite?}`, `planillas_estado {obraId?, estados?, desdePeriodo?, limite?}`, con las salidas de este diseño. Quitar la mención a `asistencia_obra`.
- Materiales: `stock_obra {obraId?, estados?, limite?}`, `consumos_partida {obraId, periodo, partidaId?}`.
- Finanzas: `cobros_por_vencer {dias?, incluirVencidos?, obraId?}`.
- Errores de herramienta: `ARGUMENTO_INVALIDO`, `OBRA_NO_ENCONTRADA`, `ERROR_INTERNO` (resultado con `isError: true`).

### `docs/convenciones.md` (Autenticación y permisos)

- Agregar el rol de realm `agente_ia`, asignado solo a la *service account* del cliente `ia-agentes`; se acepta solo en `/mcp` y ve todas las obras.
- Agregar en «Librerías»: Spring AI 2 (servidor MCP en Obras), `@modelcontextprotocol/server` 2 + `@modelcontextprotocol/express` 2 (Materiales), `laravel/mcp` 1 (Finanzas), `mcp` 2 (cliente en IA).

### `docs/arquitectura.md`

- Fila de conexiones «IA → Obras, Materiales, Finanzas · MCP»: precisar «HTTP streamable sin estado en `/mcp`, token de `ia-agentes`».

### `services/obras/docs/datos.md`

- Tabla `planilla`: agregar `presentada_en | timestamptz | última vez que pasó a PRESENTADA (501); nulo en planillas anteriores`.

### `services/ia/docs/contratos.md` (creado por la 401)

- «Consume (MCP)»: las seis herramientas, con `IA_OBRAS_MCP_URL`, `IA_MATERIALES_MCP_URL`, `IA_FINANZAS_MCP_URL`.
