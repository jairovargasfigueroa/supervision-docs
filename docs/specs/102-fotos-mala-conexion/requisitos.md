# 102 · Fotos sin señal y envío con mala conexión

**Estado:** borrador (por aprobar) · **Capa:** 1 · **Puntos del ingeniero:** 7 y 9 · **Proyectos:** services/sincronizacion, services/materiales, app-obra, infra (RustFS) · **Depende de:** 101

## Historia

Como **maestro de obra** (y como **almacenero**, para la nota de remisión) quiero tomar fotos aunque no haya señal o la señal sea mala, y que se suban solas, por partes y sin repetirse, sin trabar el envío de los demás registros.

## Criterios de aceptación

### Foto de avance sin señal

1. CUANDO el maestro toma una foto de avance (005, criterios 1 y 2) con o sin señal, ENTONCES la foto comprimida se guarda en el celular con su UUID, la partida y la fecha y hora en que se tomó, y queda en «Pendientes de envío».
2. SI la foto comprimida pesa más de 1 MB, ENTONCES se vuelve a comprimir a un máximo de 1280 px por lado y calidad JPEG 70 (decisión del equipo).
3. La foto queda registrada en Obras recién cuando su archivo está completo en el almacenamiento.

### Foto de la nota de remisión

4. CUANDO el almacenero registra un ingreso, ENTONCES puede tomar, de forma opcional, una foto de la nota de remisión (con la misma compresión), además del número de nota.
5. El ingreso se envía primero (para que el stock se actualice cuanto antes); la foto de la nota se sube después y queda asociada a ese ingreso.
6. SI el ingreso es rechazado, ENTONCES la foto de su nota también queda rechazada con el motivo «El ingreso asociado fue rechazado».
7. CUANDO alguien consulta los movimientos de una obra por la API, ENTONCES cada ingreso con foto de nota trae un enlace de descarga temporal.

### Mala conexión

8. Orden de envío: primero los datos livianos (movimientos, entradas del diario y registros de fotos cuyo archivo ya se subió), después los archivos de las fotos, de a uno.
9. Cada archivo se sube por partes de 256 KB. SI la conexión se corta, ENTONCES al volver se sigue desde la primera parte que falta, sin repetir las ya recibidas.
10. SI el archivo armado en el servidor no coincide con el del celular (huella SHA-256), ENTONCES se descarta y se vuelve a subir completo; tras tres intentos fallidos de ese tipo, la foto queda «Rechazada» con «El archivo de la foto está dañado».
11. Tiempos máximos: 30 s por lote, 20 s por parte, 30 s para completar una subida y 30 s para descargar los datos; pasado ese tiempo se trata como fallo de red y se reintenta con la espera creciente de la 101.
12. En «Pendientes de envío», una foto que se está subiendo muestra el progreso: «Subiendo foto · 3 de 5 partes».
13. SI una foto (o su registro) se envía dos veces, ENTONCES queda registrada una sola vez (005, criterio 4), y la foto de la nota se asocia una sola vez.
14. El archivo se borra del celular solo cuando el servidor confirmó el registro (o cuando el usuario descarta la operación).
15. Las partes de subidas que no se terminaron se borran solas del servidor a los 7 días (decisión del equipo); si se borraron antes de terminar, la app vuelve a subir la foto desde el principio.

## Fuera del alcance

Videos; varias fotos por nota de remisión; ver la foto de la nota en el ERP (no hay pantalla de movimientos); subida en segundo plano con la app cerrada; opción «subir fotos solo con Wi-Fi».
