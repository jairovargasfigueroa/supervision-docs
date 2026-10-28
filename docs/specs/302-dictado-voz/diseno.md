# 302 · Diseño

## Tecnología

- Librería: `@huggingface/transformers` 4 (transformers.js; corre modelos ONNX en el navegador con WebAssembly o WebGPU).
- Modelo (decisión del equipo): `onnx-community/whisper-base` (multilingüe), pesos cuantizados `q8` (`encoder_model_quantized.onnx` ≈ 23 MB + `decoder_model_merged_quantized.onnx` ≈ 54 MB; tamaños verificados en Hugging Face el 28/10/2026). Se elige *base* y no *tiny* porque *tiny* reconoce peor el español; *small* pesa demasiado para descargarlo en el navegador.
- Alternativa configurable: `onnx-community/whisper-tiny` (`q8`, ≈ 41 MB) para equipos lentos.
- Los modelos `.en` no sirven: solo transcriben inglés.

## Flujo

```
Botón micrófono → getUserMedia({ audio: true }) → MediaRecorder (webm/opus)
  → detener (botón o 60 s) → Blob → AudioContext({ sampleRate: 16000 }).decodeAudioData → Float32Array mono 16 kHz
  → postMessage al Web Worker (transferible)
Worker: pipeline("automatic-speech-recognition", modelo, { dtype: "q8", device })
  → transcribir(audio, { language: "spanish", task: "transcribe", chunk_length_s: 30, stride_length_s: 5 })
  → postMessage({ tipo: "texto", texto })
Componente: agrega el texto al campo → evento onTexto(texto)
```

- `device`: `"webgpu"` si `navigator.gpu` existe y el adaptador se obtiene; si no, `"wasm"`.
- Carga diferida: el worker y la librería se cargan solo cuando el usuario pulsa el micrófono por primera vez (no al abrir Supervisión).
- Caché: transformers.js guarda los archivos del modelo con la Cache API del navegador (`env.useBrowserCache = true`, valor por defecto). Avance de descarga con el callback `progress_callback` del `pipeline`.
- Origen del modelo: por defecto Hugging Face (`env.allowRemoteModels = true`). Variable de compilación `DICTADO_MODELO_URL` para servirlo desde otra ruta (`env.localModelPath`) si en el despliegue (capa 6) se prefiere no depender de Hugging Face (decisión del equipo).
- El audio vive solo en memoria; no se guarda en el navegador ni se envía.

## mf-supervision

- Carpeta `src/dictado/`:
  - `CampoDictado.tsx`: componente con `valor`, `onCambio(texto)`, `placeholder`, `maxSegundos` (60 por defecto) y `desactivado`. Contiene el `textarea`, el botón de micrófono, el indicador de estado y los mensajes de los criterios 7 a 9.
  - `useDictado.ts`: máquina de estados `INACTIVO → PREPARANDO → LISTO → GRABANDO → TRANSCRIBIENDO → LISTO`, más `ERROR` y `NO_DISPONIBLE`; expone `iniciar()`, `detener()`, `estado`, `progreso`, `error`.
  - `grabador.ts`: `MediaRecorder` y conversión a Float32Array 16 kHz.
  - `whisper.worker.ts`: carga el `pipeline` una sola vez y responde mensajes `{ tipo: "cargar" | "transcribir" }`.
  - `soporte.ts`: comprueba `navigator.mediaDevices`, `MediaRecorder`, `WebAssembly` y `Worker` (criterio 8).
- El worker se compila como una entrada aparte en `build.mjs` (esbuild) y se crea con `new Worker(new URL("./whisper.worker.js", import.meta.url), { type: "module" })`. Como el microfrontend se carga desde otro origen (4203) dentro del shell (4200), la URL del worker se resuelve contra la URL del propio microfrontend y el servidor de desarrollo ya tiene CORS abierto (`build.mjs --dev`).
- Estilos dentro del Shadow DOM, como el resto del microfrontend.
- Pantalla `/supervision/dictado` (criterio 11): `CampoDictado` + botón «Copiar texto» (`navigator.clipboard.writeText`). Enlace en el menú interno de Supervisión. Roles: `admin`, `gerente`, `residente`. En la capa 5 esta pantalla se puede quitar.
- El micrófono requiere contexto seguro: `http://localhost` en desarrollo y HTTPS en despliegue (capa 6).

## Gateway y servicios

Sin cambios: el texto no sale del navegador en esta spec.

## Pruebas

- `useDictado`: transiciones de la máquina de estados con el worker y el grabador simulados (permiso negado, grabación corta, texto vacío, error de carga, límite de 60 s).
- `CampoDictado`: el texto dictado se agrega al final; el campo se puede editar a mano; el botón se desactiva sin soporte.
- `grabador`: conversión a 16 kHz mono con un audio de prueba corto.
- Prueba manual en Chrome y Edge (con y sin WebGPU) con 5 frases de obra (por ejemplo «Vaciado de losa del tercer piso, faltan doce bolsas de cemento»); se anota en la tarea el tiempo de transcripción y los errores de palabras.

## Métricas mínimas (decisión del equipo)

| Métrica | Mínimo |
|---|---|
| Tasa de error de palabras (WER) en las 5 frases de prueba | ≤ 25 % |
| Tiempo de transcripción de 10 s de audio, modelo ya descargado, equipo con 8 GB de RAM | ≤ 6 s (WASM) |
| Segunda apertura: no vuelve a descargar el modelo | se comprueba en la pestaña Red |

## Cambios a contratos y datos

### `frontend/mf-supervision/docs/contratos.md`

- Consume: modelo Whisper `onnx-community/whisper-base` desde Hugging Face (o la ruta de `DICTADO_MODELO_URL`), descargado por el navegador.
- Expone (dentro del microfrontend): componente `CampoDictado` en `src/dictado/`, para la consulta por voz de la capa 5.

### `frontend/mf-supervision/docs/app.md`

| Pantalla | Quién | Caso de uso | Etapa |
|---|---|---|---|
| Dictado (prueba del componente de voz a texto) | Gerente, residente, administración | Voz a texto en el navegador | Capa 3 |

### GraphQL, REST, eventos y datos

Ninguno.
