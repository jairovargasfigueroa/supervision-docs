# 102 · Fotos sin señal y mala conexión · tareas de `infra`

Requisitos y diseño: `docs/specs/102-fotos-mala-conexion/` de la carpeta que agrupa los proyectos. Contratos: `docs/contratos.md` de este proyecto. Requiere la fase 1 hecha (RustFS con el bucket `supervision`).

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Usuario de RustFS `sincronizacion` con política limitada a `supervision/temporal/*`, creado al iniciar (contraseña en `.env`, nunca en el repo)
- [ ] Regla de expiración (ILM de RustFS) de 7 días para el prefijo `temporal/` del bucket `supervision`
- [ ] Documentar en el README cómo comprobar la regla y la política
