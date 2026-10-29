# 011 · Datos de prueba

**Estado:** aprobado · **Fase:** después del sistema base (se implementa cuando la 009 está `hecho`) · **Proyectos:** infra, services/obras, services/materiales, services/finanzas

## Historia

Como **equipo** quiero cargar con un solo comando un conjunto pequeño y realista de datos (3 obras de Santa Cruz con su presupuesto, materiales, movimientos, planillas, cobros y fotos), para probar cada funcionalidad y hacer la demostración sin registrar todo a mano, y volver al mismo estado cuando quiera.

Los datos están en `docs/datos-prueba.md` (fuente única).

## Criterios de aceptación

### Carga

1. CUANDO se corre `infra/semilla/semilla.ps1` (o `semilla.sh`) con las bases vacías y las migraciones aplicadas, ENTONCES termina sin errores y muestra un resumen con la fecha de carga D y la cantidad de registros por servicio: Obras 3 obras, 21 partidas, 5 planillas, 10 fotos; Finanzas 3 contratos, 3 reservas, 3 cobros; Materiales 15 materiales, 3 `obra_acceso`, 14 filas de stock, 67 movimientos, 3 cierres; bucket S3 de desarrollo 10 imágenes.
2. CUANDO se corre `semilla` una segunda vez, ENTONCES no se duplica nada (mismos conteos) y no falla.
3. CUANDO se modifica algo en una demostración (por ejemplo, se aprueba la planilla 3 de la obra 1) y se corre `recargar`, ENTONCES, después de confirmar, todo vuelve al estado del documento con la fecha del día.
4. La carga no publica eventos ni comandos: después de cargar, las tablas o colecciones `outbox_evento` de los tres servicios están vacías y el panel de RabbitMQ no muestra mensajes nuevos en el exchange `plataforma`.
5. SI un servicio corre en producción, o su base no es local, o falta `SEMILLA_PERMITIDA=si` en el `.env` de infra, ENTONCES la semilla y el vaciado se niegan a correr con un mensaje claro.
6. Los tres servicios usan la misma fecha D (la que calcula el script y pasa en `SEMILLA_FECHA`).

### Qué se ve el día de la carga

7. CUANDO gerente1 abre Supervisión, ENTONCES el tablero muestra **3 obras en ejecución, 1 obra en riesgo (Condominio Las Lomas), 1 material en `BAJO` y 1 cobro vencido por Bs 290.134,80**, y la tabla viene ordenada: Condominio Las Lomas (diferencia 33,66), Edificio Residencial Las Palmeras (4,84), Unidad Educativa Nueva Esperanza (2,08).
8. CUANDO gerente1 abre el Edificio Residencial Las Palmeras, ENTONCES ve avance 28,49 % y plazo 33,33 %, la suma de sus partidas es igual al monto del contrato (2.773.800,00), su saldo disponible es 2.117.900,80, tiene un cobro `VENCIDO` y uno `PENDIENTE`, y en la pestaña Material del periodo `M-1` el fierro de 1/2" de las columnas aparece **excedido** (6.000 kg usados frente a 4.800 kg previstos).
9. CUANDO admin1 abre Materiales → Stock, ENTONCES ve en la obra 1 el `FIE-12` en `JUSTO`, en la obra 2 el `CEM-IP30` en `BAJO` y el `GRA-34` en `JUSTO`, y el resto en `OK`; en el catálogo hay 15 materiales, uno inactivo y uno sin proveedor habitual.
10. La visibilidad coincide con las asignaciones: residente1 ve la obra 1; residente2, la obra 2; cliente1 ve en el portal las obras 1 y 3; cliente2 no ve ninguna obra (estado vacío).
11. CUANDO demo1 inicia sesión en el ERP, ENTONCES ve la Unidad Educativa Nueva Esperanza; CUANDO desde el menú «Aplicaciones → Portal del cliente» abre el portal, ENTONCES entra **sin volver a iniciar sesión** y ve el Condominio Las Lomas, con su planilla 2 `OBSERVADA` y sus 2 fotos publicadas.
12. CUANDO cliente1 abre en el portal la planilla 3 de la obra 1, ENTONCES la ve `PRESENTADA` con neto 330.149,10 y 3 fotos que se abren; SI la aprueba, ENTONCES la saga termina bien y se emite el cobro siguiente de la serie (`COB-AAAA-0004` si los tres cobros de prueba son del mismo año).
13. CUANDO residente2 abre la planilla 2 de la obra 2, ENTONCES la ve `OBSERVADA` con el motivo del cliente y puede corregirla y volver a presentarla.
14. Las 10 fotos se ven en el detalle de cada obra (galería por partida) y en la app; en el portal, cliente1 ve solo las 3 publicadas de la obra 1 y demo1 las 2 publicadas de la obra 2.

## Fuera del alcance

- Datos de las capas (diario, órdenes de compra, base de reportes, predicciones, agentes): cada capa amplía la semilla (sección 13 de `docs/datos-prueba.md`).
- Volumen para pruebas de carga o para entrenar modelos (los modelos de la 402 y 403 usan sus propios datos sintéticos).
- Cargar datos en los entornos de la capa 6.
