---
layer: peripheral
name: _template
# SE-209 canonical description format: "[qué hace]. Usar cuando [trigger 1], [trigger 2], o [trigger 3]. Max 200 chars."
# Example: "Audita compliance legal. Usar cuando se crea un contrato, se procesa PII, o hay incertidumbre sobre RGPD."
description: "TEMPLATE — copia este directorio para crear una skill nueva. NO se carga en runtime."
# SE-333: campos propios bajo metadata.savia.* (string→string). name/description
# y license/compatibility quedan top-level. Listas → join por coma.
metadata:
  savia.maturity: "template"
  savia.maturity: stable
  savia.context: "standalone"
  savia.context_cost: "low"
  savia.category: "meta"
  savia.tags: "template, scaffold"
  savia.priority: "low"
  # SE-152: Semantic routing (optional — omit if not applicable)
  # savia.consumes: "spec, project_slug, sprint_data"
  # savia.produces: "report, CONTEXT.md, test_suite"
  savia.loop_level: "L0"   # L0=draft | L1=report-only | L2=assisted | L3=unattended — ver docs/rules/domain/loop-phasing.md
  # savia.trigger_keywords: "keyword1, keyword2"
---

<!--
  HOW TO USE THIS TEMPLATE
  ------------------------
  1. Copy `.claude/skills/_template/` to `.claude/skills/<your-skill-name>/`
  2. Replace ALL `<placeholder>` markers below.
  3. Update frontmatter `name`, `description`, `tags`.
  4. Delete this HOW TO block before commit.

  SIZE LIMITS (SE-208) — TARGET: ≤100 lines | WARN: >100 | FAIL: ≥150
  -------------------------------------------------------------------
  Keep SKILL.md as the lean entry point. Extract heavy content to satellites:

  .claude/skills/<name>/
  ├── SKILL.md      ← ≤100 lines: entry, workflow, references  ← YOU ARE HERE
  ├── REFERENCE.md  ← extensive technical reference, tables, criteria
  ├── tests.md      ← test cases, negative examples, anti-patterns
  ├── examples.md   ← concrete input/output examples
  └── DOMAIN.md     ← only when real domain terminology exists (not by default)

  Satellites are NOT loaded by default — the agent reads them on demand.
  SKILL.md links to satellites in the ## Related section.

  PATTERN: "Authoritative Paths First" (SE-153)
  ---------------------------------------------
  Inspirado en el patrón flowsint. La sección Authoritative Paths
  va PRIMERO, antes de cualquier prosa explicativa o tutorial.
  Razón: agentes leen top-down y se quedan sin contexto. Si los
  paths canónicos están al final, el agente los pierde y empieza
  a inventar firmas. Si están al principio, el agente sabe a
  dónde mirar antes de leer el resto de la skill.
-->

## Subagent Scope Guard

> Si fuiste invocado como subagente con una tarea concreta, ejecuta solo
> esa tarea y reporta DONE / DONE_WITH_CONCERNS / BLOCKED. NO actives el
> workflow completo de esta skill. (Borra esta sección si la skill no es
> orquestadora.)

# Skill: <Nombre Legible>

<Una frase. Qué problema resuelve.>

## Authoritative Paths

> **Lee estos paths antes de actuar. NUNCA asumas firmas, NUNCA inventes paths.**

| Para | Lee este path |
|---|---|
| <tipos / contratos / interfaces> | `<path/to/types.md>` |
| <handlers / entry points> | `<path/to/handlers/>` |
| <configuración / constantes> | `<path/to/config.md>` |
| <reglas de negocio aplicables> | `<path/to/rules/>` |
| <tests de referencia> | `<path/to/tests/>` |

**Reglas duras**:
- Si un path no existe, ABORTA y reporta — no inventes uno alternativo.
- Si una firma no está documentada en los paths, lee el código fuente directamente.
- Si la tarea requiere un path no listado aquí, primero añádelo a esta tabla.

## Cuándo usar

- <Trigger 1: situación concreta detectable>
- <Trigger 2>
- <Trigger 3>

## Cuándo NO usar

- <Anti-trigger 1: situación donde otra skill es más apropiada>
- <Anti-trigger 2>

## Decision Checklist

1. <Pregunta binaria 1> → si NO: <acción>
2. <Pregunta binaria 2> → si NO: <acción>
3. <Pregunta binaria 3> → si NO: <acción>

### Abort Conditions

- <Condición que invalida la skill — abortar y delegar>
- <Otra>

## Workflow

```
<paso 1: input>
    ↓
<paso 2: transformación>
    ↓
<paso 3: output / handoff>
```

### Detalle de cada paso

1. **<Paso 1>**: <qué hacer, qué leer, qué escribir>
2. **<Paso 2>**: <qué hacer, qué leer, qué escribir>
3. **<Paso 3>**: <qué hacer, qué leer, qué escribir>

## Outputs esperados

- <Fichero / commit / PR / mensaje>
- <Métrica observable>

## Memory hooks

- <Tipo de fact a guardar tras éxito> → `bash scripts/memory-store.sh save --type <type> --title "<title>" --content "<content>" --source skill:<name>`
- <Tipo de pattern a recall al inicio> → `bash scripts/memory-store.sh recall <topic>`

## Related

- Skill: `<../related-skill/SKILL.md>`
- Rule: `<docs/rules/domain/related-rule.md>`
- Spec: `<docs/propuestas/SPEC-XXX.md>`
- Roadmap: `<docs/ROADMAP.md#SE-XXX>`
