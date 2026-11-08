# 010 · Diseño

## Flujo

```
Materiales (003, 004): stock cruza el mínimo → outbox evento.materiales.StockBajo (ya existe)
RabbitMQ (cola n8n.stock-bajo) → n8n «Avisar stock bajo»
   → Materiales GET /materiales            (nombre y unidad del material)
   → Obras      GET /obras/{obraId}        (nombre de la obra)
   → Firebase Cloud Messaging: mensaje al tema obra-{obraId}-almacenero

Todos los días 18:00 La Paz → n8n «Recordar diario»
   → Obras GET /obras?estado=EN_EJECUCION
   → por cada obra: Obras GET /obras/{id}/diario?desde=hoy&hasta=hoy → si no hay entrada:
   → Firebase Cloud Messaging: mensaje al tema obra-{obraId}-maestro

Obras (007): el residente presenta → outbox evento.obras.PlanillaPresentada (nuevo)
RabbitMQ (cola n8n.planilla-presentada) → n8n «Avisar planilla para revisar»
   → Obras GET /planillas/{planillaId} y GET /obras/{obraId}
   → Keycloak GET /admin/realms/supervision/users/{clienteId}   (nombre y correo)
   → SMTP: correo al cliente (Mailpit en desarrollo)

App de obra: suscribe el celular a los temas de sus obras (obra-{id}-maestro u obra-{id}-almacenero)
   y abre la pantalla al tocar el aviso
```

- **Todo en n8n (decisión del equipo):** n8n ya escucha eventos, tiene un token de servicio con `gerente` (lectura) y `view-users` (correo del cliente) y envía los correos de la 201. Así, Materiales no cambia, Obras solo publica un evento más y no hay servicio nuevo.
- **Temas de Firebase en lugar de guardar dispositivos (decisión del equipo):** el celular se suscribe a un tema por obra y rol, y n8n manda el aviso al tema. Ningún servicio guarda tokens de dispositivos. Consecuencia aceptada: la suscripción la hace la app (el servidor no la verifica); una app modificada podría suscribirse a temas de otra obra y recibir avisos de stock o de diario, que no tienen datos sensibles.
- **Mensajes con notificación y datos:** `notification { title, body }` para que Android la muestre con la app cerrada, y `data { tipo, obraId }` para abrir la pantalla al tocarla.

## Eventos

| Clave | Publica | Escuchan | `datos` |
|---|---|---|---|
| `evento.materiales.StockBajo` (sin cambios) | Materiales | **n8n** | `obraId, materialId, cantidad, minimo` |
| `evento.obras.PlanillaPresentada` (nuevo) | Obras | n8n | `planillaId, obraId, numero, periodo ("2026-10"), neto, reenvio (true si venía de OBSERVADA), presentadaEn` |

- Sobre común, outbox e inbox de las convenciones (`version: 1`).

## Obras (`services/obras`)

- `POST /planillas/{id}/presentar` (007): en la misma transacción que el cambio a `PRESENTADA`, outbox `evento.obras.PlanillaPresentada` con los `datos` de arriba (`reenvio` según el estado anterior). Es lo único que cambia en Obras.

## Materiales

Sin cambios: el evento `StockBajo` ya se publica al cruzar el mínimo (003 y 004).

## App de obra (`mobile/app-obra`)

### Paquetes y configuración

- `@react-native-firebase/app` y `@react-native-firebase/messaging` (con sus *config plugins* en `app.json`; instalar con `npx expo install`), que permiten suscribirse a temas (`subscribeToTopic` / `unsubscribeFromTopic`). Versiones y compatibilidad con Expo SDK 58 se verifican en la primera tarea; si no fueran compatibles, la alternativa es `expo-notifications` con el token del dispositivo guardado en Obras (volver a especificar antes de seguir).
- `google-services.json` (de Firebase) **fuera del repo** (`.gitignore`); `app.config` lo toma de la variable `GOOGLE_SERVICES_JSON` (ruta). Sin el archivo, la app compila sin avisos.
- Permiso `POST_NOTIFICATIONS` (Android 13+), pedido al entrar con señal la primera vez.

### Archivos

- `src/avisos/temas.ts` (funciones puras, con pruebas): `temasDe(obrasAsignadas, rol)` → `obra-{obraId}-maestro` u `obra-{obraId}-almacenero`; `cambiosDeTemas(actuales, nuevos)` → a suscribir y a quitar.
- `src/avisos/push.ts`: pide permiso; al cargar el paquete de datos (101) aplica `cambiosDeTemas` y guarda los temas suscritos en `expo-secure-store`; al cerrar sesión se desuscribe de todos.
- `src/avisos/rutaDeAviso.ts` (pura, con pruebas): `data { tipo, obraId }` → `obras/{id}/stock` (`STOCK_BAJO`) u `obras/{id}/diario` (`DIARIO`).
- Al tocar una notificación (app cerrada o en segundo plano) navega a esa ruta; con la app abierta muestra un `Snackbar` con el texto y «Ver».

## n8n y Firebase (infra)

### Colas (definiciones de RabbitMQ)

`n8n.stock-bajo` (clave `evento.materiales.StockBajo`) y `n8n.planilla-presentada` (clave `evento.obras.PlanillaPresentada`), durables, con el usuario `n8n` de solo lectura (201) ampliado a estas dos colas.

### Credencial de Firebase

- Cuenta de servicio de Firebase (JSON) en `.env` de infra (`FIREBASE_PROYECTO_ID` y la cuenta de servicio por `CREDENTIALS_OVERWRITE_DATA`, como las de la 201); nunca en el repo.
- Envío con **HTTP Request** a la API v1 de FCM: `POST https://fcm.googleapis.com/v1/projects/{FIREBASE_PROYECTO_ID}/messages:send` con `{ "message": { "topic", "notification": { "title", "body" }, "data": { "tipo", "obraId" }, "android": { "priority": "high" } } }`, autenticado con la credencial de cuenta de servicio de Google de n8n (alcance `https://www.googleapis.com/auth/firebase.messaging`). El nombre exacto de la credencial en n8n 2.43.7 se verifica al implementar.
- Sin `FIREBASE_PROYECTO_ID`, `n8n/iniciar.sh` importa los flujos de *push* pero no los publica (criterio 15).

### Flujo «Avisar stock bajo»

1. **RabbitMQ Trigger** (`n8n.stock-bajo`), confirmación al terminar y de a uno (como en la 201).
2. **Repetidos:** el `id` del sobre se guarda en los datos estáticos del flujo (los últimos 500); si ya está → fin (criterio 2).
3. `GET {MATERIALES_URL}/materiales` (nombre y `unidadPlural` del `materialId`) y `GET {OBRAS_URL}/obras/{obraId}` (nombre).
4. FCM al tema `obra-{obraId}-almacenero`: título «Stock bajo: {material}», cuerpo «{obra}: quedan {cantidad} {unidadPlural} (mínimo {minimo})», `data { tipo: "STOCK_BAJO", obraId }`.

### Flujo «Recordar diario»

1. **Schedule Trigger** todos los días a las 18:00 (`America/La_Paz`), más un nodo «Ejecutar ahora» para la demostración.
2. `GET {OBRAS_URL}/obras?estado=EN_EJECUCION`; por cada obra, `GET {OBRAS_URL}/obras/{id}/diario?desde={hoy}&hasta={hoy}`.
3. Sin entradas → FCM al tema `obra-{id}-maestro`: título «Diario pendiente: {obra}», cuerpo «Todavía no registraste el diario de hoy. Si ya lo registraste sin señal, se enviará al volver la señal.», `data { tipo: "DIARIO", obraId }`. Un fallo en una obra no detiene a las demás.

### Flujo «Avisar planilla para revisar»

1. **RabbitMQ Trigger** (`n8n.planilla-presentada`); repetidos como en «Avisar stock bajo».
2. `GET {OBRAS_URL}/planillas/{planillaId}`; si su `estado` ya no es `PRESENTADA` (el cliente la aprobó u observó antes de que n8n leyera el aviso) → fin sin correo (decisión de la implementación). Después `GET {OBRAS_URL}/obras/{obraId}` y Keycloak (cliente). Sin correo → **Stop and Error** «El cliente no tiene correo registrado».
   Las colas de la 010 vencen sus mensajes con una política de RabbitMQ: `n8n.stock-bajo` a 1 día y `n8n.planilla-presentada` a 7 días (si n8n estuvo apagado, no llegan avisos viejos).
3. **Send Email** al cliente, desde `COBRANZA_REMITENTE` con el nombre `EMPRESA_NOMBRE` (201). Asunto: «Planilla para revisar: N.º {numero} · {obra} · {periodo}» (o «Planilla corregida para revisar: …» si `reenvio`). Cuerpo: «Estimado/a {nombre}: le presentamos la planilla N.º {numero} de {periodo} de la obra {obra}, con un neto de Bs {neto}. Puede revisarla y aprobarla u observarla en el portal: {PORTAL_URL}/planillas/{planillaId}. {EMPRESA_NOMBRE}».
4. Variable nueva `PORTAL_URL` (`http://localhost:4300` en desarrollo).

### Comunes

Reintentos y tiempos máximos como en la 201 (3 intentos cada 5 s; 10 s por llamada). Flujos en JSON en `infra/n8n/flujos/` con `id` fijo, importados y publicados al iniciar.

## Configuración de Firebase (manual, Jairo)

1. Crear un proyecto en la consola de Firebase (plan gratuito *Spark*: el envío por FCM no tiene costo).
2. Agregar una app Android con el paquete `com.supervision.appobra` (301) y descargar `google-services.json` → ruta en `GOOGLE_SERVICES_JSON` al compilar la *development build*.
3. Configuración del proyecto → Cuentas de servicio → generar una clave privada (JSON) → sus datos en `infra/.env` (README de infra) y el id del proyecto en `FIREBASE_PROYECTO_ID`.
4. Recompilar la *development build* (`npx expo prebuild --platform android` y `npx expo run:android`).

## Pruebas

- Obras: `PlanillaPresentada` en el outbox en la misma transacción que la presentación, con `reenvio` en `false` y en `true`; no se publica si la presentación falla.
- App: `temasDe`, `cambiosDeTemas` y `rutaDeAviso` (funciones puras); suscripción al cargar el paquete y al cerrar sesión con `messaging` simulado; permiso negado; aviso con la app abierta.
- infra: colas y enlaces en `pruebas/humo.mjs`; en `pruebas/avisos.mjs` (con n8n y Mailpit): presentar una planilla → correo al cliente en Mailpit, una sola vez aunque se repita el evento; para el *push*, con Firebase configurado, comprobar en el panel de n8n que la ejecución de «Avisar stock bajo» y «Recordar diario» termina bien (FCM responde con el nombre del mensaje).
- Manual (Jairo, en un celular Android con la *development build*): registrar una salida que deja un material bajo el mínimo → llega el aviso y abre el stock; ejecutar «Recordar diario» desde n8n sin diario de hoy → llega el aviso y abre el diario; cerrar sesión → ya no llegan.

## Cambios a contratos y datos

### `docs/contratos/eventos.md`

- `StockBajo`: «Escuchan: n8n (010)».
- Fila nueva `evento.obras.PlanillaPresentada` (Obras → n8n).

### `docs/contratos/rest.md`

Sin endpoints nuevos. En Obras (`GET /obras`, `GET /obras/{id}`, `GET /obras/{obraId}/diario`, `GET /planillas/{id}`) y Materiales (`GET /materiales`), n8n figura entre los que llaman (con su rol `gerente`).

### `services/obras/docs/contratos.md`

Publica `PlanillaPresentada`.

### `mobile/app-obra/docs/app.md` y `contratos.md`

Avisos *push* (stock bajo y diario) y la suscripción a temas de Firebase; el aviso abre stock o diario.

### `docs/convenciones.md`, `docs/arquitectura.md`, `docs/entorno-local.md`, `docs/stack.md`, `docs/mensajes.md`, `docs/permisos.md`

- Colas `n8n.stock-bajo` y `n8n.planilla-presentada`; conexión n8n → Firebase Cloud Messaging (HTTPS); variables `FIREBASE_PROYECTO_ID`, `PORTAL_URL` y la cuenta de servicio de Firebase; `@react-native-firebase/app` y `messaging` en la app; textos de los avisos y del correo.
- Quitar todo lo de la versión anterior: `services/notificaciones`, `notificaciones_db`, la cola `notificaciones`, la bandeja, el *push* web, los eventos `CobroVencido` y las ampliaciones de `PlanillaAprobada`, `PlanillaObservada` y `StockBajo`, y sus permisos y textos.

### Repos con tareas de la versión anterior

Borrar `docs/specs/010-notificaciones/` en `services/finanzas`, `services/materiales`, `gateway`, `frontend/erp-shell`, `frontend/mf-materiales` y `frontend/portal`, y reemplazarla en `services/obras`, `mobile/app-obra` e `infra` por las tareas nuevas.

### `docs/plan.md` y `CLAUDE.md`

Fila 010 con los proyectos obras, app-obra e infra; en el mapa del `CLAUDE.md`, quitar la fila de `services/notificaciones` (no se crea).
