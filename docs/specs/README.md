# Especificaciones que cruzan proyectos

Aquí van solo las funcionalidades que tocan varios proyectos (por ejemplo, la saga «aprobar planilla»). Las que caen en un solo proyecto van en el `docs/specs/` de ese proyecto.

Cada funcionalidad tiene su carpeta `NNN-nombre/` con:

- `requisitos.md`: historia de usuario y criterios de aceptación en formato «CUANDO … ENTONCES …» o «SI … ENTONCES …».
- `diseno.md`: qué hace cada proyecto, en qué orden, con qué contratos y qué pasa si algo falla.

Las tareas (`tareas.md`) van en cada proyecto, porque se implementan allí.
