# epistemic-humility — Domain knowledge

## Origin

Defensive companion to SPEC-192 (anti-adulation). Implements the active
protocol the LLM follows when the Recommendation Tribunal flags sycophancy,
concession without evidence, or illusory truth in its draft. Origin in the
behavioral science literature on illusory truth effect (Hasher 1977, Fazio
2015, Pennycook 2018) — knowledge does NOT protect against repetition
becoming truth; explicit fact-checking behavior does.

## How it differs from radical-honesty

- `radical-honesty.md` is a RULE — declarative constraint, no enforcement.
- `epistemic-humility` is a SKILL — active protocol with concrete substitutions:
  never-vs-instead table, diff-of-evidence requirement, tool verification
  gate before citing user claims as fact.

SPEC-192 connects rule and skill via the three new tribunal judges + the
Layer 1 deterministic hook. This skill is the LLM-side response when those
judges fire.

## When to load

- Tribunal emits VETO or WARN ≥ 60 from sycophancy / concession /
  repetition-truth judges.
- Self-introspection: about to write "buena pregunta", "tienes razón",
  "absolutamente", "great question", "you are right" without follow-up
  evidence.
- User has insisted N≥2 times without new evidence in transcript.

## When NOT to load

- Genuine acknowledgement of own error with substantive correction
  ("mi error en X, la fuente actual dice Y" — already epistemically humble).
- Greetings or closings (not adulation).
- Domain-specific praise with concrete grounding ("este test pasa
  98% coverage en Y módulos" — quantified, not empty).

## Three patterns covered

| Pattern | Trigger | Substitution |
|---|---|---|
| A — reflexive sycophancy | RLHF training bias | strip phrase, go to content |
| B — concession under pressure | user insistence without evidence | maintain stance OR show diff |
| C — illusory truth | user claim repeated, treated as fact | hedge or verify with tool |

## Integration with Savia

- Intended to load when any of the 3 SPEC-192 judges emits WARN ≥ 60, but
  no automatic loading is wired: `recommendation-tribunal-orchestrator` does
  not reference this skill. Loading relies on the LLM or an explicit call.
- Loadable manually: `/skill load epistemic-humility`.
- Telemetry: skill loads are NOT logged. `output/anti-adulation-telemetry.jsonl`
  is written only by the Layer 1 hook (`.claude/hooks/sycophancy-strip.sh`).

## Anti-patterns

- Announcing "I will be epistemically humble now" — be it, do not narrate it.
- Replacing adulation with disdain ("obvious question") — the alternative
  is content, not contempt.
- Mechanical application — courtesy is not always sycophancy. The skill
  requires judgment.

## Related

- Rule: `docs/rules/domain/radical-honesty.md` (Rule #24)
- Spec: `docs/propuestas/SPEC-192-anti-adulation-illusory-truth.md`
- Tribunal: SPEC-125 (Recommendation Tribunal extended)
- Hook: `.opencode/hooks/sycophancy-strip.sh` (Layer 1 deterministic)
- Sibling skills: `caveman` (extreme brevity), `grill-me` (adversarial review)

## Capa determinista (hook Layer 1, SE-376)

La parte ejecutable del Patrón A es `.claude/hooks/sycophancy-strip.sh`
(PostToolUse, matcher `Task`; `.opencode/hooks` es un enlace al mismo
directorio) con el detector `scripts/anti-adulation/lexical-strip.py` y los
patrones `scripts/anti-adulation/regex-patterns.json`.

- Inspecciona el texto que devuelve un subagente: `tool_response` como cadena,
  como lista de bloques `{type, text}` o como objeto con `content[]`, `output`
  o `text`; `tool_input.text` como legado. Un sobre JSON sin texto (p. ej. un
  agente lanzado en segundo plano) no se escanea y registra `NO_TEXT`.
  Texto no JSON por stdin se analiza tal cual.
- Patrones `obvious` anclados al inicio; toleran espacios, `¡` y marcas
  markdown (`*`, `_`). "Absolutamente"/"absolutely" solo cuentan seguidos de
  puntuación o fin ("Absolutamente todos los tests fallan" no es adulación).
  Patrones `subtle` en cualquier posición: puntúan 50 y nunca bloquean.
- Modo `SAVIA_ANTIADULATION_LAYER1`: `shadow` (por defecto, solo telemetría),
  `warn` (aviso por stderr), `strip` (imprime el texto sin la apertura),
  `block` (exit 2 si score ≥ 85 y posición < 50), `off`. Un valor desconocido
  cae a `shadow`. `SAVIA_ANTIADULATION=off` lo apaga todo.
- Fail-open: si falta el detector o los patrones, o el detector falla (JSON
  o regex inválidos), sale 0 pero registra `FAIL_OPEN`; sin `jq` sale 0 sin
  rastro. El borrador llega al detector por stdin, sin límite de ARG_MAX.
- No ve evidencia ni contexto: no aplica los Patrones B y C (eso es de los
  jueces del Recommendation Tribunal, SPEC-192).

### Telemetría

El hook escribe una línea JSON por invocación en
`output/anti-adulation-telemetry.jsonl` (`decision`: `PASS`,
`SHADOW_DETECTED`, `WARN`, `STRIPPED`, `BLOCKED`, `BELOW_BLOCK_THRESHOLD`,
`NO_TEXT`, `FAIL_OPEN`; `draft_len` mide el texto del agente, no el sobre).
La carga de esta skill NO se registra: no hay ningún código que emita
`SKILL_LOADED_EPISTEMIC_HUMILITY`.
