# 001 · Diseño

## Keycloak (infra)

- Realm `supervision` del archivo de importación de la fase 1. Se agrega:
  - Usuarios de prueba (contraseña `Prueba123!`, solo desarrollo): `admin1` (admin), `residente1`, `residente2` (residente), `gerente1` (gerente), `maestro1` (maestro), `almacenero1` (almacenero), `cliente1`, `cliente2` (cliente) y `demo1` (residente y cliente, para demostrar el paso entre el ERP y el portal sin volver a escribir la contraseña; sus obras las asigna la 011). Nombre y apellido completos para mostrarlos.
  - Clientes: `erp` (redirect `http://localhost:4200/*`), `portal` (redirect `http://localhost:4300/*`), `app-obra` (redirect `exp://*` y el esquema `appobra://*`). Los tres públicos, *Standard flow* con PKCE `S256`, sin *direct access grants*.
  - Duración del token de acceso: 5 minutos; sesión SSO: 10 horas.

## ERP (erp-shell)

- keycloak-angular inicializa con `onLoad: 'login-required'`, `pkceMethod: 'S256'` y renovación automática del token.
- Al iniciar, lee los roles del token. Si no tiene `admin`, `residente` ni `gerente`, muestra el componente `SinAcceso`.
- Publica `window.plataforma.sesion` (convenciones) y emite `plataforma:sesion` al renovar el token o cerrar sesión.
- Barra superior: nombre (`name` del token), rol principal y botón «Cerrar sesión» (`keycloak.logout({ redirectUri: origin })`).
- Menú lateral: Obras, Materiales, Supervisión y «Aplicaciones», que lista solo las aplicaciones web para las que el usuario tiene rol: «Portal del cliente» (`http://localhost:4300`, configurable en `environment`) si tiene `cliente`. Si no hay ninguna, la opción no aparece.
- Interceptor HTTP: agrega `Authorization: Bearer` a las llamadas al gateway.

## Microfrontends

- mf-obras (Angular): un servicio `SesionService` que lee `window.plataforma.sesion` y un interceptor que agrega el token a las llamadas GraphQL.
- mf-materiales y mf-supervision (React): un módulo `sesion.ts` con `obtenerToken()` que delega en `window.plataforma.sesion`, usado por el `link` de Apollo Client.
- Si `window.plataforma` no existe (microfrontend abierto solo para desarrollar), muestran «Abre esta pantalla desde el ERP».

## Portal

- `react-oidc-context` con `authority = http://localhost:8080/realms/supervision`, `client_id = portal`, `automaticSilentRenew: true`.
- Ruta protegida: sin sesión → `signinRedirect()`. Sin rol `cliente` → pantalla `SinAcceso`.
- Barra superior con nombre y «Cerrar sesión» (`signoutRedirect()`).

## App

- `expo-auth-session` con descubrimiento del realm, cliente `app-obra`, PKCE, `scheme: 'appobra'` en `app.json`.
- El token y el refresh token se guardan con `expo-secure-store`.
- Navegación con Expo Router: grupo `(auth)` para el inicio de sesión y grupo `(app)` con pestañas según el rol (criterio 5).
- Sin rol `maestro` ni `almacenero` → pantalla «No tienes acceso».
- Cerrar sesión borra los tokens guardados y llama al `end_session_endpoint`.

## Servicios y gateway

- Ya validan el token desde la fase 1 (1.6 y 1.7). Esta funcionalidad agrega la **autorización por rol** en cada endpoint según la tabla de roles de cada funcionalidad, con una utilidad común por servicio:
  - Obras: `@PreAuthorize("hasAnyRole('admin','residente')")` con un convertidor que lee `realm_access.roles`.
  - Materiales y gateway: un *guard* `RolesGuard` con el decorador `@Roles(...)`.
  - Finanzas: un *middleware* `rol:admin,gerente`.

## Pruebas

- Servicios: pruebas que llaman un endpoint protegido sin token (401), con token de otro rol (403) y con token correcto (200). Los tokens de prueba se firman con una clave de prueba y la validación usa esa clave en el perfil de pruebas.
- Frontends: prueba unitaria del cálculo del menú por rol (incluida «Aplicaciones»: con `cliente` muestra el portal; sin ese rol no aparece) y de la pantalla `SinAcceso`.
- Manual (lo hace el equipo): iniciar sesión en el ERP con `demo1`, pulsar «Aplicaciones → Portal del cliente» y comprobar que entra al portal sin volver a escribir la contraseña (SSO); con `residente1`, comprobar que «Aplicaciones» no aparece; cerrar sesión en una aplicación y comprobar que la otra vuelve a pedir el inicio de sesión.
