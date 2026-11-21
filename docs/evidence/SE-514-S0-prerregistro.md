# SE-514 S0 — Prerregistro de la medición de partida

Commiteado antes de ejecutar la medición de esta ronda. Cualquier cambio posterior va a «Desviaciones» del informe (`SE-514-S0-medicion.md`), nunca aquí.

## Qué se mide (AC-1)

Cuántas peticiones de atención llegan a la persona por día y por fuente, y cuántas se duplican. Solo cifras agregadas: ningún texto de pregunta, nombre de proyecto ni contenido de sesión sale del proceso.

- **Ventana:** 14 días locales, del 2026-11-08 al 2026-11-21, ambos incluidos.
- **Instrumento:** el script de medición del primer intento de S0 (en Savia Labs, privado), sin cambios. SHA-256 de `medir.py`: `5241e83176ca486d5b5acc388b6a66a38c17fe78850942d3cef1afe7cde2888b`; de sus pruebas, `test_medir.py`: `954e8cb2a7fb625688445f6ecf7b28d23236fc800c57d42bad4ba9e8eb0a754b`. Commit de Labs que lo introduce: `32e0a9483b32`. Commit de Savia leído: `7321af6b7e36` (`origin/main`).
- **Por qué otra ronda.** La primera (2026-11-10) solo tenía el registro del reconciliador de PRs desde el 2026-11-04 (7 de 14 días). Su propio informe pedía repetirla con 14 días completos antes de fijar la línea base de AC-7.

## Criterio de duplicado (el del instrumento, sin cambios)

- Identidad de una petición = (objeto, permiso). PR: objeto `repo#n`, permiso `merge` o `review`. Pregunta interactiva o pendiente: objeto = hash del contenido, permiso `decision`.
- Dos permisos distintos sobre el mismo objeto no son duplicado (AC-4).
- Por día y por identidad con *n* registros desde *s* fuentes: 1 distinta, *n−1* duplicados, *s−1* entre fuentes, *n−s* de la misma fuente.
- Una fuente que no se puede leer es **no verificada**, nunca cero.

## Línea base sin agente (B0)

La pregunta de la refutación del 2026-11-20 es si la cola aporta algo que no dé ya un procedimiento trivial. B0 es **el propio recuento**: agrupar por (objeto, permiso) las fuentes existentes, sin agente, sin modelo y sin interfaz. Si B0 ya separa lo distinto de lo repetido, la cola solo se justifica por lo que B0 no hace: decir las cinco cosas de cada petición, dejar en `DEFER` lo que vence y no unir permisos distintos.

## Dominio piloto

**Preguntas de agentes y PRs que esperan a la persona durante una orquestación de varios agentes.** Son las dos fuentes con datos en la primera ronda (139 preguntas y 161 PRs en 14 días) y las dos de las escenas 1, 3 y 5. Los casos están en `projects/soul-continuity/tests/attention/fixtures/piloto-s0.json` y se ejecutan contra el módulo existente (`projects/soul-continuity/tests/attention/piloto-s0.test.ts`).

| Id | Tipo | Qué es | Comportamiento exigido |
|---|---|---|---|
| C1 | caso | Dos agentes preguntan la misma decisión sobre el mismo fichero (escena 1) | Una tarjeta; una respuesta resuelve las dos |
| C2 | caso | Permiso obligatorio de publicar a las 23:30, en descanso (escena 3) | No se enseña en descanso; el trabajo espera; aparece en la ventana siguiente; nada se ejecuta |
| C3 | caso | Respuesta a una tarjeta cuya versión cambió (escena 5) | Rechazada con `VERSION_CAMBIADA` y vuelve a enseñarse la actual |
| X1 | contraejemplo | Dos permisos distintos con el mismo tema | Parecen una pregunta: **no** se unen (AC-4) |
| X2 | contraejemplo | El reconciliador emite el mismo estado de una PR en cada pasada | Parecen muchas peticiones: es **una** (misma fuente y mismo id) |
| X3 | contraejemplo | Permiso sin respuesta al vencer | Parece que el silencio consiente: queda en `DEFER`, sin efecto y con una sola repregunta por ventana (AC-3) |

## Condiciones de NO-GO, fijadas antes de medir

Se aplican en orden. El resultado de S0 es una de cuatro decisiones, y solo la operadora decide qué se hace con ella.

1. **NG-1 — Sin línea base no hay AC-7.** Si dos o más de las siete fuentes de la spec siguen sin registro legible, AC-7 queda **NO MEDIBLE**: S2 no puede declarar que reduce interrupciones. Decisión: **MORE_EVIDENCE** para AC-7.
2. **NG-2 — La duplicación no justifica la cola.** Si, sin las re-emisiones del reconciliador, los duplicados entre fuentes son menos del 5 % de las peticiones distintas y las preguntas de agentes repetidas el mismo día son 0, el argumento «tres agentes preguntan lo mismo» no tiene datos. Decisión: **SIMPLIFY** — la cola se justifica por `DEFER`, caducidad y el no unir permisos, no por deduplicar; no se construye nada más para deduplicar.
3. **NG-3 — B0 iguala a la cola.** Si en los fixtures la cola no hace nada que B0 no haga (mismas peticiones distintas y ninguna de las garantías C2, C3, X1, X3), la vista se retira por su criterio de retirada. Decisión: **NO_GO** para S1.
4. **NG-4 — Integrado sin consumidor.** Si el módulo de S1/S2 no tiene ningún llamante fuera de sí mismo y de sus pruebas, se informa como «integrado, no operativo» y no se abre S3 hasta conectarlo (regla «conectar antes de construir»).
5. **GO** solo si no se cumple ninguna de las anteriores.

## Lo que no se cuenta como prueba

- «0 de N» se informa como «0 de N en esta muestra», nunca como riesgo cero.
- Las esperas falsas (una pregunta que una lectura barata habría resuelto, el análogo en la cola de un falso bloqueo) no tienen registro: se dan como **no verificadas**, no como cero.
- Una PR creada cuenta como petición de merge a la persona; es una sobrecuenta conocida del instrumento.
