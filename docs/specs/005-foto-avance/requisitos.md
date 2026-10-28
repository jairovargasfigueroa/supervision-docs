# 005 · Registrar foto de avance

**Estado:** aprobado · **Proyectos:** services/obras, app-obra, infra (RustFS)

## Historia

Como **maestro de obra** quiero tomar desde la app fotos del avance de cada partida, para que el residente tenga respaldo al elaborar la planilla y el cliente vea el avance real.

## Criterios de aceptación

1. CUANDO el maestro elige una de sus obras y pulsa «Foto de avance», ENTONCES elige la partida y toma la foto con la cámara (o la elige de la galería).
2. Antes de enviarla, la app la reduce a un máximo de 1600 px por lado y calidad JPEG 80.
3. CUANDO pulsa «Enviar», ENTONCES la foto se sube y queda registrada con obra, partida, quién la tomó y la fecha y hora en que se tomó.
4. SI el envío se repite, ENTONCES la foto queda registrada una sola vez.
5. SI la subida falla, ENTONCES la app lo dice y permite reintentar sin volver a tomar la foto.
6. CUANDO un usuario del ERP abre el detalle de una obra, ENTONCES ve las fotos agrupadas por partida, de la más reciente a la más antigua, con fecha y autor.
7. Solo `maestro` (y `residente` por la API) registra fotos, y solo en sus obras asignadas.
8. Las fotos no son visibles para el cliente hasta que se adjuntan a una planilla presentada (007).

## Fuera del alcance

Detección de casco y chaleco y difuminado de rostros (capa 3), fotos sin señal (capa 1), borrar fotos.
