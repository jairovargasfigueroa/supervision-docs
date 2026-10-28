# 104 · Diseño

## Idea general

- El **service worker** del shell guarda los archivos del ERP (shell y microfrontends ya visitados) para que cargue sin conexión.
- Los **datos** no los guarda el service worker: el ERP usa GraphQL por `POST` y el service worker de Angular solo guarda respuestas `GET`. Cada microfrontend guarda la última respuesta de sus consultas en IndexedDB mediante un almacén que publica el shell en `window.plataforma.almacen`.
- Todos los microfrontends corren en el origen del shell (`localhost:4200`), así que comparten la misma base IndexedDB.
- El shell también publica el estado de la conexión (`window.plataforma.conexion`) para que todos decidan igual cuándo están sin conexión.

## erp-shell

### PWA

- `ng add @angular/pwa`: agrega `@angular/service-worker`, `manifest.webmanifest` (nombre «Supervisión de obras», nombre corto «Supervisión», `display: standalone`), íconos y `ngsw-config.json`; registra el service worker con `provideServiceWorker('ngsw-worker.js', { enabled: !isDevMode(), registrationStrategy: 'registerWhenStable:30000' })`.
- `ngsw-config.json`:
  - `assetGroups.app` (`installMode: prefetch`): `index.html`, `*.js`, `*.css`, `manifest.webmanifest`, `favicon.ico`.
  - `assetGroups.assets` (`installMode: lazy`, `updateMode: prefetch`): `/assets/**`, íconos.
  - `assetGroups.remotos` (`installMode: lazy`, `updateMode: prefetch`): en `resources.urls`, los orígenes de los remotos (`http://localhost:4201/**`, `http://localhost:4202/**`, `http://localhost:4203/**` en desarrollo; se ajustan en la capa 6). Así quedan guardados los `remoteEntry.json` y módulos que ya se cargaron.
  - `dataGroups.manifiesto-federacion`: `/federation.manifest.json` con `strategy: freshness`, `timeout: 3s`, `maxAge: 30d`.
  - `navigationUrls` por defecto (las rutas `/obras`, `/materiales`, `/supervision` sirven `index.html`).
- Comprobar en la prueba manual que los módulos de los remotos (otro origen) se sirven sin conexión. Si un remoto no quedó guardado, el shell muestra su aviso «no disponible» como en la fase 1.
- `SwUpdate.versionUpdates`: al recibir `VERSION_READY`, aviso «Hay una versión nueva · Recargar» (`document.location.reload()`).
- El service worker solo funciona con la versión compilada: `npm run build` y servir `dist/erp-shell/browser` con un servidor estático en el puerto 4200 (por ejemplo `npx http-server dist/erp-shell/browser -p 4200`). `ng serve` no lo registra.

### Conexión (`ConexionService`)

- En línea si `navigator.onLine` es `true` y la última comprobación con el gateway no falló.
- Escucha los eventos `online` y `offline` de `window`.
- Cuando cree estar sin conexión (o cuando un microfrontend llama a `reportarFallo()`), consulta `{ salud }` al gateway cada 30 s con tiempo máximo de 3 s; al responder, vuelve a «en línea».
- Publica `window.plataforma.conexion = { enLinea: boolean, reportarFallo(): void }` y emite `plataforma:conexion` en `window` con `detail: { enLinea }` en cada cambio.

### Almacén local (`AlmacenService`)

- IndexedDB `plataforma-erp`, versión 1, con la librería `idb` (decisión del equipo). Almacenes:
  - `consultas`: clave `"{usuarioId}|{clave}"`, valor `{ datos, guardadoEn }`.
  - `borradores_planilla`: clave `"{usuarioId}|{planillaId}"`, valor `BorradorPlanilla`.
  - `sesion`: clave `"ultima"`, valor `{ usuario: { id, nombre, roles }, guardadaEn }`.
- Publica `window.plataforma.almacen` (el prefijo del usuario lo agrega el shell; los microfrontends no lo ven):

```ts
interface BorradorPlanilla {
  planillaId: string; obraId: string; numero: number; periodo: string;
  versionBase: number;                                  // version de la planilla sobre la que se editó
  lineas: { partidaId: string; cantidadPeriodo: number }[];
  fotoIds: string[];
  guardadoEn: string;                                   // ISO
  estadoEnvio: 'PENDIENTE' | 'CONFLICTO' | 'NO_EDITABLE' | 'RECHAZADO';
  ultimoError?: { codigo: string; mensaje: string; errores?: { campo: string; mensaje: string }[] };
}

interface AlmacenPlataforma {
  guardarConsulta(clave: string, datos: unknown): Promise<void>;
  leerConsulta<T>(clave: string): Promise<{ datos: T; guardadoEn: string } | null>;
  guardarBorradorPlanilla(borrador: BorradorPlanilla): Promise<void>;
  leerBorradorPlanilla(planillaId: string): Promise<BorradorPlanilla | null>;
  listarBorradoresPlanilla(): Promise<BorradorPlanilla[]>;
  borrarBorradorPlanilla(planillaId: string): Promise<void>;
}
```

- Límites (decisión del equipo): hasta 300 consultas por usuario; al guardar, se borran las de más de 7 días y, si se pasa del límite, las más antiguas. Los borradores no se borran solos.
- Emite `plataforma:borradores` en `window` cuando cambia la lista de borradores (para el indicador).

### Sesión sin conexión

- Después de cada inicio o renovación de sesión correcta, guarda `sesion.ultima`.
- Al arrancar: si `navigator.onLine` es `false`, o `keycloak.init` falla por error de red, y `sesion.ultima` tiene 24 h o menos → publica `window.plataforma.sesion` con ese `usuario`, `sinConexion: true`, y `obtenerToken()` que rechaza con `Error('SIN_CONEXION')`. Si no hay sesión guardada o tiene más de 24 h → pantalla «Conéctate a internet para iniciar sesión».
- Al volver la conexión en ese modo: `keycloak.init({ onLoad: 'check-sso', pkceMethod: 'S256', silentCheckSsoRedirectUri: origin + '/silent-check-sso.html' })`. Si queda autenticado → `sinConexion: false` y emite `plataforma:sesion`; si no → botón «Iniciar sesión» (`keycloak.login()`). Los borradores están en IndexedDB, no se pierden con la redirección.
- Cerrar sesión: si `listarBorradoresPlanilla()` no está vacío → confirmación «Tienes N borradores de planilla sin enviar. Si cierras sesión se borrarán de este equipo». Luego borra las consultas, los borradores y `sesion.ultima` del usuario, y sigue como en la 001. El caché del service worker no tiene datos del negocio y no se borra.

### Barra superior

- Etiqueta «Sin conexión» cuando `enLinea` es `false`.
- «Borradores sin enviar (N)» cuando hay borradores; abre el editor de esa planilla (ruta de mf-obras de la 007) o una lista si hay más de uno.

## Patrón común en los microfrontends

- Función `consultaConRespaldo(clave, ejecutar)` (en Angular, un servicio; en React, un *hook* `useConsultaConRespaldo`):
  - Si `window.plataforma.conexion.enLinea` → ejecuta la consulta con `fetchPolicy: 'network-only'`. Si responde sin `errors`, la guarda con `guardarConsulta` y la devuelve con `desdeEquipo: false`. Si hay error de red o tiempo agotado, llama a `reportarFallo()` y cae al paso siguiente.
  - Sin conexión (o tras el fallo) → `leerConsulta(clave)` y devuelve `{ datos, desdeEquipo: true, guardadoEn }`, o `null` si no hay nada guardado.
  - Las respuestas parciales (con algún campo `SERVICIO_NO_DISPONIBLE`) se muestran pero no se guardan, para no reemplazar una respuesta completa (decisión del equipo).
- `clave` = `"{nombreOperacion}:{JSON.stringify(variables)}"`.
- Componente de aviso común: «Sin conexión · datos del dd/mm/aaaa hh:mm» o «No hay datos guardados de esta pantalla».
- Los botones de escritura se deshabilitan cuando `enLinea` es `false`, con la ayuda «Requiere conexión». Escuchan `plataforma:conexion` para actualizarse.
- Si `window.plataforma.almacen` no existe (microfrontend abierto solo para desarrollar), trabajan como antes, sin guardar nada.

## mf-obras

- Usa `consultaConRespaldo` en `obras` (lista), `obra` (encabezado y partidas, y cada pestaña que se abre) y `planilla`.
- Editor de planilla (007):
  - Al abrir: carga la planilla (de la red o del equipo) y luego `leerBorradorPlanilla(id)`; si hay borrador, aplica sus cantidades y fotos y muestra «Borrador local sin enviar (guardado dd/mm hh:mm)». Si el borrador está en `CONFLICTO`, `NO_EDITABLE` o `RECHAZADO`, abre el diálogo correspondiente (criterios 14 a 16).
  - «Guardar» en línea: `guardarPlanilla` como en la 007. Si falla por red → guarda el borrador (`versionBase` = `version` mostrada, `estadoEnvio: 'PENDIENTE'`) y muestra el mensaje del criterio 10. Sin conexión → guarda el borrador directamente.
  - «Presentar» deshabilitado sin conexión o con borrador local.
  - La galería de fotos del periodo sin conexión muestra la fecha y un recuadro en lugar de la miniatura (los enlaces firmados vencen); se pueden seguir marcando o desmarcando.
- `EnvioBorradoresService` (arranca al cargar mf-obras): cuando `plataforma:conexion` pasa a `enLinea: true` con sesión activa (y cada 60 s mientras esté en línea y haya borradores `PENDIENTE`), envía cada borrador `PENDIENTE` con `guardarPlanilla(id, { version: versionBase, lineas, fotoIds })`:
  - Correcto → `borrarBorradorPlanilla` y aviso «Borrador de la planilla N.º X enviado».
  - `VERSION_DESACTUALIZADA` → `estadoEnvio: 'CONFLICTO'`. En el editor: «Aplicar mi borrador sobre la última versión» vuelve a pedir la planilla, cambia `versionBase` por la versión nueva y reenvía; «Descartar mi borrador» lo borra.
  - `PLANILLA_NO_EDITABLE` → `estadoEnvio: 'NO_EDITABLE'`; el editor muestra el estado actual y solo ofrece «Descartar mi borrador».
  - `SUPERA_CANTIDAD_CONTRATADA` o `FOTO_FUERA_DEL_PERIODO` → `estadoEnvio: 'RECHAZADO'` con `ultimoError`; el editor marca las filas con los `errores[]` y, al guardar de nuevo, el borrador vuelve a `PENDIENTE`.
  - Error de red → queda `PENDIENTE` para el siguiente intento.
- Crear planilla nueva: deshabilitado sin conexión.

## mf-materiales

- `useConsultaConRespaldo` en `materiales` (catálogo) y `stockObra` (stock por obra).
- Sin conexión: deshabilita crear y editar material, fijar mínimo y agregar material.

## mf-supervision

- `useConsultaConRespaldo` en `tablero`.

## Gateway

Sin cambios (la consulta `{ salud }` ya existe).

## Pruebas

- erp-shell: `ConexionService` (offline del navegador, comprobación con el gateway que falla y que vuelve), almacén (prefijo por usuario, límite de 300 y borrado de más de 7 días), sesión sin conexión con 23 h y con 25 h, reanudación con `check-sso`, cierre de sesión que avisa con borradores y borra los datos del usuario, indicador de borradores.
- mf-obras: `consultaConRespaldo` (guarda en línea, cae a lo guardado ante error de red, lee sin conexión, no guarda respuestas parciales), «Guardar» sin conexión, envío al reconectar con los cuatro resultados, «Presentar» deshabilitado.
- mf-materiales y mf-supervision: aviso con datos guardados y sin datos; botones deshabilitados.
- Manual (lo hace el equipo): compilar el shell, servirlo en 4200, abrir obras, una planilla, stock y tablero; en DevTools activar «Offline» y recargar; editar y guardar la planilla; desde otra ventana cambiar la misma planilla; volver a «Online» y comprobar el diálogo de conflicto; instalar el ERP como aplicación.

## Cambios a contratos y datos

Para integrar en los documentos compartidos (no se editaron en esta especificación).

### `docs/convenciones.md`

«Sesión dentro del ERP»: agregar

- `sesion.sinConexion: boolean`; en ese modo `obtenerToken()` rechaza con `Error('SIN_CONEXION')`.
- `window.plataforma.conexion`: `{ enLinea, reportarFallo() }` y el evento `plataforma:conexion` (`detail: { enLinea }`).
- `window.plataforma.almacen`: almacén local en IndexedDB (`guardarConsulta`, `leerConsulta`, `guardarBorradorPlanilla`, `leerBorradorPlanilla`, `listarBorradoresPlanilla`, `borrarBorradorPlanilla`), separado por usuario y borrado al cerrar sesión; evento `plataforma:borradores`.
- Los microfrontends no usan IndexedDB, `localStorage` ni service workers propios: usan lo que publica el shell.

### `frontend/erp-shell/docs/contratos.md`

«Expone a los microfrontends»: agregar `window.plataforma.conexion`, `window.plataforma.almacen`, `sesion.sinConexion` y los eventos `plataforma:conexion` y `plataforma:borradores`. «Consume»: gateway `{ salud }` para comprobar la conexión.

### `frontend/mf-obras/docs/contratos.md`, `frontend/mf-materiales/docs/contratos.md`, `frontend/mf-supervision/docs/contratos.md`

«Consume»: del shell, además de la sesión, `window.plataforma.conexion` y `window.plataforma.almacen`.

### `frontend/erp-shell/CLAUDE.md`

«Stack»: PWA con `@angular/pwa` (service worker de Angular) e IndexedDB con `idb`; nota de que el service worker solo se prueba con la versión compilada.

### `docs/plan.md`

Agregar la fila de la funcionalidad 104 (erp-shell, mf-obras, mf-materiales, mf-supervision).
