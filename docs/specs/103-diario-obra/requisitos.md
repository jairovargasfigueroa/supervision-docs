# 103 · Registrar entrada del diario de obra

**Estado:** aprobado (30/10/2026) · **Capa:** 1 · **Puntos del ingeniero:** 7 (registro de campo sin señal); el diario lo usa el agente de Seguimiento de obras (punto 5, capa 5) · **Proyectos:** services/obras, services/sincronizacion, app-obra · **Depende de:** 101

## Historia

Como **maestro de obra** quiero anotar cada día el clima y lo que pasó en la obra, aunque no haya señal, para dejar constancia de lo ocurrido; esa información la usa luego el agente de Seguimiento de obras.

## Criterios de aceptación

1. CUANDO el maestro abre una de sus obras y pulsa «Diario de obra», ENTONCES ve el formulario del día de hoy con clima (Soleado, Nublado, Lluvia leve, Lluvia fuerte) y texto libre (obligatorio, de 10 a 2000 caracteres) (valores de clima: decisión del equipo).
2. La fecha es la de hoy en hora de La Paz; puede elegir uno de los 7 días anteriores si olvidó registrarlo (decisión del equipo). No puede elegir días futuros.
3. CUANDO guarda, ENTONCES la entrada se guarda en el celular con su UUID y se envía por la cola de la 101 (también sin señal), con los mismos estados en «Pendientes de envío».
4. Una sola entrada por obra y por día: SI ya existe una entrada de ese día (en el celular o en el servidor), ENTONCES la app no deja crear otra y muestra «Ya registraste el diario del dd/mm».
5. Mientras la entrada no se envió, el maestro la puede corregir; una vez enviada ya no se edita.
6. SI la misma entrada se envía dos veces, ENTONCES queda registrada una sola vez.
7. La pantalla muestra las entradas de los últimos 30 días de la obra: las que vienen del servidor y las que todavía están pendientes (marcadas «Sin enviar»).
8. SI la obra no está en ejecución, o la fecha es futura o anterior al inicio de la obra, ENTONCES el servidor la rechaza y la entrada queda «Rechazada» con el motivo.
9. SI llega al servidor una entrada distinta para una obra y un día que ya tienen entrada (por ejemplo, desde otro celular), ENTONCES se rechaza con «Ya existe una entrada del diario para ese día».
10. Solo el `maestro` asignado a la obra registra entradas. El `residente` asignado, `admin` y `gerente` las pueden consultar por la API; el cliente no.

## Fuera del alcance

Pantalla del diario en el ERP (lo consulta el agente en la capa 5, herramienta MCP `buscar_diario`); fotos dentro del diario; editar o borrar entradas enviadas; asistencia de trabajadores.
