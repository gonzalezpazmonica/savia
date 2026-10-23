---
context_tier: L2
token_budget: 812
---

# Skill Template Protocol — SE-153

> Plantilla canónica para crear nuevas skills. Patrón "Authoritative Paths First" (inspirado en flowsint). Reduce coste de contexto y elimina inferencia incorrecta de firmas/paths por agentes.

## Por qué

Antes de SE-153 las SKILL.md mezclaban tutorial explicativo y referencia técnica. Los agentes leen top-down con presupuesto limitado de contexto. Si los paths canónicos están al final de la skill, el agente:

1. Pierde contexto antes de llegar a ellos.
2. Empieza a inventar firmas o paths basándose en convenciones genéricas.
3. Genera código que no compila o referencia ficheros inexistentes.

Solución: **paths primero, prosa después**. Sección obligatoria `## Authoritative Paths` justo tras el título de la skill, antes de cualquier tutorial o decisión.

## Ubicación

```
templates/skills/_template/SKILL.md   ← canónica
```

Las plantillas viven fuera de `.claude/skills/` a propósito: así el cliente no las descubre como skills.

## Cómo usar

1. Copiar el directorio:
   ```
   cp -r templates/skills/_template .claude/skills/<nombre-skill>
   ```
2. Editar `SKILL.md`:
   - Reemplazar todos los `<placeholder>` por valores reales.
   - Actualizar frontmatter `name`, `description`, `tags`.
   - Borrar el bloque HTML "HOW TO USE THIS TEMPLATE".
3. Mantener tamaño ≤100 líneas objetivo (WARN >100, FAIL ≥150 — SE-208).
4. Si la skill no es orquestadora (no invoca subagentes), borrar la sección `## Subagent Scope Guard`.

## Reglas duras

- **Authoritative Paths VA PRIMERO** después del título. No después del workflow, no al final. Auditado por BATS.
- **NUNCA inventar paths**: si la skill necesita un path no documentado, primero añadirlo a la tabla `Authoritative Paths`, luego usarlo.
- **NUNCA asumir firmas**: si una firma no está en los paths declarados, leer el código fuente directamente.
- **El template NO se carga en runtime**: los generadores excluyen `_template` explícitamente. Cualquier nuevo generador de catálogo DEBE excluirlo.

## Progressive Disclosure (SE-208)

Criterio: skill >100 líneas → candidata a extracción de contenido a satélites.

```
.claude/skills/<nombre>/
├── SKILL.md      ← ≤100 líneas: entrada, workflow, referencias (objetivo)
├── REFERENCE.md  ← referencia técnica extensa, tablas, criterios
├── tests.md      ← casos de test y ejemplos negativos (anti-patterns)
├── examples.md   ← ejemplos concretos de input/output
└── DOMAIN.md     ← solo si hay terminología de dominio real (no crear por defecto)
```

Reglas:
- SKILL.md enlaza a los satélites en la sección `## Related`.
- Los satélites **no** se cargan por defecto — el agente los lee bajo demanda.
- DOMAIN.md: solo cuando hay terminología de dominio real. No crear por defecto.
- Exit codes del auditor: WARN no bloquea CI; FAIL (>150 líneas) sí bloquea.

Ejemplo mínimo de satélite bien formado (`REFERENCE.md`):
```markdown
# <Skill> — Reference

> Satélite de `.claude/skills/<skill>/SKILL.md`. Cargado bajo demanda.
> Contexto: tablas detalladas, criterios extensos, configuración avanzada.

## [Sección 1]
...
```

## Description Protocol (SE-209)

Formato canónico: `[qué hace esta skill]. Usar cuando [trigger 1], [trigger 2], o [trigger 3].`

Reglas:
- Mínimo 20 caracteres.
- Al menos 1 trigger explícito con situación detectable: debe contener `when`, `cuando`, `usar` o `use` como palabra completa (sin distinguir mayúsculas; `User` no cuenta).
- Máximo 200 caracteres (compatibilidad SE-203 keyword routing). El auditor lo avisa con WARN.
- **Prohibido**: descriptions que solo repiten el nombre de la skill.
- Relación con SE-203: la `description` es la fuente primaria para keyword routing automático.

```yaml
# Bien formado:
description: "Audita compliance legal contra legislación española. Usar cuando se crea
              un contrato, se procesa PII, o hay incertidumbre sobre RGPD/LSSI."

# Bien formado (EN):
description: "Maps architecture dependencies. Use when designing a new feature,
              evaluating trade-offs, or at the start of design sessions."

# Mal formado (sin trigger):
description: "Herramienta para gestionar la agenda con sincronización Outlook."
```

## Migración

Opt-in. Las skills existentes no se migran masivamente. Una skill se actualiza al patrón cuando se toca por otra razón (refactor, fix, ampliación). Esto evita PRs ruidosos sin valor.

Lista priorizada para futuras migraciones (alta densidad de paths/handoffs):

- `spec-driven-development` (orquesta varios agentes)
- `pbi-decomposition` (handoff arquitectura ↔ análisis)
- `feasibility-probe` (paths a specs + scripts)
- `code-improvement-loop` (paths a guards + memory)
- `consensus-validation` (paths a jueces)

## Validación

- `bats tests/test-skill-template.bats` — 34/34 tests, audit 88/100.
- `bash scripts/skills-md-generate.sh --check` — drift detection no incluye `_template`.
- `bash scripts/resolver-md-generate.sh --check` — RESOLVER.md no incluye `skill:_template`.

## Referencias

- ROADMAP: `docs/ROADMAP.md` — Era 197 / Tier 1, SE-153.
- Patrón fuente: análisis flowsint 2026-05-30 (graph indexing + enricher pattern + authoritative paths first).
- Template: `templates/skills/_template/SKILL.md`.
- Tests: `tests/test-skill-template.bats`.
- Generadores: `scripts/skills-md-generate.sh`, `scripts/resolver-md-generate.sh`.
- SE-208: `docs/propuestas/SE-208-skill-100-line-limit.md`.
- SE-209: `docs/propuestas/SE-209-skill-description-protocol.md`.
