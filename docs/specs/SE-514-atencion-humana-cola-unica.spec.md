---
status: APPROVED
priority: P1
developer_type: agent-team
created: 2026-11-09
author: Savia
phase: D
risk: L2
human_surface: true
depends_on: [SE-490, SE-504]
related_specs: [SE-431, SE-458, SE-459, SE-471, SE-488, SE-490, SE-492, SE-504, SE-507, SE-512, SE-513, SE-515]
origin: "Tesis Savia Viva R6 (2026-11-09), candidata C2 con sus antecedentes R4 y R5. Original e informe en Savia Labs. Contrastada con main e59b795ee."
timeline:
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "PROPOSED"
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "APPROVED"
---

# SE-514 — Atención humana: una sola cola de preguntas, con su porqué

## Problema (leído en las specs de main e59b795ee, 2026-11-09)

La atención de la persona es el recurso más escaso del sistema y hoy se pide desde siete sitios que no se conocen entre sí.

| Fuente de peticiones | Dónde está definida | Qué cubre |
|---|---|---|
| PRs esperando revisión | SE-458 (tope, lotes, prioridad) | Solo PRs |
| Tarjeta de aprobación | SE-459 S1, SE-488 R1 | Qué se aprueba y por qué, por aprobación |
| Avisos de Soul | SE-490, «Política de atención» | Agrupar, aplazar y «¿por qué me avisaste?», solo para eventos de Soul |
| Relevo nocturno | SE-471 (digest, tope 7) | Solo la noche |
| Pendientes de la mañana | SE-512 R6 | Solo lo que el sprint nocturno no pudo hacer |
| «Esperan algo de ti» | SE-504 | Lista en la app |
| Avisos de runs | SE-507 punto 9 | Runs sin señal |

Faltan tres cosas, y ninguna spec las tiene:

1. **Una cola única.** Las preguntas interactivas de los agentes y los diálogos de permiso no están en ninguna de esas listas. Tres agentes pueden preguntar lo mismo a la vez.
2. **Aplazar una pregunta de un agente sin que el silencio cuente.** SE-490 lo garantiza para avisos; para una pregunta que bloquea un trabajo no hay regla. Una pregunta nocturna sin respuesta ya congeló una orquestación cuatro horas.
3. **Saber qué ocupa al sistema.** No hay una vista que diga qué demandas están abiertas, cuáles se están ignorando, por qué y cuándo se revisan.

Savia Viva R6 añade un cuarto caso: cuando una lección obliga a revisar algo antes de actuar (SE-515, fuerza `review_required`), esa revisión es otra petición de atención y tiene que entrar por la misma cola.

## Qué decide esta spec

- **Una cola, no una bandeja nueva.** La cola es una vista derivada sobre las fuentes de la tabla más las preguntas de agentes. Se muestra en la app de SE-504 y la gobierna la política de atención de SE-490. No se crea otro buzón ni otro planificador. Si la lista «Esperan algo de ti» de SE-504 ya cubre la necesidad con las fuentes unidas, no se construye nada más (criterio de retirada).
- **Cada petición dice cinco cosas:** qué se pide, por qué ahora, qué alternativa tiene el sistema si no contestas, qué pasa si se aplaza y hasta cuándo vale. Cuando viene de una lección: qué regla aplica y qué prueba falta.
- **El silencio no aprueba nada.** Una pregunta sin respuesta deja el trabajo en espera (`DEFER`). No se repregunta en bucle ni se toma una opción por defecto que tenga efectos.
- **Antes de preguntar, mirar.** Si una lectura permitida y barata resuelve la duda, se hace esa lectura y no se pregunta.
- **Agrupar sin mezclar permisos.** Dos preguntas sobre lo mismo se unen. Dos permisos distintos nunca se unen en una sola respuesta.
- **Lo crítico no se silencia.** Los modos de foco y descanso retrasan lo que puede esperar. Una autorización obligatoria o una parada no se ocultan: se muestran cuando la política de SE-490 lo permite y el trabajo espera mientras tanto.
- **La respuesta tiene identidad.** Una decisión humana se registra contra la pregunta concreta y la versión de lo que se enseñó. Una respuesta a una tarjeta caducada no vale.

## Lo que he entendido

### Escenas
1. Son las 10:05 y estás concentrada. Dos agentes necesitan saber si pueden tocar el mismo fichero y un tercero quiere confirmar un nombre. En el móvil ves una sola tarjeta: «Dos agentes van a editar el mismo fichero. ¿Quién va primero?», y debajo «1 pregunta más que puede esperar a las 12:00».
2. Abres la app y preguntas «¿en qué estás?». Savia responde: «Cuatro trabajos en marcha. Dos preguntas esperándote, una desde hace 40 minutos. He dejado de lado el aviso de dependencias porque no bloquea nada; lo reviso al cerrar la tarde.»
3. Son las 23:30 y duermes. Un agente necesita un permiso para publicar. No suena nada. El agente queda en espera y sigue con otra tarea. A las 8:00 ves: «Anoche quedó en espera la publicación del informe. Necesita tu permiso. Si dices que no, el informe se queda en borrador.»
4. Savia te pregunta algo y añade: «Te lo pregunto porque la última vez que se publicó sin comprobar los consumidores se rompió uno. Falta la comprobación de compatibilidad. Puedo ejecutarla yo y volver con el resultado.»
5. Contestas a una tarjeta de ayer. Savia responde: «Esa pregunta caducó: el cambio ya no es el mismo. Te la vuelvo a enseñar con lo actual.»

### Palabras de la persona
«Actualiza y mejora todo el roadmap y specs de Savia en base a esta tesis y posibles mejoras, optimizaciones o podas necesarias que puedas encontrar.» — 2026-11-09, mensaje de la operadora que encarga esta repriorización.

### Qué SÍ será
- Una lista única de lo que espera tu respuesta, con el motivo de cada cosa.
- Trabajos que esperan sin inventarse tu respuesta.
- Una respuesta honesta a «¿en qué estás?».

### Qué NO será
- No es otra bandeja de entrada ni otra app.
- No decide por ti cuando no contestas.
- No te interrumpe por cada lección que el sistema recupera.
- No escucha el ambiente ni infiere cómo estás (SE-492).

### Confirmación
- fecha: 2026-11-09
- respuesta: «Confirmo las escenas». Opción elegida por la operadora en la pregunta interactiva del 2026-11-09 en la que se le enseñaron estas escenas literalmente.

## Slice S0 — Prototipo navegable
- prototipo: `docs/specs/assets/SE-514-prototipo.html` — pantalla de la cola en la app de SE-504 con las cinco escenas sobre datos de ejemplo, usable en el móvil.

### Confirmación del prototipo
- fecha: 2026-11-10
- respuesta: «Confirmo (Recommended)». Opción elegida por la operadora en pregunta interactiva el 2026-11-10, con el prototipo delante.

## Slices

| Slice | Entrega | Entrada |
|---|---|---|
| S0 | Prototipo confirmado y medición de partida: cuántas peticiones por día llegan hoy por cada fuente y cuántas se duplican | Escenas confirmadas |
| S1 | Vista de cola única de solo lectura sobre las fuentes existentes, con las cinco cosas de cada petición | S0 confirmado; SE-504 con la lista «Esperan algo de ti» |
| S2 | Preguntas de agentes en la cola: identificador, caducidad, `DEFER` sin respuesta, agrupación | S1; SE-513 S1 |
| S3 | Vista «en qué estoy» y peticiones que vienen de lecciones | S2; SE-515 S2 |

## Criterios de aceptación

| AC | Criterio | Slice |
|---|---|---|
| AC-1 | Medición de partida publicada por fuente, con duplicados | S0 |
| AC-2 | La cola muestra peticiones de todas las fuentes de la tabla; cada una con qué, por qué, alternativa, coste de aplazar y caducidad | S1 |
| AC-3 | **Negativo:** pregunta sin respuesta al vencer → trabajo en `DEFER`; ningún efecto ejecutado; no se repregunta más de una vez por ventana | S2 |
| AC-4 | **Negativo:** dos permisos distintos nunca aparecen como una sola respuesta | S2 |
| AC-5 | **Negativo:** respuesta a una tarjeta caducada o cuya versión cambió → rechazada y vuelta a enseñar | S2 |
| AC-6 | **Negativo:** una autorización obligatoria no se pierde en modo descanso: aparece al salir y el trabajo esperó | S2 |
| AC-7 | Tres agentes y una persona en sesiones comparables: menos interrupciones que la línea base de S0 sin retrasar ninguna decisión crítica. Si no mejora, la vista se retira | S2 |
| AC-8 | La persona puede contestar y consultar el estado con todos los agentes ocupados | S2 |
| AC-9 | «¿En qué estás?» lista demandas abiertas, ignoradas con su motivo y hora de revisión, sin exponer nada a quien no tiene acceso | S3 |
| AC-10 | Una petición nacida de una lección cita la regla y la prueba que falta, y ofrece la alternativa de ejecutarla | S3 |
| AC-11 | Prueba con una persona no técnica: entiende cada tarjeta sin ayuda | S1–S3 |

## Fuera de alcance

- La política de foco y descanso y sus umbrales (SE-490, SE-492).
- El formato de la tarjeta de aprobación (SE-459) y el recibo de aprobación (SE-488).
- Voz y escucha ambiental.
- Revisión de código dentro de la cola.

## Riesgos

- **Otra bandeja más.** Si la vista no sustituye a las listas parciales, añade ruido. Por eso S1 es de solo lectura y tiene criterio de retirada.
- **Agrupar de más.** Unir preguntas que parecen iguales puede ocultar una diferencia de permiso. AC-4 es el control.
- **Dependencia de la app.** Sin SE-504 en uso, S1 no tiene dónde mostrarse.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Vista de cola | App de SE-504 sobre Space | La misma |
| Preguntas de agentes | Pregunta interactiva del frontend | Diálogo `ask` de Space |

### Verification protocol

- [ ] La cola recoge preguntas de los dos frontends
- [ ] Tests con negativos por AC
- [ ] Probado en el dispositivo de la persona antes de pedirle nada

### Portability classification

- [x] **DUAL_BINDING**: la vista es de Space; la captura de preguntas necesita un binding por frontend.

## Aprobación

APPROVED por la operadora el 2026-11-09 por pregunta interactiva («Savia Viva + tokens y efectos»), tras confirmar las escenas cuando la spec las exige. Se formaliza al fusionar la PR (SE-488). 

## Rediseño 2026-11-20 (propuesto, pendiente de la operadora)

> Estado: **propuesto**. No cambia el `status` de la spec ni desaparca nada: lo aprueba o lo rechaza la operadora. Hasta entonces S2 sigue aparcada en la cola (`parked` de S30 en `planning-state.json`). Leído en origin/main 6d42ab1bc.

### Qué dependía de SE-513

S2 tenía como entrada «S1; SE-513 S1». SE-513 S1 aportaba la admisión duradera: una entrada persistida con dueño, deduplicada, que sobrevivía a un reinicio, en una transacción SQLite de la cola de SE-075. SE-513 se retiró el 2026-11-14 con su código (`docs/propuestas/LOG.d/SE-513-RETIRED.md`, #1582). Sin ella, S2 no tiene dónde guardar una pregunta de un agente con su identificador, su caducidad y su respuesta.

### Fuente de verdad que la sustituye: el registro de runs

| Fuente | Dónde | Qué tiene hoy | Qué le falta para S2 |
|---|---|---|---|
| Registro de runs (SE-349) | `scripts/savia-runs.sh:25` (`data/agent-runs-ledger.jsonl`, fuera de git) | Un registro por run: `run_id`, `mode`, `agent`, `task`, `activity_state` (`spawning`, `active`, `waiting_input`, `blocked`, `exited`; `:217`), `is_terminated`, `pr`. Escritura con cerrojo (`:766-818`, aplicado a `start`, `state`, `pr`, `finish`, `cost` en `:819-821`) y reescritura atómica por renombrado (`:72-106`). El estado visible se **deriva al leer**, nunca se guarda (`:108-133`): `waiting_input` y `blocked` dan la columna `needs_input` | La pregunta en sí: identificador, qué se pide, caducidad, versión de lo enseñado, permiso, respuesta |
| Bus de mensajes (SE-347) | `scripts/agent-messaging.sh` (`~/.savia/msg/ledger.jsonl` e inboxes) | `id`, `ts`, `from`, `to`, `role`, `message`, `status`, `ack_at` | Escribe dos ficheros sin cerrojo ni transacción (es el punto 1 del Problema de SE-513). No sirve como fuente de verdad de una pregunta que bloquea |
| Peticiones de Pulse (SE-518 S1) | Contrato `peticiones.json` en SE-518 «Contratos Pulse ↔ Soul» | Ya define las cinco cosas de esta spec por petición | Sin implementar: ningún script del repo lo escribe hoy. Es fuente de S1, no de S2 |

Se elige el registro de runs: ya es duradero, ya tiene cerrojo, ya modela «este trabajo espera a la persona» (`needs_input`) y su regla «derivar al leer» encaja con «el silencio no aprueba nada». No se crea almacén nuevo.

### S2 rediseñado — preguntas de agentes en el registro de runs

- **Preguntar.** Un subcomando nuevo de `savia-runs.sh`, bajo el mismo cerrojo, añade al registro del run una pregunta: `id` estable, `asked_at`, `expires_at`, `version` (hash de lo que se enseña), `permission` (qué autoriza la respuesta, o `none`), y las cinco cosas (qué, por qué ahora, alternativa, coste de aplazar, caducidad). Pone `activity_state` en `waiting_input`. Una segunda pregunta con el mismo `id` no crea otra: se informa como repetida.
- **Contestar.** Otro subcomando registra la respuesta con `id`, `version` y canal. Si el `id` no existe, la pregunta caducó o la `version` no coincide, se rechaza y se vuelve a enseñar la actual (AC-5).
- **Silencio.** `DEFER` no se escribe: se deriva al leer, como el resto de estados, cuando `now > expires_at` sin respuesta. El agente que pregunta recibe `DEFER` como salida distinta y sigue con otra tarea; ningún camino toma una opción por defecto con efectos (AC-3).
- **Agrupar.** La vista agrupa preguntas del mismo asunto; dos con `permission` distinto nunca comparten respuesta (AC-4).
- **Quién pregunta fuera de un run.** Las preguntas interactivas de la sesión principal no pasan por aquí salvo que la orquestadora registre un run. Se dice en la vista («preguntas de sesión no incluidas»).

**Entrada corregida.** S1. Sin SE-513.

**Criterios de aceptación añadidos (AC-3 a AC-8 sin cambios).**

- **AC-12 — Durabilidad sin almacén nuevo.** Una pregunta registrada sigue ahí tras matar el proceso que preguntó y reabrir la vista; un corte durante la escritura (proceso muerto antes del renombrado) deja el registro anterior íntegro, nunca uno a medias. Dos agentes que preguntan a la vez dejan las dos preguntas (con cerrojo; mutación: sin cerrojo, el test con escritores concurrentes pierde una y falla). El listado de ficheros de estado antes y después de S2 solo difiere en `data/agent-runs-ledger.jsonl`.
- **AC-13 — Caducidad derivada.** Con el reloj del test pasado `expires_at`, la vista da `DEFER` sin que nadie lo haya escrito; con el reloj antes, `needs_input`. Una respuesta con `version` vieja sale rechazada y el registro no cambia.

### Qué se pierde respecto al diseño anterior

1. **Transacción admisión–salida.** SE-513 guardaba entrada y salida en una transacción SQLite. El registro de runs reescribe el fichero entero bajo cerrojo: es atómico por escritura, no por pareja pregunta–despacho. Si el agente muere entre registrar la respuesta y actuar, la respuesta queda registrada y la acción no; la vista lo muestra como respondida y el run como no terminado.
2. **Estados de incorporación.** `APPLIED_TO_PLAN` y `UNKNOWN` de SE-513 no existen aquí: la vista dice «respondida», no «aplicada».
3. **Cobertura.** Solo preguntas de trabajos registrados como run. Las de la sesión principal y los diálogos de permiso del frontend quedan fuera hasta que pasen por un run.
4. **Escala.** El registro reescribe el fichero completo en cada cambio. Con muchos runs y preguntas, el coste crece; S2 lo mide y, si pasa de un umbral que fija S0, se reabre la decisión.

### Decisión para la operadora

- **D5 — S2.** (a) Aprobar el rediseño sobre el registro de runs, con las pérdidas declaradas (recomendada: ya es duradero, tiene cerrojo y modela la espera). (b) Esperar a que SE-518 S1 implemente `peticiones.json` y usarlo como fuente de S2 (más coherente con Pulse; hoy no existe). (c) Retirar S2 y quedarse con la vista de solo lectura de S1 más `needs_input` del registro de runs, sin identificador ni caducidad por pregunta.
