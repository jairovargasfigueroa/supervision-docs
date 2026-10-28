# 401 · Diseño

## Visión general

```
Obras ──ObraRegistrada, PlanillaAprobada, PlanillaObservada──┐
Finanzas ──ContratoRegistrado, CobroEmitido──────────────────┼──> exchange plataforma ──> cola «ia» ──> IA (worker)
Materiales ──MovimientoRegistrado────────────────────────────┘                                      │
                                                                         reportes_db (PostgreSQL) <─┤ proyecciones rpt_*
                                                                         ia_db (MongoDB) <──────────┘ (402, 403)
Gateway ──REST──> IA (api, puerto 8085)   (402, 403)
```

El servicio de IA tiene dos procesos que salen de la misma imagen:

- **`ia-api`**: FastAPI con Uvicorn en el puerto 8085. Atiende al gateway.
- **`ia-worker`**: consumidor de RabbitMQ y tareas programadas (recalcular plazo, vencer cobros; en 402 y 403, predicciones).

## Servicio de IA (`services/ia`)

### Stack (versiones verificadas en PyPI el 28/10/2026; se anota la mayor)

| Uso | Paquete |
|---|---|
| Lenguaje | Python 3.12 (lo exigen `xgboost` 3 y `numpy` 2.5) |
| Gestor de dependencias | `uv` (`pyproject.toml` + `uv.lock`) (decisión del equipo) |
| API | `fastapi` 0.162, `uvicorn` 0.54, `pydantic` 2, `pydantic-settings` 2 |
| PostgreSQL | `sqlalchemy` 2 (async) + `psycopg` 3; migraciones con `alembic` 1 |
| MongoDB | `pymongo` 4 (cliente asíncrono `AsyncMongoClient`) |
| RabbitMQ | `aio-pika` 10 |
| Token | `PyJWT[crypto]` 2 (`PyJWKClient` con el JWKS del realm) |
| Tareas programadas | `apscheduler` 3 (`AsyncIOScheduler`) |
| Pruebas | `pytest` 9, `pytest-asyncio` 1, `httpx` (cliente de pruebas de FastAPI) |
| ML (402, 403) | `xgboost` 3, `scikit-learn` 1, `pandas` 3, `numpy` 2, `joblib` 1 |

TensorFlow **no** es dependencia del servicio: solo del entorno de `entrenamiento/` (301).

### Arquitectura: DDD + hexagonal ligera (decisión del equipo)

Paquete `src/ia/`, un contexto por área, con la misma división que Obras:

```
src/ia/
  main.py                 FastAPI (ia-api)
  worker.py               consumidor + tareas programadas (ia-worker)
  config.py               variables de entorno (pydantic-settings)
  comun/                  Problem Details, X-Request-Id, registros JSON, tiempo de La Paz
  auth/                   validación del token y visibilidad de obras
  mensajeria/             conexión aio-pika, inbox, reintentos y fallidos
  reportes/               (401) proyecciones de eventos a rpt_*
    dominio/  aplicacion/  infraestructura/
  riesgo/                 (402)
  atipicos/               (403)
migraciones/              alembic (reportes_db)
ml/                       generadores sintéticos y entrenamiento (402, 403)
modelos/                  artefactos versionados de los modelos (402, 403)
entrenamiento/            TensorFlow, entorno aparte (301)
tests/
```

- El dominio (`reportes/dominio`) no importa FastAPI, SQLAlchemy ni aio-pika: cálculo de avance, plazo y vencimiento con fechas fijas.

### Configuración (`.env.example`; `.env` nunca se sube)

| Variable | Ejemplo |
|---|---|
| `IA_PUERTO` | `8085` |
| `IA_REPORTES_DB_URL` | `postgresql+psycopg://ia:ia@localhost:5433/reportes_db` |
| `IA_MONGO_URL` · `IA_MONGO_DB` | `mongodb://localhost:27017` · `ia_db` |
| `IA_RABBITMQ_URL` | `amqp://guest:guest@localhost:5672/` |
| `IA_KEYCLOAK_ISSUER` | `http://localhost:8080/realms/supervision` |
| `IA_AUDIENCIA` | `plataforma-api` |
| `IA_ZONA_HORARIA` | `America/La_Paz` |

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

### Reglas de cada proyección (`reportes/dominio`)

- **ObraRegistrada:** inserta la obra con `estado = SIN_CONTRATO`, `avance_pct = 0`, `plazo_pct` calculado hoy. Si ya existe, actualiza los datos descriptivos.
- **ContratoRegistrado:** `estado = EN_EJECUCION`. Si la obra no existe todavía, falla (reintento): con una sola cola, `ObraRegistrada` llega antes.
- **PlanillaAprobada:** `monto_periodo = Σ lineas.monto`; `avance_periodo_pct = monto_periodo / monto_contrato × 100`; inserta o actualiza `rpt_planilla` como `APROBADA`; `avance_pct` de la obra = Σ `monto_periodo` de sus planillas `APROBADA` / `monto_contrato` × 100 (2 decimales, mitad hacia arriba). Inserta o completa `rpt_cobro` con `cobro_id`, `obra_id`, `planilla_id`, `monto = neto`, `cliente_id` y `zona` de la obra.
- **CobroEmitido:** inserta o completa `rpt_cobro` con `numero`, `vence_en`, `planilla_id`, `emitido_en` = fecha de `ocurridoEn` en La Paz, `estado = PENDIENTE` (si `vence_en` < hoy, `VENCIDO`). El orden de llegada con `PlanillaAprobada` no importa: cada uno completa sus columnas (criterio 6).
- **PlanillaObservada:** inserta o actualiza `rpt_planilla` con `estado = OBSERVADA` (si no estaba `APROBADA`), `veces_observada + 1`, `ultimo_motivo`, `ultimo_origen`.
- **MovimientoRegistrado:** inserta `rpt_movimiento`. Si `tipo = SALIDA`: suma en `rpt_consumo_material` (`cantidad += cantidad`, `monto += cantidad × precioReferencial`, `salidas += 1`). Si el evento no trae `precioReferencial` (eventos anteriores al cambio), el monto suma 0.

### Tareas programadas (zona horaria La Paz)

| Hora | Tarea |
|---|---|
| 00:20 | `rpt_cobro`: `PENDIENTE` con `vence_en < hoy` → `VENCIDO` (criterio 9) |
| 00:30 | `rpt_obra_resumen`: recalcular `plazo_pct` de todas las obras (criterio 10) |

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
| aprobada_en | timestamptz | `ocurridoEn` de `PlanillaAprobada` |
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
| precio_referencial | numeric(14,2) | null en eventos anteriores al cambio |
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
  "ultimosEventos": [{ "tipo": "PlanillaAprobada", "aplicadoEn": "2026-11-15T14:30:00Z" }]
}
Errores: 401 · 403
```

No se expone por GraphQL en esta spec (decisión del equipo): es una ayuda para comprobar la proyección.

## Obras (`services/obras`): zona

- Migración: `obra.zona varchar(10) null`.
- Valores: `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO` (decisión del equipo). Enum en el dominio.
- `POST /obras` acepta `"zona": "NORTE"` (opcional); valor fuera de la lista → `400` con `errores[]` (`campo` = `zona`).
- `GET /obras` y `GET /obras/{id}` devuelven `zona` (u `null`).
- `ObraRegistrada` agrega `ubicacion` y `zona` en `datos`. Finanzas y Materiales ignoran los campos que no usan (no cambian).

## Materiales (`services/materiales`): precio en el evento

- `MovimientoRegistrado` agrega `precioReferencial` (el `precio_referencial` del material al registrar el movimiento) en `datos`. Es un campo nuevo; la `version` del sobre sigue en 1.

## Gateway

- `RegistrarObraEntrada.zona: ZonaObra`, `Obra.zona: ZonaObra`, `ObraResumen.zona: ZonaObra` con `enum ZonaObra { NORTE SUR ESTE OESTE CENTRO }`. Se mapean tal cual desde Obras.
- El cliente REST del servicio de IA (`IA_URL`) se agrega en 402.

## mf-obras

- Formulario de registro de obra (002): selector «Zona» con las cinco opciones y «Sin zona».
- Lista y detalle de obra: muestran la zona («Sin zona» si es null).

## Infra

- Base `reportes_db` y usuario `ia` en PostgreSQL (script de inicio y nota para la instalación local de Jairo en el puerto 5433).
- RabbitMQ: la cola durable `ia`, sus 6 enlaces y `plataforma.fallidos` ya están en el archivo de definiciones desde la fase 1 (`docs/entorno-local.md`), así no se pierden los eventos anteriores a esta spec; aquí solo se comprueba que estén y se agrega lo que falte.
- Datos de prueba: la 011 carga también filas en las tablas `rpt_*` (dependencia: `docs/specs/011-datos-prueba/`), para que 402, 403, 502 y 503 tengan datos sin esperar eventos.
- Docker Compose: servicios `ia-api` (8085) e `ia-worker` construidos desde `services/ia` (opcionales, como las bases).

## Pruebas

- IA (dominio): avance con varias planillas aprobadas y redondeo; plazo antes de iniciar (0), a mitad y vencido (100); vencimiento de cobros en el borde (vence hoy: `PENDIENTE`; venció ayer: `VENCIDO`).
- IA (proyecciones, con PostgreSQL real en contenedor o local): cada evento produce las filas esperadas; mismo evento dos veces no duplica ni suma dos veces; `CobroEmitido` antes y después de `PlanillaAprobada` deja la misma fila; `ContratoRegistrado` sin obra falla y se reintenta; tercer fallo publica en `plataforma.fallidos` (canal de RabbitMQ simulado).
- IA (API): `/salud` sin token; `/reportes/estado` con `admin` (200), con `gerente` (403) y sin token (401); formato Problem Details.
- Obras: `zona` válida, inválida (400) y ausente; `ObraRegistrada` con `ubicacion` y `zona` en el outbox.
- Materiales: `MovimientoRegistrado` con `precioReferencial`.
- Gateway: `zona` en la mutación y en las consultas.
- Integración (infra): registrar una obra y aprobar una planilla con Docker Compose y comprobar `rpt_obra_resumen`, `rpt_planilla` y `rpt_cobro`.

## Cambios a contratos y datos

### `docs/contratos/eventos.md` (y `docs/contratos.md` de Obras, Materiales, Finanzas e IA)

| Clave de enrutamiento | Publica | Escuchan | `datos` | Funcionalidad |
|---|---|---|---|---|
| `evento.obras.ObraRegistrada` | Obras | Finanzas, Materiales, **IA** | agrega `ubicacion, zona` a los campos actuales | 002, 401 |
| `evento.finanzas.ContratoRegistrado` | Finanzas | Obras, **IA** | sin cambios | 002, 401 |
| `evento.materiales.MovimientoRegistrado` | Materiales | **IA** | agrega `precioReferencial` a los campos actuales | 004, 401 |
| `evento.finanzas.CobroEmitido` | Finanzas | Obras, **IA** | sin cambios | 008, 401 |
| `evento.obras.PlanillaAprobada` | Obras | **IA** | sin cambios | 008, 401 |
| `evento.obras.PlanillaObservada` | Obras | **IA** | sin cambios | 008, 401 |

- Agregar: «La cola `ia` y sus enlaces se declaran en las definiciones de RabbitMQ de `infra` para que existan desde el inicio».

### `docs/contratos/rest.md` (sección nueva «IA (puerto 8085)») y `services/ia/docs/contratos.md`

- `GET /salud` y `GET /reportes/estado` como en la sección «REST del servicio de IA».

### `docs/contratos/rest.md` y `services/obras/docs/contratos.md`

- `POST /obras · 002, 401`: el cuerpo admite `"zona": "NORTE"` (opcional; `NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`).
- `GET /obras` y `GET /obras/{id} · …, 401`: agregan `"zona": "NORTE"` (u `null`).

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

- Tablas de `reportes_db` y colecciones de `ia_db` de la sección «Datos».

### `docs/reglas-negocio.md`

- «Obra»: agregar «La obra puede tener una zona (`NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`; decisión del equipo), opcional; se usa en los reportes».
- Nueva sección «Base de reportes (capa 4)»: «Se alimenta solo con eventos; el avance usa la misma regla que Obras; un cobro `PENDIENTE` pasa a `VENCIDO` al día siguiente de su vencimiento; lo ocurrido antes de crear la cola `ia` no se carga».

### `docs/convenciones.md`

- «Eventos y comandos»: agregar la librería de IA: `aio-pika` 10.
- «Autenticación»: agregar la librería de IA: `PyJWT` 2 con `PyJWKClient`.
- «Puertos»: el servicio de IA usa 8085 (ya figura); `reportes_db` con usuario propio `ia`.

### `docs/arquitectura.md`

- Pieza IA: «FastAPI (procesos `ia-api` e `ia-worker`) + Ollama (capa 5)».
- Conexiones: «RabbitMQ → IA · AMQP · eventos para la base de reportes».

### `CLAUDE.md` (raíz), mapa de proyectos

- `services/ia`: «Python 3.12 · FastAPI · PostgreSQL (`reportes_db`) · MongoDB (`ia_db`)», etapa «Capas 3 a 5 (existe desde la 301/401)».
