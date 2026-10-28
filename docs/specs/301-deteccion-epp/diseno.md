# 301 · Diseño

## Enfoque: detector en dos etapas (decisión del equipo)

Se usan **dos modelos TensorFlow Lite** que corren uno tras otro en el celular:

| Etapa | Modelo | Quién lo entrena | Entrada | Salida |
|---|---|---|---|---|
| 1. Personas | EfficientDet-Lite0 (COCO), versión TFLite que publica MediaPipe para su *Object Detector* (`efficientdet_lite0.tflite`, variante int8) | Preentrenado (no se reentrena) | imagen 320 × 320, `uint8` | cajas, clases, puntajes y cantidad (posproceso NMS incluido en el modelo) |
| 2. EPP por persona | Clasificador multietiqueta **MobileNetV3-Small** con ajuste fino (*transfer learning*) | El equipo, con TensorFlow / Keras | recorte de la persona, 224 × 224, `float32` (0–255) | 2 probabilidades: `casco`, `chaleco` |

Por qué dos etapas y no un solo detector de casco/chaleco:

- Contar «personas sin casco» y «sin chaleco» sale directo: cada persona detectada recibe sus dos probabilidades. Con un detector de objetos sueltos (casco, chaleco, cabeza) habría que emparejar cada casco y cada chaleco con una persona.
- Las herramientas clásicas para reentrenar detectores y exportarlos a TFLite (TFLite Model Maker y la Object Detection API de TF1/TF2) no funcionan con Python 3.12 ni con las versiones actuales de TensorFlow. Un clasificador de Keras se entrena y se exporta a TFLite sin herramientas extra.
- La parte de *deep learning* entrenada por el equipo (punto 12) es el clasificador: red convolucional con pesos de ImageNet, ajuste fino sobre recortes de personas de un dataset público de EPP.

Alternativa documentada (si el equipo prefiere un único detector): ajuste fino de un RetinaNet con *backbone* MobileNet de `tf-models-official` y exportación con su script de TFLite. No se elige por su complejidad.

URL del modelo de personas (verificada el 28/10/2026): `https://storage.googleapis.com/mediapipe-models/object_detector/efficientdet_lite0/int8/1/efficientdet_lite0.tflite`. El orden de los tensores de salida y el índice de la clase «person» se confirman al integrar (tarea de la app).

## Flujo en la app

```
Foto tomada → compresión 1600 px / JPEG 80 (005)
  → redimensionar a 320×320 (expo-image-manipulator, base64) → decodificar JPEG a RGB (jpeg-js)
  → EfficientDet-Lite0 → personas con puntaje ≥ 0,50 y alto ≥ 64 px en la foto de 1600 px
  → por cada persona (máx. 10, las de mayor puntaje): recorte con margen 10 % → 224×224 → RGB float32
  → clasificador EPP → casco = p_casco ≥ umbral_casco; chaleco = p_chaleco ≥ umbral_chaleco
  → { personas, sinCasco, sinChaleco, versionModelo } + recuadros para la vista previa
  → aviso (si corresponde) → «Enviar» (005, con el campo deteccion)
```

- Umbrales: los fija el notebook al evaluar (se guardan en `etiquetas.json` del modelo); valor inicial 0,50.
- Personas pequeñas (alto < 64 px) no se cuentan: no hay detalle suficiente para clasificar (decisión del equipo).
- Tiempo máximo de 5 s para todo el análisis (criterio 5); si se pasa, se descarta el resultado.

## App (`mobile/app-obra`)

- Dependencias (instalar siempre con `npx expo install`):
  - `react-native-fast-tflite` 3 (con su *config plugin* en `app.json`; agregar `tflite` a `resolver.assetExts` en `metro.config.js`).
  - `expo-dev-client` 58: la librería tiene código nativo y **no funciona en Expo Go**; se usa una *development build* (`npx expo run:android` o EAS Build con perfil `development`).
  - `jpeg-js` 0.4 (decodificar JPEG a píxeles en JavaScript) y `buffer` 6 (pasar de base64 a bytes).
- Archivos de modelo en `assets/modelos/`: `efficientdet_lite0.tflite`, `clasificador_epp.tflite` y `epp.json` (versión, umbrales, tamaño de entrada).
- Módulo `src/avance/epp/`:
  - `cargarModelos()`: carga los dos modelos una vez (`loadTensorflowModel`) al abrir la pantalla de foto; delegado GPU en Android si está disponible, si no CPU.
  - `analizarFoto(uri): Promise<ResultadoEpp>` con `{ personas, sinCasco, sinChaleco, versionModelo, cajas[] }`.
  - Funciones puras probadas sin modelo: conversión RGBA → RGB, filtro de cajas, conteo con umbrales, escalado de cajas a la foto original.
- Pantalla `obras/[id]/foto` (005): después de la compresión muestra «Analizando…», luego el resumen y el aviso con recuadros sobre la vista previa. «Enviar» siempre habilitado.
- El resultado se guarda junto con el `fotoId` y el archivo hasta confirmar el registro (para reintentar sin volver a analizar).
- `versionModelo` = `epp-<versión del clasificador>` (por ejemplo `epp-1.0.0`), leído de `epp.json`.

## Obras (`services/obras`)

- Migración: `foto_avance` agrega `sin_chaleco int null` y `version_modelo_epp varchar(40) null`. `personas_detectadas` y `sin_casco` ya existen. Los cuatro quedan `null` cuando la foto no se analizó.
- `POST /obras/{obraId}/fotos` acepta el campo opcional `deteccion`:

```json
{
  "id": "uuid", "partidaId": "uuid", "claveArchivo": "fotos/…jpg", "tomadaEn": "2026-11-15T15:20:00Z",
  "deteccion": { "personas": 4, "sinCasco": 1, "sinChaleco": 2, "versionModelo": "epp-1.0.0" }
}
```

- Validación en el dominio: enteros ≥ 0, `sinCasco ≤ personas`, `sinChaleco ≤ personas`, `versionModelo` de 1 a 40 caracteres. Si no se cumple, **la foto se registra igual sin la detección** (`deteccion: null`), se escribe un aviso en el registro con el `fotoId` y la respuesta incluye `avisos: ["DETECCION_DESCARTADA"]` (decisión del equipo: la detección es un dato de apoyo y no debe obligar a volver a tomar la foto).
- Idempotencia sin cambios: si el `id` ya existe se devuelve `200` con el registro existente y **no** se actualiza la detección.
- La respuesta de `POST` y cada elemento de `GET /obras/{obraId}/fotos` agregan `deteccion` (u `null`). Para el rol `cliente`, `deteccion` es siempre `null`.

## Gateway

- Nuevo tipo y campo:

```graphql
type DeteccionEpp { personas: Int! sinCasco: Int! sinChaleco: Int! versionModelo: String! }
extend type Foto { deteccion: DeteccionEpp }
```

- Se mapea tal cual desde `GET /obras/{obraId}/fotos`; sin llamadas nuevas.

## mf-obras

- Pestaña «Fotos» del detalle de obra: etiqueta sobre cada miniatura según el criterio 9 (color de advertencia si hay alertas, neutro si no). Texto de ayuda al pasar el cursor: «Detectado en el celular con el modelo epp-1.0.0».

## Entrenamiento (`services/ia/entrenamiento/epp/`)

- Entorno aparte del servicio (el servicio de la capa 4 no instala TensorFlow): `requirements-entrenamiento.txt` con `tensorflow` 2.21, `keras` 3, `numpy`, `pandas`, `scikit-learn`, `matplotlib`, `pillow`. Python 3.12. Se puede ejecutar en Google Colab con GPU o en local.
- Archivos:
  - `preparar_recortes.py`: lee las anotaciones del dataset, recorta personas y les asigna etiquetas.
  - `entrenar_clasificador_epp.ipynb`: entrenamiento, evaluación, elección de umbrales y exportación.
  - `salida/`: `clasificador_epp.tflite`, `epp.json`, `metricas.json`, matriz de confusión (PNG). Solo se versionan el `.tflite`, `epp.json` y `metricas.json`.
  - `README.md`: cómo descargar el dataset, ejecutar y copiar los archivos a `mobile/app-obra/assets/modelos/`.
- **Dataset** (decisión del equipo; se elige uno en la primera tarea tras revisar licencia y clases):
  - *Construction Site Safety Image Dataset* (Kaggle, exportado de Roboflow): clases de persona, casco, chaleco y sus negativos (`NO-Hardhat`, `NO-Safety Vest`).
  - *SH17* (Kaggle y GitHub `ahmadmughees/SH17dataset`, artículo de 2024): 17 clases, entre ellas persona, cabeza, casco y chaleco de seguridad.
  - Ambos existen (verificado el 28/10/2026); la licencia y la lista exacta de clases se confirman antes de usarlos y se citan en el `README.md`.
- **Etiquetado de recortes** (`preparar_recortes.py`):
  - Un recorte por caja de persona de al menos 64 px de alto, con margen de 10 %.
  - `casco = 1` si una caja de casco tiene ≥ 60 % de su área dentro del 40 % superior de la persona; `casco = 0` si hay una caja `NO-Hardhat` (o «cabeza» sin casco) en esa zona.
  - `chaleco = 1` si una caja de chaleco tiene ≥ 60 % de su área dentro de la persona; `chaleco = 0` si hay `NO-Safety Vest` (o, en datasets anotados por completo, si no hay chaleco).
  - Si un atributo no se puede decidir, ese atributo lleva peso 0 en el entrenamiento (`sample_weight` por salida); el otro se usa igual.
  - División 70 / 15 / 15 por **imagen** (no por recorte) para que una misma foto no quede en entrenamiento y prueba.
- **Modelo:** `keras.applications.MobileNetV3Small(include_top=False, weights="imagenet", include_preprocessing=True)` + `GlobalAveragePooling` + `Dropout(0.2)` + dos salidas `Dense(1, sigmoid)` (`casco`, `chaleco`).
  - Aumentos: volteo horizontal, brillo y contraste, rotación ±10°, recorte aleatorio.
  - Fase 1: base congelada, 10 épocas, Adam 1e-3. Fase 2: se descongelan las últimas 30 capas, 10 épocas, Adam 1e-5, parada temprana por pérdida de validación.
- **Exportación:** `model.export("salida/saved_model")` y `tf.lite.TFLiteConverter.from_saved_model(...)` con cuantización float16 (`Optimize.DEFAULT` + `supported_types=[tf.float16]`). Se comprueba que el `.tflite` da las mismas predicciones que el modelo de Keras sobre 50 recortes (diferencia máxima 0,02). Si la versión de TensorFlow instalada marca `tf.lite` como obsoleto, se usa el convertidor que indique su nota de versión (LiteRT).

## Métricas mínimas (decisión del equipo)

Sobre el conjunto de prueba (15 %), por atributo, tomando como clase positiva la **falta** de EPP («sin casco», «sin chaleco»):

| Métrica | Mínimo |
|---|---|
| Sensibilidad (*recall*) de «sin casco» y de «sin chaleco» | ≥ 0,85 |
| Precisión de «sin casco» y de «sin chaleco» | ≥ 0,75 |
| Exactitud global por atributo | ≥ 0,85 |
| Tamaño de los dos `.tflite` juntos | ≤ 10 MB |
| Tiempo de análisis en el celular (criterio 13) | ≤ 2 s con hasta 5 personas |

Se prioriza la sensibilidad: es peor no avisar de alguien sin casco que avisar de más. Si hay fotos propias de obra (20 a 50, tomadas con permiso), se reporta además el error absoluto medio del conteo por foto (objetivo ≤ 1), solo como referencia.

## Pruebas

- Obras: registro con y sin `deteccion`; `sinCasco > personas` (foto registrada sin detección y aviso `DETECCION_DESCARTADA`); registro repetido no cambia la detección; el cliente recibe `deteccion: null`.
- App: funciones puras de `epp/` (conversión de píxeles, filtro por tamaño y puntaje, conteo con umbrales); `analizarFoto` con modelos simulados; tiempo límite de 5 s; el envío incluye `deteccion` y la reintenta con el mismo `fotoId`. Prueba manual en la *development build* con 5 fotos de referencia (resultado anotado en la tarea).
- Entrenamiento: el notebook falla con un mensaje claro si no se alcanzan las métricas mínimas; prueba de equivalencia Keras vs TFLite.
- Gateway: `Foto.deteccion` mapeado y `null`.
- mf-obras: etiqueta con alertas, sin alertas y sin análisis.

## Cambios a contratos y datos

### `services/obras/docs/datos.md` — tabla `foto_avance`

| Campo | Tipo | Notas |
|---|---|---|
| sin_chaleco | int | capa 3 (301); null si no se analizó |
| version_modelo_epp | varchar(40) | capa 3 (301); versión del modelo usado en el celular |

Actualizar la nota de `personas_detectadas` y `sin_casco`: «capa 3 (301); null si no se analizó».

### `docs/contratos/rest.md` y `services/obras/docs/contratos.md`

- `POST /obras/{obraId}/fotos · 005, 301`: el cuerpo admite `"deteccion": { "personas": 4, "sinCasco": 1, "sinChaleco": 2, "versionModelo": "epp-1.0.0" }` (opcional). La respuesta agrega `deteccion` (u `null`). Nuevo aviso en la respuesta: `avisos: ["DETECCION_DESCARTADA"]` cuando la detección no es válida (la foto se guarda igual).
- `GET /obras/{obraId}/fotos · 005, 006, 007, 008, 301`: cada elemento agrega `deteccion` (u `null`; siempre `null` para `cliente`).

### `docs/contratos/graphql-erp.md` y `gateway/docs/contratos.md`

```graphql
type DeteccionEpp { personas: Int! sinCasco: Int! sinChaleco: Int! versionModelo: String! }
type Foto { … deteccion: DeteccionEpp }   # 301
```

### `mobile/app-obra/docs/contratos.md`

- Obras: registrar foto de avance con el campo `deteccion` (capa 3).
- Archivos locales: `assets/modelos/efficientdet_lite0.tflite`, `clasificador_epp.tflite`, `epp.json`.

### `mobile/app-obra/docs/app.md`

- La fila «Aviso de casco y chaleco en la foto» apunta a la spec 301.

### `docs/specs/102-fotos-mala-conexion/diseno.md` y contratos de Sincronización

- El tipo `FOTO_AVANCE` de `POST /lotes` suma el campo opcional `deteccion` en `datos`: `{ id, obraId, partidaId, claveArchivo, tomadaEn, deteccion? }`, con `deteccion = { personas, sinCasco, sinChaleco, versionModelo }`. Sincronización lo reenvía tal cual a Obras `POST /obras/{obraId}/fotos`. Así la detección hecha sin señal llega igual (con la capa 1 la app ya no llama directo a Obras).
- `mobile/app-obra`: la operación `FOTO_AVANCE` de la cola guarda `deteccion` junto con los demás datos.

### Eventos

Ninguno.
