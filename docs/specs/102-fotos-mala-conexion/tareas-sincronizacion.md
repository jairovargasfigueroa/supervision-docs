# 102 · Fotos sin señal y mala conexión · tareas de `services/sincronizacion`

Requisitos y diseño: `docs/specs/102-fotos-mala-conexion/` de la carpeta que agrupa los proyectos. Requiere la 101 hecha (el proyecto ya existe). Cuando exista el proyecto, este archivo se copia a `services/sincronizacion/docs/specs/102-fotos-mala-conexion/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] `POST /fotos/url-subida`: reenvío a Obras con el token del usuario, errores del dueño tal cual, `503` y `504`
- [ ] Tipo `FOTO_AVANCE` en `POST /lotes` (Obras `POST /obras/{obraId}/fotos`)
- [ ] Actualizar `docs/contratos.md` del proyecto y pruebas de la spec (servicios dueños simulados)
