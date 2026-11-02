# 201 · Cobranza automática · tareas de `services/ia`

Requisitos y diseño: `docs/specs/201-cobranza-automatica/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas se copian a `services/ia/docs/specs/201-cobranza-automatica/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/datos.md`, `docs/contratos.md`)
- [ ] Migración de `reportes_db`: `rpt_cobro` agrega `pagado_en`; el estado admite `PAGADO`
- [ ] Consumidor de `evento.finanzas.CobroPagado` (inbox, reintentos y fallidos como los demás): `rpt_cobro.estado = PAGADO` y `pagado_en`
- [ ] La tarea diaria de vencidos no toca los `PAGADO`; la carga inicial (401) lee el estado `PAGADO` y `pagadoEn` de `GET /cobros`
- [ ] Catálogo de reportes (503): en el conjunto de cobros, el valor `PAGADO` del filtro de estado y la columna «Fecha de pago»; pruebas del constructor y de la seguridad (504) con el valor nuevo
