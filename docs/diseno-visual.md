# Diseño visual

Un solo aspecto para el ERP (Angular y React), el portal y la app. Colores y tipografías tomados del prototipo HTML de la carpeta general (`Supervisión de Obras · Prototipo – Alcance mínimo (17 casos de uso).html`), que es la **referencia visual de cada pantalla**: ábrelo en el navegador para ver la distribución antes de maquetar.

## Colores

| Token | Valor | Uso |
|---|---|---|
| `primario` | `#0E4D5C` | barra superior, botones principales, enlaces, selección |
| `primario-oscuro` | `#0A3741` | menú lateral, estados *hover* del primario |
| `primario-suave` | `#E2EEF1` | fondos de selección, chips informativos |
| `acento` | `#F08A24` | acción destacada (una por pantalla), indicadores de atención |
| `acento-suave` | `#FDEEDC` | fondo de avisos de atención |
| `texto` | `#14232A` | texto principal |
| `texto-secundario` | `#56676F` | etiquetas, ayudas, texto secundario |
| `borde` | `#DAE2E5` | bordes de tarjetas, tablas y campos |
| `fondo` | `#F2F5F6` | fondo de la aplicación |
| `superficie` | `#FFFFFF` | tarjetas, tablas, diálogos |
| `exito` / `exito-suave` | `#1B7343` / `#E2F3E9` | estado OK, aprobada, registrado |
| `atencion` / `atencion-suave` | `#9A4A00` / `#FDEEDC` | estado JUSTO, presentada, en riesgo |
| `error` / `error-suave` | `#B42318` / `#FCE8E6` | estado BAJO, observada, errores, excedido |

## Estados del dominio → color

| Estado | Color |
|---|---|
| Stock `OK` · Planilla `APROBADA` · Cobro `PENDIENTE` | éxito |
| Stock `JUSTO` · Planilla `PRESENTADA` / `APROBANDO` · Obra «En riesgo» | atención |
| Stock `BAJO` · Planilla `OBSERVADA` · Cobro `VENCIDO` · Consumo excedido | error |
| Planilla `BORRADOR` · Obra `SIN_CONTRATO` | primario-suave con texto secundario |
| Obra `EN_EJECUCION` | primario |

Los estados se muestran como *chip* (Angular `mat-chip`, MUI `Chip`, Paper `Chip`) con fondo suave y texto del color fuerte.

## Tipografía

- Texto: **Inter** (400, 500, 600). Números en tablas y montos: **IBM Plex Mono** (400, 500) con `font-variant-numeric: tabular-nums`.
- Se cargan **una sola vez en el `index.html` del shell y del portal** desde Google Fonts. Los microfrontends React no cargan fuentes: las heredan (las `@font-face` no funcionan dentro del Shadow DOM, pero la familia sí se hereda).
- Escala: títulos de página 24 px/600, títulos de sección 18 px/600, texto 14 px/400, ayudas 12 px.
- App: Inter con `expo-font` (o la fuente del sistema si no carga), mismos pesos.

## Forma y espacios

- Radio de bordes: 10 px en tarjetas y diálogos, 6 px en botones y campos, 999 px en chips.
- Espaciado en múltiplos de 4 px; separación estándar entre bloques 16 px; márgenes de página 24 px (16 px en el celular).
- Densidad: tablas compactas (filas de 40 px) en el ERP; normal en el portal y la app.

## Formatos

- Montos: `Bs 1.250.000,00` (locale `es-BO`, 2 decimales). Cantidades con hasta 3 decimales y la unidad: `120,5 m²`.
- Fechas: `15/11/2026`; fecha y hora: `15/11/2026 14:30` en hora de La Paz.
- Porcentajes: `32,5 %`.
- Una utilidad de formato por proyecto (`formato.ts`), con pruebas.

## Implementación del tema

- **Angular Material 22** (Material 3): un tema propio en `src/styles/tema.scss` con `mat.theme(...)`, paleta primaria generada desde `#0E4D5C` y terciaria desde `#F08A24`; tipografía Inter; densidad `-2` en el ERP. Los campos (`mat-form-field`) usan la apariencia `outline` en el ERP: con la densidad `-2`, la apariencia `fill` oculta la etiqueta. Variables CSS `--sv-*` con los tokens de arriba para lo que no cubre Material.
- **MUI 9**: `createTheme` en `src/tema.ts` con `palette.primary.main = #0E4D5C`, `secondary.main = #F08A24`, `success/warning/error` según la tabla, `background.default = #F2F5F6`, `shape.borderRadius = 10`, `typography.fontFamily = Inter`. El mismo archivo en mf-materiales, mf-supervision y el portal.
- **Microfrontends React dentro del Shadow DOM**: `createCache({ key: 'mf', container: shadowRoot })` con `CacheProvider`; `ScopedCssBaseline` en la raíz; diálogos, menús, *tooltips* y *popovers* montados dentro del Shadow DOM (en el tema, `defaultProps.container` de `MuiPopover`, `MuiPopper`, `MuiModal` y `MuiDialog` apuntando al contenedor del microfrontend).
- **React Native Paper 5**: `MD3LightTheme` extendido en `src/tema.ts` con los mismos colores.
- Solo tema claro.

## Distribución del ERP (shell)

- Barra superior (`primario`, 56 px): nombre de la plataforma, nombre y rol del usuario, menú de aplicaciones y cerrar sesión.
- Menú lateral (`primario-oscuro`, 240 px, colapsable): Obras, Materiales, Supervisión.
- Contenido sobre `fondo`, con título de página, migas de pan y tarjetas.
- Cada área muestra un estado vacío con texto y acción («Aún no hay obras. Registrar obra») y un estado de error («No disponible por el momento. Reintentar»).

## Pantallas chicas (responsive)

Todas las aplicaciones web se adaptan al ancho de la pantalla. Puntos de quiebre (los de Material): menos de 600 px (celular), 600–959 px (tablet), 960 px o más (escritorio).

- **ERP:** pensado para escritorio, pero usable en tablet y celular.
  - Desde 960 px: menú lateral fijo.
  - Debajo de 960 px: menú lateral como cajón (`mat-sidenav` modo `over`) con botón en la barra.
  - Debajo de 600 px: las tablas largas pasan a tarjetas apiladas, o tienen desplazamiento horizontal con la primera columna fija. Los formularios de varios pasos muestran un paso por pantalla.
  - Los microfrontends React usan los mismos puntos de quiebre con `useMediaQuery` de MUI.
- **Portal:** diseñado primero para celular, porque el cliente lo abre desde el teléfono.
  - Listas como tarjetas; tablas de planilla con las columnas esenciales (partida, cantidad, monto) y el resto en un detalle desplegable.
  - Botones «Aprobar» y «Observar» fijos al pie en el celular.
- **App:** solo vertical; probar en pantallas de 360 a 430 px de ancho.
- Ningún texto ni botón se corta ni se superpone a 360 px de ancho; los objetivos táctiles miden al menos 44 × 44 px.

## Accesibilidad mínima

Contraste AA en texto, foco visible, etiquetas en todos los campos, navegación con teclado en formularios y tablas, textos de error junto al campo.
