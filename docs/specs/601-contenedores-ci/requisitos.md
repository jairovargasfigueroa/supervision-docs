# 601 · Preparar el despliegue: imágenes, configuración, CI y ensayo local

**Estado:** aprobado (03/11/2026) · **Capa:** 6 (requisito del ingeniero: despliegue en 3 nubes; punto 20, nivel de despliegue) · **Proyectos:** services/obras, services/materiales, services/finanzas, services/ia, services/sincronizacion, gateway, frontend/erp-shell, frontend/mf-obras, frontend/mf-materiales, frontend/mf-supervision, frontend/portal, mobile/app-obra, infra

**Decisiones de Jairo (03/11/2026):** el despliegue va en tres etapas: **empaquetar** y **ensayar** en local (esta spec, sin nube ni créditos) y **subir** (602, se reescribe al momento de desplegar, con las cuentas disponibles). Esta spec no depende de en qué nube va cada pieza: la misma imagen sirve en cualquiera y el reparto vive en la configuración (los *compose* y las variables). Reemplaza al borrador anterior, que mezclaba el empaquetado con el despliegue en cada nube. Ajustes de Jairo al aprobarla: los frontends **no llevan imagen** (son archivos estáticos, como en Amplify) y el APK lo genera Jairo cuando lo necesite, fuera de esta spec.

## Historia

Como **equipo** queremos que cada proyecto se empaquete en su propia imagen, que se configure solo con variables, que GitHub lo pruebe y lo publique, y ensayar en la laptop la plataforma tal como quedará en las nubes, para que subirla después sea rápido y sin sorpresas.

## Criterios de aceptación

### Imágenes (empaquetar)

1. Cada servicio tiene en su raíz un `Dockerfile` y un `.dockerignore`: Obras, Materiales, Finanzas, IA, Sincronización y el gateway (6 imágenes). El servicio de IA tiene una sola imagen con sus procesos (`ia-api`, `ia-worker` e `ia-carga-inicial`). Los frontends (shell, 3 microfrontends y portal) no llevan imagen: se compilan a archivos estáticos que sirve un *hosting* de estáticos (en la nube) o Caddy (en el ensayo local). La app no lleva imagen.
2. Las imágenes se construyen en etapas: las herramientas de compilación no quedan en la imagen final.
3. El proceso corre con un usuario sin privilegios (no `root`).
4. La imagen no contiene `.env`, claves ni contraseñas ni direcciones de otros servicios: todo entra por variables de entorno al arrancar.
5. Cada servicio responde `GET /salud` dentro del contenedor; la imagen trae su `HEALTHCHECK`.
6. Los servicios aplican sus migraciones al iniciar (Obras, Finanzas e IA) y escriben sus registros en la salida estándar.

### Configuración de producción

7. Ningún proyecto tiene una dirección fija de otro servicio, de Keycloak o de RabbitMQ: todo sale de variables, con el valor de desarrollo en su `.env.example`. Los nombres de las variables son los de la tabla del diseño.
8. Cada servicio tiene un modo producción por variable (perfil `prod` en Spring, `APP_ENV=production` en Laravel, `NODE_ENV=production` en Node, sin recarga en FastAPI): sin trazas de error para el usuario, CORS solo con los orígenes configurados, conexiones a bases y a RabbitMQ con TLS cuando se configura.
9. Los frontends se compilan **una vez** y leen su configuración (direcciones de Keycloak, gateway, portal, Obras y de los microfrontends) de un archivo `configuracion.json` que se escribe **al publicar** los archivos, a partir de variables. Así la misma compilación sirve en la laptop y en cualquier nube.
10. Keycloak se puede importar para producción con variables: direcciones de regreso y orígenes permitidos de cada aplicación, secretos de los clientes y contraseña de los usuarios de prueba (en producción, distinta de `Prueba123!`, que está en el repositorio público).

### Datos de demostración

11. La semilla (011) se puede cargar en un entorno de producción solo con un permiso explícito (`SEMILLA_DEMO=si`): carga los datos de prueba sin duplicar, igual que en desarrollo, pero **nunca vacía** (en producción no hay `recargar`).

### CI en GitHub

12. Cada repositorio tiene un workflow `ci.yml`: en cada *pull request* hacia `develop` o `main` corre las pruebas, el lint, los tipos y la compilación, y en los servicios construye la imagen sin publicarla. Si algo falla, el PR queda en rojo.
13. Al hacer *push* a `main` (un *release*), el workflow de cada servicio publica su imagen en GitHub Container Registry con las etiquetas `sha-<7 caracteres>` y `main`, y el de cada frontend guarda la carpeta compilada como artefacto del workflow. El despliegue en cada nube no es parte de esta spec (602).
14. Los workflows no usan secretos de la aplicación: solo el `GITHUB_TOKEN` para publicar.
15. La app tiene su workflow de pruebas (tipos y pruebas), sin imagen.

### Ensayo local («producción local»)

16. Con un comando (`infra`) se levanta la plataforma con las **imágenes de producción** y los **frontends compilados** (servidos por Caddy), separada en tres grupos que hacen de las tres nubes (`azure`, `google` y `aws`, según el reparto planeado en la 602): cada grupo tiene su propia red y los grupos se hablan solo por direcciones públicas con **HTTPS** (Caddy con una autoridad certificadora local) y RabbitMQ con **TLS**.
17. Las bases corren como en la nube, en su grupo: PostgreSQL (Obras, Finanzas y Keycloak), MongoDB en *replica set*, PostgreSQL de reportes, DynamoDB Local y un S3 compatible (MinIO) para las fotos.
18. Con los datos de demostración cargados, desde el navegador se puede: iniciar sesión en el ERP y en el portal, registrar una obra, ver el tablero, presentar y aprobar una planilla (la saga cruza dos grupos), recibir los correos de la cobranza en Mailpit y usar los reportes y los agentes (con el modelo de lenguaje configurado).
19. Mover un servicio de un grupo a otro solo cambia los archivos de *compose* y las variables, nunca una imagen.

### Prueba de humo

20. Un script recibe las direcciones del entorno (las de la «producción local» o, después, las de la nube) y comprueba: `GET /salud` de cada servicio, que Keycloak emite tokens de usuario y de cliente de servicio, una consulta del gateway, que `/mcp` rechaza llamadas sin token, que RabbitMQ tiene sus colas, que n8n y Mailpit responden, y (con `--completa`) una aprobación de planilla de punta a punta. Termina con un resumen y un código de salida distinto de 0 si algo falla.

### App

21. La app lee las direcciones de Keycloak y de Sincronización de variables al compilar (por defecto, las de desarrollo), para que el APK que genere Jairo más adelante pueda apuntar a la nube sin tocar código.

## Fuera del alcance

Crear recursos en las nubes, el despliegue automático en cada nube, los secretos en los gestores de cada nube, los dominios reales y la elección del modelo de lenguaje en la nube (todo eso es la 602); generar y distribuir el APK de la app (lo hace Jairo); Kubernetes; varios entornos en la nube (*staging*); escaneo de vulnerabilidades obligatorio; publicación en tiendas de aplicaciones.
