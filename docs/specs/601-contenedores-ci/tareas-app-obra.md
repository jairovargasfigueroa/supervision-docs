# 601 · Preparar el despliegue · tareas de `mobile/app-obra`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `mobile/app-obra/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] `EXPO_PUBLIC_KEYCLOAK_URL` y `EXPO_PUBLIC_SINCRONIZACION_URL` en `app.config.js` (por defecto las de desarrollo); pruebas
- [ ] `.github/workflows/ci.yml`: `npm ci`, `npx tsc --noEmit` y `npx jest` (sin imagen)
