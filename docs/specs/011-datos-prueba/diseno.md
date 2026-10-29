# 011 · Diseño

Los datos (ids, montos, fechas, cuentas) están en `docs/datos-prueba.md`; su sección 12 explica la carga en general. Aquí va qué hace cada proyecto.

## Principios

- Cada servicio carga **solo su base**, con un comando propio que se puede correr solo. `infra` los orquesta.
- **Sin eventos:** la semilla no escribe en `outbox_evento` ni en `mensaje_procesado`, no publica en RabbitMQ y no arranca consumidores (motivos en `docs/datos-prueba.md`, sección 12).
- **Fechas relativas** a D (`SEMILLA_FECHA`, por defecto hoy en `America/La_Paz`) con la notación de la sección 1: `D-120`, `D+18`, `M-3`, `M-1/09 10:00`, `D-2 11:00`.
- **Idempotente:** se inserta solo lo que no existe por `id`; no se pisa lo existente. `recargar` vacía primero.
- **Derivados calculados, no copiados:** stock, saldo del contrato, número y estado del cobro, montos de planilla. La semilla los calcula con las mismas reglas del dominio y las pruebas comparan con las cifras del documento.
- **Guardas** de la sección 12 en cada comando.

## Resolvedor de fechas (los tres servicios)

Función pura `resolver(expresion, D)` en cada servicio (Java, TypeScript y PHP), con las mismas pruebas, usando D = 2026-10-28:

| Expresión | Resultado |
|---|---|
| `D-120` | `2026-06-30` |
| `D+18` | `2026-11-15` |
| `M-3` | `2026-07` (para `planilla.periodo` se guarda `2026-07-01`) |
| `M-1/09 10:00` | `2026-09-09T14:00:00Z` |
| `D-2 11:00` | `2026-10-26T15:00:00Z` |

Expresiones mal formadas o días fuera de 2–27 → error al cargar (no se adivina).

## services/obras

- Paquete `com.constructora.obras.semilla` (infraestructura; el dominio no lo conoce): `SemillaRunner` (`ApplicationRunner` con `@Profile("semilla")`), `FechaRelativa` y los registros del archivo de datos.
- Datos en `src/main/resources/semilla/obras.json`: obras (con la copia del contrato y `contrato_id`), partidas, insumos, planillas con sus líneas (solo las cantidades; montos y totales se calculan), fotos y fotos adjuntas.
- `application-semilla.yaml`: `spring.main.web-application-type: none` (no ocupa el puerto 8081 aunque Obras esté corriendo), consumidores de RabbitMQ con `auto-startup: false`, publicador del outbox desactivado por propiedad, `semilla.fecha: ${SEMILLA_FECHA:}` y `semilla.modo: cargar` (o `recargar`).
- Carga en una transacción con `JdbcTemplate` e `INSERT … ON CONFLICT (id) DO NOTHING` (o la clave primaria compuesta en `insumo_previsto`, `linea_planilla` y `planilla_foto`). Los montos de las líneas y los totales de la planilla se calculan con la clase de dominio `Planilla` (o su función de cálculo), para no duplicar la regla.
- Modo `recargar`: `TRUNCATE … CASCADE` de todas las tablas del negocio (no `flyway_schema_history`) y luego carga.
- Al terminar, registra el resumen y cierra el proceso (`SpringApplication.exit`).
- Guarda: se niega si el perfil `prod` está activo o si el host de `spring.datasource.url` no es local.

## services/finanzas

- `database/seeders/DatosPruebaSeeder.php` con los datos en `database/seeders/datos/finanzas.json`: contratos, reservas y cobros. Si existe `ProveedorSeeder` (201), lo llama primero.
- Calcula: `numero` del cobro por año de `emitido_en` en orden de emisión; `estado` = `VENCIDO` si `vence_en` < D. El saldo disponible no se guarda (Finanzas lo calcula al leer: monto − cobros − reservas `RESERVADA`) y el correlativo de la 008 sigue solo, porque toma el mayor número del año.
- Inserta con `insertOrIgnore` (o `upsert` sin columnas a actualizar) dentro de `DB::transaction`.
- Comando `php artisan datos-prueba:vaciar`: vacía todas las tablas del negocio (no `migrations`).
- Guarda: se niega con `APP_ENV=production` o si `DB_HOST` no es local.

## services/materiales

- Carpeta `src/semilla/`: `main.ts` (crea un contexto con `NestFactory.createApplicationContext(SemillaModule)`; `SemillaModule` importa solo la configuración y los esquemas de Mongoose, sin HTTP ni mensajería), `fecha-relativa.ts`, `cargar-semilla.ts`, `vaciar.ts` y `materiales.json` (catálogo, `obra_acceso`, mínimos, movimientos, cierres).
- Scripts en `package.json`: `semilla` y `semilla:vaciar`.
- En una transacción de MongoDB (sesión del *replica set*): *upsert* con `$setOnInsert` por `_id`. Los movimientos se insertan en orden de fecha (ingresos antes que salidas el mismo día); `periodo`, `supera_stock` y `stock_obra.cantidad` se calculan al recorrerlos; `cerrado` sale de los cierres. La carga **falla** si el estado final de algún stock no coincide con la tabla de la sección 9 del documento (protege contra errores al copiar).
- Guarda: se niega con `NODE_ENV=production` o si la URL de MongoDB no es local.

## infra

- **Keycloak:** en el JSON del realm, los 9 usuarios con el `id`, nombre, apellido y correo de la sección 3: los 8 de la 001 y `demo1` (roles `residente` y `cliente`, contraseña `Prueba123!`).
- **Fotos:** `semilla/fotos/generar-fotos.ps1` (System.Drawing) y las 10 imágenes generadas en `semilla/fotos/{obraId}/{fotoId}.jpg`, subidas al repo.
- **Cliente S3:** las fotos van al bucket S3 de desarrollo en AWS (`docs/entorno-local.md`, «Archivos en desarrollo»). Para subir y borrar fotos se usa la imagen oficial de AWS CLI `amazon/aws-cli:2.38.0` (versión publicada en Docker Hub el 13/10/2026, verificada el 28/10/2026) como servicio `s3-cli` en Docker Compose (perfil `herramientas`, con `semilla/fotos` montada de solo lectura y las credenciales del usuario IAM de desarrollo del `.env` de infra en `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` y `AWS_DEFAULT_REGION`). Carga: `aws s3 sync /semilla/fotos s3://$S3_BUCKET/fotos`. Vaciado: `aws s3 rm s3://$S3_BUCKET/fotos --recursive` (solo el prefijo `fotos/` de las semillas). La guarda contra producción rechaza cualquier bucket cuyo nombre no empiece con `supervision-dev-`.
- **RabbitMQ (solo en `recargar`):** vacía las colas de la plataforma que existan (`obras`, `materiales`, `finanzas`, `ia`, `n8n.*`, `plataforma.fallidos`) con la API HTTP del panel (`DELETE /api/queues/%2F/{cola}/contents`).
- **Scripts** `semilla/semilla.ps1`, `semilla/semilla.sh`, `semilla/recargar.ps1`, `semilla/recargar.sh` con los pasos de la sección 12 del documento. Variables nuevas en `.env.example`: `SEMILLA_PERMITIDA=si`, `OBRAS_DIR`, `MATERIALES_DIR`, `FINANZAS_DIR` (por defecto las carpetas hermanas). En Windows, Finanzas se ejecuta con el PHP de Herd y los proyectos de Node con Node 24.
- **README:** sección «Datos de prueba» (qué hay, cómo cargar, cómo recargar, cuándo cambian los indicadores).

## Orden

Servicios (Obras, Finanzas, Materiales; independientes entre sí) → infra (Keycloak, fotos y scripts). Se implementa después de la 009, cuando existen todas las tablas del sistema base.

## Pruebas

- Los tres servicios: resolvedor de fechas con la tabla de arriba; cargar dos veces con D fija → mismos conteos; vaciar deja vacías las tablas del negocio y conserva el historial de migraciones; la guarda rechaza producción y base no local; ninguna fila en `outbox_evento`.
- Obras (IT con Testcontainers, D = 2026-10-28): `GET /obras` con token de gerente → avance, plazo, diferencia y `enRiesgo` de la sección 7; `GET /planillas/{id}` → subtotal, anticipo, retención y neto de las 5 planillas; `GET /obras/{id}/material-previsto?periodo=2026-09` de la obra 1 → 4.800 kg de `FIE-12` en P-03; visibilidad de residente1 (obra 1), residente2 (obra 2), demo1 (obra 3 como residente; obra 2 como cliente), cliente1 (obras 1 y 3) y cliente2 (ninguna).
- Finanzas (Feature): saldos de la sección 8; números `COB-2026-0001` a `0003` con D = 2026-10-28 y correlativo por año con D = 2027-01-20 (`COB-2026-0001`, `COB-2026-0002` y `COB-2027-0001`); estados `VENCIDO`/`PENDIENTE`; `GET /cobros/resumen` → 1 vencido por 290.134,80 y 2 por vencer por 771.629,60.
- Materiales (mongodb-memory-server en *replica set*): stock y estado de las 14 filas; solo la salida 20018 con `supera_stock`; `GET /obras/{id}/consumos?periodo=2026-09` de la obra 1 → 6.000 kg de `FIE-12` en P-03; movimientos de periodos cerrados con `cerrado = true`; `GET /stock/resumen` → 1 material bajo en la obra 2.
- Manual (infra): `semilla` dos veces, revisar criterios 1 a 14 de `requisitos.md` en el ERP, el portal y la app; aprobar la planilla 3 de la obra 1 en el portal; `recargar` y comprobar que vuelve al estado inicial.

## Cambios a contratos y datos

No cambia ningún contrato REST, GraphQL ni de eventos, ni ninguna tabla. Para integrar en los documentos compartidos (no se editaron en esta especificación):

- `docs/plan.md`: fila de la funcionalidad 011 (infra, obras, materiales, finanzas), después de la 009.
- `CLAUDE.md` (raíz), «Documentos transversales»: agregar `docs/datos-prueba.md`.
- `docs/convenciones.md`: en «Puertos» o en una sección nueva, la variable `SEMILLA_PERMITIDA` y la regla «los datos de prueba solo se cargan en desarrollo».
- `docs/specs/001-iniciar-sesion/diseno.md`: los usuarios de prueba tienen `id` fijo y nombres según `docs/datos-prueba.md`, y se agrega `demo1` (roles `residente` y `cliente`) para la prueba manual del SSO entre ERP y portal.
- `docs/stack.md` y `docs/entorno-local.md`: en infra, la imagen `amazon/aws-cli:2.38.0` (servicio `s3-cli`, perfil `herramientas`) para la semilla.
- `infra/docs/specs/503-reportes-voz/tareas.md` y `infra/docs/specs/502-agentes-erp/tareas.md`: partir de los datos de prueba de la 011 y su ampliación por la 401.
