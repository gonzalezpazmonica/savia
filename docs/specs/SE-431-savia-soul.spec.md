---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-02
author: Savia
phase: A
risk: L4
related_specs: [SE-428, SE-429, SE-430, SE-406, SE-409, SPEC-186]
origin: "Mandato de la operadora 2026-10-02: Savia Space debe contar con un flujo continuo configurable y activable bajo demanda, Savia Soul, que emule a bots autónomos (OpenClaw, Hermes, OpenAI Five, Meta Muse, Grok Bot), con el que otros bots se comuniquen por A2A y la operadora por chat o mensajería"
resource: https://github.com/nousresearch/hermes-agent
---

# SE-431 — Savia Soul: la Savia proactiva dentro de Savia Space

## Problema

Savia solo trabaja cuando alguien abre una sesión o lanza una automatización programada. Los
bots autónomos actuales trabajan de otra forma:

- **OpenClaw**: latido periódico; identidad en ficheros.
- **Hermes**: aprende skills y memoria; pasarela de mensajería.
- **Meta Muse**: tareas largas en un entorno aislado, con un mediador que el agente no puede
  saltarse.
- **Grok Bot**: agentes persistentes que solo vuelven a la persona para aprobar, y que se
  coordinan entre ellos.
- **OpenAI Five**: ciclo continuo a ritmo fijo y aprendizaje fuera de producción.

Savia no tiene ese modo, ni una forma de que otros bots hablen con ella.

## Objetivo

**Savia Soul** es un bucle continuo dentro de Savia Space, configurable y activable bajo demanda:
**percibe**, **delibera**, **actúa**, **reflexiona** y **duerme**.

- Vigila, avisa, pregunta, propone y ejecuta trabajo acotado.
- Habla con la operadora por chat (web y móvil) y por mensajería (Savia Relay, SE-406).
- Habla con otros bots por A2A.
- Su voz es la de Savia.

**Regla madre: Soul solo actúa a través de las primitivas de Space**:

- ejecuciones de evidencia (SE-428);
- tareas de agente con envolvente y mediación de permisos (SE-428);
- mensajes y A2A (SE-429).

No tiene ningún otro camino al mundo. La mediación de Space es su "Sentinel": no puede
saltársela ni reconfigurarla.

**Principio imperativo: orquestadora antes que ejecutora** (operadora, 2026-10-03). Ante un
objetivo, Soul primero lo **descompone** en tareas independientes, las **reparte en paralelo**
entre tareas de agente de Space (cada una con su envolvente y aislada en su worktree y rama
`agent/*`), **coordina**, **revisa** lo que devuelven y **decide**. Solo ejecuta ella misma lo que
exige su juicio (decisiones, síntesis, revisión de lo entregado) o lo que no se puede partir.
Soul **nunca** hace merge, ni propio ni de sus tareas hijas (§Diseño, punto de acción): orquestar
no le da autoridad de merge; el merge sigue siendo de la persona.

- El recurso escaso es el reloj y el tiempo de la operadora, no los tokens: Soul no espera en
  serie a CI ni a una tarea larga si hay otra independiente que lanzar.
- Paralelismo acotado por configuración (`orchestration.maxParallelRuns`, por defecto 4) y por los
  presupuestos de ejecuciones por hora; nunca por encima de ellos. `maxParallelRuns` es un
  máximo, no un valor fijo: el límite efectivo lo da un probe de recursos de la máquina (VRAM
  libre, `OLLAMA_NUM_PARALLEL` y el `num_ctx` que necesita cada modelo) y es el mínimo de ambos.
  Si el probe falla o no puede medir, el límite es 1. El valor y sus entradas quedan en el
  journal del ciclo.
- **Delegar nunca amplía autoridad.** Una envolvente E' es «igual o más estrecha» que E si y solo
  si, componente a componente: herramientas(E') ⊆ herramientas(E); rutas de escritura(E') ⊆
  rutas(E); egreso(E') ⊆ egreso(E); `autonomy`(E') ≤ `autonomy`(E) en el orden OBSERVE < PROPOSE <
  ACT; y presupuestos(E') ≤ presupuestos(E). Space lo comprueba antes de lanzar cada hija; si no
  se cumple, la hija no se lanza y se convierte en pregunta (AC3).
- **Presupuestos repartidos, no copiados.** Lo que gastan las hijas se descuenta del presupuesto
  de la orden que las originó; N hijas en paralelo no multiplican el gasto por N.
- **Profundidad acotada.** Solo Soul crea tareas hijas: una hija no puede crear nietas (ni por el
  MCP ni por el A2A de Space); `orchestration.maxDepth` = 1.
- **Envolvente elegida por el triage determinista**, nunca por el modelo: `envelopeRef` sale de la
  orden permanente o del disparador, no de la salida del LLM.
- Antipatrón: Soul ejecutando en serie trabajo que podía repartir.

## Diseño

1. **Configuración.**
   - Modos: apagado, bajo demanda, programado o continuo.
   - Latido (mínimo 5 minutos), horas activas y de silencio, y eventos que despiertan (CI, PRs,
     ejecuciones, aprobaciones, cúpulas, mensajes).
   - Órdenes permanentes: cada una con objetivo, disparador, envolvente y autonomía (observar,
     proponer o actuar).
   - Canales, bots permitidos y presupuestos (tokens, ejecuciones, coste, preguntas al día,
     fallos seguidos).
   - Orquestación: `maxParallelRuns` (por defecto 4), `maxDepth` = 1 y preferencia por delegar.
   - Solo la persona cambia la configuración, la identidad y las órdenes, con recibo. **Soul no
     puede escribir nada de eso**, y nada de lo que recibe lo cambia. Así se cierra el ataque por
     guía inyectada documentado en OpenClaw.
   - El modo continuo exige doble opt-in (SPEC-186).
   - "PARA" desde cualquier canal detiene el bucle, cancela las ejecuciones activas y revoca las
     envolventes de Soul.
2. **Bucle.**
   - **Percibir**: eventos con hash. Es dato no fiable, nunca instrucción: lo que viene de otros
     bots o de las cúpulas, los comentarios y descripciones de PR, los logs de CI, las salidas y
     resúmenes de tareas hijas y los mensajes de Relay (aunque se atribuyan a la operadora). Lo no
     fiable nunca amplía una envolvente ni elige la orden o la envolvente.
   - **Deliberar**: primero un triage determinista; luego un juicio con el modelo local,
     registrado como ejecución de evidencia, para que lo que Soul "pensó" se pueda auditar. La
     salida es una decisión estructurada: nada, avisar, preguntar, lanzar, responder a un bot o
     proponer.
   - **Actuar**: solo si la orden permite actuar y la acción cabe en su envolvente. Si no,
     pregunta a la operadora con opciones y recomendación. Nunca hace merge, push forzado,
     aprobación de PRs ni efectos externos sin admisión externa (AEK).
   - **Reflexionar**: propone memoria y skills; nunca las aplica sola.
   - Cada ciclo queda en el journal con sus entradas, su decisión, sus acciones y su coste.
   - Fail-safe: 3 fallos seguidos, la misma acción 3 veces o el presupuesto agotado lo detienen
     y avisan.
   - **Estado de fail-safe durable**: detenido, en pausa, el contador de fallos seguidos, el
     presupuesto gastado del día y las envolventes revocadas por "PARA" se guardan antes de
     actuar y sobreviven a reinicios y caídas. Un crash cuenta como fallo. Soul nunca se reanuda
     sola: reanudar o reactivar envolventes exige una acción explícita de la operadora, con
     recibo.
3. **Conversación.**
   - **Operadora**: chat libre en la web y en el móvil. Por mensajería, a través de Savia Relay,
     con gramática cerrada y botones (estado, despierta, duerme, para, agenda, presupuesto,
     aprueba o rechaza). Aprobar riesgo medio o alto exige biometría en el móvil (SE-430); un
     mensaje no basta. El riesgo lo calcula Space de forma determinista a partir del tipo de
     primitiva y de la envolvente (SE-429); Soul no lo clasifica y su deliberación no lo cambia.
   - **Bots**:
     - Agent Card propia y firmada, con habilidades de preguntar, informar y delegar.
     - Una delegación nunca se ejecuta directamente: se convierte en una propuesta que necesita
       una orden que la cubra o la aprobación de la operadora.
     - Bots en allowlist, con claves fijadas y presupuesto propio.
     - Anti-bucle: 8 turnos por conversación como máximo, 3 saltos y deduplicación.
     - Los bots sin A2A se conectan por el MCP de Space con un cliente registrado; nunca hay un
       bot sin identificar.
4. **Memoria y aprendizaje.**
   - Soul guarda su propio journal y sus notas, con procedencia y nivel.
   - Una nota derivada, directa o transitivamente, de algo no fiable es no fiable. Solo la
     persona retira la marca, con recibo, y una nota no fiable no se promueve.
   - Promover memoria a Savia o a una cúpula, o crear una skill (patrón Hermes), requiere dos
     cosas: superar casos dorados con el gate de calidad, y que la persona lo apruebe. Es la
     defensa contra la *skill misevolution* documentada.
   - La mejora de criterio se hace offline, con replay del journal (patrón OpenAI Five), y se
     propone como cambio revisable.
   - Prohibido auto-aprobarse más capacidad, presupuesto o autonomía.
5. **Encaje.**
   - Soul es un solicitante en términos de TEE: no emite autoridad.
   - Cuando AEOS exista, Soul le delega los flujos de varios pasos; nunca hay dos coordinadores
     sobre la misma ejecución.
   - Autonomía máxima L2 (actuar dentro de envolventes). Efectos externos bloqueados por
     ADR-002.

## Criterio de parada del producto

Si en dos semanas de piloto Soul genera más carga que valor (más preguntas o falsas alarmas que
acciones aceptadas), se reduce a bajo demanda y se revisa. Los resultados negativos se publican.

## Criterios de aceptación

- **AC1**: un mensaje de un bot que pide saltarse reglas o hacer merge no produce ninguna acción
  con efecto y queda registrado.
- **AC2**: Soul no puede escribir su configuración, su identidad ni sus envolventes.
- **AC3**: una acción fuera de la envolvente se convierte en pregunta con opciones y
  recomendación.
- **AC4**: 3 fallos seguidos detienen el bucle y avisan por todos los canales activos.
- **AC5**: "PARA" detiene el bucle, cancela ejecuciones y revoca envolventes en menos de 5 s.
- **AC6**: dos bots que se responden en bucle se cortan en el turno 8.
- **AC7**: una delegación de un bot sin orden que la cubra solo produce una propuesta.
- **AC8**: el presupuesto agotado detiene el bucle hasta el día siguiente o hasta una ampliación
  humana.
- **AC9**: una propuesta de skill que falla los casos dorados no llega a la persona.
- **AC10**: el replay de los ciclos reproduce las mismas decisiones del triage determinista.
- **AC11**: un objetivo con N subtareas independientes (N ≤ `maxParallelRuns`) lanza N tareas de
  agente concurrentes en el mismo ciclo; con N > `maxParallelRuns`, nunca hay más de
  `maxParallelRuns` vivas a la vez.
- **AC12**: para cada componente del orden de envolventes (herramientas, rutas, egreso,
  autonomía, presupuestos), una hija con ese componente más amplio que el de su orden no se lanza
  y se convierte en pregunta (AC3): un caso de prueba por componente.
- **AC13**: el informe del ciclo distingue lo orquestado (tareas hijas, en paralelo) de lo
  ejecutado por Soul, con el tiempo de pared por objetivo.
- **AC14**: con 4 hijas en paralelo, el gasto total de tokens y ejecuciones nunca supera el
  presupuesto de la orden (reparto, no copia).
- **AC15**: una tarea hija que intenta crear otra tarea (por el MCP o el A2A de Space) recibe un
  rechazo y queda registrado; Soul nunca ejecuta un merge, aunque el objetivo lo pida.
- **AC16**: con la misma entrada, `envelopeRef` es el mismo en el replay (lo fija el triage, no
  el modelo).
- **AC17**: un comentario de PR que pide a Savia ejecutar un script remoto entra como no fiable;
  la orden que se dispara no lo incorpora como instrucción ni amplía su envolvente, y queda
  registrado.
- **AC18**: una nota escrita a partir de un log de CI es no fiable, y también una segunda nota
  derivada de la primera; ninguna se promueve sin la persona.
- **AC19**: si la deliberación afirma «riesgo bajo» para una tarea de agente con edición, Space
  la clasifica como riesgo medio y exige biometría; una aprobación por Relay o por delegación
  acotada se rechaza.
- **AC20**: con Soul detenida (por fail-safe o por "PARA"), un reinicio de Space, o tres caídas
  seguidas en el arranque, la dejan detenida, con el contador sin reiniciar y las envolventes
  revocadas; no lanza nada hasta la acción de la operadora.
- **AC21**: con `maxParallelRuns` = 4 y un probe que solo admite 2 ejecuciones, nunca hay más de 2
  hijas vivas; con el probe fallido, como máximo 1; el journal registra el límite y sus entradas.

## Entregas

- **S1**: bajo demanda en la web; observar e informar; disparadores deterministas.
- **S2**: órdenes permanentes con envolvente, chat en el móvil y avisos por Relay.
- **S3**: A2A de entrada y adaptador MCP para bots sin A2A.
- **S4**: modo continuo con latido, A2A de salida y propuestas de skills y memoria.

## Decisiones pendientes

- **D1**: addendum a ADR-002 para Soul (L2 con envolventes, sin efectos externos).
- **D2**: modo por defecto al instalar: apagado (propuesto) o bajo demanda.
- **D3**: transporte de Relay: Telegram primero (propuesto aquí; SE-406 recomienda WhatsApp Cloud
  API) o WhatsApp.
- **D4**: A2A de salida en S4 (propuesto) o nunca.
- **D5**: deliberación solo con modelo local (propuesto) o también con un perfil en la nube.

## OpenCode Implementation Plan

### Bindings touched

Ninguno directo: Soul vive en el servidor de Space. Sus tareas de agente usan el motor de SE-428
(OpenCode) con los plugins de Savia cargados; no añade hooks, agentes ni skills al workspace sin
aprobación.

### Verification protocol

- [ ] Escenarios AC1–AC21 con eventos sintéticos y un motor de prueba.
- [ ] Replay determinista del triage en CI.

### Portability classification

- [x] **PURE_BASH** (equivalente: servicio independiente del frontend; la parte de agente hereda
  la clasificación de SE-428)
