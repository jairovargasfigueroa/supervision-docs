# 401 · Diseño

## Mecanismo: CQRS, modelo de lectura alimentado por eventos

Decisión de Jairo (31/10/2026). El ingeniero pidió «algún mecanismo» para los reportes que cruzan servicios (punto 20, nivel de datos), no un microservicio aparte:

- **Escritura (comandos):** cada microservicio sigue escribiendo y leyendo **lo suyo** en su base (Obras y Finanzas en PostgreSQL, Materiales en MongoDB). Nada cambia en ellos salvo dos campos en sus eventos (zona y precio).
- **Lectura (consultas que cruzan servicios):** un **modelo de lectura** desnormalizado, `reportes_db` (tablas `rpt_*`), que se arma con **proyecciones** de los eventos de RabbitMQ. Lo usan las predicciones (402, 403) y los reportes por voz (capa 5).
- **CQRS solo para lo que cruza servicios:** las pantallas de un solo servicio siguen leyendo de su dueño (por el gateway). **Sin *event sourcing*:** los eventos no son la fuente de verdad; solo alimentan el modelo de lectura, que se puede volver a armar con la carga inicial.
- El modelo de lectura vive **dentro del servicio de IA** (`services/ia`), que es quien lo consume.
- **Consistencia eventual:** el modelo de lectura va unos segundos detrás de los servicios (criterio 3), y el plazo y el vencimiento de cobros se recalculan una vez al día.

## Visión general

```
Obras ──ObraRegistrada, PlanillaAprobada, PlanillaObservada──┐
Finanzas ──ContratoRegistrado, CobroEmitido──────────────────┼──> exchange plataforma ──> cola «ia» ──> IA (worker)
Materiales ──MovimientoRegistrado────────────────────────────┘                                      │
                                                                         reportes_db (PostgreSQL) <─┤ proyecciones rpt_*
                                                                         ia_db (MongoDB) <──────────┘ (402, 403)
Gateway ──REST──> IA (api, puerto 8085)   (402, 403)

Carga inicial (una vez):  IA (comando carga-inicial) ──REST GET, token ia-reportes──> Obras, Materiales, Finanzas
                                                     └──> reportes_db (mismas proyecciones)
```

El servicio de IA tiene dos procesos que salen de la misma imagen, más un comando de una sola vez:

- **`ia-api`**: FastAPI con Uvicorn en el puerto 8085. Atiende al gateway.
- **`ia-worker`**: consumidor de RabbitMQ y tareas programadas (recalcular plazo, vencer cobros; en 402 y 403, predicciones).
- **`ia-carga-inicial`**: comando que llena el modelo de lectura con lo que ya existe (sección «Carga inicial») y termina.

La capa 4 **no usa un modelo de lenguaje**: 401, 402 y 403 son proyecciones, cálculos y modelos de ML clásicos. El modelo de lenguaje se decide y se agrega en la capa 5.

## Servicio de IA (`services/ia`)

### Stack (versiones verificadas en PyPI el 28/10/2026; se anota la mayor)

| Uso | Paquete |
|---|---|
| Lenguaje | Python 3.12 (lo exigen `xgboost` 3 y `numpy` 2.5) |
| Gestor de dependencias | `uv` (`pyproject.toml` + `uv.lock`) (decisión del equipo) |
| API | `fastapi` 0.162, `uvicorn` 0.54, `pydantic` 2, `pydantic-settings` 2 |
| Cliente HTTP (carga inicial) | `httpx` (el mismo que usan las pruebas de FastAPI; en pruebas, `httpx.MockTransport`) |
| PostgreSQL | `sqlalchemy` 2 (async) + `psycopg` 3; migraciones con `alembic` 1 |
| MongoDB | `pymongo` 4 (cliente asíncrono `AsyncMongoClient`) |
| RabbitMQ | `aio-pika` 10 |
| Token | `PyJWT[crypto]` 2 (`PyJWKClient` con el JWKS del realm) |
| Tareas programadas | `apscheduler` 3 (`AsyncIOScheduler`) |
| Pruebas | `pytest` 9, `pytest-asyncio` 1, `httpx` (cliente de pruebas de FastAPI) |
| ML (402, 403) | `xgboost` 3, `scikit-learn` 1, `pandas` 3, `numpy` 2, `joblib` 1 |

TensorFlow **no** es dependencia del servicio: si la 301 lo usa (por decidir), va solo en el entorno aparte de `entrenamiento/`. Tampoco hay librerías de modelos de lenguaje en la capa 4.

### Arquitectura: DDD + hexagonal ligera (decisión del equipo)

Paquete `src/ia/`, un contexto por área, con la misma división que Obras:

```
src/ia/
  main.py                 FastAPI (ia-api)
  worker.py               consumidor + tareas programadas (ia-worker)
  carga_inicial.py        comando de la carga inicial (ia-carga-inicial)
  config.py               variables de entorno (pydantic-settings)
  comun/                  Problem Details, X-Request-Id, registros JSON, tiempo de La Paz
  auth/                   validación del token y visibilidad de obras
  mensajeria/             conexión aio-pika, inbox, reintentos y fallidos
  reportes/               (401) proyecciones de eventos a rpt_* y carga inicial
    dominio/  aplicacion/  infraestructura/   (clientes REST de Obras, Materiales y Finanzas en infraestructura/)
  riesgo/                 (402)
  atipicos/               (403)
migraciones/              alembic (reportes_db)
ml/                       generadores sintéticos y entrenamiento (402, 403)
modelos/                  artefactos versionados de los modelos (402, 403)
entrenamiento/            entorno aparte de la 301 (si se usa; por decidir)
tests/
```

- El dominio (`reportes/dominio`) no importa FastAPI, SQLAlchemy, aio-pika ni httpx: cálculo de avance, plazo y vencimiento con fechas fijas.
- Las proyecciones son **casos de uso** de `reportes/aplicacion` que reciben datos ya traducidos (un `ObraLeida`, `PlanillaLeida`…). Los usan los dos adaptadores de entrada: el consumidor de eventos y la carga inicial. Así las reglas son las mismas por los dos caminos.

### Configuración (`.env.example`; `.env` nunca se sube)

| Variable | Ejemplo |
|---|---|
| `IA_PUERTO` | `8085` |
| `IA_REPORTES_DB_URL` | `postgresql+psycopg://ia:ia@localhost:5433/reportes_db` |
| `IA_MONGO_URL` · `IA_MONGO_DB` | `mongodb://localhost:27017` · `ia_db` |
| `IA_RABBITMQ_URL` | `amqp://ia:<RABBITMQ_IA_CLAVE de infra/.env>@localhost:5672/` (usuario propio del servicio: `guest` solo entra desde dentro del contenedor) |
| `IA_KEYCLOAK_ISSUER` | `http://localhost:8080/realms/supervision` |
| `IA_AUDIENCIA` | `plataforma-api` |
| `IA_ZONA_HORARIA` | `America/La_Paz` |
| `IA_OBRAS_URL` · `IA_MATERIALES_URL` · `IA_FINANZAS_URL` | `http://localhost:8081` · `http://localhost:8082` · `http://localhost:8083` (carga inicial; `IA_MATERIALES_URL` es la misma variable que usa la 503) |
| `IA_REPORTES_CLIENT_ID` · `IA_REPORTES_CLIENT_SECRET` | `ia-reportes` · secreto del cliente en Keycloak (solo lo lee el comando de carga inicial) |

### Autenticación y visibilidad

- Toda ruta salvo `/salud` exige token: firma (JWKS de `IA_KEYCLOAK_ISSUER`), vencimiento, emisor y audiencia `plataforma-api`. `401` sin token válido.
- Roles desde `realm_access.roles`; usuario = `sub`.
- Visibilidad (convenciones): `admin` y `gerente` ven todas las obras; `residente` las que tiene asignadas según `rpt_obra_resumen.residente_id`. Los demás roles reciben `403` en todo el servicio (el servicio de IA atiende solo al ERP).

### Convenciones aplicadas

- Errores en Problem Details con `codigo` (manejador de excepciones de FastAPI que responde `application/problem+json`).
- JSON en `camelCase` (alias de Pydantic); base en `snake_case`.
- `X-Request-Id` leído del encabezado (o creado) e incluido en cada registro; en eventos se registra `correlacionId`.
- Registros en JSON en producción y texto en desarrollo.

## Mensajería (`ia-worker`)

- Cola durable `ia` en el exchange `plataforma`. La cola y sus enlaces se declaran **en la infraestructura** (definiciones de RabbitMQ importadas al iniciar, desde la fase 1: `docs/entorno-local.md`), además de que el worker los declare al conectarse; así los eventos se guardan aunque el servicio de IA todavía no esté corriendo (criterio 13).
- Enlaces (claves de enrutamiento):

| Clave | Proyección |
|---|---|
| `evento.obras.ObraRegistrada` | `rpt_obra_resumen` (alta) |
| `evento.finanzas.ContratoRegistrado` | `rpt_obra_resumen.estado = EN_EJECUCION` |
| `evento.obras.PlanillaAprobada` | `rpt_planilla`, avance en `rpt_obra_resumen`, `rpt_cobro` (obra, planilla, monto, cliente, zona) |
| `evento.obras.PlanillaObservada` | `rpt_planilla` (veces observada, último motivo) |
| `evento.finanzas.CobroEmitido` | `rpt_cobro` (número, emisión, vencimiento) |
| `evento.materiales.MovimientoRegistrado` | `rpt_movimiento` y, si es `SALIDA`, `rpt_consumo_material` |

- Prefetch 10, confirmación manual (`ack`) después de aplicar.
- **Inbox:** cada evento se aplica en **una transacción** de PostgreSQL que inserta `evento_aplicado(evento_id)` y actualiza las tablas `rpt_*`. Si el `id` ya existe, se confirma el mensaje sin hacer nada (criterio 11).
- Escrituras en MongoDB: las de la 403 (consumos atípicos) se hacen **antes** de la transacción de PostgreSQL y son idempotentes (por clave), para que un reintento no pierda nada. Las predicciones de la 402 se calculan **después** de confirmar la transacción, porque necesitan los datos ya actualizados (ver 402).
- **Reintentos y fallidos** (como los demás servicios): si aplicar un evento lanza una excepción, se vuelve a publicar en la cola `ia` con el encabezado `x-intentos` + 1; al tercer fallo se publica en `plataforma.fallidos` con el error y se confirma el original.
- Un `version` del sobre mayor a 1 que el servicio no conoce va directo a `plataforma.fallidos`.
- Campos desconocidos en `datos` se ignoran (lector tolerante).

### Reglas de cada proyección (`reportes/dominio` y `reportes/aplicacion`)

Las mismas reglas sirven para los eventos y para la carga inicial. Cada escritura es idempotente **por fila** (`INSERT … ON CONFLICT` por la clave primaria), así un dato que llega por los dos caminos queda una sola vez.

- **ObraRegistrada:** inserta la obra con `estado = SIN_CONTRATO`, `avance_pct = 0`, `plazo_pct` calculado hoy. Si ya existe, actualiza solo los datos descriptivos (nunca devuelve el `estado` a `SIN_CONTRATO`).
- **ContratoRegistrado:** `estado = EN_EJECUCION`. Si la obra no existe todavía, falla (reintento): con una sola cola, `ObraRegistrada` llega antes.
- **PlanillaAprobada:** bloquea la fila de la obra (`SELECT … FOR UPDATE` en `rpt_obra_resumen`); `monto_periodo = Σ lineas.monto`; `avance_periodo_pct = monto_periodo / monto_contrato × 100`; inserta o actualiza `rpt_planilla` como `APROBADA`; `avance_pct` de la obra = Σ `monto_periodo` de sus planillas `APROBADA` / `monto_contrato` × 100 (2 decimales, mitad hacia arriba), recalculado desde `rpt_planilla` (no se suma al valor anterior). Inserta o completa `rpt_cobro` con `cobro_id`, `obra_id`, `planilla_id`, `monto = neto`, `cliente_id` y `zona` de la obra. Si la obra no existe todavía, falla (reintento).
- **CobroEmitido:** inserta o completa `rpt_cobro` con `numero`, `vence_en`, `planilla_id`, `emitido_en` = fecha de `ocurridoEn` en La Paz, `estado = PENDIENTE` (si `vence_en` < hoy, `VENCIDO`). Solo llena columnas vacías (`COALESCE`), salvo `estado`, que se calcula con `vence_en`. El orden de llegada con `PlanillaAprobada` no importa: cada uno completa sus columnas (criterio 6).
- **PlanillaObservada:** bloquea la fila de la obra si existe; inserta o actualiza `rpt_planilla` con `estado = OBSERVADA` (si no estaba `APROBADA`), `veces_observada + 1`, `ultimo_motivo`, `ultimo_origen`. **Excepción por la carga inicial:** si la fila tiene `cargada_en` y el `ocurridoEn` del evento es anterior o igual, la observación ya está contada en la carga: solo se registra en `evento_aplicado`, sin sumar.
- **MovimientoRegistrado:** inserta `rpt_movimiento` con `ON CONFLICT (movimiento_id) DO NOTHING`. **Solo si la fila se insertó** y `tipo = SALIDA`: suma en `rpt_consumo_material` (`cantidad += cantidad`, `monto += cantidad × precioReferencial`, `salidas += 1`). Si el movimiento ya estaba (por ejemplo, lo trajo la carga inicial), no suma nada. Si el evento no trae `precioReferencial` (eventos anteriores al cambio), el monto suma 0.

**Concurrencia.** El worker procesa hasta 10 mensajes a la vez (prefetch) y la carga inicial puede correr al mismo tiempo. Los únicos cálculos que leen varias filas para escribir otra son el avance de la obra y el conteo de observaciones: por eso `PlanillaAprobada`, `PlanillaObservada` y la carga de cada obra bloquean antes la fila de la obra en `rpt_obra_resumen` y quedan en fila uno detrás de otro. Lo demás son *upserts* de una sola fila, que PostgreSQL hace atómicos.

### Tareas programadas (zona horaria La Paz)

| Hora | Tarea |
|---|---|
| 00:20 | `rpt_cobro`: `PENDIENTE` con `vence_en < hoy` → `VENCIDO` (criterio 9) |
| 00:30 | `rpt_obra_resumen`: recalcular `plazo_pct` de todas las obras (criterio 10) |

## Carga inicial (criterios 17 a 22)

Decisión de Jairo (31/10/2026; antes estaba fuera del alcance). Llena el modelo de lectura con lo que los servicios ya tienen: obras creadas antes de que existiera la cola `ia`, una cola vaciada (por ejemplo con `recargar`) o los datos de prueba de la 011, que se cargan sin eventos (`docs/datos-prueba.md`, sección 12).

### Cuándo y cómo se corre

- Comando del servicio de IA (misma imagen): `uv run python -m ia.carga_inicial` (en el contenedor, `ia-carga-inicial`). Se corre **una vez** después de `alembic upgrade head` al crear `reportes_db`, con Obras, Materiales y Finanzas levantados. Termina con código 0 si todo se cargó y distinto de 0 si falló.
- Se puede correr de nuevo cuando se quiera (por ejemplo, después de `recargar` los datos de prueba): es idempotente.
- Una sola a la vez: toma `pg_try_advisory_lock` con una clave fija; si ya está tomada, termina con «Ya hay una carga inicial en curso» y código distinto de 0.
- **El worker no se detiene:** los eventos se siguen aplicando mientras corre (criterio 20).
- Registra cada corrida en la tabla `carga_inicial` (inicio, fin, estado, filas por tabla, error) y la muestra `GET /reportes/estado`.

### Token (cliente `ia-reportes`)

- Cliente confidencial de Keycloak **`ia-reportes`** con *service account* (solo el flujo *client credentials*; sin inicio de sesión de personas ni *direct access grants*) y el **rol de realm `gerente`** asignado a su *service account*. Lleva la audiencia `plataforma-api` como todos los tokens.
- El comando pide el token a `IA_KEYCLOAK_ISSUER/protocol/openid-connect/token` con `IA_REPORTES_CLIENT_ID` y `IA_REPORTES_CLIENT_SECRET`, y pide otro cuando falta menos de 30 s para que venza.
- **Por qué `gerente` y no un rol técnico nuevo:** los endpoints que usa la carga ya aceptan `gerente`, y `gerente` ya ve todas las obras en los tres servicios (convenciones, «Visibilidad de obras»). Como `azp = ia-reportes` no es `erp`, `portal` ni `app-obra`, cada servicio usa los roles del token tal cual (convenciones, «Usuario con varios roles»). Así **no cambia nada en Obras, Materiales ni Finanzas**. Un rol técnico nuevo obligaría a tocar los guardias y la visibilidad de los tres servicios (Java, TypeScript y PHP) solo para leer lo mismo que ya lee `gerente`.
- Límites: el comando solo hace `GET`; el secreto solo lo lee el comando de carga (no `ia-api` ni `ia-worker`, para que los agentes de la capa 5 no puedan usar este token; 504); el cliente no sirve para entrar a ninguna aplicación. Ninguna persona usa este cliente.
- Cada corrida usa un `X-Request-Id` propio (UUID) en todas sus llamadas, para seguirla en los registros de cada servicio.

### Endpoints que usa (todos existen en `docs/contratos/rest.md`)

| Paso | Servicio · endpoint | Rol que lo permite | Para qué |
|---|---|---|---|
| 1 | Materiales `GET /materiales?pagina=N&tamano=100` (todas las páginas) | `gerente` (internos) | `precioReferencial` actual de cada material |
| 2 | Obras `GET /obras` | todos; `gerente` ve todas | Lista de obras (`id`) |
| 3 | Obras `GET /obras/{id}` | quien ve la obra | `nombre`, `ubicacion`, `zona` (desde el cambio de esta spec), `estado`, `fechaInicio`, `asignaciones`, `contrato.monto`, `contrato.plazoDias`, `avancePct` (para comprobar) |
| 4 | Obras `GET /obras/{id}/planillas` | quien ve la obra | Planillas de la obra con `estado` |
| 5 | Obras `GET /planillas/{id}` (cada planilla del paso 4; la lista no trae `observacion` ni las líneas) | quien ve la obra | `periodo`, `neto`, `lineas[].monto`, `observacion`, `cobroId` |
| 6 | Finanzas `GET /cobros?obraId={id}&pagina=N&tamano=100` (todas las páginas) | `gerente` | `id`, `numero`, `planillaId`, `montoNeto`, `emitidoEn`, `venceEn`, `estado` |
| 7 | Materiales `GET /obras/{id}/movimientos?pagina=N&tamano=100&orden=registradoEn&direccion=asc` (todas las páginas, sin `periodo`) | internos que ven la obra; `gerente` ve todas | `id`, `materialId`, `tipo`, `cantidad`, `partidaId`, `periodo`, `superaStock`, `registradoEn` |

No hace falta Finanzas `GET /contratos`: el monto y el plazo vienen en `GET /obras/{id}` (Obras guarda la copia del contrato) y el `estado` de Obras ya dice si Finanzas registró el contrato (`EN_EJECUCION`). Un `404 OBRA_NO_ENCONTRADA` de Materiales en el paso 7 (obra que no está en `obra_acceso`) se toma como «sin movimientos».

Tiempo máximo por llamada: 10 s; un reintento con espera de 1 s ante `5xx`, error de red o tiempo agotado. Si vuelve a fallar, la carga se detiene (criterio 21).

### Qué escribe y cómo (por obra, en una transacción)

Para cada obra, en orden: lee los pasos 3 a 7 y, con todo en memoria, abre **una transacción** que:

1. Inserta la obra si no existe (`ON CONFLICT DO NOTHING`) y **bloquea su fila** (`SELECT … FOR UPDATE`), como `PlanillaAprobada`.
2. Datos descriptivos como `ObraRegistrada`. `estado`: `EN_EJECUCION` si Obras dice `EN_EJECUCION` (o si la fila ya lo tenía); si no, `SIN_CONTRATO` (`CONCLUIDA` no se carga: el sistema base no la usa).
3. Planillas `APROBADA` y `OBSERVADA` en `rpt_planilla` **solo si no existen** (lo que ya escribió un evento se respeta). Con `cargada_en` = momento en que se leyó el paso 4. `APROBADA`: `monto_periodo = Σ lineas.monto`, `avance_periodo_pct` como `PlanillaAprobada`, `aprobada_en = null` (Obras no expone la fecha de aprobación). Las dos: si `observacion` no es null, `veces_observada = 1`, `ultimo_motivo = observacion`, `ultimo_origen = null` (Obras guarda solo el último motivo, sin conteo ni origen). Una `BORRADOR`, `PRESENTADA` o `APROBANDO` se carga solo si tiene `observacion` (se observó antes y se volvió a presentar): como `OBSERVADA`, igual que la dejarían los eventos; si no, no se carga (no llega ningún evento por ella).
4. Recalcula `avance_pct` desde `rpt_planilla` (misma regla) y `plazo_pct` de hoy. Si `avance_pct` no coincide con el `avancePct` de Obras, registra una advertencia con la obra y los dos valores (no detiene la carga).
5. Cobros en `rpt_cobro` con las reglas de `PlanillaAprobada` y `CobroEmitido` (completa columnas vacías): `monto = montoNeto`, `cliente_id` y `zona` de la obra, `estado` de Finanzas (`PENDIENTE` o `VENCIDO`).
6. Movimientos en `rpt_movimiento` con la regla de `MovimientoRegistrado` (solo los que se insertan suman en `rpt_consumo_material`). `precio_referencial` = precio actual del catálogo (paso 1): Materiales no guarda el precio de cada movimiento, así que para los movimientos anteriores es una aproximación documentada (criterio 22).

Al terminar todas las obras, `carga_inicial` queda `TERMINADA` con las filas insertadas por tabla. Desde la 402, el mismo comando calcula después la predicción de todas las obras (motivo `CARGA_INICIAL`), para no esperar a la tarea de la 01:00. La carga **no** evalúa consumos atípicos (fuera del alcance).

### Por qué no choca con los eventos (criterio 20)

| Caso | Resultado |
|---|---|
| Un evento viejo en la cola `ia` repite algo que ya trajo la carga | `ObraRegistrada`, `ContratoRegistrado`, `PlanillaAprobada` y `CobroEmitido` dejan la misma fila (escriben lo mismo o completan vacíos); `MovimientoRegistrado` encuentra el movimiento y no suma; `PlanillaObservada` con `ocurridoEn` ≤ `cargada_en` no suma |
| Un evento nuevo llega mientras se carga la misma obra | Espera el bloqueo de la fila de la obra (o lo toma primero); después del otro, recalcula el avance desde `rpt_planilla`, así que el resultado es el mismo en cualquier orden |
| La carga lee una planilla `OBSERVADA` y antes de escribir llega su `PlanillaAprobada` | La fila ya existe como `APROBADA` y la carga no la toca |
| Se corre la carga dos veces | Todo se inserta «si no existe»; los movimientos ya cargados no suman de nuevo |
| La carga falla a mitad de camino | Las obras ya confirmadas quedan; la siguiente corrida las salta (ya existen) y completa las demás |

Límite conocido: si una planilla se observó dos veces antes de la carga, queda con `veces_observada = 1` (Obras no expone el conteo).

## Datos

### `reportes_db` (PostgreSQL, misma instancia en el puerto 5433, usuario propio `ia`)

#### rpt_obra_resumen
| Campo | Tipo | Notas |
|---|---|---|
| obra_id | uuid | PK |
| nombre | varchar | |
| ubicacion | varchar | |
| zona | varchar | `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO` o null |
| cliente_id | uuid | ref Keycloak (el nombre lo resuelve el gateway) |
| residente_id | uuid | ref Keycloak; visibilidad |
| maestro_id | uuid | ref Keycloak |
| almacenero_id | uuid | ref Keycloak |
| estado | varchar | `SIN_CONTRATO`, `EN_EJECUCION` |
| fecha_inicio | date | |
| plazo_dias | int | |
| monto_contrato | numeric(14,2) | |
| avance_pct | numeric(5,2) | misma regla que Obras |
| plazo_pct | numeric(5,2) | se recalcula a diario |
| riesgo_retraso | numeric(4,3) | probabilidad 0 a 1 del modelo (402); null sin predicción |
| nivel_riesgo | varchar | `BAJO`, `MEDIO`, `ALTO`, `SIN_DATOS` (402) |
| actualizado_en | timestamptz | |

#### rpt_planilla
| Campo | Tipo | Notas |
|---|---|---|
| planilla_id | uuid | PK |
| obra_id | uuid | índice |
| periodo | char(7) | `AAAA-MM`; null si solo se conoce por una observación |
| estado | varchar | `APROBADA`, `OBSERVADA` |
| neto | numeric(14,2) | |
| monto_periodo | numeric(14,2) | Σ montos de las líneas |
| avance_periodo_pct | numeric(5,2) | monto_periodo / monto_contrato × 100 |
| veces_observada | int | por defecto 0 |
| ultimo_motivo | text | |
| ultimo_origen | varchar | `CLIENTE`, `SAGA` |
| aprobada_en | timestamptz | `ocurridoEn` de `PlanillaAprobada`; null si la trajo la carga inicial |
| cargada_en | timestamptz | momento en que la carga inicial leyó la planilla; null si solo llegó por eventos |
| actualizado_en | timestamptz | |

#### rpt_consumo_material
| Campo | Tipo | Notas |
|---|---|---|
| obra_id | uuid | PK (compuesta) |
| periodo | char(7) | PK |
| material_id | varchar | PK, ref Materiales |
| partida_id | uuid | PK, ref Obras |
| cantidad | numeric(14,3) | suma de salidas |
| monto | numeric(14,2) | suma de cantidad × precio referencial |
| salidas | int | número de salidas |
| actualizado_en | timestamptz | |

#### rpt_movimiento
| Campo | Tipo | Notas |
|---|---|---|
| movimiento_id | uuid | PK |
| obra_id | uuid | |
| material_id | varchar | |
| partida_id | uuid | null en ingresos |
| tipo | varchar | `INGRESO`, `SALIDA` |
| cantidad | numeric(14,3) | |
| precio_referencial | numeric(14,2) | null en eventos anteriores al cambio; en la carga inicial, el precio del catálogo al cargar |
| periodo | char(7) | |
| supera_stock | boolean | |
| registrado_en | timestamptz | |

Índices: (`obra_id`, `material_id`, `registrado_en`), (`material_id`, `tipo`). Lo usa el modelo de consumos atípicos (403).

#### rpt_cobro
| Campo | Tipo | Notas |
|---|---|---|
| cobro_id | uuid | PK |
| numero | varchar | de `CobroEmitido` |
| obra_id | uuid | de `PlanillaAprobada` |
| planilla_id | uuid | |
| cliente_id | uuid | copia de la obra |
| zona | varchar | copia de la obra |
| monto | numeric(14,2) | neto de la planilla |
| emitido_en | date | |
| vence_en | date | |
| estado | varchar | `PENDIENTE`, `VENCIDO` |
| actualizado_en | timestamptz | |

Columnas que llegan por eventos distintos pueden estar null hasta que llega el otro evento.

#### evento_aplicado
| Campo | Tipo | Notas |
|---|---|---|
| evento_id | uuid | PK; `id` del sobre |
| tipo | varchar | |
| aplicado_en | timestamptz | |

#### carga_inicial
| Campo | Tipo | Notas |
|---|---|---|
| carga_id | uuid | PK; también es el `X-Request-Id` de sus llamadas |
| iniciada_en | timestamptz | |
| terminada_en | timestamptz | null mientras corre |
| estado | varchar | `EN_CURSO`, `TERMINADA`, `FALLIDA` |
| obras | int | obras procesadas |
| filas | jsonb | filas insertadas por tabla (`{"rptObraResumen": 3, …}`) |
| error | text | servicio, obra y causa si falló |

Una corrida que se cortó sin terminar (proceso detenido) queda `EN_CURSO`; la siguiente, que ya tomó el bloqueo, la marca `FALLIDA` al empezar.

### `ia_db` (MongoDB)

Se crea la conexión y los índices en esta spec; las colecciones las llenan 402 (`prediccion`) y 403 (`consumo_atipico`). La capa 5 agrega las de los agentes.

## REST del servicio de IA (401)

```
### GET /salud
Sin token · `200 {"estado":"ok"}`

### GET /reportes/estado · 401
Servicio: IA · Quién llama: (pruebas y administración) · Rol: `admin`
Recibe: —
Devuelve: 200 {
  "tablas": { "rptObraResumen": 12, "rptPlanilla": 40, "rptConsumoMaterial": 310, "rptMovimiento": 2210, "rptCobro": 35 },
  "ultimosEventos": [{ "tipo": "PlanillaAprobada", "aplicadoEn": "2026-11-15T14:30:00Z" }],
  "cargaInicial": {
    "cargaId": "uuid", "estado": "TERMINADA", "iniciadaEn": "2026-11-01T13:00:00Z", "terminadaEn": "2026-11-01T13:00:09Z",
    "obras": 3, "filas": { "rptObraResumen": 3, "rptPlanilla": 4, "rptMovimiento": 67, "rptCobro": 3 }, "error": null
  }
}
`cargaInicial`: la última corrida; `null` si nunca se corrió.
El ejemplo es la carga de los datos de prueba (011): 4 de sus 5 planillas, porque la N.º 3 de la obra 1 está `PRESENTADA` sin observación y no se carga (regla del paso 3 de «Qué escribe y cómo»).
Errores: 401 · 403
```

No se expone por GraphQL en esta spec (decisión del equipo): es una ayuda para comprobar la proyección y la carga.

## Obras (`services/obras`): zona

- Migración: `obra.zona varchar(10) null`.
- Valores: `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO` (decisión del equipo). Enum en el dominio.
- `POST /obras` acepta `"zona": "NORTE"` (opcional); valor fuera de la lista → `400` con `errores[]` (`campo` = `zona`).
- `GET /obras` y `GET /obras/{id}` devuelven `zona` (u `null`). La carga inicial la lee de `GET /obras/{id}`.
- `ObraRegistrada` agrega `ubicacion` y `zona` en `datos`. Finanzas y Materiales ignoran los campos que no usan (no cambian).
- Obras no cambia nada más por la carga inicial: el token de `ia-reportes` trae `gerente`, que ya puede leer los endpoints de la tabla «Endpoints que usa».

## Materiales (`services/materiales`): precio en el evento

- `MovimientoRegistrado` agrega `precioReferencial` (el `precio_referencial` del material al registrar el movimiento) en `datos`. Es un campo nuevo; la `version` del sobre sigue en 1.
- Nada cambia por la carga inicial (usa `GET /materiales` y `GET /obras/{obraId}/movimientos` con `gerente`).

## Finanzas (`services/finanzas`)

- Sin cambios: la carga inicial usa `GET /cobros?obraId=` con `gerente`.

## Gateway

- `RegistrarObraEntrada.zona: ZonaObra`, `Obra.zona: ZonaObra`, `ObraResumen.zona: ZonaObra` con `enum ZonaObra { NORTE SUR ESTE OESTE CENTRO }`. Se mapean tal cual desde Obras.
- El cliente REST del servicio de IA (`IA_URL`) se agrega en 402.

## mf-obras

- Formulario de registro de obra (002): selector «Zona» con las cinco opciones y «Sin zona».
- Lista y detalle de obra: muestran la zona («Sin zona» si es null).

## Infra

- Base `reportes_db` y usuario `ia` en PostgreSQL (script de inicio y nota para la instalación local de Jairo en el puerto 5433).
- RabbitMQ: la cola durable `ia`, sus 6 enlaces y `plataforma.fallidos` ya están en el archivo de definiciones desde la fase 1 (`docs/entorno-local.md`), así no se pierden los eventos anteriores a esta spec; aquí solo se comprueba que estén y se agrega lo que falte.
- Keycloak (realm `supervision`): cliente confidencial `ia-reportes` con *service account* (solo *client credentials*: `standardFlowEnabled`, `directAccessGrantsEnabled` e `implicitFlowEnabled` en `false`), audiencia `plataforma-api` y el rol de realm `gerente` en su *service account*. El secreto va en `infra/.env` (`.env.example` con el valor de desarrollo) y se copia a `IA_REPORTES_CLIENT_SECRET` del `.env` de IA.
- Datos de prueba: ya no hace falta una semilla propia de las tablas `rpt_*`. Después de la semilla de los servicios (011) y con ellos levantados, se corre la carga inicial, que las llena por REST. `recargar` vacía también `reportes_db` (tablas `rpt_*`, `evento_aplicado` y `carga_inicial`; nunca el historial de Alembic) y, al final, indica correr la carga inicial.
- Docker Compose: servicios `ia-api` (8085) e `ia-worker` construidos desde `services/ia` (opcionales, como las bases), y `ia-carga-inicial` (misma imagen, corre una vez y termina; perfil propio para no correrlo en cada `up`).

## Pruebas

- IA (dominio): avance con varias planillas aprobadas y redondeo; plazo antes de iniciar (0), a mitad y vencido (100); vencimiento de cobros en el borde (vence hoy: `PENDIENTE`; venció ayer: `VENCIDO`).
- IA (proyecciones, con PostgreSQL real en contenedor o local): cada evento produce las filas esperadas; mismo evento dos veces no duplica ni suma dos veces; `CobroEmitido` antes y después de `PlanillaAprobada` deja la misma fila; `ContratoRegistrado` sin obra falla y se reintenta; tercer fallo publica en `plataforma.fallidos` (canal de RabbitMQ simulado).
- IA (carga inicial, con PostgreSQL real y los tres servicios simulados con `httpx.MockTransport`): llena las tablas con los datos de la 011 (3 obras, 4 de sus 5 planillas —la N.º 3 de la obra 1, `PRESENTADA` sin observación, no se carga—, 3 cobros, 67 movimientos) y el avance coincide con el de Obras; correrla dos veces deja las mismas filas y el mismo consumo; un `MovimientoRegistrado` y un `PlanillaObservada` viejos aplicados después de la carga no suman; un `PlanillaAprobada` aplicado en paralelo con la carga de la misma obra deja el avance correcto (dos conexiones); una segunda carga simultánea se niega; un `503` de Finanzas en la segunda obra deja `FALLIDA` con la obra y el servicio en `error`, y la siguiente corrida completa; pide un token nuevo cuando el anterior está por vencer; solo hace `GET`.
- IA (API): `/salud` sin token; `/reportes/estado` con `admin` (200, con `cargaInicial`), con `gerente` (403) y sin token (401); formato Problem Details.
- Obras: `zona` válida, inválida (400) y ausente; `ObraRegistrada` con `ubicacion` y `zona` en el outbox.
- Materiales: `MovimientoRegistrado` con `precioReferencial`.
- Gateway: `zona` en la mutación y en las consultas.
- Integración (infra): registrar una obra y aprobar una planilla con Docker Compose y comprobar `rpt_obra_resumen`, `rpt_planilla` y `rpt_cobro`; cargar la semilla, correr la carga inicial con el cliente `ia-reportes` real y comprobar las filas en `reportes_db`.

## Cambios a contratos y datos

### `docs/contratos/eventos.md` (y `docs/contratos.md` de Obras, Materiales, Finanzas e IA)

Comprobado el 31/10/2026 contra `docs/contratos/eventos.md`: los 6 eventos existen y traen los campos que usan las proyecciones, salvo `ubicacion` y `zona` en `ObraRegistrada` y `precioReferencial` en `MovimientoRegistrado`, que agregan Obras y Materiales en esta spec. `emitido_en` sale del `ocurridoEn` del sobre de `CobroEmitido` y `aprobada_en` del de `PlanillaAprobada`.

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.ObraRegistrada` | Obras | Finanzas, Materiales, **IA** | agrega `ubicacion, zona` a los campos actuales (**cambia Obras**) | 002, 401 |
| `evento.finanzas.ContratoRegistrado` | Finanzas | Obras, **IA** | sin cambios | 002, 401 |
| `evento.materiales.MovimientoRegistrado` | Materiales | **IA** | agrega `precioReferencial` a los campos actuales (**cambia Materiales**) | 004, 401 |
| `evento.finanzas.CobroEmitido` | Finanzas | Obras, **IA** | sin cambios | 008, 401 |
| `evento.obras.PlanillaAprobada` | Obras | **IA** | sin cambios | 008, 401 |
| `evento.obras.PlanillaObservada` | Obras | **IA** | sin cambios | 008, 401 |

- Agregar: «La cola `ia` y sus enlaces se declaran en las definiciones de RabbitMQ de `infra` para que existan desde el inicio».

### `docs/contratos/rest.md` (sección nueva «IA (puerto 8085)») y `services/ia/docs/contratos.md`

- `GET /salud` y `GET /reportes/estado` (con `cargaInicial`) como en la sección «REST del servicio de IA».
- `services/ia/docs/contratos.md`, «Consume»: los 7 endpoints de la tabla «Endpoints que usa» de la carga inicial, con el cliente `ia-reportes`.

### `docs/contratos/rest.md` y `services/obras/docs/contratos.md`

- `POST /obras · 002, 401`: el cuerpo admite `"zona": "NORTE"` (opcional; `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`).
- `GET /obras` y `GET /obras/{id} · …, 401`: agregan `"zona": "NORTE"` (u `null`).
- «Quién llama» de `GET /obras`, `GET /obras/{id}`, `GET /obras/{obraId}/planillas` y `GET /planillas/{id}`: agregar «el servicio de IA en la carga inicial (401), con el token de `ia-reportes` (`gerente`)».

### `docs/contratos/rest.md`, `services/materiales/docs/contratos.md` y `services/finanzas/docs/contratos.md`

- «Quién llama» de Materiales `GET /materiales` y `GET /obras/{obraId}/movimientos`, y de Finanzas `GET /cobros`: agregar lo mismo (carga inicial, 401). Sin cambios en el contrato.

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

```graphql
enum ZonaObra { NORTE SUR ESTE OESTE CENTRO }   # 401
type ObraResumen { … zona: ZonaObra }
type Obra { … zona: ZonaObra }
input RegistrarObraEntrada { … zona: ZonaObra }
```

### `services/obras/docs/datos.md` — tabla `obra`

| Campo | Tipo | Notas |
|---|---|---|
| zona | varchar(10) | `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`; null = sin zona (401) |

### `services/ia/docs/datos.md` (nuevo)

- Tablas de `reportes_db` (incluidas `carga_inicial` y la columna `rpt_planilla.cargada_en`) y colecciones de `ia_db` de la sección «Datos».

### `docs/reglas-negocio.md`

- «Obra»: agregar «La obra puede tener una zona (`NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`; decisión del equipo), opcional; se usa en los reportes».
- Nueva sección «Base de reportes (capa 4)»: «Modelo de lectura (CQRS) que se alimenta con eventos; lo que ya existía se trae una vez con la carga inicial por REST; el avance usa la misma regla que Obras; un cobro `PENDIENTE` pasa a `VENCIDO` al día siguiente de su vencimiento».

### `docs/convenciones.md`

- «Eventos y comandos»: agregar la librería de IA: `aio-pika` 10.
- «Autenticación»: agregar la librería de IA: `PyJWT` 2 con `PyJWKClient`.
- «Puertos»: el servicio de IA usa 8085 (ya figura); `reportes_db` con usuario propio `ia`.
- Cliente `ia-reportes` y rol `gerente` de su *service account*: **ya aplicado** el 31/10/2026 al aprobar esta spec («Autenticación y permisos»), igual que en `docs/permisos.md`.

### `docs/datos-prueba.md`

- **Ya aplicado** el 31/10/2026: la fila «401» de la sección 13 dice que las tablas `rpt_*` se llenan con la carga inicial (sin semilla propia).

### `docs/arquitectura.md`

- **Ya aplicado** el 31/10/2026: nivel de datos con «CQRS: modelo de lectura alimentado por eventos», pieza IA sin modelo de lenguaje en la capa 4 y las conexiones «RabbitMQ → IA · AMQP · eventos para el modelo de lectura» e «IA → Obras, Materiales, Finanzas · REST (solo `GET`) · carga inicial (401)».

### `docs/entorno-local.md`

- Orden de arranque: después de levantar IA por primera vez (y después de `recargar`), correr la carga inicial con Obras, Materiales y Finanzas levantados.

### `CLAUDE.md` (raíz), mapa de proyectos

- `services/ia`: «Python 3.12 · FastAPI · PostgreSQL (`reportes_db`) · MongoDB (`ia_db`)», etapa «Capas 4, 3 y 5 (el repositorio `supervision-ms-ia` ya existe; lo llena la 401)».
