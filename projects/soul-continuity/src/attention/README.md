# Política de atención y registro de demanda (SE-490)

Librería TypeScript pura: sin red, sin LLM, sin dependencias y sin reloj propio (el minuto entra como argumento). Porta `soul-atencion` de Labs y la adapta a SE-490.

- Modos `DISPONIBLE`, `FOCO`, `DESCANSO` y `FUERA` con ventana; sin modo declarado no hay disponibilidad implícita.
- Presupuesto de avisos por ventana. Lo que excede va al siguiente resumen.
- Alertas declaradas con tope propio fuera del presupuesto (3 por defecto). Por encima del tope, un solo mensaje «hay N alertas más» (`drenarAlertasAgrupadas`; si la entrega falla, `reencolarAlertasAgrupadas`). En `FOCO`, `DESCANSO` y `FUERA` solo pasan las marcadas para el modo activo; las demás se difieren.
- Resúmenes de inicio y de cierre a la hora fijada (`resumenesDebidos`), una vez cada uno.
- Registro de demanda: `ledger.porQue(id)` y `ledger.queAhorro()`. No guarda nada de la persona.
- Ningún texto ni modelo eleva la urgencia; el silencio no es respuesta. En la ruta web (`ruta: 'WEB'`) ninguna regla produce alerta, sea o no de remitente: se degrada a aviso (`degradadaAAviso`). Un nivel fuera de N1..N4 o un canal mal configurado redactan el texto.

## Ejecutar

```bash
cd projects/soul-continuity
node --experimental-strip-types --test tests/attention/*.test.ts      # tests
node --experimental-strip-types tests/attention/evals.ts              # 228 evals (120 de Labs + 108 de AC-4b)
node --experimental-strip-types tests/attention/bench/mutaciones.ts   # 41 mutantes (18 de Labs + 18 de AC-4b + 5 del puente y la redacción)
tsc -p src/attention/tsconfig.json                                    # strict, sin emitir
```

Node ≥ 22.6. Los tests y las evals usan solo operadores sintéticos.

## Límites conocidos

- La bandeja y el registro viven en memoria; el estado persistible (`estadoATexto`) guarda modo, vetos, PARA, contadores, ids de eventos ya tratados, alertas agrupadas pendientes y último resumen emitido. Nunca guarda contenido.
- Un resumen que sale más de 60 min después de su hora no se emite (`TOLERANCIA_RESUMEN`); sus pendientes siguen en la bandeja para el siguiente.
- El tope de alertas cuenta por instancia de ventana; fuera de toda ventana, por día local.
