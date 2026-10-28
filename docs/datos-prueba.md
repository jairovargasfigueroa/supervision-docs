# Datos de prueba

Conjunto de datos fijo para probar y demostrar la plataforma: **3 obras, 15 materiales, 5 planillas, 3 cobros, 67 movimientos y 10 fotos**. Es poco a propósito («ni tan vacío ni un montón»), pero cada pantalla del sistema base tiene algo que mostrar y cada regla tiene al menos un caso visible (obra en riesgo, material `BAJO` y `JUSTO`, consumo fuera de lo previsto, salida que supera el stock, cobro vencido, planilla observada).

Funcionalidad: `docs/specs/011-datos-prueba/`. Este documento es la **fuente única** de los valores: los archivos de semilla de cada servicio son copia de su parte y, si algo cambia, se cambia aquí primero.

Reglas generales:

- **Solo desarrollo.** Nunca se carga en las nubes de la capa 6 ni en una base que no sea local (ver «Guardas»).
- **Cada servicio carga lo suyo** en su propia base (principio 4 del `CLAUDE.md`). Los identificadores son fijos y están escritos aquí para que los tres servicios coincidan sin hablarse.
- **La carga no publica eventos** (ver «Por qué la semilla no publica eventos»).
- Montos en bolivianos (Bs). En este documento se escriben con punto de miles y coma decimal (`2.773.800,00`); en JSON y en la base, como número (`2773800.00`).
- Los nombres de personas, empresas y obras son **ficticios**. Los precios son **referenciales aproximados** para la demostración (decisión del equipo), no cotizaciones verificadas del mercado.

## 1. Fecha de carga y fechas relativas

Para que los indicadores (plazo transcurrido, riesgo, cobros vencidos) tengan sentido el día que se carga, ninguna fecha está escrita en duro: todas se calculan a partir de la **fecha de carga D**.

- **D** = fecha de hoy en `America/La_Paz` al empezar la carga. El script de `infra` la calcula **una sola vez** y la pasa a los tres servicios en la variable `SEMILLA_FECHA` (`AAAA-MM-DD`), para que no haya dos fechas distintas si la carga cruza la medianoche. Si `SEMILLA_FECHA` ya viene definida, se usa esa (sirve para las pruebas automáticas y para repetir una demostración con una fecha fija).
- **Notación** (la usan este documento y los archivos de semilla):

| Notación | Significa | Ejemplo con D = 2026-10-28 |
|---|---|---|
| `D − n` / `D + n` | fecha, n días antes o después de D | `D − 120` = 2026-06-30 |
| `M0` | periodo (mes calendario) que contiene a D | 2026-10 |
| `M-k` / `M+k` | periodo k meses antes o después de `M0` | `M-3` = 2026-07 |
| `M-k, día d` | día d del mes `M-k` a las **10:00 hora de La Paz** (14:00 UTC), salvo que se indique otra hora | `M-1, día 9` = 2026-09-09T14:00:00Z |
| `D − n, hh:mm` | ese día a esa hora de La Paz | `D − 2, 11:00` = 2026-10-26T15:00:00Z |

- Los días de un mes van de 2 a 27, para que existan en cualquier mes.
- Los movimientos y fotos de las obras con historia usan `M-k, día d` (caen siempre dentro del periodo correcto, que es lo que importa para planillas y cierres). Las fechas de inicio, firma y cobros usan `D ± n` (lo que importa ahí es la distancia en días a hoy). Se comprobó que las dos notaciones no se contradicen para cualquier D: por ejemplo, `D − 120` cae como muy tarde el día 3 de `M-3`, antes del primer movimiento (`M-3, día 5`), y los cobros se emiten siempre después de terminar el periodo de su planilla.
- Los meses previstos de cada partida (`partida.meses`) se escriben con las abreviaturas en español del mes inicial y final (`jul-ago`; un solo mes: `jul`).

**Los indicadores cambian con los días.** Son exactos el día D; después:

| Desde | Qué cambia |
|---|---|
| D + 11 | El cobro de la obra 2 (vence D + 10) pasa a `VENCIDO` con la tarea diaria de Finanzas. |
| D + 19 | La obra 1 pasa a «en riesgo» (plazo 38,61 % − avance 28,49 % > 10) y su cobro N.º 2 (vence D + 18) pasa a `VENCIDO`. |
| D + 20 | La obra 3 pasa a «en riesgo» (plazo 10,42 % y avance 0 %). |

Por eso, **antes de cada demostración se recarga** (`recargar.ps1`): vuelve a calcular todo con la fecha del día.

## 2. Identificadores fijos

Todos son UUID válidos (versión 4 en su forma; no son aleatorios) con un prefijo por tipo y un sufijo legible. `O` = número de obra (1, 2, 3); `NN`, `PP` = correlativos de 2 dígitos.

| Entidad | Servicio | Patrón | Ejemplo |
|---|---|---|---|
| Usuario | Keycloak | `a0000000-0000-4000-8000-0000000000NN` | `a0000000-0000-4000-8000-000000000003` (residente1) |
| Obra | Obras | `b0000000-0000-4000-8000-00000000000O` | `b0000000-0000-4000-8000-000000000001` |
| Partida | Obras | `b1000000-0000-4000-8000-000000000OPP` | `b1000000-0000-4000-8000-000000000103` (obra 1, P-03) |
| Planilla | Obras | `d0000000-0000-4000-8000-000000000ONN` | `d0000000-0000-4000-8000-000000000102` (obra 1, N.º 2) |
| Foto de avance | Obras | `f1000000-0000-4000-8000-0000000OPPNN` | `f1000000-0000-4000-8000-000000010302` (obra 1, P-03, foto 2) |
| Contrato | Finanzas | `c0000000-0000-4000-8000-00000000000O` | `c0000000-0000-4000-8000-000000000002` |
| Reserva de saldo | Finanzas | `c1000000-0000-4000-8000-000000000ONN` (mismo `ONN` que la planilla) | `c1000000-0000-4000-8000-000000000101` |
| Cobro | Finanzas | `c2000000-0000-4000-8000-000000000ONN` (mismo `ONN` que la planilla) | `c2000000-0000-4000-8000-000000000101` |
| Proveedor (capa 2) | Finanzas | los de la 201 | `7b1e5c1a-0001-4c3e-9a10-000000000001` |
| Material | Materiales | `e0000000-0000-4000-8000-0000000000NN` | `e0000000-0000-4000-8000-000000000001` (cemento) |
| Movimiento | Materiales | `f0000000-0000-4000-8000-0000000ONNNN` | `f0000000-0000-4000-8000-000000010033` |

Las claves compuestas (`stock_obra._id`, `cierre_periodo._id`) se arman con estos ids en el formato que ya usan las funcionalidades 003 y 008.

## 3. Usuarios (Keycloak)

Los de la 001 más `demo1`, con el `id` fijo (el realm los importa con ese `id`, que es el `sub` del token). Contraseña `Prueba123!` (no temporal), correo verificado.

| `id` | Usuario | Nombre | Apellido | Correo | Rol |
|---|---|---|---|---|---|
| `a0000000-0000-4000-8000-000000000001` | admin1 | Carla | Méndez Rivero | admin1@constructora-andina.test | `admin` |
| `a0000000-0000-4000-8000-000000000002` | gerente1 | Jorge | Antelo Suárez | gerente1@constructora-andina.test | `gerente` |
| `a0000000-0000-4000-8000-000000000003` | residente1 | Daniela | Roca Justiniano | residente1@constructora-andina.test | `residente` |
| `a0000000-0000-4000-8000-000000000004` | residente2 | Marcelo | Vaca Saucedo | residente2@constructora-andina.test | `residente` |
| `a0000000-0000-4000-8000-000000000005` | maestro1 | Freddy | Choque Mamani | maestro1@constructora-andina.test | `maestro` |
| `a0000000-0000-4000-8000-000000000006` | almacenero1 | Rosa | Flores Arteaga | almacenero1@constructora-andina.test | `almacenero` |
| `a0000000-0000-4000-8000-000000000007` | cliente1 | Roberto | Justiniano Paz | cliente1@correo.test | `cliente` |
| `a0000000-0000-4000-8000-000000000008` | cliente2 | Patricia | Saucedo Ribera | cliente2@correo.test | `cliente` |
| `a0000000-0000-4000-8000-000000000009` | demo1 | Lucía | Paz Antelo | demo1@constructora-andina.test | `residente` y `cliente` |

`demo1` existe para demostrar el paso entre el ERP y el portal sin volver a iniciar sesión (SSO de la 001): es residente de la obra 3 y cliente de la obra 2. Entra al ERP (tiene `residente`) y al portal (tiene `cliente`). Ojo: la regla de visibilidad de `docs/convenciones.md` está escrita por rol y no dice qué pasa con un usuario que tiene dos. Si cada servicio la aplica como unión de sus roles, demo1 verá las obras 2 y 3 tanto en el ERP como en el portal (en el portal solo podrá aprobar u observar la obra 2, porque eso exige ser el cliente dueño). Si se quiere que cada aplicación muestre solo lo de su rol, hay que decidirlo y anotarlo en las convenciones.

Los usuarios de servicio de las capas (`n8n`, `ia-agentes`) son clientes confidenciales, no usuarios: no van aquí.

## 4. Proveedores (Finanzas, capa 2)

Los tres de la 201 (`ProveedorSeeder`), sin cambios: `7b1e5c1a-0001-4c3e-9a10-000000000001` Ferretería El Constructor, `7b1e5c1a-0002-4c3e-9a10-000000000002` Aceros del Oriente y `7b1e5c1a-0003-4c3e-9a10-000000000003` Agregados Santa Cruz. En el sistema base la tabla `proveedor` todavía no existe; los materiales ya guardan su `proveedor_habitual_id` (el campo está en el modelo de Materiales).

## 5. Catálogo de materiales (Materiales)

| N.º | Código | Nombre | Tipo | Unidad / plural | Precio ref. (Bs) | Proveedor habitual | Atributos | Activo |
|---|---|---|---|---|---|---|---|---|
| 01 | `CEM-IP30` | Cemento IP-30 | `CEMENTO` | bolsa / bolsas | 62,00 | Ferretería El Constructor | peso: 50 kg | sí |
| 02 | `FIE-12` | Fierro corrugado de 1/2" | `ACERO` | kg / kg | 8,60 | Aceros del Oriente | diámetro: 12 mm · largo de barra: 12 m | sí |
| 03 | `FIE-10` | Fierro corrugado de 3/8" | `ACERO` | kg / kg | 8,70 | Aceros del Oriente | diámetro: 10 mm · largo de barra: 12 m | sí |
| 04 | `FIE-06` | Fierro corrugado de 1/4" | `ACERO` | kg / kg | 9,10 | Aceros del Oriente | diámetro: 6 mm | sí |
| 05 | `ALA-16` | Alambre de amarre N.º 16 | `ACERO` | kg / kg | 14,50 | Aceros del Oriente | — | sí |
| 06 | `ARE-FIN` | Arena fina | `AGREGADO` | m3 / m3 | 110,00 | Agregados Santa Cruz | uso: revoque y mortero | sí |
| 07 | `ARE-GRU` | Arena gruesa | `AGREGADO` | m3 / m3 | 130,00 | Agregados Santa Cruz | uso: hormigón | sí |
| 08 | `GRA-34` | Grava de 3/4" | `AGREGADO` | m3 / m3 | 185,00 | Agregados Santa Cruz | tamaño: 3/4" | sí |
| 09 | `PIE-MAN` | Piedra manzana | `AGREGADO` | m3 / m3 | 150,00 | Agregados Santa Cruz | uso: cimiento ciclópeo | sí |
| 10 | `LAD-6H` | Ladrillo de 6 huecos | `LADRILLO` | pieza / piezas | 1,30 | Ferretería El Constructor | medidas: 25 × 15 × 10 cm | sí |
| 11 | `MAD-ENC` | Tabla de encofrado de 1" | `MADERA` | pie tablar / pies tablares | 7,50 | Ferretería El Constructor | — | sí |
| 12 | `CLA-25` | Clavo de 2 1/2" | `OTRO` | kg / kg | 16,00 | Ferretería El Constructor | — | sí |
| 13 | `CER-4545` | Cerámica de piso 45 × 45 | `OTRO` | m2 / m2 | 78,00 | Ferretería El Constructor | tráfico: alto | sí |
| 14 | `TUB-PVC4` | Tubo PVC sanitario de 4" | `SANITARIO` | pieza / piezas | 95,00 | **sin proveedor** (`null`) | largo: 6 m | sí |
| 15 | `LAD-18H` | Ladrillo de 18 huecos | `LADRILLO` | pieza / piezas | 2,10 | Ferretería El Constructor | — | **no** |

- `TUB-PVC4` no tiene proveedor habitual (muestra la etiqueta «Sin proveedor habitual» de la 201) y `LAD-18H` está inactivo (criterio 5 de la 003).
- `id` del material = `e0000000-0000-4000-8000-0000000000NN` con el N.º de la tabla.

## 6. Obras

| | Obra 1 | Obra 2 | Obra 3 |
|---|---|---|---|
| `id` | `b0000000-…-000000000001` | `b0000000-…-000000000002` | `b0000000-…-000000000003` |
| Nombre | Edificio Residencial Las Palmeras | Condominio Las Lomas (12 viviendas) | Unidad Educativa Nueva Esperanza |
| Ubicación | Av. Beni entre 3er y 4to anillo, Santa Cruz de la Sierra | Av. Virgen de Cotoca, 6to anillo, Santa Cruz de la Sierra | Plan Tres Mil, Distrito 8, Santa Cruz de la Sierra |
| Zona (desde la 401) | `NORTE` | `ESTE` | `SUR` |
| Escenario | **buen ritmo** | **en riesgo** | **recién registrada** |
| Estado | `EN_EJECUCION` | `EN_EJECUCION` | `EN_EJECUCION` |
| Residente | residente1 | residente2 | **demo1** |
| Maestro de obra | maestro1 | maestro1 | maestro1 |
| Almacenero | almacenero1 | almacenero1 | almacenero1 |
| Cliente | cliente1 | **demo1** | cliente1 |
| Contrato firmado | D − 130 | D − 160 | D − 12 |
| Fecha de inicio | D − 120 | D − 150 | D − 5 |
| Plazo | 360 días | 300 días | 240 días |
| Anticipo / retención | 10 % / 7 % | 15 % / 7 % | 10 % / 5 % |
| Monto del contrato | **2.773.800,00** | **3.185.140,00** | **1.900.140,00** |
| `contrato_id` | `c0000000-…-000000000001` | `c0000000-…-000000000002` | `c0000000-…-000000000003` |

- `perimetro` y `motivo_rechazo_contrato` quedan en `null`. Anticipo + retención < 100 en las tres.
- Visibilidad resultante: residente1 ve la obra 1; residente2, la obra 2; demo1, la obra 3 en el ERP y la obra 2 en el portal; maestro1 y almacenero1, las tres; cliente1, las obras 1 y 3 en el portal; **cliente2 no tiene obras** (sirve para ver el estado vacío del portal).

### 6.1 Material previsto por unidad (insumos)

Las partidas del mismo tipo usan la misma receta (decisión del equipo, valores aproximados de obra):

| Receta | Insumos (`cantidad_por_unidad` por unidad de la partida) |
|---|---|
| Excavación, limpieza | sin insumos |
| Hormigón armado en zapatas (m3) | `CEM-IP30` 7,0 · `ARE-GRU` 0,50 · `GRA-34` 0,80 · `FIE-12` 80 |
| Hormigón armado en columnas (y vigas) (m3) | `CEM-IP30` 7,5 · `ARE-GRU` 0,50 · `GRA-34` 0,80 · `FIE-12` 120 |
| Losa maciza de hormigón armado, e = 15 cm (m2) | `CEM-IP30` 1,05 · `ARE-GRU` 0,075 · `GRA-34` 0,12 · `FIE-10` 9,0 |
| Losa alivianada con viguetas (m2) | `CEM-IP30` 0,65 · `ARE-GRU` 0,05 · `GRA-34` 0,07 · `FIE-10` 3,5 |
| Cimiento de hormigón ciclópeo (m3) | `CEM-IP30` 2,8 · `ARE-GRU` 0,25 · `GRA-34` 0,30 · `PIE-MAN` 0,55 |
| Muro de ladrillo de 6 huecos (m2) | `LAD-6H` 30 · `CEM-IP30` 0,20 · `ARE-FIN` 0,03 |
| Revoque grueso y fino (m2) | `CEM-IP30` 0,18 · `ARE-FIN` 0,025 |
| Contrapiso y piso cerámico (m2) | `CER-4545` 1,05 · `CEM-IP30` 0,30 · `ARE-FIN` 0,03 |

### 6.2 Presupuesto por partidas

`id` de la partida = `b1000000-0000-4000-8000-000000000OPP` (obra y número de la partida). Meses de ejemplo con D = 2026-10-28.

**Obra 1 · Edificio Residencial Las Palmeras**

| Código | Partida | Unidad | Cantidad | P. unitario | Monto | Meses | Receta |
|---|---|---|---|---|---|---|---|
| P-01 | Excavación con maquinaria | m3 | 1.200 | 46,50 | 55.800,00 | `M-3` (jul) | — |
| P-02 | Hormigón armado en zapatas | m3 | 180 | 2.448,00 | 440.640,00 | `M-3`…`M-2` (jul-ago) | zapatas |
| P-03 | Hormigón armado en columnas | m3 | 140 | 3.365,00 | 471.100,00 | `M-2`…`M+2` (ago-dic) | columnas |
| P-04 | Losa maciza de hormigón armado | m2 | 2.400 | 418,50 | 1.004.400,00 | `M-2`…`M+3` (ago-ene) | losa maciza |
| P-05 | Muro de ladrillo de 6 huecos | m2 | 3.200 | 134,80 | 431.360,00 | `M-1`…`M+5` (sep-mar) | muro |
| P-06 | Revoque grueso y fino | m2 | 6.000 | 61,75 | 370.500,00 | `M+1`…`M+7` (nov-may) | revoque |

Cuenta: 55.800,00 + 440.640,00 + 471.100,00 + 1.004.400,00 + 431.360,00 + 370.500,00 = **2.773.800,00** = monto del contrato ✓

**Obra 2 · Condominio Las Lomas**

| Código | Partida | Unidad | Cantidad | P. unitario | Monto | Meses | Receta |
|---|---|---|---|---|---|---|---|
| P-01 | Excavación manual para cimientos | m3 | 420 | 68,00 | 28.560,00 | `M-4` (jun) | — |
| P-02 | Cimiento de hormigón ciclópeo | m3 | 260 | 985,00 | 256.100,00 | `M-4`…`M-3` (jun-jul) | ciclópeo |
| P-03 | Hormigón armado en zapatas | m3 | 96 | 2.455,00 | 235.680,00 | `M-3`…`M-2` (jul-ago) | zapatas |
| P-04 | Hormigón armado en columnas y vigas | m3 | 150 | 3.290,00 | 493.500,00 | `M-2`…`M+1` (ago-nov) | columnas |
| P-05 | Losa alivianada con viguetas | m2 | 1.800 | 392,40 | 706.320,00 | `M-1`…`M+2` (sep-dic) | losa alivianada |
| P-06 | Muro de ladrillo de 6 huecos | m2 | 4.200 | 132,50 | 556.500,00 | `M0`…`M+3` (oct-ene) | muro |
| P-07 | Revoque grueso y fino | m2 | 8.400 | 60,20 | 505.680,00 | `M+1`…`M+4` (nov-feb) | revoque |
| P-08 | Contrapiso y piso cerámico | m2 | 1.900 | 212,00 | 402.800,00 | `M+3`…`M+5` (ene-mar) | piso |

Cuenta: 28.560,00 + 256.100,00 + 235.680,00 + 493.500,00 + 706.320,00 + 556.500,00 + 505.680,00 + 402.800,00 = **3.185.140,00** = monto del contrato ✓

(El atraso se ve también aquí: la excavación y el cimiento estaban previstos en `M-4` y `M-3`, y se cobraron recién en `M-2`.)

**Obra 3 · Unidad Educativa Nueva Esperanza**

| Código | Partida | Unidad | Cantidad | P. unitario | Monto | Meses | Receta |
|---|---|---|---|---|---|---|---|
| P-01 | Limpieza y replanteo del terreno | m2 | 2.500 | 9,80 | 24.500,00 | `M0` (oct) | — |
| P-02 | Excavación para fundaciones | m3 | 380 | 63,00 | 23.940,00 | `M0`…`M+1` (oct-nov) | — |
| P-03 | Hormigón armado en zapatas | m3 | 85 | 2.470,00 | 209.950,00 | `M+1` (nov) | zapatas |
| P-04 | Hormigón armado en columnas y vigas | m3 | 120 | 3.310,00 | 397.200,00 | `M+1`…`M+3` (nov-ene) | columnas |
| P-05 | Losa maciza de hormigón armado | m2 | 1.350 | 425,00 | 573.750,00 | `M+2`…`M+4` (dic-feb) | losa maciza |
| P-06 | Muro de ladrillo de 6 huecos | m2 | 2.600 | 136,00 | 353.600,00 | `M+3`…`M+5` (ene-mar) | muro |
| P-07 | Revoque grueso y fino | m2 | 5.200 | 61,00 | 317.200,00 | `M+5`…`M+7` (mar-may) | revoque |

Cuenta: 24.500,00 + 23.940,00 + 209.950,00 + 397.200,00 + 573.750,00 + 353.600,00 + 317.200,00 = **1.900.140,00** = monto del contrato ✓

## 7. Planillas (Obras)

Cada planilla tiene una línea por cada partida de su obra; las que no figuran abajo van con cantidad 0 y monto 0. Cálculo según `docs/reglas-negocio.md` (monto de línea = cantidad × precio; descuento por anticipo = subtotal × anticipo %; retención = subtotal × retención %; neto = subtotal − anticipo − retención; redondeo a 2 decimales, mitad hacia arriba). `version` = 1 en todas.

### Obra 1 (anticipo 10 %, retención 7 %)

| | N.º 1 | N.º 2 | N.º 3 |
|---|---|---|---|
| `id` | `d0000000-…-000000000101` | `d0000000-…-000000000102` | `d0000000-…-000000000103` |
| Periodo | `M-3` | `M-2` | `M-1` |
| Estado | `APROBADA` | `APROBADA` | `PRESENTADA` |
| Líneas | P-01: 1.200 × 46,50 = 55.800,00<br>P-02: 120 × 2.448,00 = 293.760,00 | P-02: 60 × 2.448,00 = 146.880,00<br>P-03: 50 × 3.365,00 = 168.250,00<br>P-04: 300 × 418,50 = 125.550,00 | P-03: 40 × 3.365,00 = 134.600,00<br>P-04: 500 × 418,50 = 209.250,00<br>P-05: 400 × 134,80 = 53.920,00 |
| Subtotal | 349.560,00 | 440.680,00 | 397.770,00 |
| Descuento por anticipo | 34.956,00 | 44.068,00 | 39.777,00 |
| Retención | 24.469,20 | 30.847,60 | 27.843,90 |
| **Neto** | **290.134,80** | **365.764,40** | **330.149,10** |
| `cobro_id` | `c2000000-…-000000000101` | `c2000000-…-000000000102` | `null` |
| Fotos adjuntas | — | — | `…010302`, `…010402`, `…010502` |

Acumulados contra lo contratado: P-02 120 + 60 = 180 de 180 (terminada); P-03 50 + 40 = 90 de 140; P-04 300 + 500 = 800 de 2.400; P-05 400 de 3.200 ✓ (ninguna supera lo contratado).

### Obra 2 (anticipo 15 %, retención 7 %)

| | N.º 1 | N.º 2 |
|---|---|---|
| `id` | `d0000000-…-000000000201` | `d0000000-…-000000000202` |
| Periodo | `M-2` | `M-1` |
| Estado | `APROBADA` | `OBSERVADA` |
| Líneas | P-01: 420 × 68,00 = 28.560,00<br>P-02: 260 × 985,00 = 256.100,00<br>P-03: 96 × 2.455,00 = 235.680,00 | P-04: 40 × 3.290,00 = 131.600,00 |
| Subtotal | 520.340,00 | 131.600,00 |
| Descuento por anticipo | 78.051,00 | 19.740,00 |
| Retención | 36.423,80 | 9.212,00 |
| **Neto** | **405.865,20** | **102.648,00** |
| `cobro_id` | `c2000000-…-000000000201` | `null` |
| `observacion` | — | «La medición de columnas y vigas (40 m³) no coincide con lo verificado en la visita de obra, que fue de unos 30 m³. Corrijan la cantidad y adjunten fotos de los vaciados.» |
| Fotos adjuntas | — | `…020401`, `…020402` |

La planilla N.º 2 la observó el cliente (demo1) desde el portal; residente2 puede corregirla y volver a presentarla.

### Obra 3

Sin planillas.

### Indicadores el día D

| Obra | Avance (planillas aprobadas) | Plazo transcurrido | Diferencia | ¿En riesgo? | Última planilla |
|---|---|---|---|---|---|
| 1 | (349.560,00 + 440.680,00) / 2.773.800,00 = **28,49 %** | 120 / 360 = **33,33 %** | 4,84 | no | `M-1` · `PRESENTADA` |
| 2 | 520.340,00 / 3.185.140,00 = **16,34 %** | 150 / 300 = **50,00 %** | 33,66 | **sí** | `M-1` · `OBSERVADA` |
| 3 | 0 / 1.900.140,00 = **0,00 %** | 5 / 240 = **2,08 %** | 2,08 | no | — |

Avance por partida (ejemplos): obra 1 P-02 100 %, P-03 50 / 140 = 35,71 %, P-04 300 / 2.400 = 12,50 %; obra 2 P-01, P-02 y P-03 100 %.

### Sagas

No se cargan filas en `saga_aprobacion`: la historia de la saga no se muestra en ninguna pantalla, y el resultado de las aprobaciones ya queda completo con `planilla.cobro_id` (Obras), la reserva `CONSUMIDA` y el cobro (Finanzas) y el cierre del periodo (Materiales). `outbox_evento` y `mensaje_procesado` quedan vacías.

## 8. Contratos, reservas y cobros (Finanzas)

### Contratos

| `id` | Obra | Monto | Plazo | Anticipo | Retención | Firmado | Cobrado | Reservado | **Saldo disponible** |
|---|---|---|---|---|---|---|---|---|---|
| `c0000000-…-000000000001` | 1 | 2.773.800,00 | 360 | 10 | 7 | D − 130 | 655.899,20 | 0,00 | **2.117.900,80** |
| `c0000000-…-000000000002` | 2 | 3.185.140,00 | 300 | 15 | 7 | D − 160 | 405.865,20 | 0,00 | **2.779.274,80** |
| `c0000000-…-000000000003` | 3 | 1.900.140,00 | 240 | 10 | 5 | D − 12 | 0,00 | 0,00 | **1.900.140,00** |

Saldo disponible = monto − cobros emitidos − reservas vigentes (obra 1: 2.773.800,00 − 290.134,80 − 365.764,40 = 2.117.900,80).

### Reservas de saldo

Una por planilla aprobada, en estado `CONSUMIDA` (la consumió el cobro): `c1000000-…-000000000101` (planilla 101, 290.134,80), `c1000000-…-000000000102` (planilla 102, 365.764,40) y `c1000000-…-000000000201` (planilla 201, 405.865,20). No hay reservas `RESERVADA` ni `LIBERADA`.

### Cobros

| `id` | Planilla | Número | Neto | Emitido | Vence (+30 días) | Estado el día D |
|---|---|---|---|---|---|---|
| `c2000000-…-000000000101` | obra 1 · N.º 1 | `COB-AAAA-0001` | 290.134,80 | D − 40 | D − 10 | **`VENCIDO`** |
| `c2000000-…-000000000201` | obra 2 · N.º 1 | `COB-AAAA-0002` | 405.865,20 | D − 20 | D + 10 | `PENDIENTE` |
| `c2000000-…-000000000102` | obra 1 · N.º 2 | `COB-AAAA-0003` | 365.764,40 | D − 12 | D + 18 | `PENDIENTE` |

- **Número:** `AAAA` = año de `emitido_en`; el correlativo se asigna por orden de emisión dentro de cada año. Con D = 2026-10-28: `COB-2026-0001`, `-0002` y `-0003`. Si D cae a inicios de año y algún cobro queda en el año anterior, el correlativo empieza de nuevo en el año nuevo (regla del número de cobro). La semilla deja el mecanismo de correlativo de la 008 en el último número usado, para que el siguiente cobro emitido por la saga continúe la serie (con D = 2026-10-28, `COB-2026-0004`).
- **Estado:** `VENCIDO` si `vence_en` < D; si no, `PENDIENTE`.
- **Resumen del tablero (`GET /cobros/resumen`):** vencidos 1 por 290.134,80; por vencer en 30 días 2 por 771.629,60.

## 9. Materiales

### Copia de asignaciones (`obra_acceso`)

Una fila por obra con su `nombre` y las asignaciones de la sección 6 (`actualizado_en` = D). Se carga directamente: no llega por `ObraRegistrada`.

### Stock mínimo y resultado

El stock **no se escribe a mano**: la semilla inserta los movimientos y calcula `stock_obra.cantidad` como ingresos − salidas (la tabla es la verificación). `version` = 1.

| Obra | Material | Mínimo | Cantidad final | Estado |
|---|---|---|---|---|
| 1 | `CEM-IP30` | 150 | 238 | `OK` |
| 1 | `FIE-12` | 1.000 | 1.150 | **`JUSTO`** (1.000 ≤ 1.150 ≤ 1.250) |
| 1 | `FIE-10` | 500 | 900 | `OK` |
| 1 | `ARE-GRU` | 10 | 25 | `OK` |
| 1 | `GRA-34` | 15 | 25 | `OK` |
| 1 | `LAD-6H` | 2.000 | 2.900 | `OK` |
| 1 | `ARE-FIN` | 4 | 8 | `OK` |
| 2 | `CEM-IP30` | 150 | 25 | **`BAJO`** |
| 2 | `ARE-GRU` | 8 | 24 | `OK` |
| 2 | `GRA-34` | 8 | 9 | **`JUSTO`** (8 ≤ 9 ≤ 10) |
| 2 | `PIE-MAN` | 0 | 5 | `OK` (cimiento terminado; ya no se pide) |
| 2 | `FIE-12` | 400 | 950 | `OK` |
| 3 | `CEM-IP30` | 100 | 300 | `OK` |
| 3 | `FIE-12` | 800 | 2.000 | `OK` |

Total: **1 `BAJO`**, 2 `JUSTO`, 11 `OK`.

### Movimientos

`id` = `f0000000-0000-4000-8000-0000000` + el N.º de 5 cifras de la tabla (por ejemplo `10033` → `f0000000-0000-4000-8000-000000010033`). Registrados por almacenero1. Los ingresos llevan `nota_remision = { numero: "NR-<N.º>" }` (por ejemplo `NR-10001`) sin foto. `periodo` = mes de `registrado_en` en La Paz. Cuando dos movimientos tienen la misma fecha, los ingresos van primero. La columna «Stock» es el stock de ese material en esa obra después del movimiento.

`cerrado = true` en los movimientos de los periodos con planilla aprobada (obra 1: `M-3` y `M-2`; obra 2: `M-2`); `false` en los demás. `supera_stock = true` solo en el marcado con ⚠.

**Obra 1**

| N.º | Fecha | Tipo | Material | Cantidad | Partida | Stock |
|---|---|---|---|---|---|---|
| 10001 | M-3, día 5 | Ingreso | CEM-IP30 | 900 | — | 900 |
| 10002 | M-3, día 5 | Ingreso | ARE-GRU | 65 | — | 65 |
| 10003 | M-3, día 5 | Ingreso | GRA-34 | 100 | — | 100 |
| 10004 | M-3, día 6 | Ingreso | FIE-12 | 10.000 | — | 10.000 |
| 10005 | M-3, día 12 | Salida | FIE-12 | 9.500 | P-02 | 500 |
| 10006 | M-3, día 19 | Salida | CEM-IP30 | 830 | P-02 | 70 |
| 10007 | M-3, día 19 | Salida | ARE-GRU | 59 | P-02 | 6 |
| 10008 | M-3, día 19 | Salida | GRA-34 | 95 | P-02 | 5 |
| 10009 | M-2, día 3 | Ingreso | CEM-IP30 | 1.100 | — | 1.170 |
| 10010 | M-2, día 3 | Ingreso | ARE-GRU | 75 | — | 81 |
| 10011 | M-2, día 3 | Ingreso | GRA-34 | 125 | — | 130 |
| 10012 | M-2, día 4 | Ingreso | FIE-12 | 11.000 | — | 11.500 |
| 10013 | M-2, día 4 | Ingreso | FIE-10 | 3.000 | — | 3.000 |
| 10014 | M-2, día 10 | Salida | CEM-IP30 | 415 | P-02 | 755 |
| 10015 | M-2, día 10 | Salida | ARE-GRU | 30 | P-02 | 51 |
| 10016 | M-2, día 10 | Salida | GRA-34 | 47 | P-02 | 83 |
| 10017 | M-2, día 10 | Salida | FIE-12 | 4.750 | P-02 | 6.750 |
| 10018 | M-2, día 17 | Salida | FIE-12 | 6.100 | P-03 | 650 |
| 10019 | M-2, día 20 | Salida | CEM-IP30 | 380 | P-03 | 375 |
| 10020 | M-2, día 20 | Salida | ARE-GRU | 25 | P-03 | 26 |
| 10021 | M-2, día 20 | Salida | GRA-34 | 40 | P-03 | 43 |
| 10022 | M-2, día 25 | Salida | FIE-10 | 2.650 | P-04 | 350 |
| 10023 | M-2, día 26 | Salida | CEM-IP30 | 320 | P-04 | 55 |
| 10024 | M-2, día 26 | Salida | ARE-GRU | 23 | P-04 | 3 |
| 10025 | M-2, día 26 | Salida | GRA-34 | 36 | P-04 | 7 |
| 10026 | M-1, día 2 | Ingreso | CEM-IP30 | 1.100 | — | 1.155 |
| 10027 | M-1, día 2 | Ingreso | ARE-GRU | 80 | — | 83 |
| 10028 | M-1, día 2 | Ingreso | GRA-34 | 110 | — | 117 |
| 10029 | M-1, día 3 | Ingreso | FIE-12 | 6.500 | — | 7.150 |
| 10030 | M-1, día 3 | Ingreso | FIE-10 | 5.000 | — | 5.350 |
| 10031 | M-1, día 4 | Ingreso | LAD-6H | 15.000 | — | 15.000 |
| 10032 | M-1, día 4 | Ingreso | ARE-FIN | 20 | — | 20 |
| 10033 | M-1, día 9 | Salida | FIE-12 | 6.000 | P-03 | 1.150 |
| 10034 | M-1, día 14 | Salida | CEM-IP30 | 305 | P-03 | 850 |
| 10035 | M-1, día 14 | Salida | ARE-GRU | 20 | P-03 | 63 |
| 10036 | M-1, día 14 | Salida | GRA-34 | 32 | P-03 | 85 |
| 10037 | M-1, día 18 | Salida | FIE-10 | 4.450 | P-04 | 900 |
| 10038 | M-1, día 21 | Salida | CEM-IP30 | 530 | P-04 | 320 |
| 10039 | M-1, día 21 | Salida | ARE-GRU | 38 | P-04 | 25 |
| 10040 | M-1, día 21 | Salida | GRA-34 | 60 | P-04 | 25 |
| 10041 | M-1, día 23 | Salida | LAD-6H | 12.100 | P-05 | 2.900 |
| 10042 | M-1, día 23 | Salida | CEM-IP30 | 82 | P-05 | 238 |
| 10043 | M-1, día 23 | Salida | ARE-FIN | 12 | P-05 | 8 |

**Obra 2**

| N.º | Fecha | Tipo | Material | Cantidad | Partida | Stock |
|---|---|---|---|---|---|---|
| 20001 | M-2, día 4 | Ingreso | CEM-IP30 | 1.500 | — | 1.500 |
| 20002 | M-2, día 4 | Ingreso | ARE-GRU | 120 | — | 120 |
| 20003 | M-2, día 4 | Ingreso | GRA-34 | 160 | — | 160 |
| 20004 | M-2, día 4 | Ingreso | PIE-MAN | 150 | — | 150 |
| 20005 | M-2, día 5 | Ingreso | FIE-12 | 8.000 | — | 8.000 |
| 20006 | M-2, día 11 | Salida | CEM-IP30 | 735 | P-02 | 765 |
| 20007 | M-2, día 11 | Salida | ARE-GRU | 66 | P-02 | 54 |
| 20008 | M-2, día 11 | Salida | GRA-34 | 80 | P-02 | 80 |
| 20009 | M-2, día 11 | Salida | PIE-MAN | 145 | P-02 | 5 |
| 20010 | M-2, día 16 | Salida | FIE-12 | 7.700 | P-03 | 300 |
| 20011 | M-2, día 22 | Salida | CEM-IP30 | 680 | P-03 | 85 |
| 20012 | M-2, día 22 | Salida | ARE-GRU | 49 | P-03 | 5 |
| 20013 | M-2, día 22 | Salida | GRA-34 | 77 | P-03 | 3 |
| 20014 | M-1, día 3 | Ingreso | ARE-GRU | 40 | — | 45 |
| 20015 | M-1, día 3 | Ingreso | GRA-34 | 39 | — | 42 |
| 20016 | M-1, día 6 | Ingreso | FIE-12 | 5.500 | — | 5.800 |
| 20017 | M-1, día 8 | Salida | FIE-12 | 4.850 | P-04 | 950 |
| 20018 | M-1, día 10 | Salida | CEM-IP30 | 120 | P-04 | -35 ⚠ |
| 20019 | M-1, día 12 | Ingreso | CEM-IP30 | 250 | — | 215 |
| 20020 | M-1, día 18 | Salida | CEM-IP30 | 190 | P-04 | 25 |
| 20021 | M-1, día 18 | Salida | ARE-GRU | 21 | P-04 | 24 |
| 20022 | M-1, día 18 | Salida | GRA-34 | 33 | P-04 | 9 |

⚠ La salida 20018 supera el stock que había (85 bolsas antes de una salida de 120): se acepta y queda marcada para revisión (`supera_stock = true`); el ingreso 20019 la repone.

**Obra 3**

| N.º | Fecha | Tipo | Material | Cantidad | Partida | Stock |
|---|---|---|---|---|---|---|
| 30001 | D − 3, 10:00 | Ingreso | CEM-IP30 | 300 | — | 300 |
| 30002 | D − 2, 10:00 | Ingreso | FIE-12 | 2.000 | — | 2.000 |

### Cierres de periodo (`cierre_periodo`)

| Obra | Periodo | Planilla | Estado | `cerrado_en` |
|---|---|---|---|---|
| 1 | `M-3` | `d0000000-…-000000000101` | `CERRADO` | D − 40, 10:00 (emisión del cobro) |
| 1 | `M-2` | `d0000000-…-000000000102` | `CERRADO` | D − 12, 10:00 |
| 2 | `M-2` | `d0000000-…-000000000201` | `CERRADO` | D − 20, 10:00 |

### Usado frente a previsto

Previsto = cantidad de la planilla del periodo × insumo por unidad (sección 6.1). Todos los consumos quedan entre 98 % y 105 % de lo previsto, salvo uno:

| Obra · periodo · partida | Material | Previsto | Usado | % | Resultado |
|---|---|---|---|---|---|
| 1 · `M-1` · P-03 columnas (40 m3) | `FIE-12` | 40 × 120 = 4.800 kg | 6.000 kg | **125 %** | **excedido** (usado > 1,20 × previsto) |
| 1 · `M-1` · P-04 losa (500 m2) | `FIE-10` | 4.500 kg | 4.450 kg | 98,9 % | normal |
| 1 · `M-1` · P-05 muro (400 m2) | `LAD-6H` | 12.000 piezas | 12.100 piezas | 100,8 % | normal |
| 2 · `M-1` · P-04 columnas (40 m3) | `CEM-IP30` | 300 bolsas | 310 bolsas | 103,3 % | normal |

## 10. Fotos de avance (Obras y almacén S3)

Dos por partida en ejecución, todas registradas por maestro1 a las 11:00 de La Paz. `clave_archivo = fotos/{obraId}/{fotoId}.jpg`. Las adjuntas a una planilla presentada están publicadas para el cliente (`publicada_cliente = true`); las demás son internas. Los campos de la capa 3 (`clave_archivo_cliente`, `personas_detectadas`, `sin_casco`) quedan en `null`.

| `id` (`f1000000-0000-4000-8000-0000000…`) | Obra · partida | Tomada | Publicada | Adjunta a |
|---|---|---|---|---|
| `10301` | 1 · P-03 columnas | `M-1, día 10` | no | — |
| `10302` | 1 · P-03 columnas | `M-1, día 15` | sí | planilla 103 |
| `10401` | 1 · P-04 losa | `M-1, día 19` | no | — |
| `10402` | 1 · P-04 losa | `M-1, día 22` | sí | planilla 103 |
| `10501` | 1 · P-05 muro | `M-1, día 24` | no | — |
| `10502` | 1 · P-05 muro | `M-1, día 27` | sí | planilla 103 |
| `20401` | 2 · P-04 columnas y vigas | `M-1, día 9` | sí | planilla 202 |
| `20402` | 2 · P-04 columnas y vigas | `M-1, día 19` | sí | planilla 202 |
| `30101` | 3 · P-01 limpieza y replanteo | `D − 2, 11:00` | no | — |
| `30102` | 3 · P-01 limpieza y replanteo | `D − 1, 11:00` | no | — |

Todas las fotos adjuntas son del periodo de su planilla (regla `FOTO_FUERA_DEL_PERIODO`).

**Imágenes: generadas, no descargadas** (decisión del equipo). Así no hay dudas de derechos de autor ni dependencia de un sitio externo. El script `infra/semilla/fotos/generar-fotos.ps1` usa `System.Drawing` (incluido en Windows PowerShell 5.1, sin instalar nada) para dibujar cada imagen: 1600 × 1200 px, JPEG calidad 80 (como las de la app), fondo de color por obra, un dibujo simple de la partida (bloques de columnas, losa o muro) y el texto «IMAGEN DE MUESTRA · <obra> · <código y partida> · foto N». Se corre una sola vez y las 10 imágenes se suben al repo `infra` en `semilla/fotos/{obraId}/{fotoId}.jpg` (unos 100 KB cada una), para que la carga no dependa de Windows.

## 11. Qué se ve al cargar (día D)

| Quién | Dónde | Qué ve |
|---|---|---|
| gerente1 o admin1 | Tablero (009) | 3 obras en ejecución · **1 en riesgo** · **1 material en `BAJO`** · cobros vencidos **1 por Bs 290.134,80**. Tabla ordenada por diferencia: Condominio Las Lomas (33,66; 1 material bajo; `M-1` observada, «En riesgo»), Edificio Las Palmeras (4,84; `M-1` presentada), Unidad Educativa (2,08; sin planillas) |
| residente1 | Tablero | obra 1; 0 en riesgo; 0 materiales bajos; sin el indicador de cobros (solo `admin` y `gerente`) |
| demo1 | ERP → Tablero y Obras | obra 3 (sin planillas, 2 fotos de limpieza y replanteo); 0 en riesgo |
| residente2 | Tablero | obra 2; 1 en riesgo; 1 material bajo |
| gerente1 | Obras → Edificio Las Palmeras (006) | avance 28,49 %, plazo 33,33 %; pestaña Material con periodo `M-1`: `FIE-12` en columnas **excedido** (6.000 frente a 4.800 kg); Cobros: uno vencido y uno pendiente; saldo 2.117.900,80 |
| admin1 | Materiales → Stock (003) | obra 1: `FIE-12` `JUSTO`; obra 2: `CEM-IP30` `BAJO`, `GRA-34` `JUSTO`; obra 3: dos materiales `OK`; catálogo con 15 materiales (uno inactivo) |
| residente2 | Planilla 2 de la obra 2 (007) | estado `OBSERVADA` con la observación del cliente; puede corregir y presentar |
| cliente1 | Portal (008) | obras 1 y 3; planillas 1 y 2 aprobadas y la 3 presentada con 3 fotos; puede aprobarla (la saga emite `COB-AAAA-0004`) u observarla |
| demo1 | Portal (desde el menú «Aplicaciones → Portal del cliente» del ERP, sin volver a iniciar sesión) | obra 2; planilla 1 aprobada y 2 observada (sin botones de acción) con 2 fotos |
| cliente2 | Portal | ninguna obra (estado vacío) |
| almacenero1 / maestro1 | App de obra (004, 005) | las tres obras; stock con los mismos estados; fotos por partida |

## 12. Cómo se carga

### Por qué la semilla no publica eventos

La semilla escribe en cada servicio sus datos **ya coherentes** con los de los demás (mismos ids, mismos montos). No publica ningún evento ni comando, deja vacías las tablas `outbox_evento` y `mensaje_procesado`, y no arranca los consumidores. Motivos:

1. **No hace falta:** lo que en uso real viaja por eventos (contrato creado por `ObraRegistrada`, copia `obra_acceso`, cobro emitido por la saga, cierre de periodo) ya se escribe directamente en el servicio dueño.
2. **Publicar repetiría efectos:** `ObraRegistrada` haría que Finanzas intente crear el contrato otra vez y responda `ContratoRegistrado`; un `CobroEmitido` sin saga se registraría como incidente; un `StockBajo` dispararía en la capa 2 una orden de compra y un correo cada vez que se carga.
3. **La carga dejaría de ser determinista e idempotente:** dependería del orden de llegada de los mensajes y de que todos los servicios estén corriendo.

Consecuencia: lo que **solo** se alimenta de eventos no se llena con la carga del sistema base. Por eso cada capa que agrega una de esas piezas amplía la semilla (sección 13); por ejemplo, la base de reportes de la 401.

### Cada servicio carga lo suyo

| Pieza | Comando | Qué hace |
|---|---|---|
| Keycloak | (al iniciar el contenedor) | El JSON del realm (fase 1, 1.4) trae los 9 usuarios (los 8 de la 001 y `demo1`) con su `id` fijo, nombres y contraseña. |
| Obras | `./mvnw spring-boot:run -Dspring-boot.run.profiles=dev,semilla` (en Windows `mvnw.cmd`) | Perfil `semilla`: arranca sin servidor web, sin consumidores de RabbitMQ y sin publicador del outbox, carga y termina. Opción `--semilla.modo=recargar` para vaciar antes. |
| Finanzas | `php artisan db:seed --class=DatosPruebaSeeder` | Contratos, reservas y cobros (y los proveedores de la 201 cuando exista). Vaciar: `php artisan datos-prueba:vaciar`. Desde PowerShell con el PHP de Herd. |
| Materiales | `npm run semilla` | Script que crea un contexto de NestJS solo con Mongoose (sin HTTP ni RabbitMQ). Vaciar: `npm run semilla:vaciar`. |
| Almacén S3 (RustFS, servicio `almacen`) | AWS CLI en un contenedor (`amazon/aws-cli:2.38.0`, con `--endpoint-url http://almacen:9000`) | `aws s3 sync` de `infra/semilla/fotos/` al bucket `supervision` bajo `fotos/`. |

- Cada servicio guarda su parte en un archivo de datos propio con la notación de fechas de la sección 1 (por ejemplo `"fechaInicio": "D-120"`, `"registradoEn": "M-1/09 10:00"`) y un pequeño resolvedor de fechas con pruebas. Valores y cálculos derivados (stock, saldo, número de cobro, estado del cobro) los calcula la semilla, no se copian.
- **Idempotencia:** cada registro se inserta solo si su `id` no existe (`INSERT … ON CONFLICT (id) DO NOTHING` en PostgreSQL; *upsert* con `$setOnInsert` en MongoDB; el almacén S3 sobrescribe la misma clave y `aws s3 sync` no vuelve a subir lo que ya está igual). Correr la carga dos veces no duplica nada. La carga **no pisa** lo que ya existe: si en una demostración se aprobó una planilla, cargar de nuevo no la devuelve a `PRESENTADA`; para eso está `recargar`.
- Cada carga va en una transacción por servicio: o queda todo o nada.

### Scripts de `infra`

- `semilla/semilla.ps1` (Windows) y `semilla/semilla.sh` (Linux y macOS) hacen lo mismo, en este orden:
  1. **Guardas** (abajo) y comprobación de que PostgreSQL, MongoDB, Keycloak y el almacén S3 responden.
  2. Calcula D y exporta `SEMILLA_FECHA`.
  3. Keycloak: comprueba con la API de administración (credenciales de administrador del `.env` de infra) que cada usuario existe con su `id`. Si no, se detiene y explica cómo reimportar el realm (`recargar` lo hace).
  4. Obras → Finanzas → Materiales (cada uno con su comando; las rutas de los proyectos salen de variables del `.env`, por defecto las carpetas hermanas `../services/…`).
  5. Fotos al almacén S3.
  6. Resumen: cuántos registros quedaron por servicio y la fecha D usada.
- `semilla/recargar.ps1` y `semilla/recargar.sh` **vacían y vuelven a cargar**: piden confirmación («Esto borra todos los datos de desarrollo de obras_db, finanzas_db, materiales_db y del bucket supervision. ¿Continuar? (s/N)»; `-Si` / `--si` la omite), vacían cada servicio con su propio comando (todas las tablas o colecciones del negocio; nunca el historial de migraciones), vacían las colas de RabbitMQ de la plataforma (para que no lleguen mensajes viejos que apunten a datos borrados), borran los objetos del bucket, reimportan los usuarios del realm si sus `id` no coinciden y corren `semilla`. Se recomienda detener antes los servicios.

### Guardas

La semilla y el vaciado se niegan a correr (mensaje claro y código de salida distinto de 0) si:

- el servicio corre con un perfil o entorno de producción (`prod` en Spring, `APP_ENV=production` en Laravel, `NODE_ENV=production` en Node);
- la base no está en `localhost`, `127.0.0.1` o en el nombre de un contenedor del Docker Compose de infra;
- en infra, la variable `SEMILLA_PERMITIDA=si` no está en el `.env` (el `.env.example` la trae; los entornos de la capa 6 no).

## 13. Ampliaciones por capa

Esta funcionalidad carga las tablas del **sistema base** (001 a 009). Cuando una funcionalidad posterior agrega tablas, colecciones o campos que deben tener datos para probarla, **esa funcionalidad amplía su parte de la semilla** en el servicio dueño (y este documento) en el mismo trabajo, con las mismas reglas: ids fijos, fechas relativas, sin eventos, idempotente. Previsto:

| Funcionalidad | Qué agrega a la semilla |
|---|---|
| 103 Diario de obra | Entradas de diario de maestro1, sobre todo en la obra 2 (días de lluvia que explican el atraso; las usa la 502). |
| 201 Compra automática | `DatosPruebaSeeder` llama a `ProveedorSeeder`. Opcional: una orden de compra para el `CEM-IP30` `BAJO` de la obra 2, cargada directamente (sin `StockBajo`). |
| 301 y 303 (capa 3) | `personas_detectadas`, `sin_casco` y `clave_archivo_cliente` de las fotos (las imágenes generadas no tienen personas). |
| 401 Base de reportes | Columna `zona` de las obras (sección 6). La base de reportes solo se llena con eventos, así que el servicio de IA agrega su propia semilla que escribe las filas `rpt_*` equivalentes a este documento. |
| 402 y 403 | Predicciones y consumos atípicos de prueba coherentes con la obra 2 (riesgo) y con el `FIE-12` excedido de la obra 1. |
| 502 Agentes | Revisa que estén sus casos: obra atrasada (obra 2), material bajo (`CEM-IP30` obra 2), salida que supera el stock (20018), cobro vencido (`COB-…-0001`), planilla presentada (obra 1 N.º 3), y agrega lo que falte. |
