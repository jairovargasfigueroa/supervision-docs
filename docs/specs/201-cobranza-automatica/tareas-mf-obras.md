# 201 · Cobranza automática · tareas de `frontend/mf-obras`

Requisitos y diseño: `docs/specs/201-cobranza-automatica/` de la carpeta que agrupa los proyectos. Al implementarla, estas tareas se copian a `frontend/mf-obras/docs/specs/201-cobranza-automatica/tareas.md`.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Aplicar «Cambios a contratos y datos» que tocan este proyecto (`docs/contratos.md`, `docs/app.md`)
- [ ] Pestaña «Cobros»: estado `PAGADO` en verde con «Pagado el dd/mm/aaaa» y el comprobante; columna «Correos» con las etiquetas de envío y «Nota sin enviar»
- [ ] Diálogo «Registrar pago» (solo `admin`): fecha (por defecto hoy, entre la emisión y hoy) y comprobante opcional; mutación `registrarPagoCobro`; mensajes de error del catálogo; la tabla se actualiza
- [ ] Pruebas (estados, etiquetas, diálogo por rol, validaciones, errores)
