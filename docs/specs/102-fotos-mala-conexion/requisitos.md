# 102 · Fotos sin señal y envío con mala conexión

**Estado:** aprobado (30/10/2026, simplificado en la evaluación de la capa 1: sin subida por partes ni foto de la nota de remisión) · **Capa:** 1 · **Puntos del ingeniero:** 7 y 9 · **Proyectos:** services/sincronizacion, app-obra · **Depende de:** 101

## Historia

Como **maestro de obra** quiero tomar fotos de avance aunque no haya señal o la señal sea mala, y que se suban solas sin repetirse, sin trabar el envío de los demás registros.

## Criterios de aceptación

### Foto de avance sin señal

1. CUANDO el maestro toma una foto de avance (005, criterios 1 y 2) con o sin señal, ENTONCES la foto se comprime en el celular (máximo 1280 px por lado, calidad JPEG 70; decisión del equipo: unos 150 a 400 KB), se guarda en el celular con su UUID, la partida y la fecha y hora en que se tomó, y queda en «Pendientes de envío».
2. La foto queda registrada en Obras recién cuando su archivo está completo en el almacenamiento.
3. SI hay más de 100 fotos sin enviar en el celular, ENTONCES la app avisa «Tienes N fotos sin enviar; busca señal para enviarlas» (no impide tomar más).

### Mala conexión

4. Orden de envío: primero los datos livianos (movimientos, entradas del diario y registros de fotos cuyo archivo ya se subió), después los archivos de las fotos, de a uno.
5. El archivo se sube completo y directo al almacenamiento con una URL firmada (como en la 005), que la app pide a Sincronización justo antes de subir. SI la subida falla por la red o por tiempo agotado (30 s), ENTONCES se vuelve a subir completo con la espera creciente de la 101, pidiendo una URL nueva.
6. Tiempos máximos: 30 s por lote, 10 s para pedir la URL, 30 s para subir el archivo y 30 s para descargar los datos; pasado ese tiempo se trata como fallo de red.
7. En «Pendientes de envío», cada foto muestra su miniatura, la partida y el estado; mientras sube, «Subiendo foto…».
8. SI una foto (o su registro) se envía dos veces, ENTONCES queda registrada una sola vez (005, criterio 4).
9. SI Obras rechaza la foto (por ejemplo, la partida ya no es de la obra), ENTONCES queda «Rechazada» con el motivo y no se reintenta.
10. El archivo se borra del celular cuando el servidor confirmó el registro (o cuando el usuario descarta la operación).

## Fuera del alcance

Subida por partes y reanudación a mitad de un archivo (con fotos de unos 300 KB, reenviarla completa cuesta poco); foto de la nota de remisión; videos; subida en segundo plano con la app cerrada; opción «subir fotos solo con Wi-Fi».
