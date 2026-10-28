# 503 · Reportes por voz · tareas de `services/ia`

Requisitos y diseño: `docs/specs/503-reportes-voz/` de la carpeta que agrupa los proyectos. Requiere la base de reportes de la 401 (tablas `rpt_*` y conexión SQLAlchemy), la 402 (columnas `riesgo_retraso` y `nivel_riesgo`) y el puerto `ModeloLenguaje` de la 502.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Variables `IA_REPORTES_DB_URL_LECTURA` (usuario `ia_reportes_lector`) e `IA_MATERIALES_URL` en `config.py` y `.env.example`
- [ ] Migración de Alembic con los `GRANT SELECT` de `ia_reportes_lector` sobre `rpt_obra_resumen`, `rpt_consumo_material`, `rpt_movimiento` y `rpt_cobro`
- [ ] `reportes_voz/dominio/catalogo.py`: los siete reportes con título, descripción, ejemplos, filtros y valores por defecto, columnas y SQL con parámetros `:nombre`
- [ ] Modelo `IntencionReporte` y validación en orden (esquema, NINGUNO, filtros aceptados, rangos de periodos, valores por defecto, patrón de obra con escape)
- [ ] Ejecutor de SQL con `sqlalchemy.text()`: transacción `READ ONLY`, `statement_timeout` de 5 s, `limite + 1` para `truncado`, conversión de filas a texto
- [ ] Catálogo de Materiales con el token del usuario (caché de 5 min): `materialNombre` → `material_ids` y nombres y unidad en el resultado; comportamiento si Materiales no responde
- [ ] Interpretación y redacción con Ollama (datos delimitados, tiempos de 20 s y 25 s, plantilla de respaldo, error `LLM_NO_DISPONIBLE`)
- [ ] Repositorio de `consulta_voz` y límite de 10 consultas por minuto por usuario
- [ ] Endpoints `POST /reportes-voz/consultas`, `GET /reportes-voz/consultas`, `GET /reportes-voz/catalogo` (solo `admin` y `gerente`) con sus errores
- [ ] Pruebas del diseño con LLM simulado y PostgreSQL con las migraciones de la 401 (incluidos los permisos de `ia_reportes_lector`)
- [ ] Prueba manual con 20 preguntas de ejemplo y resultados anotados en el README
