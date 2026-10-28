# 302 · Dictado por voz en el navegador

**Estado:** borrador · **Capa:** 3 (IA en el dispositivo) · **Punto:** 6 · **Proyectos:** frontend/mf-supervision

## Historia

Como **gerente, residente o administración** quiero dictar texto con la voz en el ERP y que se transcriba en mi propio navegador, para escribir notas y consultas sin teclear y sin que mi audio salga de mi computadora.

Esta spec construye el **componente de dictado reutilizable** de mf-supervision. La consulta de reportes por voz de la capa 5 lo usa tal cual.

## Criterios de aceptación

1. CUANDO el usuario pulsa el botón de micrófono del componente, ENTONCES el navegador pide permiso para usar el micrófono (solo la primera vez) y empieza a grabar, con un indicador visible «Grabando…» y el tiempo transcurrido.
2. CUANDO vuelve a pulsar el botón (o pasan 60 segundos, decisión del equipo), ENTONCES la grabación se detiene, se muestra «Transcribiendo…» y el texto reconocido aparece en el campo de texto del componente, donde se puede corregir a mano.
3. La transcripción ocurre **en el navegador** con un modelo Whisper; el audio no se envía a ningún servidor. Lo que el componente entrega a la pantalla que lo usa es solo el texto.
4. El idioma de la transcripción es español.
5. La primera vez, el navegador descarga el modelo y el componente muestra el avance («Preparando el dictado: 45 %»). Las veces siguientes usa el modelo guardado en el navegador y no lo descarga de nuevo.
6. Mientras se descarga el modelo o se transcribe, la pantalla sigue respondiendo (no se congela).
7. SI el usuario niega el permiso del micrófono, ENTONCES el componente muestra «Sin permiso para usar el micrófono» y el campo de texto se puede usar escribiendo.
8. SI el navegador no tiene lo necesario (micrófono, WebAssembly o Web Workers) o el modelo no se puede descargar, ENTONCES el botón de micrófono se desactiva con el motivo y el campo sigue funcionando para escribir.
9. SI la grabación dura menos de 1 segundo o no se reconoce texto, ENTONCES se muestra «No se entendió el audio, intenta de nuevo» sin borrar lo que ya había en el campo.
10. Cada nuevo dictado se agrega al final del texto existente (no lo reemplaza).
11. Mientras no exista la capa 5, el componente se puede probar en la pantalla «Dictado» de Supervisión, con un campo de texto y el botón «Copiar texto» (decisión del equipo).

## Fuera del alcance

- Dictado en la app móvil (diario de obra) y en el portal.
- Enviar el texto al servicio de IA o interpretarlo (capa 5).
- Comandos de voz, otros idiomas, transcripción en vivo palabra por palabra, identificar quién habla.
