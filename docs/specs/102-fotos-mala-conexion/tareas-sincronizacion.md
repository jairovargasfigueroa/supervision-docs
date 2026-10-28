# 102 · Fotos sin señal y mala conexión · tareas de `services/sincronizacion`

Requisitos y diseño: `docs/specs/102-fotos-mala-conexion/` de la carpeta que agrupa los proyectos. Requiere la 101 hecha (el proyecto ya existe). Cuando exista el proyecto, este archivo se copia a `services/sincronizacion/docs/specs/102-fotos-mala-conexion/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Tabla `subida_archivo` (TTL 7 días) en la creación de tablas de desarrollo
- [ ] Cliente S3 limitado al prefijo `temporal/subidas/` (`SINC_S3_*`, *path-style*)
- [ ] `POST /subidas` y `GET /subidas/{idSubida}` (creación condicional, `SUBIDA_AJENA`, `SUBIDA_DISTINTA`)
- [ ] `PUT /subidas/{idSubida}/partes/{n}` con cuerpo binario (límite 300 KB), validación de número y tamaño, `ADD partes_recibidas`
- [ ] `POST /subidas/{idSubida}/completar`: partes faltantes, reinicio si falta un objeto, verificación SHA-256, URL firmada del dueño (Obras o Materiales), `PUT` final, borrado de temporales, idempotencia
- [ ] Tipos `FOTO_AVANCE` y `FOTO_NOTA_REMISION` en `POST /lotes`
- [ ] Actualizar `docs/datos.md` y `docs/contratos.md` del proyecto
- [ ] Pruebas de la spec (DynamoDB Local y RustFS o S3 simulado, servicios dueños simulados)
