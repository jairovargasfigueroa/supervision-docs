# Producto

## Qué es

Plataforma de **una** empresa constructora (en los ejemplos, «Constructora Andina») para supervisar sus obras. No es un mercado público: los clientes entran con una cuenta que la constructora les da al firmar el contrato.

## Problema que resuelve

- Los atrasos se detectan tarde: el avance se conoce recién a fin de mes.
- El material se pierde o se gasta de más sin que nadie lo note.
- El cliente observa las planillas porque el avance no tiene respaldo.
- En muchas obras no hay señal estable.

## Usuarios

| Usuario | Quién es | Aplicación |
|---|---|---|
| Administración | Personal de oficina | ERP |
| Residente | Ingeniero a cargo de una o varias obras | ERP (y app de obra) |
| Gerente | Jefe de la empresa | ERP |
| Maestro de obra | Dirige las cuadrillas en la obra | App de obra |
| Almacenero | Controla el depósito de la obra | App de obra |
| Cliente | Quien paga la obra; tiene contrato con la constructora | Portal del cliente |

## Aplicaciones

- **ERP** (web interna): gestión de obras, materiales, planillas y supervisión. Usa GraphQL y tiene los agentes.
- **Portal del cliente** (web externa): ver el avance y aprobar u observar las planillas.
- **App de obra** (móvil): registrar avance y material en la obra, aun sin señal.

Las tres comparten el inicio de sesión (Keycloak) y los mismos servicios.

## Sistema base (lo primero que se construye)

El ciclo completo de una obra, con conexión a internet:

1. **Preparar la obra:** registrar la obra, su contrato y su presupuesto por partidas (con material previsto por unidad). Catálogo de materiales y stock mínimo.
2. **Ejecutar:** registrar desde la app las fotos de avance y los ingresos y salidas de material.
3. **Controlar:** avance frente al plazo y material usado frente al previsto.
4. **Cobrar:** elaborar y presentar la planilla del mes; el cliente la aprueba (saga) o la observa.
5. **Supervisar:** tablero simple de obras.

Funciones del sistema base: iniciar sesión, registrar obra, gestionar materiales, consultar obra, registrar ingreso de material, registrar salida de material, registrar foto de avance, elaborar y presentar planilla, revisar planilla (portal), consultar tablero.

## Capas (se agregan sobre el sistema base)

| Capa | Qué agrega |
|---|---|
| 1. Terreno sin señal | App offline, mala conexión, sincronización sin duplicados (DynamoDB); ERP como PWA para el borrador de planilla |
| 2. Automatización | Stock bajo → orden de compra → correo al proveedor → cuenta por pagar (n8n) |
| 3. IA en el dispositivo | Detección de casco y chaleco (TensorFlow Lite); voz a texto y rostros difuminados en el navegador |
| 4. Datos y predicciones | Servicio de IA: riesgo de retraso (supervisado), consumos raros (no supervisado), base de reportes |
| 5. Inteligencia en el ERP | Reportes por voz con exportación a Excel; 3 agentes; servidores MCP |
| 6. Despliegue | Contenedores repartidos en AWS, Google Cloud y Azure |

## Fuera del alcance

- Registro de usuarios: se gestionan en el panel de Keycloak.
- Alta de trabajadores y proveedores: vienen como datos iniciales.
- Registro de pagos de clientes y a proveedores.
- Aprobación de órdenes de compra de monto alto.
- Incidentes, planos, órdenes de cambio, subcontratistas, control de calidad.
- Contabilidad, facturación ante Impuestos Nacionales y trámites legales.
