# 603 · Historia de demostración · Diseño

## Idea

Un **generador** (`infra/semilla/historia/generar.mjs`, Node 24, sin dependencias, semilla aleatoria fija) calcula la historia de las obras 4, 5 y 6 **de una sola vez** —partidas → avance de cada mes → planillas → cobros y pagos → material usado → compras y salidas → stock— con las reglas del negocio, y escribe un archivo por servicio con **el mismo formato** que los de la 011:

| Servicio | Archivo | Qué agrega |
|---|---|---|
| Obras | `src/main/resources/semilla/obras-historia.json` | obras, partidas, planillas, fotos |
| Finanzas | `database/seeders/datos/finanzas-historia.json` | contratos, reservas, cobros (con pago), envíos |
| Materiales | `src/semilla/materiales-historia.json` | `obraAcceso`, mínimos de stock, movimientos, cierres |

Además copia, para cada foto nueva, una de las 10 imágenes de la 011 (de una partida parecida) a `infra/semilla/fotos/{obraId}/{fotoId}.jpg`.

Con `SEMILLA_HISTORIA=si`, cada servicio **une** su archivo de la 011 con el de historia (listas concatenadas; catálogos y recetas, los de la 011) y aplica sus validaciones al conjunto. El número de los cobros (`COB-AAAA-NNNN`) se calcula sobre el conjunto, en orden de emisión.

## Reglas del generador

- **Calendario:** las fechas de meses pasados van como `M-k/dd HH:MM` (Obras y Materiales) y las de Finanzas como `D-n` (su formato); el generador las calcula contra D = 2026-11-09 para evitar los domingos y que un mismo hecho tenga la misma fecha en los tres servicios. El mes en curso usa `D-n`.
- **Avance:** cada partida tiene meses previstos; lo ejecutado por mes sigue el escenario (adelantada, muy atrasada o con atraso leve) sin pasar lo contratado.
- **Planillas:** una por mes (`cantidades` = lo ejecutado); presentada los primeros días del mes siguiente y aprobada unos días después (cobro `D-n 10:00` en Obras, `D-n` en Finanzas, mismo día).
- **Cobros:** neto = subtotal − anticipo − retención (reglas de negocio, con redondeo a centavos como `TotalesPlanilla`); vencen a 30 días; pagados entre 8 y 28 días después de emitidos (comprobante «Transferencia …»), salvo los recientes y el vencido de la obra 5.
- **Envíos:** `NOTA_COBRO` a los 5 minutos de emitido; `CONSTANCIA_PAGO` el día del pago; `RECORDATORIO_VENCIDO` al día siguiente del vencimiento del cobro vencido. Destinatario: el correo del cliente en `docs/datos-prueba.md`.
- **Material:** usado del mes por partida = ejecutado × receta × variación (±6 %; en la obra 5, la losa alivianada usa 1,25); repartido en salidas de días hábiles (horas alrededor de las 10:00, entre 07:30 y 17:30) con variación log-normal; compras («NR-…», 08:30) cuando el stock bajaría de 1,3 × el mínimo, en lotes redondos (bolsas de a 50, kg de a 500, m³ de a 6, piezas de a 1.000, m² de a 50). Stock final según el escenario.
- **Ids:** obras `b0000000-…-00000000000O`; partidas `b1000000-…-000000000OPP`; planillas `d0000000-…-000000000ONN`; contratos `c0000000-…-00000000000O`; reservas `c1000000-…-000000000ONN`; cobros `c2000000-…-000000000ONN`; envíos `c3000000-…-00000000TONN` (T: 0 nota, 1 constancia, 2 recordatorio vencido); fotos `f1000000-…-0000000OPPNN`; movimientos `f0000000-…-0000000ONNNN`; diario `b3000000-…-0000000ONNNN` (O = obra).

## Cambios por servicio

- **Obras:** `semilla.historia` (`SEMILLA_HISTORIA`); `DatosSemilla.leer(historia)` une `obras-historia.json`.
- **Finanzas:** con `SEMILLA_HISTORIA=si`, `DatosPruebaSeeder` une `finanzas-historia.json`. Los cobros aceptan `pagadoEn` (`D-n`) y `comprobante`: estado `PAGADO`, `pago_registrado_por` = admin1 y `pago_registrado_en` = ese día a las 11:00 de La Paz.
- **Materiales:** con `SEMILLA_HISTORIA=si`, `datos-semilla` une `materiales-historia.json`.
- **infra:** `semilla.ps1`/`.sh` pasan `SEMILLA_HISTORIA` a los tres; `agentes.mjs` con `SEMILLA_HISTORIA=si` registra además el diario de lunes a sábado de las seis obras (texto y clima según el escenario y el mes, generados al correr con la fecha D real); `eventos-ia.mjs --todas` publica el `MovimientoRegistrado` de todas las salidas de las obras 4 a 6 y de las dos de la 011, en orden cronológico (id de evento `fa000000-…` con el número del movimiento).
- **IA (agentes):** el proveedor no acepta `maxLength` ni `maxItems` en el esquema; las instrucciones del reporte dicen los límites y `ajustar_largos` corta los textos en una oración completa y deja los 10 primeros hallazgos (con sus sugerencias) antes de validar; 8192 fichas de salida.

## Pruebas

- En cada servicio, una prueba que arma la semilla **con** la historia (sin base de datos donde se pueda) y comprueba que pasa sus validaciones y los totales esperados; las de la 011 siguen igual.
- En la nube: vaciar, cargar con `SEMILLA_HISTORIA=si`, carga inicial, `eventos-ia.mjs --todas`, `agentes.mjs`, prueba de humo y revisión del tablero, el riesgo y los atípicos.
