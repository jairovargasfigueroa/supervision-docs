# 601 · Preparar el despliegue · tareas de `frontend/mf-obras`

Requisitos y diseño: `docs/specs/601-contenedores-ci/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `frontend/mf-obras/docs/specs/601-contenedores-ci/tareas.md` (eran del borrador anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/`, `CLAUDE.md`, `.env.example`)
- [ ] Leer la dirección del gateway de `window.plataforma.configuracion` (como mf-materiales y mf-supervision) con respaldo al valor de desarrollo; pruebas
- [ ] `.github/workflows/ci.yml`: job `prueba` (pruebas y compilación) y job `archivos`
