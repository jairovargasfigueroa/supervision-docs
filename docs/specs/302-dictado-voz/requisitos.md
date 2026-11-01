# 302 · Dictado por voz en el navegador

**Estado:** aprobado (31/10/2026) · **Capa:** 5 (antes 3; se hace junto a la 503) · **Punto:** 6 (IA local en el navegador) · **Proyectos:** frontend/mf-supervision · **Depende de:** 009

**Decisión de Jairo (31/10/2026):** la capa 3 se salta por ahora y el dictado pasa a la capa 5, junto a los reportes por voz (503), que lo usan. Modelo **Whisper base** (`onnx-community/whisper-base`, pesos `q8`) corriendo en el navegador, dentro de mf-supervision (confirmado: ya estaba diseñado así).

## Historia

Como **gerente, residente o administración** quiero dictar texto con la voz en el ERP y que se transcriba en mi propio navegador, para escribir notas y consultas sin teclear y sin que mi audio salga de mi computadora.

Esta spec construye el **componente de dictado reutilizable** de mf-supervision. La pantalla «Reportes» de la 503 lo usa tal cual; por eso se implementa antes que la 503.

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
11. El componente se puede probar solo en la pantalla «Dictado» de Supervisión, con un campo de texto y el botón «Copiar texto» (decisión del equipo). Al terminar la 503 esa pantalla se puede quitar del menú (el dictado queda dentro de «Reportes»).

## Fuera del alcance

- Dictado en la app móvil (diario de obra) y en el portal.
- Enviar el texto al servicio de IA o interpretarlo (lo hace la 503).
- Comandos de voz, otros idiomas, transcripción en vivo palabra por palabra, identificar quién habla.
