# 602 · Tareas de app-obra

Al empezar la implementación, estas casillas pasan a `mobile/app-obra/docs/specs/602-despliegue-tres-nubes/tareas.md`.

- [ ] `scripts/apk-nube.ps1`: compila el APK de la nube con `EXPO_PUBLIC_KEYCLOAK_URL`, `EXPO_PUBLIC_SINCRONIZACION_URL` y, si se da, `GOOGLE_SERVICES_JSON` (`npx expo prebuild --clean` y `gradlew assembleRelease`); con `-Instalar`, lo instala por cable (`adb install -r`). Comprobar que el APK queda firmado con la clave de depuración de la plantilla y que se instala sobre la *development build*
- [ ] README: sección «APK para la nube» (qué hace el *script*, dónde queda el archivo y cómo pasarlo a otro celular)
- [ ] Con las tres nubes: iniciar sesión en el APK y registrar sin señal una salida y una foto que llegan una sola vez (paso 6 del «Orden» de la 602)
