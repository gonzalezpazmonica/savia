# Política de atención y registro de demanda (SE-490)

Librería TypeScript pura: sin red, sin LLM, sin dependencias y sin reloj propio (el minuto entra como argumento). Porta `soul-atencion` de Labs y la adapta a SE-490.

- Modos `DISPONIBLE`, `FOCO`, `DESCANSO` y `FUERA` con ventana; sin modo declarado no hay disponibilidad implícita.
- Presupuesto de avisos por ventana. Lo que excede va al siguiente resumen.
- Alertas declaradas con tope propio fuera del presupuesto (3 por defecto). Por encima del tope, un solo mensaje «hay N alertas más» (`drenarAlertasAgrupadas`; si la entrega falla, `reencolarAlertasAgrupadas`). En `FOCO`, `DESCANSO` y `FUERA` solo pasan las marcadas para el modo activo; las demás se difieren.
- Resúmenes de inicio y de cierre a la hora fijada (`resumenesDebidos`), una vez cada uno. Lo que solo informa (avisos, alertas) sale una vez: lo avisado al momento no entra y lo que ya salió en un resumen no se repite. Lo que pide una decisión vuelve en cada resumen hasta que la persona responde.
- Registro de demanda: `ledger.porQue(id)` y `ledger.queAhorro()`. No guarda nada de la persona.
- Ningún texto ni modelo eleva la urgencia; el silencio no es respuesta. En la ruta web (`ruta: 'WEB'`) nada autentica, venga con el origen que venga: ninguna regla produce alerta, sea o no de remitente: un aviso con regla se degrada a aviso con presupuesto (`degradadaAAviso`). Un permiso por la web se bloquea como ilegítimo y lo demás (decisiones, aprobaciones, reintentos, avisos sin regla) se registra sin pedir nada, lleve o no código de regla. Una ruta que el puente no conoce se trata como web. El puente da `DESCONOCIDO` al remitente `unknown`, que tampoco autentica.
- Detener (`PARA`) y vetar se aceptan de la persona o de un agente autenticado. Una alerta llega aunque esté `PARA`, pero no si su objetivo está vetado o su contexto ha vencido: se registra. Un nivel fuera de N1..N4 o un canal mal configurado redactan el texto.

## Ejecutar

```bash
cd projects/soul-continuity
node --experimental-strip-types --test tests/attention/*.test.ts      # tests
node --experimental-strip-types tests/attention/evals.ts              # 228 evals (120 de Labs + 108 de AC-4b)
node --experimental-strip-types tests/attention/bench/mutaciones.ts   # 57 mutantes (18 de Labs + 18 de AC-4b + 5 del puente y la redacción + 16 de las revisiones)
tsc -p src/attention/tsconfig.json                                    # strict, sin emitir
```

Node ≥ 22.6. Los tests y las evals usan solo operadores sintéticos.

## Límites conocidos

- La bandeja y el registro viven en memoria; el estado persistible (`estadoATexto`) guarda modo, vetos, PARA, contadores, ids de eventos ya tratados, alertas agrupadas pendientes y último resumen emitido. Nunca guarda contenido.
- Un resumen que sale más de 60 min después de su hora no se emite (`TOLERANCIA_RESUMEN`); sus pendientes siguen en la bandeja para el siguiente.
- El tope de alertas cuenta por instancia de ventana; fuera de toda ventana, por día local.
- Un aviso degradado desde la web gasta el presupuesto común, como cualquier aviso (AC-4c: «solo un aviso»). Quien suplante por la web a un remitente con regla puede agotar el presupuesto de una ventana y aplazar al resumen las preguntas de agentes autenticados; no las pierde ni concede nada. Un presupuesto aparte para la web es una decisión de diseño pendiente de la spec.
- Los ids ya tratados (`preguntadas`) no se purgan: el estado crece con cada evento atendido. Purgarlos exige saber cuándo deja de poder repetirse un evento, y eso lo decide quien integre el transporte.
- Una decisión diferida por `PUEDE_ESPERAR` no se marca como tratada: su deduplicación vive en la bandeja, que está en memoria. Tras un reinicio, si vuelve a llegar, se encola de nuevo; es lo que evita perderla, porque la bandeja anterior ya no existe.
- Una hora de franja fuera de 0–23 / 0–59 da una franja vacía.
