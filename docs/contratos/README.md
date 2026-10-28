# Contratos entre proyectos

Cómo se hablan los proyectos. Es la fuente única: cuando un contrato cambia, se actualiza aquí y en el `docs/contratos.md` de cada proyecto afectado.

| Archivo | Contenido | Estado |
|---|---|---|
| `graphql-erp.md` | Consultas, mutaciones y suscripciones entre el ERP y el gateway | Escrito para el sistema base |
| `rest.md` | Endpoints REST de Obras, Materiales y Finanzas (los que usan el gateway, el portal, la app y otros servicios) | Escrito para el sistema base |
| `eventos.md` | Eventos y comandos por RabbitMQ, incluida la saga «aprobar planilla» | Escrito para el sistema base |

Las capas agregan sus operaciones al escribir su `diseno.md`. El formato de errores, el sobre de los eventos y las claves de RabbitMQ están en `docs/convenciones.md`.

## Formato de cada operación REST

```
### POST /planillas/{id}/aprobar
Servicio: Obras · Quién llama: Portal · Rol: cliente
Recibe: —
Devuelve: 202 { "estado": "APROBANDO" }
Errores: 404 (no es su obra; no se revela que existe) · 409 PLANILLA_NO_PRESENTADA (la planilla no está PRESENTADA)
```

## Formato de cada evento

```
### PlanillaAprobacionIniciada
Publica: Obras · Escuchan: Finanzas
Datos: planillaId, obraId, contratoId, neto, periodo
```
