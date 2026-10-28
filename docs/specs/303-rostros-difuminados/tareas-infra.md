# 303 · Rostros difuminados · tareas de `infra`

Requisitos y diseño: `docs/specs/303-rostros-difuminados/` de esta carpeta. Contratos: `docs/contratos.md` de este proyecto.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Almacén S3 (RustFS): dejar explícita la regla CORS del bucket con los orígenes del ERP (`http://localhost:4200`, `http://localhost:4201`) y comprobar desde el navegador un `GET` y un `PUT` con URL firmada (pasos anotados en el README de infra)
