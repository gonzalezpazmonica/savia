---
spec_id: SE-208
title: SKILL.md hard limit 100 lines + progressive disclosure
status: IMPLEMENTED
drift_note: "drift: components existed pre-triage (skill-catalog-auditor.sh has WARN>100/FAIL>=150 + skill-template-protocol.md has progressive disclosure section SE-208)"
implemented_at: "2026-06-24"
priority: P1
effort: B
era: 201
origin: output/research/mattpocock-skills-savia-20260607.md
inspiration: mattpocock/skills write-a-skill protocol (120k stars)
---

# SE-208 — SKILL.md hard limit 100 lines + progressive disclosure

## Problema

El límite actual de SKILL.md es 150 líneas (FAIL). No existe nivel WARN intermedio. Resultado: skills crecen hasta 149 líneas sin alerta, acumulando contenido que debería estar en ficheros satélite. 6 skills están exactamente en 150 líneas (verification-lattice, reflection-validation, orgchart-import, human-code-map, code-improvement-loop, agent-code-map). El catálogo de 102 skills no tiene incentivo estructural para mantenerse compacto.

## Solución

Añadir WARN en >100 líneas. Documentar **progressive disclosure**: cuando una skill supera 100 líneas, el contenido extra se extrae a ficheros satélite en el mismo directorio. SKILL.md queda como punto de entrada + referencias a satélites.

## Scope

### 1. `scripts/skill-catalog-auditor.sh`

Añadir comprobación WARN cuando `SKILL.md` supera 100 líneas. El FAIL existente en >150 líneas no se modifica. Comportamiento:

```
WARN  [SE-208] spec-driven-development/SKILL.md: 149 lines > 100 (progressive disclosure recommended)
FAIL  [Rule#11] verification-lattice/SKILL.md: 150 lines ≥ 150 (hard limit exceeded)
```

El WARN no bloquea el exit code del auditor (AC4).

### 2. `templates/skills/_template/SKILL.md`

Actualizar el bloque HOW TO USE para incluir:

- Límite explícito: ≤100 líneas objetivo, >100 WARN, ≥150 FAIL.
- Instrucción de progressive disclosure: qué va en cada satélite.
- Tabla de satélites canónicos.

### 3. `docs/rules/domain/skill-template-protocol.md`

Añadir sección `## Progressive Disclosure` con:

- Criterio: skill >100 líneas → candidata a extracción.
- Tabla de satélites: `REFERENCE.md`, `tests.md`, `examples.md`, `DOMAIN.md`.
- Regla sobre `DOMAIN.md`: solo cuando hay terminología de dominio real (no crear por defecto).
- Ejemplo mínimo de satélite bien formado.

### 4. Candidatas a refactor (>100 líneas, identificadas)

| Skill | Líneas | Satélite recomendado |
|---|---|---|
| `verification-lattice` | 150 | REFERENCE.md (criterios de lattice) |
| `reflection-validation` | 150 | REFERENCE.md (checklist metacognitivo) |
| `orgchart-import` | 150 | examples.md (formatos de orgchart) |
| `human-code-map` | 150 | REFERENCE.md (mapa de módulos) |
| `code-improvement-loop` | 150 | REFERENCE.md (pipeline detallado) |

## Acceptance Criteria

- **AC1**: `skill-catalog-auditor.sh` emite WARN cuando `SKILL.md` > 100 líneas, sin modificar el FAIL en ≥150.
- **AC2**: El template `_template/SKILL.md` documenta el límite de 100 líneas explícitamente con la tabla de satélites.
- **AC3**: `skill-template-protocol.md` tiene sección `## Progressive Disclosure` con formato canónico de satélites.
- **AC4**: El WARN no modifica el exit code del auditor — no bloquea CI.

## Progressive Disclosure — Satélites canónicos

```
.claude/skills/<nombre>/
├── SKILL.md          ← ≤100 líneas: entrada, workflow, references
├── REFERENCE.md      ← referencia técnica extensa, tablas, criterios
├── tests.md          ← casos de test y ejemplos negativos (anti-patterns)
├── examples.md       ← ejemplos concretos de input/output
└── DOMAIN.md         ← solo si hay terminología de dominio real
```

Regla: `SKILL.md` enlaza a los satélites en la sección `## Related`. Los satélites NO son cargados por defecto — el agente los lee bajo demanda.

## OpenCode Implementation Plan

```yaml
classification: PURE_BASH
files_touched:
  - scripts/skill-catalog-auditor.sh
  - templates/skills/_template/SKILL.md
  - docs/rules/domain/skill-template-protocol.md
requires_restart: false
verification: bash scripts/skill-catalog-auditor.sh --check
```

## Referencias

- `docs/rules/domain/skill-template-protocol.md` — protocolo actual (SE-153)
- `docs/ROADMAP.md#era-201` — Era 201 Skill quality discipline
- `scripts/skill-catalog-auditor.sh` — auditor actual
