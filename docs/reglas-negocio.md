# Reglas del negocio

Reglas que cruzan varios proyectos. Los valores marcados como **(decisión del equipo)** no vienen de una norma: los fijó el equipo para el proyecto y se pueden cambiar actualizando este archivo.

## Obra

- Estados: `SIN_CONTRATO` → `EN_EJECUCION` → `CONCLUIDA`.
- Una obra pasa a `EN_EJECUCION` cuando tiene contrato y presupuesto por partidas registrados.
- La suma de las partidas (cantidad × precio unitario) debe coincidir con el monto del contrato.
- Una obra tiene un residente, un maestro de obra y un almacenero asignados; cada uno ve solo sus obras.
- El cliente de la obra solo ve sus obras en el portal.

## Contrato

- Lo registra Administración: monto, plazo en días, porcentaje de anticipo y porcentaje de retención.
- Es de Finanzas. Obras guarda una copia de monto, plazo, anticipo y retención para calcular la planilla.
- Flujo al registrar la obra: Administración llena en un solo formulario los datos de la obra, del contrato y el presupuesto. Obras guarda la obra (estado `SIN_CONTRATO`) con la copia del contrato y publica `ObraRegistrada`. Finanzas crea el contrato y publica `ContratoRegistrado`. Obras guarda el `contrato_id` y pasa la obra a `EN_EJECUCION`. Si Finanzas rechaza el contrato, la obra queda en `SIN_CONTRATO` con el motivo y Administración lo corrige.
- Saldo disponible = monto − suma de cobros emitidos − reservas vigentes.
- Validaciones del contrato: monto > 0, plazo > 0, anticipo y retención entre 0 y 100, y anticipo + retención < 100.
- Número de cobro: `COB-<año>-<correlativo de 4 dígitos>` (por ejemplo `COB-2026-0007`), correlativo global por año.

## Avance y plazo

- Cantidad ejecutada acumulada de una partida = suma de `cantidad_periodo` de sus líneas en planillas `APROBADA`.
- Avance de una partida (%) = ejecutada acumulada / cantidad contratada × 100.
- Avance de la obra (%) = Σ (ejecutada acumulada × precio unitario) / monto del contrato × 100.
- Plazo transcurrido (%) = días desde `fecha_inicio` hasta hoy / `plazo_dias` × 100, entre 0 y 100.
- Obra **en riesgo** (**decisión del equipo**): plazo transcurrido − avance > 10 puntos. En la capa 4 se suma el riesgo de retraso que predice el modelo.

## Presupuesto por partidas

- Cada partida tiene unidad, cantidad contratada, precio unitario y meses de ejecución.
- Cada partida puede tener material previsto por unidad (por ejemplo, 1,1 bolsas de cemento por m² de losa).
- Material previsto de un periodo = cantidad medida en el periodo × cantidad prevista por unidad.

## Planilla de avance

- Una por obra y por periodo (mes). Número correlativo por obra, empezando en 1.
- El periodo de una planilla nueva debe ser posterior al de la última planilla de la obra y no puede ser un mes futuro.
- Al crearla, tiene una línea por cada partida de la obra con cantidad 0.
- Acumulado anterior de una línea = ejecutada acumulada de la partida (planillas aprobadas).
- Por cada partida se indica la cantidad ejecutada en el periodo.
- **Regla:** acumulado anterior + cantidad del periodo ≤ cantidad contratada. Si se supera, se rechaza.
- Cálculo:
  - monto de la línea = cantidad del periodo × precio unitario
  - subtotal = suma de los montos de las líneas
  - descuento por anticipo = subtotal × anticipo %
  - retención = subtotal × retención %
  - neto a cobrar = subtotal − descuento por anticipo − retención
- No se puede presentar una planilla con subtotal 0.

### Estados de la planilla

| Desde | Hacia | Quién | Condición |
|---|---|---|---|
| — | `BORRADOR` | Residente | Crea la planilla del periodo |
| `BORRADOR` | `PRESENTADA` | Residente | Sin errores y subtotal mayor a 0 |
| `PRESENTADA` | `APROBANDO` | Cliente | Aprueba en el portal; empieza la saga |
| `APROBANDO` | `APROBADA` | Saga | Todos los pasos terminaron bien; se emitió el cobro |
| `APROBANDO` | `OBSERVADA` | Saga | Algún paso falló; se compensaron los anteriores |
| `PRESENTADA` | `OBSERVADA` | Cliente | Observa con un motivo obligatorio |
| `OBSERVADA` | `PRESENTADA` | Residente | Corrige y vuelve a presentar |

- Solo se editan planillas en `BORRADOR` u `OBSERVADA`.
- El residente puede adjuntar como respaldo fotos de avance de la obra registradas dentro del periodo.
- Solo puede haber una planilla abierta (no aprobada) por obra.

### Saga «aprobar planilla»

- Cada paso espera la respuesta hasta 60 segundos (**decisión del equipo**); si no llega, se trata como fallo y se compensa.
1. Obras pasa la planilla a `APROBANDO`.
2. Finanzas reserva el neto contra el saldo del contrato. Si no alcanza, falla.
3. Materiales cierra los consumos del periodo de esa obra.
4. Finanzas emite el cobro (vence a los 30 días calendario desde su emisión, **decisión del equipo**) y consume la reserva. Un cobro `PENDIENTE` pasa a `VENCIDO` al día siguiente de su vencimiento.
5. Obras marca la planilla `APROBADA` y guarda el identificador del cobro.
- Compensaciones, en orden inverso: reabrir consumos, liberar la reserva y pasar la planilla a `OBSERVADA` con el motivo del fallo.

## Material y stock

- Se registran hechos: `INGRESO` o `SALIDA`, con cantidad. Nunca se escribe el stock a mano.
- Stock de un material en una obra = suma de ingresos − suma de salidas.
- Una salida indica la partida de destino.
- Una salida que supera el stock conocido **se acepta** y genera una alerta para revisión.
- Cada material tiene un stock mínimo por obra. Si el stock queda por debajo, se publica el evento «stock bajo» (lo usa la automatización de la capa 2).
- Estado del stock (**decisión del equipo**): `BAJO` si cantidad < mínimo; `JUSTO` si mínimo ≤ cantidad ≤ 1,25 × mínimo; `OK` si cantidad > 1,25 × mínimo.
- Consumo fuera de lo previsto (**decisión del equipo**): el material usado en una partida durante el periodo supera en más de 20 % al previsto (usado > 1,20 × previsto). Se marca como alerta; no bloquea nada.
- El cierre del periodo (paso 3 de la saga) congela los movimientos de ese periodo; la compensación los reabre.

## Fotos de avance

- Cada foto pertenece a una obra y a una partida, y la registra quien está en la obra.
- El cliente solo ve las fotos que el residente adjunta a una planilla como respaldo: se publican (`publicada_cliente = true`) cuando la planilla se presenta. Las demás fotos son internas.
- Sistema base: se publican tal cual. Capa 3: se publica la versión con rostros difuminados (`clave_archivo_cliente`).

## Diario de obra (capa 1)

- El maestro de obra registra una entrada por día y obra desde la app (también sin señal): clima y texto libre.
- Valores de clima: soleado, nublado, lluvia leve, lluvia fuerte (**decisión del equipo**).
- Texto de 10 a 2000 caracteres.
- La fecha no puede ser futura (hora de La Paz) ni anterior al inicio de la obra; la obra debe estar en ejecución.
- La app permite elegir hasta 7 días atrás (**decisión del equipo**).
- Una entrada enviada no se edita.
- Lo usa el agente de Seguimiento de obras (herramienta MCP `buscar_diario`). No forma parte del sistema base.
