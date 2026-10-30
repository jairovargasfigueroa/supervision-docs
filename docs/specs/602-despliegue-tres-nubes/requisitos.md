# 602 · Despliegue en tres nubes

> **Ajuste pendiente por la evaluación de la capa 1 (30/10/2026):** la 102 se simplificó. La app sube la foto completa y directo a S3 con la URL firmada de Obras (pedida a Sincronización), y ya no existen la subida por partes (`/subidas`), la tabla `subida_archivo`, el prefijo `temporal/subidas/`, el acceso de Sincronización a S3 ni la foto de la nota de remisión (`notas-remision/`, variables `MATERIALES_S3_*`). Al evaluar esta capa, quitar esas menciones de este documento.

**Estado:** borrador para aprobar · **Capa:** 6 (requisito del ingeniero) · **Proyectos:** infra (y la configuración de producción de todos los proyectos, hecha en 601)

## Historia

Como **equipo** queremos la plataforma funcionando en internet repartida entre AWS, Google Cloud y Azure, con HTTPS, secretos protegidos y costo bajo, para demostrar que cada pieza se despliega por separado y que las piezas se comunican de forma segura entre nubes.

## Reparto

| Nube | Qué aloja |
|---|---|
| AWS | Sincronización, DynamoDB (tablas de la 101 y la 102), S3 (fotos, versiones para el cliente, notas de remisión y partes temporales) |
| Google Cloud | IA (`ia-api` e `ia-worker`) + Ollama (máquina virtual con memoria), Materiales, MongoDB, PostgreSQL de reportes |
| Azure | Gateway, Obras, Finanzas, Keycloak, RabbitMQ, n8n, Mailpit, apps web (shell, microfrontends, portal), PostgreSQL de Obras y Finanzas |

## Criterios de aceptación

### Acceso y seguridad

1. Toda URL pública usa **HTTPS** con certificado válido; RabbitMQ entre nubes usa **AMQPS** (TLS, puerto 5671).
2. Toda llamada entre servicios lleva un token de Keycloak válido (el del usuario reenviado o el de un cliente de servicio); los servicios validan el emisor público de Keycloak.
3. Ningún secreto queda en el código, en las imágenes ni en los registros: se guardan en el gestor de secretos de cada nube o en GitHub Secrets.
4. Ollama y la PostgreSQL de reportes no son accesibles desde internet (solo desde la VM de IA).
5. El panel de RabbitMQ, n8n, la interfaz de Mailpit y la consola de administración de Keycloak solo se abren por HTTPS y con usuario y contraseña propios (no los de prueba).
6. Las bases de datos administradas exigen TLS y contraseñas distintas por servicio.

### Funcionamiento

7. Desde un navegador en internet se puede: iniciar sesión en el ERP, ver la lista de obras, registrar una obra, ver el tablero, abrir el portal con un cliente y aprobar una planilla (la saga cruza Azure y Google).
8. Desde la app (versión instalable) se puede iniciar sesión y, también sin señal, registrar una salida de material y una foto; al volver la señal llegan una sola vez por Sincronización (101, 102) y la foto queda en S3.
9. La compra automática funciona en la nube (201): un stock bajo crea la orden, el correo al proveedor queda visible en Mailpit y, al registrar el ingreso con la orden, se crea la cuenta por pagar.
10. Los agentes y los reportes por voz funcionan en la nube (IA en Google llama a los servidores MCP en Azure y Google); `ia-worker` procesa los eventos de la base de reportes de forma permanente.
11. Un *script* de prueba de humo comprueba `GET /salud` de cada servicio, `{ salud }` del gateway, la emisión de tokens de servicio, que `/mcp` rechaza llamadas sin token y que Sincronización recibe una parte binaria de una subida.

### Operación y costo

12. Cada pieza se despliega por separado con su workflow (601) y se puede volver a la versión anterior desplegando la etiqueta anterior.
13. Se usan niveles gratuitos o de bajo costo y créditos de estudiante; cada nube tiene una alerta de presupuesto.
14. Hay *scripts* para apagar y encender las máquinas virtuales y bajar a cero las réplicas fuera de las demostraciones.
15. Los registros de cada servicio se pueden consultar en la consola de su nube.

## Fuera del alcance

Envío de correos reales a proveedores (en producción se capturan en Mailpit; decisión del equipo), alta disponibilidad (varias zonas o réplicas), dominio propio obligatorio, CDN, copias de seguridad automáticas más allá de las que da cada servicio administrado, entorno de *staging*.
