# 303 · Rostros difuminados en las fotos publicadas al cliente

**Estado:** borrador · **Capa:** 3 (IA en el dispositivo) · **Punto:** 6 · **Proyectos:** frontend/mf-obras, services/obras, gateway, frontend/portal, infra

## Historia

Como **residente** quiero que, al presentar una planilla, las fotos de respaldo se publiquen al cliente con los rostros de los trabajadores difuminados, para proteger su privacidad; y quiero que eso se haga en mi navegador, sin mandar las fotos a otro servicio para analizarlas.

## Criterios de aceptación

### ERP (mf-obras)

1. CUANDO el residente pulsa «Presentar» en una planilla con fotos adjuntas (007), ENTONCES antes de presentarla el ERP prepara la **versión para el cliente** de cada foto adjunta que todavía no la tiene, mostrando el avance («Preparando fotos para el cliente: 2 de 5»).
2. Preparar una foto significa: detectar los rostros **en el navegador**, difuminar cada rostro con un margen alrededor y guardar la foto resultante como una copia aparte. La foto original no cambia.
3. CUANDO termina la preparación, ENTONCES el ERP muestra una vista previa de las versiones para el cliente, con el número de rostros difuminados en cada una.
4. En la vista previa el residente puede **marcar a mano** zonas adicionales para difuminar (arrastrando un rectángulo sobre la foto) si ve un rostro que no se detectó, y puede quitar una foto de la planilla.
5. CUANDO el residente confirma, ENTONCES se suben las versiones para el cliente y luego se presenta la planilla. SI cancela, ENTONCES la planilla sigue en su estado y no se presenta.
6. La versión para el cliente se guarda sin los metadatos de la foto original (EXIF, incluida la ubicación GPS).
7. SI la foto ya tiene versión para el cliente (por ejemplo, al volver a presentar una planilla `OBSERVADA`), ENTONCES no se vuelve a preparar, salvo que el residente pida «Volver a preparar» en la vista previa.
8. SI el modelo de detección no carga o una foto no se puede procesar, ENTONCES el ERP lo dice, permite reintentar o quitar esa foto, y **no** presenta la planilla con fotos sin versión para el cliente.

### Obras

9. Una planilla con fotos adjuntas solo se puede presentar si todas tienen versión para el cliente; si no, se rechaza con el motivo y la lista de fotos que faltan.
10. CUANDO el cliente pide las fotos de una obra, ENTONCES recibe la versión para el cliente de cada foto publicada.

### Portal

11. CUANDO el cliente ve las fotos de una obra o de una planilla, ENTONCES ve las versiones con rostros difuminados y una nota: «Los rostros se difuminan para proteger la privacidad del personal».

## Fuera del alcance

- Difuminar placas de vehículos, carteles u otros datos.
- Difuminar fotos en el celular o en el servidor.
- Reconocer o identificar personas.
- Editar la foto original.
