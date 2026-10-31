# 301 · Detección de casco y chaleco en la foto de avance

**Estado:** borrador · **Capa:** 3 (IA en el dispositivo) · **Puntos:** 6 y 12 · **Proyectos:** mobile/app-obra, services/obras, services/ia (entrenamiento), gateway, mf-obras

**Nota (31/10/2026):** el uso del deep learning en esta funcionalidad está **por decidir**; se decide al reevaluar la capa 3 (que ahora va después de la capa 4).

## Historia

Como **maestro de obra** quiero que la app me avise, al tomar la foto de avance, cuántas personas aparecen sin casco o sin chaleco, para corregirlo en el momento; y como **residente** quiero ver ese dato junto a cada foto para dar seguimiento a la seguridad de la cuadrilla.

## Criterios de aceptación

### App de obra

1. CUANDO el maestro toma (o elige) la foto de avance y la app termina de comprimirla (005), ENTONCES la app analiza la foto **en el celular**, sin conexión a internet, y muestra el resultado antes de enviarla: «Personas: 4 · Sin casco: 1 · Sin chaleco: 2».
2. SI se detecta al menos una persona sin casco o sin chaleco, ENTONCES la app muestra un aviso visible («Hay personas sin equipo de protección. Recuerda el uso de casco y chaleco.») con un recuadro sobre cada persona señalada en la vista previa.
3. El aviso **no bloquea**: el botón «Enviar» sigue disponible y la foto se envía igual.
4. SI no se detecta ninguna persona, ENTONCES se muestra «No se detectaron personas» y no hay aviso.
5. SI el análisis falla o tarda más de 5 segundos (decisión del equipo), ENTONCES la app lo dice («No se pudo analizar la foto»), la foto se puede enviar igual y se envía sin datos de detección.
6. Al enviar la foto, la app manda junto con ella el número de personas, de personas sin casco, de personas sin chaleco y la versión del modelo usada.
7. La foto **no** se envía a ningún servidor para analizarla: el análisis ocurre solo en el celular.
8. SI el envío se repite (mismo `fotoId`), ENTONCES la foto y sus datos de detección quedan registrados una sola vez (005, criterio 4).

### ERP

9. CUANDO un usuario del ERP abre la pestaña «Fotos» del detalle de obra (006), ENTONCES cada foto analizada muestra una etiqueta con «N sin casco · M sin chaleco» si alguno es mayor que 0, y «Sin alertas de EPP» si ambos son 0; las fotos no analizadas no muestran etiqueta.
10. El cliente **no** ve los datos de detección en el portal.

### Modelo

11. El modelo se entrena con TensorFlow a partir de un dataset público de equipo de protección personal (EPP) y se exporta a TensorFlow Lite; el notebook y los scripts de entrenamiento quedan en `services/ia/entrenamiento/epp/` y se pueden volver a ejecutar.
12. El modelo cumple las métricas mínimas de `diseno.md` («Métricas mínimas», decisión del equipo) antes de incluirse en la app; las métricas obtenidas se guardan junto al modelo.
13. El análisis de una foto con hasta 5 personas tarda como máximo 2 segundos en un celular Android de gama media (decisión del equipo: 4 GB de RAM, del año 2022 o posterior).

## Fuera del alcance

- Detección en video o en tiempo real con la cámara abierta.
- Otros EPP (guantes, lentes, botas, arnés).
- Identificar a las personas o guardar recortes de ellas.
- Bloquear el envío de la foto o notificar automáticamente al residente (los agentes de la capa 5 pueden usar el dato).
- Análisis de fotos sin señal: funciona igual porque es local, pero el envío sin señal es de la capa 1.
