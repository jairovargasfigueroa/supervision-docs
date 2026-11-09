# 603 · Historia de demostración · Requisitos

**Decisión de Jairo (09/11/2026):** la plataforma desplegada debe verse como si la empresa la usara desde hace meses: datos realistas y coherentes de al menos tres meses atrás hasta hoy, de todo tipo, para que los reportes, los agentes, los modelos (402, 403) y el tablero muestren resultados variados. El detalle de los escenarios lo define el equipo (esta especificación).

## Historia de usuario

Como **equipo** que presenta la plataforma quiero que los datos de demostración tengan **varios meses de uso** (planillas, cobros y pagos, compras y salidas de material, diario de obra y fotos) en más obras, para que cada funcionalidad tenga algo real que mostrar.

## Criterios de aceptación

### Carga

1. CON `SEMILLA_HISTORIA=si` (además de `SEMILLA_DEMO=si` en la nube o de `SEMILLA_PERMITIDA=si` en desarrollo), la semilla carga los datos de la 011 **más** tres obras nuevas con su historia desde su inicio hasta el día de carga D. SIN la variable, la carga es exactamente la de la 011 (sus pruebas no cambian).
2. Las obras nuevas son:

   | Obra | Escenario | Inicio | Plazo |
   |---|---|---|---|
   | 4 · Edificio de Oficinas Casco Viejo (CENTRO) | **adelantada**: avance algo mayor que el plazo; cobros pagados a tiempo | D − 185 | 420 días |
   | 5 · Mercado Municipal Villa 1ro de Mayo (ESTE) | **muy atrasada**: avance muy por debajo del plazo, ritmo bajo, la última planilla observada, un cobro vencido sin pagar, cemento y ladrillo en `BAJO`, consumos atípicos | D − 215 | 300 días |
   | 6 · Condominio Jardines del Urubó (OESTE) | **atraso leve** (más de 10 puntos): la última planilla presentada esperando al cliente | D − 158 | 360 días |

3. Cada obra nueva tiene, coherente entre Obras, Finanzas y Materiales:
   - contrato y presupuesto por partidas (con sus recetas de material de la 011); el presupuesto suma el monto del contrato;
   - una planilla por mes desde su inicio; las aprobadas con su cobro, su reserva consumida y el cierre del periodo en Materiales; ninguna partida pasa lo contratado;
   - cobros con vencimiento a 30 días: la mayoría **pagados** (fecha, comprobante y constancia enviada), los recientes pendientes y uno vencido sin pagar (obra 5);
   - compras de material periódicas y **salidas casi diarias** (lunes a sábado, de 07:30 a 17:30) por partida, que cuadran con lo ejecutado cada mes según las recetas (con variación realista; en la obra 5 una partida pasa el 20 % de lo previsto); el stock queda como dice el escenario;
   - fotos de avance de cada periodo adjuntas a sus planillas.
4. Salidas raras para los consumos atípicos (403): en la obra 5, una de noche, una en domingo y una que supera el stock; en la obra 6, una de cantidad muy grande. Lo decide el modelo; no se fuerza.
5. Diario de obra de lunes a sábado en las **seis** obras (desde su inicio), con clima y texto coherentes con su escenario: en la obra 5, días de lluvia, falta de material y de personal.
6. Después de la carga inicial (401), se evalúan **todas** las salidas con el modelo de consumos atípicos, en orden cronológico, y se recalcula el riesgo. Se espera: obra 4 `BAJO`, obra 5 `ALTO`, obra 6 `MEDIO` o más.

### Coherencia y fechas

7. Fechas relativas a D, como en la 011. La historia está pensada para cargarse entre el día 5 y el 25 del mes; los días de la semana siguen el calendario de noviembre de 2026 (mes en que se generó): en otro mes alguna salida puede caer en domingo.
8. Ids fijos, carga idempotente y sin eventos, como en la 011. Las mismas validaciones de cada servicio (presupuesto, acumulados, stock fila por fila, cobro solo en planillas aprobadas) se aplican a los datos de la 011 más la historia.

## Fuera del alcance

Cambiar los datos de la 011 (obras 1 a 3), historial de ejecuciones de agentes, consultas de reportes guardadas y predicciones con fechas pasadas (el historial del riesgo empieza el día de la carga).
