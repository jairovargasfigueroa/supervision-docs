# 602 · Despliegue en tres nubes

**Estado:** borrador para aprobar (reescrito el 08/11/2026 a partir de la 601) · **Capa:** 6 (requisito del ingeniero) · **Proyectos:** infra y app-obra (la configuración de producción de los demás ya está hecha en la 601)

## Historia

Como **equipo** queremos la plataforma funcionando en internet, repartida entre AWS, Google Cloud y Azure, con HTTPS, secretos protegidos y costo bajo. Así demostramos que cada pieza se despliega por separado y que las piezas se comunican de forma segura entre nubes. Las máquinas se encienden solo para probar y para la presentación.

## Reparto

Es el de la 601 y `docs/arquitectura.md`, sin cambios:

| Nube | Qué aloja |
|---|---|
| Azure | Gateway, Obras, Finanzas, Keycloak, RabbitMQ, n8n, Mailpit, apps web (shell, microfrontends y portal) y PostgreSQL de Obras, Finanzas y Keycloak |
| Google Cloud | Materiales, IA (`ia-api` e `ia-worker`), MongoDB y PostgreSQL de reportes |
| AWS | Sincronización, DynamoDB (tablas de la 101) y S3 (fotos) |

## Decisiones de Jairo (08/11/2026)

1. **Una máquina virtual por nube con Docker Compose**, con los mismos *compose* que el ensayo local de la 601. Las máquinas están **apagadas** salvo para probar y para la presentación, y se encienden y apagan con un comando.
2. **Primero Azure y AWS; Google cuando esté su cuenta.** Hasta entonces, en la nube no funcionan Materiales ni IA, y la aprobación de planilla espera el paso de Materiales. La prueba completa y los datos de demostración se hacen con las tres nubes.
3. **Modelo de lenguaje:** se decide al desplegar Google. Lo normal es la API de Anthropic con límite de gasto (la máquina de Google queda chica). La otra opción es Ollama, que necesita una máquina de 16 GB.
4. **Correo real con un Gmail de la plataforma:** una cuenta creada solo para esto, con una contraseña de aplicación. Mailpit queda instalado como respaldo y se cambia de uno a otro con variables.
5. **Avisos *push* con Firebase** (plan gratuito Spark; no depende de la cuenta de Google Cloud), cuando Jairo cree el proyecto (010).
6. **Usuarios de prueba con contraseña nueva:** `Prueba123!` está en el repositorio público y no se usa en la nube.
7. **Dominio:** `supervision.workflow-tramites.site` (Namecheap). Los registros `api` y `sga-api` de ese dominio son de otro proyecto y no se tocan.
8. **Región São Paulo en las tres nubes:** Azure `brazilsouth`, AWS `sa-east-1` y Google `southamerica-east1`. Responde más rápido desde Bolivia y las tres nubes quedan cerca entre sí. Cuesta ~60 % más por hora que el este de EE. UU. Con las máquinas encendidas solo para probar, la diferencia es de pocos dólares y la cubren los créditos.
9. **Release `v1.0.0`** antes de desplegar: las máquinas descargan las imágenes que GitHub Actions publica al fusionar en `main`.

## Criterios de aceptación

### Acceso y seguridad

1. Toda dirección pública usa **HTTPS** con certificado válido (Let's Encrypt). RabbitMQ entre nubes usa **AMQPS** (TLS, puerto 5671).
2. Toda llamada entre servicios lleva un token de Keycloak válido: el del usuario reenviado o el de un cliente de servicio. Los servicios validan el emisor público de Keycloak.
3. Ningún secreto queda en el código, en las imágenes ni en los registros. Los secretos están solo en el `.env` de la nube en la PC de Jairo (no se sube) y en el `.env` de cada máquina, con permisos `600`. Cada máquina recibe solo los secretos de su grupo.
4. Desde internet solo se abren 80 y 443 en las tres máquinas, más 5671 en la de Azure. El 22 (SSH) se abre solo para la IP actual de Jairo y con clave, no con contraseña. Las bases de datos, RabbitMQ 5672, n8n, Mailpit SMTP y Ollama no tienen puerto público.
5. El panel de RabbitMQ, n8n, la interfaz de Mailpit y la consola de Keycloak se abren por HTTPS y con usuario y contraseña propios, generados al azar.
6. Los usuarios de prueba entran con una contraseña nueva, distinta de `Prueba123!`.

### Funcionamiento (con las tres nubes)

7. Desde un navegador en internet se puede iniciar sesión en el ERP, ver la lista de obras, registrar una obra con insumos, ver el tablero y, en el portal con un cliente, aprobar una planilla. La saga cruza Azure y Google.
8. Desde la app (APK instalable que apunta a la nube) se puede iniciar sesión y, también sin señal, registrar una salida de material y una foto. Al volver la señal llegan una sola vez por Sincronización (101, 102) y la foto queda en S3.
9. La cobranza automática funciona en la nube (201): al aprobar la planilla se emite el cobro y la nota de cobro **llega por correo real** al cliente de demostración.
10. Con Firebase configurado, el almacenero recibe el aviso de stock bajo en el celular (010).
11. Los agentes y los reportes por voz funcionan en la nube (capa 5) con el proveedor de modelo elegido. `ia-worker` procesa los eventos de forma permanente.
12. La prueba de humo de la 601 (`humo-despliegue.mjs`) pasa contra la nube: completa con las tres nubes y sin las comprobaciones de Google mientras Google no esté.

### Operación y costo

13. Cada nube se crea, se despliega, se enciende, se apaga y se revisa con un comando desde la PC de Jairo. Lo creado queda como *scripts* versionados en `infra/nube/`, que se pueden volver a ejecutar.
14. Al encender, todo vuelve solo y la plataforma está lista en menos de 10 minutos. Con las máquinas apagadas no se pierden eventos: las colas son durables.
15. Se puede volver a la versión anterior desplegando la etiqueta de imagen anterior.
16. Hay una alerta de presupuesto en Azure y en AWS (y en Google al crearla). Con las máquinas apagadas solo se pagan los discos y las IP fijas.
17. Los registros de cada servicio se pueden consultar con un comando (`docker compose logs` en su máquina).

## Fuera del alcance

Servicios administrados (Container Apps, Cloud Run, Lambda, bases administradas y Static Web Apps; los usaba el borrador anterior), despliegue automático desde GitHub Actions (se despliega con los *scripts*), alta disponibilidad, copias de seguridad automáticas, CDN, entorno de *staging*, Terraform y gestores de secretos de cada nube (Key Vault, Secret Manager).
