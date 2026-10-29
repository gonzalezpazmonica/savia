---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-29
author: Savia
phase: D
risk: L2
related_specs: [SE-475, SE-476]
origin: revisión de Anthropic Research en Savia Labs (privado), propuesta derivada a spec pública por encargo de la operadora 2026-10-29
blocked_by: evaluación previa en Savia Labs (privado); esta spec no se implementa antes de su resultado
timeline:
  - from: "2026-10-29"
    learned: "2026-10-29"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
  - from: "2026-10-29"
    learned: "2026-10-29"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-478 — Protocolo de decisiones: triaje, simetría de argumentos y criterio previo

> **Condicionada.** Esta spec queda en PROPOSED hasta que termine una evaluación previa en Savia Labs (privado).
> Si esa evaluación no muestra mejora, la spec se descarta o se reduce a la simetría de argumentos.

## Problema

Savia plantea a la persona las decisiones que no le corresponde tomar sola. Lo hace con preguntas de opción
múltiple, y siempre marca una opción como recomendada y la pone la primera. Esto mezcla tres tipos de decisión
que necesitan un trato distinto:

- **Técnica con respuesta comprobable**, por ejemplo la causa de un fallo de CI o qué timeout falta. Preguntarla
  gasta la atención de la persona en algo que Savia puede verificar sola.
- **Autorización**: gasto, tiers de riesgo, publicación, permisos, identidad. La decisión es de autoridad, no de
  conocimiento, y siempre requiere a la persona.
- **Juicio, valores o prioridad**, donde varias opciones son razonables y no hay una respuesta correcta. Aquí
  recomendar de entrada, y argumentar la recomendada mejor que las demás, puede sustituir el criterio de la
  persona por el del agente sin que ella lo note.

`docs/rules/domain/savia-ethical-principles.md` ya dice que Savia acompaña sus propuestas con la alternativa
razonable más fuerte. Ningún mecanismo comprueba que se cumpla.

## Fuente

- Anthropic, «How AI agents shape experts' judgment calls» (2026). En un ensayo controlado con 50 analistas,
  el 86 % siguió en decisiones analíticas la inclinación que se había asignado al agente al azar. El 77 % repitió
  los argumentos del agente y solo el 15 % se los atribuyó. El agente rara vez argumentaba bien la opción
  contraria. El artículo propone como áreas de **estudio futuro**, sin validarlas, presentar el caso de cada
  opción, pedir el criterio de la persona antes de dar el propio y limitar las consultas a lo que importa.
  <https://www.anthropic.com/research/agents-judgment-calls>
- Anthropic, sobre los permisos en Claude Code: la gente aprueba la gran mayoría de las solicitudes, y Anthropic
  lo trata como fatiga de aprobación, no como supervisión.
  <https://www.anthropic.com/engineering/claude-code-auto-mode>
- Anthropic, «Measuring agent autonomy»: las paradas que inicia el propio agente son una forma de supervisión.
  <https://www.anthropic.com/research/measuring-agent-autonomy>

## Propuesta

1. **Triaje.** Antes de preguntar, Savia clasifica la decisión como técnica, de autorización o de juicio. Ante la
   duda, la trata como juicio.
   - Técnica: Savia decide, deja registradas la decisión y su verificación, y no pregunta salvo que no pueda verificar.
   - Autorización: pregunta siempre, con el riesgo y la reversibilidad en primer plano.
   - Juicio: aplica el punto 2.
2. **Simetría y criterio previo, solo en decisiones de juicio.**
   - Todas las opciones llevan el mismo esquema (a favor, en contra, coste, qué tendría que ser verdad) con una
     extensión parecida.
   - La primera ronda no marca ninguna opción como recomendada e incluye la opción «Dame tu recomendación primero».
   - Si falta contexto para decidir, Savia da el contexto mínimo o aplaza la pregunta.
3. **Medida continua**: un informe periódico, por clase, de la tasa de aceptación de la opción recomendada y de
   las respuestas propias.

## Criterios de aceptación

- [ ] La evaluación previa de Savia Labs ha terminado y su resultado justifica implementar (condición de entrada).
- [ ] Existe un contrato documentado de las tres clases, con ejemplos, y la regla «ante la duda, juicio».
- [ ] Un gate determinista, un PreToolUse sobre la herramienta de preguntas que lee JSON por stdin, avisa si en una
  pregunta marcada como de juicio aparece «(Recommended)» en la primera ronda, o si la descripción más larga
  supera al doble de la más corta.
- [ ] El informe de tasas se genera sin copiar el texto de las preguntas ni de las respuestas.
- [ ] Tests BATS del gate con casos positivos y negativos que fallen sin el gate.

## Riesgos

- **Abrumar a la persona.** El propio artículo lo advierte. Mitigación: el protocolo de juicio se aplica solo a esa clase.
- **Que el triaje oculte decisiones.** Clasificar como técnica algo que es de juicio hace que el agente decida solo.
  Mitigación: ante la duda, juicio, más una auditoría periódica de una muestra.
- **Coste de tiempo.** Dar el criterio propio cuesta más que aceptar una recomendación.

## Alternativas

- **Solo simetría de argumentos.** Cumple la regla ética que ya existe con un coste mínimo, pero mantiene la
  recomendada primera y marcada.
- **Regla inmediata sin evaluación.** Rápida, pero las recomendaciones del artículo no están validadas.
- **No cambiar nada.** Se mantiene el mecanismo que el artículo describe.

## Lo que no se hace

- No se implementa nada antes del resultado de la evaluación previa.
- No se cambia el trato de las autorizaciones: se siguen preguntando siempre.
- No se publican datos de uso de ninguna persona.

## Alcance

Contrato de clases, gate de aviso sobre la herramienta de preguntas e informe de tasas. Sin cambios en Yema, que
no plantea decisiones de este tipo.

## Esfuerzo

S1 contrato y gate (unas 6 h), S2 informe (unas 3 h). Solo si la condición de entrada se cumple.

## Decisiones pendientes de la operadora

- Si la evaluación previa sale positiva: implementar el protocolo completo o solo la simetría.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Gate de preguntas | hook PreToolUse sobre `AskUserQuestion` (JSON por stdin) | plugin TS equivalente sobre la herramienta de preguntas de OpenCode, si la expone; si no, documentado como degradación |
| Informe de tasas | script bash/python sobre los transcripts | el mismo script sobre los logs de OpenCode, si existen |

### Verification protocol

- [ ] Funciona en runtime OpenCode, o la degradación queda documentada.
- [ ] Tests cubren ambos paths.
- [ ] Sin dependencias de red.

### Portability classification

- [x] **DEGRADED_OPENCODE**: si OpenCode no expone una herramienta de preguntas estructurada, el gate solo existe en Claude Code y el informe se limita a Claude Code.
