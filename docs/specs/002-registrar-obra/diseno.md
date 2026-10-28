# 002 · Diseño

## Flujo

```
mf-obras --GraphQL registrarObra--> gateway --POST /obras--> Obras
Obras: guarda obra (SIN_CONTRATO) + partidas + insumos + outbox(ObraRegistrada)
Obras --evento.obras.ObraRegistrada--> Finanzas  (crea contrato)
                                   \--> Materiales (guarda obra_acceso)
Finanzas --evento.finanzas.ContratoRegistrado | ContratoRechazado--> Obras
Obras: guarda contrato_id y pasa a EN_EJECUCION (o guarda motivo_rechazo)
mf-obras: consulta la obra cada 2 s (máx. 30 s) mientras esté SIN_CONTRATO sin motivo
```

## Obras

- Endpoint `POST /obras` (rol `admin`). Cuerpo y respuesta en `docs/contratos.md` de Obras.
- Validaciones (422 con `codigo`): `PRESUPUESTO_NO_COINCIDE`, `CODIGO_PARTIDA_REPETIDO`, `INSUMO_REPETIDO`, `CONTRATO_INVALIDO` (porcentajes), y 400 para formato.
- No valida que los usuarios existan en Keycloak ni que los materiales existan (los elige el formulario de listas reales); guarda los ids.
- Dominio: agregado `Obra` con `Partida` e `InsumoPrevisto`; la regla del presupuesto vive en `Obra.registrar(...)`.
- Tabla `obra`: agregar columna `motivo_rechazo_contrato text null`.
- Consume `ContratoRegistrado` → `obra.contrato_id = contratoId`, `estado = EN_EJECUCION`. Consume `ContratoRechazado` → `motivo_rechazo_contrato = motivo`. Ambos idempotentes con `mensaje_procesado`.
- `GET /obras/{id}` devuelve `estado` y `motivoRechazoContrato`.

## Finanzas

- Consume `ObraRegistrada`: valida los datos del contrato; si son válidos crea `contrato` con `saldo_disponible = monto` y publica `ContratoRegistrado`; si no, publica `ContratoRechazado` con el motivo, uno de estos textos (si fallan varias reglas, se unen con «; »): «El monto del contrato debe ser mayor a 0», «El plazo del contrato debe ser mayor a 0 días», «El anticipo y la retención deben estar entre 0 % y 100 %», «El anticipo más la retención deben sumar menos de 100 %». Administración lo ve en el detalle de la obra (criterio 9) y en el aviso «Contrato rechazado» (010). Idempotente por `id` del mensaje y por `contrato.obra_id` único.
- Consumidor: comando de Artisan `php artisan mensajeria:consumir` (proceso largo) y publicador del outbox `php artisan mensajeria:publicar` (cada segundo).

## Materiales

- Consume `ObraRegistrada` y guarda `obra_acceso` (ver `docs/datos.md` de Materiales). Idempotente.

## Gateway

- Consulta `usuarios(rol: Rol!): [Usuario!]!` (rol `admin`): llama a la API de administración de Keycloak con el cliente `gateway` (`GET /admin/realms/supervision/roles/{rol}/users`) y devuelve `id`, `nombre`, `correo`.
- Mutación `registrarObra(entrada: RegistrarObraEntrada!): Obra!` → `POST /obras`, reenvía errores con su `codigo`.
- Consulta `materiales(soloActivos: true)` ya existe por la 003; si la 003 no está hecha, el paso 3 permite registrar partidas sin insumos.

## mf-obras

- Ruta `/obras/nueva` con un formulario reactivo de 3 pasos (`ReactiveForms`), resumen del presupuesto calculado en vivo y mensajes de error por campo según `extensions.codigo`.
- Tras guardar, navega a `/obras/{id}`; el detalle muestra «Registrando contrato…» y consulta cada 2 s hasta `EN_EJECUCION` o rechazo.

## Pruebas

- Obras: regla del presupuesto (coincide, no coincide, tolerancia), códigos repetidos, 403 para no admin, publicación de `ObraRegistrada` en el outbox, consumo de `ContratoRegistrado` y `ContratoRechazado` (incluido mensaje repetido).
- Finanzas: contrato válido → `ContratoRegistrado`; inválido → `ContratoRechazado`; mensaje repetido no crea dos contratos.
- Materiales: `ObraRegistrada` crea `obra_acceso`; repetido no duplica.
- Gateway: `registrarObra` mapea errores del servicio a `extensions.codigo`.
- mf-obras: cálculo del total y validación de la diferencia.
