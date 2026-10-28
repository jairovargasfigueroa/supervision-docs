# 301 · Detección de casco y chaleco · tareas de `services/ia` (entrenamiento)

Requisitos y diseño: `docs/specs/301-deteccion-epp/` de esta carpeta. El proyecto `services/ia` todavía no existe; esta spec solo crea su parte de entrenamiento (`entrenamiento/epp/`). El servicio FastAPI se agrega en la 401.

Marca cada tarea al terminarla (con sus pruebas y su commit).

- [ ] Crear el proyecto `services/ia` y su repositorio (GitHub `supervision-ms-ia`, rama `main`) con `.gitignore` de Python (ignora `entrenamiento/**/datos/`, `entrenamiento/**/salida/saved_model/` y `.env`), `README.md` y un `CLAUDE.md` mínimo que diga que el servicio llega en la 401
- [ ] Elegir el dataset (Construction Site Safety o SH17): revisar licencia y clases, y documentar la fuente, la cita y la descarga en `entrenamiento/epp/README.md`
- [ ] `requirements-entrenamiento.txt` (Python 3.12, `tensorflow` 2.21, `keras` 3, `numpy`, `pandas`, `scikit-learn`, `matplotlib`, `pillow`) y comprobación del entorno en Colab o local
- [ ] `preparar_recortes.py`: recortes de personas, etiquetas `casco`/`chaleco` con pesos 0 para lo indeterminado, división 70/15/15 por imagen; pruebas de las reglas de etiquetado con cajas de ejemplo
- [ ] Notebook `entrenar_clasificador_epp.ipynb`: MobileNetV3-Small en dos fases, aumentos, evaluación con las métricas mínimas, elección de umbrales y matriz de confusión
- [ ] Exportar a TFLite float16 y comprobar la equivalencia con Keras (50 recortes, diferencia ≤ 0,02); guardar `clasificador_epp.tflite`, `epp.json` y `metricas.json` en `salida/`
- [ ] Copiar los modelos a `mobile/app-obra/assets/modelos/` (junto con `efficientdet_lite0.tflite` int8) y anotar en el README la versión entregada
