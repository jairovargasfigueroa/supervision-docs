# 001 · Iniciar sesión y paso entre aplicaciones

**Estado:** aprobado · **Proyectos:** infra (Keycloak), erp-shell, mf-obras, mf-materiales, mf-supervision, portal, app-obra, gateway, services/*

Requiere la fase 1 terminada (realm, shell con login, validación de tokens en servicios y gateway).

## Historias

- Como **usuario interno** (admin, residente, gerente) quiero iniciar sesión una vez en el ERP y ver solo las opciones de mi rol.
- Como **cliente** quiero entrar al portal con la cuenta que me dio la constructora.
- Como **maestro de obra o almacenero** quiero entrar a la app y ver solo las opciones de mi rol.
- Como **usuario** quiero pasar a otra aplicación de la plataforma sin volver a escribir mi contraseña.

## Criterios de aceptación

1. CUANDO un usuario sin sesión abre el ERP, el portal o la app, ENTONCES se le muestra el inicio de sesión de Keycloak (realm `supervision`).
2. CUANDO inicia sesión con un rol válido para esa aplicación, ENTONCES entra a la pantalla inicial de su rol.
3. SI el usuario no tiene un rol permitido en esa aplicación, ENTONCES ve la pantalla «No tienes acceso a esta aplicación» con su nombre y un botón «Cerrar sesión». Roles permitidos: ERP `admin`, `residente`, `gerente`; portal `cliente`; app `maestro`, `almacenero`.
4. CUANDO entra al ERP, ENTONCES el menú muestra solo lo de su rol:
   - `admin`: Obras, Materiales, Supervisión
   - `residente`: Obras, Materiales, Supervisión
   - `gerente`: Obras, Materiales, Supervisión
   (todos ven las tres áreas; lo que cambia es lo que pueden hacer dentro, ver cada funcionalidad).
5. CUANDO entra a la app, ENTONCES el menú muestra: `maestro` → Mis obras, Foto de avance; `almacenero` → Mis obras, Ingreso, Salida, Stock.
6. CUANDO un usuario con sesión iniciada en una aplicación abre otra de la plataforma en el mismo navegador, ENTONCES entra sin volver a escribir su contraseña (SSO de Keycloak).
7. CUANDO el usuario pulsa «Cerrar sesión» en cualquier aplicación web, ENTONCES se cierra la sesión de Keycloak y al abrir otra aplicación web se le vuelve a pedir el inicio de sesión.
8. CUANDO el token vence mientras el usuario trabaja, ENTONCES se renueva solo sin interrumpirlo; SI no se puede renovar, ENTONCES vuelve al inicio de sesión.
9. CUANDO cualquier servicio recibe una petición sin token o con token inválido, ENTONCES responde `401`; con token válido pero sin el rol necesario, responde `403`.
10. El menú del shell tiene la opción «Aplicaciones» con un enlace a cada aplicación web de la plataforma para la que el usuario tiene rol (hoy, el portal del cliente si tiene el rol `cliente`); se abre en otra pestaña. SI el usuario no tiene rol en ninguna otra aplicación web, ENTONCES la opción no se muestra.
11. La barra superior del ERP, el portal y la app muestran el nombre del usuario y su rol.

## Fuera del alcance

Registro de usuarios, cambio de contraseña dentro de las aplicaciones (se hace en Keycloak), recuperar contraseña.
