# 504 · Seguridad de la IA · tareas de `services/ia`

Requisitos y diseño: `docs/specs/504-seguridad-ia/` de la carpeta que agrupa los proyectos. Las pruebas M1 a M6 se hacen en cada servicio con sus tareas de 501.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Módulo `src/ia/seguridad/` (`delimitar.py`, `limpiar.py`, `limites.py`, `reglas_sistema.py`) y uso obligatorio en 502 y 503
- [ ] Registro de cada llamada al modelo sin tokens ni secretos
- [ ] Prueba de arquitectura: en el código de la capa 5, SQL solo en `src/ia/reportes_voz/infraestructura/ejecutor_sql.py` y solo desde el catálogo
- [ ] Pruebas S1 a S13 (reportes por voz)
- [ ] Pruebas G1 a G12 (agentes)
- [ ] Ejecutar `tests/seguridad/` en el workflow de integración continua (601)
- [ ] Prueba manual con 10 entradas maliciosas contra el modelo real, con resultados en el README
