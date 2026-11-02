# Reglas del negocio

Reglas que cruzan varios proyectos. Los valores marcados como **(decisión del equipo)** no vienen de una norma: los fijó el equipo para el proyecto y se pueden cambiar actualizando este archivo.

## Obra

- Estados: `SIN_CONTRATO` → `EN_EJECUCION` → `CONCLUIDA`.
- Una obra pasa a `EN_EJECUCION` cuando tiene contrato y presupuesto por partidas registrados.
- La suma de las partidas (cantidad × precio unitario) debe coincidir con el monto del contrato.
- Una obra tiene un residente, un maestro de obra y un almacenero asignados; cada uno ve solo sus obras.
- El cliente de la obra solo ve sus obras en el portal.
- La obra puede tener una zona (`NORTE`, `SUR`, `ESTE`, `OESTE`, `CENTRO`; **decisión del equipo**), opcional; se usa en los reportes (401).

## Contrato

- Lo registra Administración: monto, plazo en días, porcentaje de anticipo y porcentaje de retención.
- Es de Finanzas. Obras guarda una copia de monto, plazo, anticipo y retención para calcular la planilla.
- Flujo al registrar la obra: Administración llena en un solo formulario los datos de la obra, del contrato y el presupuesto. Obras guarda la obra (estado `SIN_CONTRATO`) con la copia del contrato y publica `ObraRegistrada`. Finanzas crea el contrato y publica `ContratoRegistrado`. Obras guarda el `contrato_id` y pasa la obra a `EN_EJECUCION`. Si Finanzas rechaza el contrato, la obra queda en `SIN_CONTRATO` con el motivo y Administración lo corrige.
- Saldo disponible = monto − suma de cobros emitidos − reservas vigentes. Los cobros `PAGADO` siguen contando como emitidos: registrar un pago no cambia el saldo (201).
- Validaciones del contrato: monto > 0, plazo > 0, anticipo y retención entre 0 y 100, y anticipo + retención < 100.
- Número de cobro: `COB-<año>-<correlativo de 4 dígitos>` (por ejemplo `COB-2026-0007`), correlativo global por año.

## Avance y plazo

- Cantidad ejecutada acumulada de una partida = suma de `cantidad_periodo` de sus líneas en planillas `APROBADA`.
- Avance de una partida (%) = ejecutada acumulada / cantidad contratada × 100.
- Avance de la obra (%) = Σ (ejecutada acumulada × precio unitario) / monto del contrato × 100.
- Plazo transcurrido (%) = días desde `fecha_inicio` hasta hoy / `plazo_dias` × 100, entre 0 y 100.
- Obra **en riesgo** (**decisión del equipo**): plazo transcurrido − avance > 10 puntos.
- Capa 4 (402): además, el modelo da una probabilidad de retraso (terminar más de 10 % después del plazo: `plazo_dias × 1,10`) con niveles `BAJO` < 30 %, `MEDIO` < 60 % y `ALTO` ≥ 60 % (**decisión del equipo**). Es una señal aparte: no cambia la etiqueta «En riesgo» de la regla. Sin predicción (`SIN_DATOS`) si la obra no tiene contrato o lleva menos de 5 % del plazo.

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
4. Finanzas emite el cobro (vence a los 30 días calendario desde su emisión, **decisión del equipo**) y consume la reserva. Estados del cobro: `PENDIENTE` → `VENCIDO` al día siguiente de su vencimiento; `PENDIENTE` o `VENCIDO` → `PAGADO` cuando administración registra el pago (201). Un `PAGADO` no cambia más.
5. Obras marca la planilla `APROBADA` y guarda el identificador del cobro.
- Compensaciones, en orden inverso: reabrir consumos, liberar la reserva y pasar la planilla a `OBSERVADA` con el motivo del fallo.

## Material y stock

- Se registran hechos: `INGRESO` o `SALIDA`, con cantidad. Nunca se escribe el stock a mano.
- Stock de un material en una obra = suma de ingresos − suma de salidas.
- Una salida indica la partida de destino.
- Una salida que supera el stock conocido **se acepta** y genera una alerta para revisión.
- Cada material tiene un stock mínimo por obra. Si el stock queda por debajo, se publica el evento «stock bajo» (lo usarán las notificaciones de la 010; la capa 2 ya no lo usa desde que la 201 pasó a ser la cobranza automática).
- Estado del stock (**decisión del equipo**): `BAJO` si cantidad < mínimo; `JUSTO` si mínimo ≤ cantidad ≤ 1,25 × mínimo; `OK` si cantidad > 1,25 × mínimo.
- Consumo fuera de lo previsto (**decisión del equipo**): el material usado en una partida durante el periodo supera en más de 20 % al previsto (usado > 1,20 × previsto). Se marca como alerta; no bloquea nada.
- El cierre del periodo (paso 3 de la saga) congela los movimientos de ese periodo; la compensación los reabre.
- Consumo atípico (capa 4, 403): una salida que el modelo de detección de anomalías marca como rara frente al consumo habitual (alrededor del 2 % de las salidas; **decisión del equipo**). No bloquea nada; queda `PENDIENTE` hasta que el residente asignado o administración la marca `NORMAL` o `CONFIRMADO` (confirmar exige un comentario de 5 a 300 caracteres). Es distinto del «consumo fuera de lo previsto» (> 1,20 × previsto). Para el modelo, una salida está fuera del horario habitual si se registra antes de las 06:00 o desde las 20:00 (hora de La Paz), o en domingo (el sábado se trabaja; **decisión del equipo**).

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

## Cobranza (capa 2)

- Lo que pasa con el cobro después de que la saga lo emite (201). Las reglas las decide Finanzas; n8n une los datos, envía los correos y anota en Finanzas lo que envió.
- **Pago:** se paga el cobro completo (sin pagos parciales; **decisión del equipo**). Lo registra administración con la fecha de pago (obligatoria, entre la emisión del cobro y hoy, hora de La Paz) y el n.º de comprobante (opcional, hasta 50 caracteres). Un cobro `PAGADO` no se vence, no se paga otra vez ni se deshace.
- **Nota de cobro:** al emitirse el cobro, el cliente de la obra recibe por correo la nota de cobro en PDF en menos de 1 minuto (**decisión del equipo**). Lleva las líneas del mes con cantidad mayor a 0, los totales de la planilla, el número de cobro, la emisión, el vencimiento y la leyenda «Este documento no es una factura».
- **Recordatorios:** todos los días a las 08:00 de La Paz (**decisión del equipo**): «por vencer» para los `PENDIENTE` que vencen entre hoy y hoy + 3 días (**decisión del equipo**) y «vencido» para los `VENCIDO` (o `PENDIENTE` con vencimiento pasado). Cada cobro recibe como máximo un recordatorio de cada tipo. Si hubo alguno, cobranzas recibe el resumen del día.
- **Constancia de pago:** al registrarse el pago, el cliente la recibe por correo.
- Cada correo al cliente va con copia oculta al correo de cobranzas de la empresa (**decisión del equipo**). Un aviso repetido no envía dos veces el mismo correo. Si el cliente no tiene correo en Keycloak, no se envía nada y la ejecución queda fallida.
- Un cobro `PAGADO` no recibe recordatorios, no cuenta como vencido ni por vencer en el tablero (009) y no lo informa el agente de cobros (502).

## Base de reportes (capa 4)

- Modelo de lectura (CQRS) que se alimenta con eventos, solo para lo que cruza servicios: cada servicio sigue escribiendo y leyendo lo suyo (401). Sin *event sourcing*.
- Lo que ya existía se trae una vez con la carga inicial por REST (y otra vez después de `recargar` los datos de prueba); se puede repetir sin duplicar.
- El avance usa la misma regla que Obras y el plazo transcurrido la de «Avance y plazo»; el plazo se recalcula una vez al día.
- Un cobro `PENDIENTE` pasa a `VENCIDO` al día siguiente de su vencimiento (igual que en Finanzas); un `PAGADO` no se vence (201).
- Va unos segundos detrás de los servicios (consistencia eventual).
- Aproximaciones de la carga inicial (lo que los servicios no exponen): una planilla observada antes de la carga cuenta como observada una sola vez, y los movimientos anteriores usan el precio actual del catálogo.

## Reportes (capa 5)

- Solo se consultan los conjuntos del catálogo (Obras, Material usado, Movimientos de material, Cobros, Planillas y Consumos atípicos), leídos de la base de reportes (401) y de los consumos atípicos (403); el modelo de lenguaje arma una receta y el código la valida y arma la consulta (503).
- La base de reportes puede ir hasta un día atrasada en el plazo y en el estado de los cobros (se recalculan una vez al día), y solo conoce las planillas **aprobadas** u **observadas**: las que están en borrador o presentadas sin observación no salen en los reportes.
- Hasta 100 filas en pantalla (el resto se avisa); 10 consultas por minuto por usuario, también con los reportes comunes (**decisión del equipo**). Solo `admin` y `gerente` (los reportes cruzan todas las obras).
- «Monto referencial» del material = cantidad × precio referencial del material al registrar la salida (401; no es el precio del contrato). «Cobrado» = cobros emitidos, pagados o no. Desde la 201 los reportes de cobros muestran además el estado `PAGADO` y la fecha de pago.

## Agentes (capa 5)

- Tres agentes fijos con su misión: Seguimiento de obras, Control de materiales y Control de cobros. Se ejecutan todos los días a las 06:00 (La Paz) y a pedido de `admin` o `gerente` («Ejecutar ahora»); una ejecución a la vez (502).
- Solo consultan sus herramientas MCP de solo lectura y sugieren acciones de la lista permitida de cada agente; no ejecutan nada. Aprobar una sugerencia solo registra la decisión (no se crea ni se envía nada en otra área); rechazarla exige un motivo de 10 a 500 caracteres; el comentario al aprobar es opcional, hasta 300. No se repite una sugerencia pendiente con la misma obra y acción.
- Planilla sin respuesta del cliente: `PRESENTADA` hace más de 7 días (**decisión del equipo**; desde la 501, Obras guarda `presentada_en`, la última vez que la planilla pasó a `PRESENTADA`). Cobros por vencer: los próximos 15 días (**decisión del equipo**); los `PAGADO` (201) no se informan.
- Visibilidad: el residente ve solo los hallazgos y sugerencias de sus obras y nunca los de Control de cobros.
