# 301 · Detección de casco y chaleco en la foto de avance

**Estado:** aprobado (01/11/2026) · **Capa:** 3 (IA en el dispositivo) · **Puntos:** 6 y 12 · **Proyectos:** mobile/app-obra, services/obras, services/sincronizacion, services/ia (entrenamiento), gateway, mf-obras

**Decisiones de Jairo (01/11/2026):** el deep learning de la plataforma es la detección de casco y chaleco (la guía la pone de ejemplo y resuelve un problema típico de la obra: accidentes por falta de EPP); se aplica en la foto de avance y además en un **control de seguridad** propio de la app, para no depender de que aparezcan personas en la foto de avance. En la defensa, el celular hace de **dispositivo de borde**: el mismo `.tflite` podría correr en una cámara fija de la obra; aquí se demuestra con el celular. Plan de respaldo si el entrenamiento no alcanza: clasificador de grietas en el hormigón con la misma técnica (no se implementa salvo que haga falta).

## Historia

Como **maestro de obra** quiero que la app me avise, al tomar la foto de avance o al hacer un control de seguridad de la cuadrilla, cuántas personas aparecen sin casco o sin chaleco, para corregirlo en el momento; y como **residente** quiero ver ese dato junto a cada foto de avance para dar seguimiento a la seguridad de la cuadrilla.

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
9. Sin señal, la foto y su detección viajan juntas por la cola de la app y Sincronización (102), y llegan a Obras igual que con señal.

### Control de seguridad (app de obra)

10. CUANDO el maestro abre «Control de seguridad» desde el detalle de la obra en la app y toma (o elige) una foto de la cuadrilla, ENTONCES la app la analiza en el celular, sin conexión, con el mismo modelo, y muestra el mismo resumen, el aviso y los recuadros de los criterios 1, 2 y 4 (y el mensaje del criterio 5 si falla).
11. La foto del control de seguridad **no se envía ni se guarda**: el resultado es un aviso en el momento para el maestro (decisión del equipo: no hay registro de controles de seguridad en el servidor). Puede repetir el control con otra foto.

### ERP

12. CUANDO un usuario del ERP abre la pestaña «Fotos» del detalle de obra (006), ENTONCES cada foto analizada muestra una etiqueta con «N sin casco · M sin chaleco» si alguno es mayor que 0, y «Sin alertas de EPP» si ambos son 0; las fotos no analizadas no muestran etiqueta.
13. El cliente **no** ve los datos de detección en el portal.

### Modelo

14. El modelo se entrena con TensorFlow a partir de un dataset público de equipo de protección personal (EPP) y se exporta a TensorFlow Lite; el notebook y los scripts de entrenamiento quedan en `services/ia/entrenamiento/epp/` y se pueden volver a ejecutar.
15. El modelo cumple las métricas mínimas de `diseno.md` («Métricas mínimas», decisión del equipo) antes de incluirse en la app; las métricas obtenidas se guardan junto al modelo.
16. El análisis de una foto con hasta 5 personas tarda como máximo 2 segundos en un celular Android de gama media (decisión del equipo: 4 GB de RAM, del año 2022 o posterior).

## Fuera del alcance

- Detección en video o en tiempo real con la cámara abierta.
- Otros EPP (guantes, lentes, botas, arnés).
- Identificar a las personas o guardar recortes de ellas.
- Bloquear el envío de la foto o notificar automáticamente al residente (los agentes de la capa 5 pueden usar el dato).
- Guardar o enviar las fotos del control de seguridad, o llevar un historial de controles.
