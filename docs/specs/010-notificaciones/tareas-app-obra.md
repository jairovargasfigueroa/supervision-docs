# 010 · Avisos al celular y al cliente · tareas de `mobile/app-obra`

Requisitos y diseño: `docs/specs/010-notificaciones/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `mobile/app-obra/docs/specs/010-notificaciones/tareas.md` (eran de la versión anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Verificar `@react-native-firebase/app` y `messaging` con Expo SDK 58 (versiones, *config plugins*, temas); si no son compatibles, detenerse y proponer la alternativa del diseño
- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/app.md`, `docs/contratos.md`); `google-services.json` fuera del repo y tomado de `GOOGLE_SERVICES_JSON`
- [ ] `src/avisos/temas.ts` y `rutaDeAviso.ts` (funciones puras) con sus pruebas
- [ ] `src/avisos/push.ts`: permiso, suscripción a los temas al cargar el paquete de datos, desuscripción al cerrar sesión; pruebas con `messaging` simulado
- [ ] Abrir la pantalla al tocar el aviso y `Snackbar` con la app abierta; pruebas
- [ ] Prueba manual en un Android con la *development build* (Jairo)
