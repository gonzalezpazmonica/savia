---
status: APPROVED
priority: P1
developer_type: agent-team
created: 2026-11-26
author: Savia
phase: D
risk: L3
human_surface: true
related_specs: [SE-310, SE-308, SE-312, SE-075, SE-538, SE-432]
supersedes: [SE-310]
origin: "Propuesta de la operadora del 2026-11-26 sobre Savia Sonora multilingüe, dúplex y con avatar 2D (en Savia Labs). Auditoría AS-IS sobre origin/main 4104a2bd1 el mismo día; escenas confirmadas por pregunta interactiva el 2026-11-26."
timeline:
  - from: "2026-11-26"
    learned: "2026-11-26"
    value: "PROPOSED"
    source: "orquestadora; escenas confirmadas por la operadora en pregunta interactiva del 2026-11-26"
  - from: "2026-11-26"
    learned: "2026-11-26"
    value: "APPROVED"
    source: "operadora, pregunta interactiva del 2026-11-26: «Aprobar las tres»"
---
# SE-537 — Sonora conversa con la sesión de Claude de Savia

## Problema (verificado en origin/main 4104a2bd1, 2026-11-26)

Sonora graba y transcribe reuniones, y lo hace bien: el backend pasa 401 tests y el frontend 27. Pero no conversa con nadie. La única conversación por voz con Claude que existe está en otro sitio y lleva meses sin uso.

1. **No hay servicio de conversación.** `projects/savia-sonora/app/src-pyloid/` no tiene `services/conversation/` ni nada con otro nombre que haga lo mismo. SE-310 lo describe, pero sigue PROPOSED desde 2026-08-07.
2. **SE-310 elige un cerebro que ya no vale.** Su tabla de decisiones pone Ollama como cerebro, a través de `OpenAICompatibleProvider` (`services/recording/llm.py:32`). Desde el 2026-10-15 la inferencia de Savia va a los modelos de Claude, y Ollama trunca el prompt en silencio. Hoy ese proveedor solo genera el resumen y el título de las reuniones (`recording/controller.py:763-769`, `_provider_from_config`) y prueba la conexión (`:706`, `_probe_provider`).
3. **La voz de Savia no tiene consumidor.** `scripts/savia-kokoro.py` y `savia-voice-*.sh` funcionan y tienen tests, pero nadie los llama. Son una CLI que escribe un WAV, no un proceso que reproduce por frases.
4. **El único binding a Claude está dormido y sale a la nube.** `zeroclaw/savia-voice/session.py:56` lanza un `claude -p --output-format stream-json --include-partial-messages --resume` en cada turno. Tiene barge-in y cola de voz (`daemon.py:74-136`, `tts.py:59-108`), pero no hay servicio instalado ni nadie que lo llame. Y `tts.py:144` recurre a edge-tts, la voz en la nube de Microsoft, ante cualquier error de Kokoro, sin preguntar.
5. **Cortar la voz no es cancelar el trabajo, y en ZeroClaw se confunden.** `tts.cancel()` calla la voz, pero el `claude -p` del turno solo muere por timeout (`session.py:80`). Encima hay rellenos pregrabados («Déjame que lo mire», `session.py:83-99`) que anuncian una acción que ningún evento real respalda.

## Lo que he entendido

Esta spec cambia lo que la persona oye y ve en Sonora. Por eso lleva escenas y la confirmación de la persona (2026-11-26).

### Qué ve la persona hoy

Sonora graba reuniones y dicta texto en el cursor. Si quiere hablar con Savia, tiene que escribirle en la terminal o en Space. Sonora no le responde y no tiene voz.

### Qué verá la persona con esta spec

Un atajo propio, distinto del de dictado, para hablar con Savia. Savia contesta con voz local, frase a frase, y con el texto debajo. Un indicador aparte muestra si Savia sigue trabajando aunque la voz se haya callado. Si no hay red, Sonora lo dice claramente.

### Escenas

1. **Pregunta por voz.** En el Mac, la persona mantiene pulsado el atajo, dice en castellano «¿cómo van las PR de hoy?» y lo suelta. Sonora lo transcribe en local, la sesión de Claude de Savia responde y la persona la oye con voz local, frase a frase, mientras lee el texto debajo.
2. **Interrumpir sin cancelar.** Mientras Savia contesta, la persona vuelve a pulsar el atajo. La voz se calla al instante, pero el trabajo que Savia tenía en marcha sigue. Se ve en un indicador aparte.
3. **La cara.** Encima de los subtítulos hay una cara 2D sencilla, no realista, que solo mueve la boca cuando suena la voz y que indica si escucha o habla. La persona puede elegir entre al menos dos estilos o quitarla, y la conversación sigue igual. *(Esta escena la desarrolla SE-538. Aquí solo cuenta que la conversación no depende de la cara.)*
4. **Ninguna voz ni audio sale del Mac.** Ni la voz ni el audio salen del Mac; lo único que sale es el texto del turno hacia la sesión de Claude, como cuando se escribe en ella (ver D7). Si se cae la red, el dictado sigue funcionando y Sonora avisa de que no puede razonar, sin inventarse respuestas.

### Palabras de la persona

«Analiza, specs y roadmap de Savia Sonora esta semana. Dedica todos los recursos posibles.» Es el texto literal de la operadora del 2026-11-26. Las escenas las redactó la orquestadora a partir de su propuesta, y la operadora las confirmó.

### Qué SÍ será

- Pulsar para hablar con un atajo propio, separado del de dictado (es la decisión de SE-310 y se mantiene).
- Transcripción local con el faster-whisper que ya usa Sonora.
- Respuesta de **la sesión de Claude de Savia** (Claude Code con la cuenta configurada en esa máquina), en texto que va apareciendo por partes.
- Voz local con Kokoro (`ef_dora` por defecto), sintetizada por frases en un proceso propio con cola.
- Dos acciones distintas: **callar la voz** (`interrupt_speech`) y **cancelar el trabajo** (`request_cancel_execution`), con controles y eventos diferentes.
- Comportamiento sin red declarado: el dictado sigue, y la conversación dice que no puede razonar.
- Una prueba de egreso en CI: ningún byte de audio ni de voz sale a la red durante una conversación.

### Qué NO será

- Ni Ollama ni otro modelo local como cerebro. El `OpenAICompatibleProvider` se queda para los resúmenes de reuniones.
- Ni voz ni transcripción en la nube, tampoco como fallback.
- Sin micrófono abierto ni cancelación de eco en este paso: solo se habla pulsando.
- Sin voz a voz (Haru, PersonaPlex, Moshi), sin catálogo de motores y sin gallego. Todo eso se investiga en Savia Labs, sin spec.
- Sin rellenos que anuncien acciones («voy a mirarlo») si no hay un evento real detrás.
- Sin avatar dentro de esta spec (es SE-538).

### Confirmación

- fecha: 2026-11-26
- respuesta: «Sí, es eso». Es la respuesta de la operadora, por pregunta interactiva, a las escenas 1 a 4 tal como aparecen arriba. La opción describía «la enmienda de SE-310 … y la spec nueva del avatar 2D». Esta spec es esa enmienda escrita en el formato vigente. SE-310 se marca como sustituida y no se reescribe (ver D1).

## Slice S0 — Prototipo navegable

prototipo: el mismo de SE-538 (página local con los estados escuchando, pensando, hablando, voz callada con el trabajo en marcha, y sin red). Es una sola superficie: la conversación y la cara se enseñan juntas.

### Confirmación del prototipo

- fecha: 2026-11-26
- respuesta: «Confirmo el prototipo». Respuesta de la operadora, por pregunta interactiva, a la página privada publicada ese día, con dos estilos y «sin cara», pulsar para hablar, voz callada sin cancelar el trabajo, sin red, movimiento reducido y tema. La pregunta advertía que faltaba el botón «Parar trabajo». Se añade en la versión siguiente del prototipo y forma parte de S3 de SE-537.

## Qué decide esta spec

### D1 — Sustituye a SE-310

SE-310 está en el formato antiguo (`projects/savia-sonora/specs/`), no figura en `planning-state.json` y elige Ollama como cerebro. Esta spec ocupa su lugar: hereda el atajo separado y el arbitraje con el dictado, y cambia el cerebro. SE-310 pasa a `SUPERSEDED` con un enlace aquí.

### D2 — Cerebro: sesión de Claude Code persistente

- Se porta el `SessionManager` de ZeroClaw a `services/conversation/claude_session.py`, con una diferencia: **un proceso persistente** en modo de entrada y salida `stream-json`, no uno por turno. Así se mantiene la identidad de la sesión y se evitan unos segundos de arranque en cada turno.
- El proceso arranca en el directorio del workspace de Savia, para que cargue su `CLAUDE.md` y su perfil. El directorio se configura y no se adivina.
- Lo que la sesión no puede aprobar por voz (permisos de herramientas) se muestra **como texto en Sonora**, que dice «necesito tu permiso en la terminal». Nunca se aprueba por voz. Antes de S1 hay que medir en el Mac qué hace `-p` con los permisos (es una pregunta abierta).
- Si en el Mac existe una pasarela de sesión de Savia Space o de Soul que dé lo mismo, se usa esa en vez de la CLI (pregunta abierta 2; no se ha mirado en el repo privado).

### D3 — Voz: proceso Kokoro con cola y época

`services/conversation/tts_worker.py` es un proceso hijo con Kokoro cargado una sola vez. Recibe frases del separador existente (`scripts/lib/sentence-splitter.py`) y reproduce PCM. Cada turno tiene una **época**: `interrupt_speech` sube la época, vacía la cola y corta la reproducción en curso. Cualquier frase de una época anterior se descarta. Sin fallback en la nube: si Kokoro falla, Sonora muestra en pantalla «no tengo voz» y deja el texto de la respuesta.

### D4 — Callar no es cancelar

| Acción | Gesto | Efecto | Evento |
|---|---|---|---|
| `interrupt_speech` | volver a pulsar el atajo mientras Savia habla | vacía la cola de voz; la sesión sigue | `speech-interrupted` |
| `request_cancel_execution` | botón «Parar trabajo» en la ventana, con confirmación | interrumpe el turno de la sesión | `execution-cancel-requested` → `execution-cancelled` |

El indicador de trabajo depende solo de los eventos de la sesión (`turn-started`, `tool-running`, `turn-finished`), nunca de la voz.

### D5 — Sin red

El dictado y la transcripción no necesitan red. Si la sesión de Claude no responde (sin red o con error), Sonora lo muestra en pantalla y, si Kokoro está disponible, lo dice con una frase fija sintetizada en local: «Ahora no puedo pensar: no hay conexión con mi sesión». No reintenta en bucle ni se inventa respuestas.

### D7 — Qué sale y con qué nivel (revisión de la PR #1670)

- **El audio no sale nunca.** Ni el micrófono, ni la voz sintetizada, ni las capturas. El audio de una conversación es N3 y se queda en el Mac.
- **El texto transcrito del turno sí sale**, hacia la sesión de Claude en la nube, por el mismo canal y con las mismas reglas que un mensaje escrito en esa sesión. No es un canal nuevo. Se trata como N2 con recibo, según la regla vigente de inferencia en Claude (2026-10-15).
- **Si la persona dicta algo N3 o superior**, se aplica el mismo gate de soberanía de datos que a un mensaje escrito. Si el gate bloquea, el turno no se envía y Sonora lo dice en pantalla. Sonora no rebaja ni anonimiza a mano.
- **Lo que se guarda en local** (texto de la conversación y audio, si se activa) tiene el tratamiento N3 de las reuniones.

### D6 — ZeroClaw

`zeroclaw/savia-voice/` se retira entero en una PR aparte, sin spec. Lo decidió la operadora el 2026-11-26 por pregunta interactiva («Retirar ZeroClaw voz entera»). Con él se van su fallback a edge-tts (`tts.py:144`) y el empaquetado en `scripts/sovereignty-ops.sh:75`. Lo útil (cola con época, barge-in, clasificación de solapamientos) se reescribe en Sonora desde esta spec, mirando el historial de git.

## Slices

| Slice | Contenido | Tier | Depende de |
|---|---|---|---|
| S0 | Prototipo navegable compartido con SE-538 y confirmación | 1 | — |
| S1 | `claude_session.py` + atajo de conversación + texto que aparece por partes en la ventana (sin voz) | 2 | S0 confirmado; medición de permisos en el Mac |
| S2 | `tts_worker.py` con cola y época; `interrupt_speech`; indicador de trabajo | 2 | S1 |
| S3 | `request_cancel_execution`, comportamiento sin red, prueba de egreso en CI | 2 | S2 |

### S1 — Hablar y leer la respuesta

**Criterios de aceptación**

- [ ] Con el atajo de conversación pulsado y luego soltado, el audio se transcribe en local y se envía como turno a la sesión persistente.
- [ ] La respuesta aparece en la ventana por partes, a medida que llega.
- [ ] El atajo de dictado sigue pegando en el cursor y nunca envía nada a la sesión (test de arbitraje).
- [ ] Dos turnos seguidos usan el mismo proceso de sesión (test con una sesión falsa).
- [ ] Una petición de permiso de la sesión se muestra como texto y no se aprueba sola (test negativo).

### S2 — Voz por frases y callarla

- [ ] La primera frase empieza a sonar antes de que termine la respuesta (test con un reloj falso: la frase 1 se encola antes de `turn-finished`).
- [ ] `interrupt_speech` deja la cola vacía y la época sube. Las frases de la época anterior que llegan después no suenan (test).
- [ ] Tras `interrupt_speech`, la sesión sigue: el turno termina y su texto llega completo (test negativo: callar la voz no mata la tarea).
- [ ] Con Kokoro roto, no hay voz, el texto sí aparece y no se hace ninguna llamada de red (test).

### S3 — Cancelar, red caída y egreso

- [ ] «Parar trabajo» pide confirmación y, si se confirma, interrumpe el turno. La voz se calla también.
- [ ] Una orden hablada como «borra… no, no borres» no dispara la cancelación ni ninguna acción por sí misma: el texto va a la sesión como cualquier turno (test).
- [ ] Sin red, el dictado funciona y la conversación responde con la frase fija de D5 (test con la sesión desconectada).
- [ ] Prueba de egreso: durante una conversación simulada, ningún byte de audio sale del proceso de Sonora por ningún socket. Hacia el proceso de la sesión solo va el texto del turno, y ese mensaje no contiene audio ni rutas a ficheros de audio (test en CI con la red bloqueada y la sesión falsa capturando lo que recibe).
- [ ] **Negativo, N3 dictado:** un turno que el gate de soberanía clasifica como N3 no llega a la sesión y Sonora lo avisa en pantalla (test con el gate real y una sesión falsa).
- [ ] **Negativo, caché fría:** con los pesos de Whisper o de Kokoro ausentes, la conversación no descarga nada. Muestra «falta el modelo de voz» y deja la descarga como acción explícita de la persona en ajustes (test con la caché vacía y la red bloqueada). Hoy los dos descargan de Hugging Face la primera vez, y una caché caliente ocultaría esa salida.

## Criterios de aceptación transversales

- [ ] Los tests de Sonora y de la conversación se ejecutan en el CI raíz. Hoy no se ejecutan: el workflow anidado `app/.github/workflows/ci.yml` GitHub no lo ve.
- [ ] Ninguna dependencia nueva de voz en la nube en `requirements` ni en `package.json`.
- [ ] Los datos de conversación (texto y audio, si se guarda) van a `~/.savia/transcriptor/conversaciones/` con el mismo tratamiento N3 que las reuniones. Por defecto no se guarda el audio.

## OpenCode Implementation Plan

### Bindings touched

`projects/savia-sonora/app/src-pyloid/services/conversation/` (nuevo), `services/hotkey.py` (atajo nuevo), `ui_event_bridge.py` (eventos nuevos), `app/src/` (vista de conversación). No toca `.claude/` ni `.opencode/`.

### Verification protocol

pytest del backend de Sonora y vitest del frontend en CI raíz; la prueba de latencia y de voz se hace a mano en el Mac.

### Portability classification

Independiente del frontend de Savia: Sonora llama a la CLI de Claude Code como proceso hijo. En OpenCode no hay equivalente en este paso.

## Fuera de alcance

Micrófono abierto y AEC; voz a voz; catálogo y selección de motores; gallego e inglés; gobernador de recursos; visemas; avatar (SE-538); la vista de reuniones (no cambia).

## Preguntas abiertas

1. ¿Qué hace `claude -p --input-format stream-json` con una herramienta que pide permiso, en la versión instalada en el Mac? Hay que medirlo antes de S1.
2. ¿Savia Space o Soul ofrecen ya una pasarela de sesión local que Sonora debería usar en vez de la CLI?
3. ¿`hotkey.py` tiene un camino en macOS? Hoy usa evdev, que es de Linux, y en el Mac hacen falta permisos de Accesibilidad.
4. Antes de S1 hay que reconciliar SE-308 y SE-312: el código está entregado pero las specs siguen PROPOSED y fuera de `planning-state.json`.

## Riesgos

- **Mac sin probar.** Pyloid, Qt WebEngine, los atajos y el micrófono no se han probado nunca en macOS arm64. *Mitigación:* el primer trabajo de S1 es arrancar la app en el Mac, antes de escribir código.
- **Cuenta de la organización.** En algunos equipos solo vale la cuenta de Claude que fija la organización. *Mitigación:* el directorio y la cuenta los configura la persona; Sonora no guarda credenciales.
- **Latencia.** La sesión de Claude añade segundos antes de la primera frase. *Mitigación:* el texto que aparece por partes y la cara en estado «pensando» (SE-538) hacen visible la espera. No se usan rellenos que anuncien acciones.

## Aprobación

**Aprobada por la operadora el 2026-11-26** por pregunta interactiva («Aprobar las tres») y la confirmación del prototipo. Cada slice se fusiona con la revisión de su PR concreta. Se formaliza al fusionar esta PR (SE-488).
