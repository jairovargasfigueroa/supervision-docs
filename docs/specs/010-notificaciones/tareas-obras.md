# 010 · Avisos al celular y al cliente · tareas de `services/obras`

Requisitos y diseño: `docs/specs/010-notificaciones/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas reemplazan a `services/obras/docs/specs/010-notificaciones/tareas.md` (eran de la versión anterior).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/contratos.md`)
- [ ] Outbox `evento.obras.PlanillaPresentada` al presentar una planilla (con `reenvio`), en la misma transacción; pruebas
