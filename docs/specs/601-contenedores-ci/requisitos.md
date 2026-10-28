# 601 · Contenedores e integración y despliegue continuos

**Estado:** borrador para aprobar · **Capa:** 6 (requisito del ingeniero: despliegue en 3 nubes; punto 20, nivel de despliegue) · **Proyectos:** todos (services/obras, services/materiales, services/finanzas, services/ia, services/sincronizacion, gateway, frontend/erp-shell, frontend/mf-obras, frontend/mf-materiales, frontend/mf-supervision, frontend/portal, mobile/app-obra, infra)

## Historia

Como **equipo** queremos que cada proyecto se empaquete en su propia imagen de contenedor y que GitHub Actions lo pruebe, construya, publique y despliegue solo, para que cada repositorio se entregue por separado y sin pasos manuales.

## Criterios de aceptación

### Imagen de cada proyecto

1. Cada proyecto desplegable tiene en su raíz un `Dockerfile` y un `.dockerignore`. La app móvil no tiene imagen (se distribuye como aplicación). El servicio de IA tiene una sola imagen con dos procesos, `ia-api` e `ia-worker` (401).
2. Las imágenes se construyen en etapas (*multi-stage*): las herramientas de compilación no quedan en la imagen final.
3. El proceso corre con un usuario sin privilegios (no `root`).
4. La imagen no contiene `.env`, `.env.properties`, claves ni contraseñas; toda la configuración entra por variables de entorno.
5. El puerto sale de una variable de entorno con el valor por defecto de `convenciones.md`. Las variables usan los nombres que ya definen las specs y cada proyecto (tabla del diseño).
6. Los servicios responden `GET /salud` dentro del contenedor (la imagen sirve para las sondas de salud de cada nube).
7. Los frontends web producen archivos estáticos; su `Dockerfile` los sirve con un servidor web sin privilegios (para Docker Compose y como alternativa), aunque en la nube se publiquen como sitio estático (602).

### Workflow de cada repositorio

8. Cada repositorio tiene `.github/workflows/ci-cd.yml`.
9. CUANDO se abre o actualiza un *pull request* hacia `main`, ENTONCES el workflow corre las pruebas, el lint y la compilación (y construye la imagen sin publicarla). Si algo falla, el PR queda en rojo.
10. CUANDO se hace *push* a `main` (o se lanza a mano), ENTONCES el workflow: (1) prueba, (2) construye la imagen, (3) la publica en el registro que corresponde con la etiqueta del commit (`sha-<7 caracteres>`) y `main`, y (4) despliega esa etiqueta en su nube.
11. El despliegue usa siempre la etiqueta del commit (inmutable); volver atrás es desplegar la etiqueta anterior.
12. Los workflows se autentican en las nubes con **OIDC de GitHub** (credenciales federadas, sin claves de larga duración guardadas) y en GitHub Container Registry con el `GITHUB_TOKEN`.
13. Los secretos de despliegue viven en **GitHub Secrets** del entorno `produccion`; ningún secreto aparece en el código ni en los registros del workflow.
14. La app móvil tiene su workflow de pruebas (tipos, pruebas y `expo-doctor`) y uno manual para generar la versión instalable.

## Fuera del alcance

Varios entornos (solo hay `produccion`, además del desarrollo local), Kubernetes, escaneo de vulnerabilidades obligatorio, publicación en tiendas de aplicaciones.
