---
spec_id: SE-209
title: Canonical description format for SKILL.md
status: IMPLEMENTED
drift_note: "drift: components existed pre-triage (Description Protocol SE-209 section in docs/rules/domain/skill-template-protocol.md line 79 with canonical format + trigger validation)"
implemented_at: "2026-06-24"
priority: P1
effort: B
era: 201
origin: output/research/mattpocock-skills-savia-20260607.md
inspiration: mattpocock/skills description-as-trigger protocol
---

# SE-209 — Formato canónico para description en SKILL.md

## Problema

El campo `description` en el frontmatter de SKILL.md no tiene formato normalizado. Resultado:

- Algunas descriptions son solo el nombre de la skill sin trigger ("Usar cuando se lee o escribe...").
- Otras son phrases largas sin criterio de activación claro.
- El keyword routing de SE-203 depende de que las descriptions sean legibles como triggers.
- 102 skills con descriptions heterogéneas → routing semántico degradado.

## Solución

Formato canónico: `[qué hace]. Usar cuando [triggers específicos].` — máximo 200 caracteres. Compatible con SE-203 keyword routing.

## Scope

### 1. `scripts/skill-catalog-auditor.sh`

Añadir WARN heurístico si `description`:
- Tiene menos de 20 caracteres (demasiado corta para ser útil).
- No contiene ninguna de las palabras `when`, `cuando`, `Usar`, `Use` (ausencia de trigger explícito).

El WARN es **no bloqueante** (AC4). Implementar como función `check_description_format`.

### 2. `templates/skills/_template/SKILL.md`

Actualizar el campo `description` del frontmatter de ejemplo:

```yaml
# Antes (genérico):
description: "TEMPLATE — copia este directorio para crear una skill nueva."

# Después (formato canónico, como ejemplo en comentario):
# description: "[Qué hace esta skill en una frase]. Usar cuando [trigger 1],
#               [trigger 2], o [trigger 3]. Max 200 chars."
```

### 3. `docs/rules/domain/skill-template-protocol.md`

Añadir sección `## Description Protocol`:

- Formato: `[qué]. Usar cuando [triggers].`
- Máximo 200 caracteres (compatibilidad SE-203).
- Al menos 1 trigger explícito con situación detectable.
- Prohibido: descriptions que solo repiten el nombre de la skill.
- Relación con SE-203: la description es la fuente primaria para keyword routing.

### 4. Audit one-liner

Script o one-liner para listar las skills cuyas descriptions no siguen el formato:

```bash
# Uso: bash scripts/skill-catalog-auditor.sh --description-audit
# Output: lista de skills con warnings de formato de description
```

Alternativa directa:
```bash
grep -rL "cuando\|when\|Usar\|Use" .claude/skills/*/SKILL.md | \
  grep -v "_template" | sed 's|.*/\([^/]*\)/SKILL.md|\1|'
```

## Acceptance Criteria

- **AC1**: El template tiene description de ejemplo con formato `[qué]. Usar cuando [triggers].` (como comentario o valor real).
- **AC2**: `skill-catalog-auditor.sh` emite WARN si description < 20 chars o no contiene `when`/`cuando`/`Usar`/`Use`.
- **AC3**: `skill-template-protocol.md` documenta el protocolo en sección `## Description Protocol` con relación a SE-203.
- **AC4**: El WARN no modifica el exit code del auditor — no bloquea CI.

## Formato canónico — ejemplos

```yaml
# Bien formado:
description: "Audita compliance legal contra legislación española. Usar cuando se crea
              un contrato, se procesa PII, o hay incertidumbre sobre RGPD/LSSI."

# Bien formado (EN):
description: "Maps architecture dependencies. Use when designing a new feature,
              evaluating trade-offs, or at the start of design sessions."

# Mal formado (demasiado corto, sin trigger):
description: "Legal compliance."

# Mal formado (sin trigger explícito):
description: "Herramienta para gestionar la agenda con sincronización Outlook."
```

## OpenCode Implementation Plan

```yaml
classification: PURE_BASH
files_touched:
  - scripts/skill-catalog-auditor.sh
  - templates/skills/_template/SKILL.md
  - docs/rules/domain/skill-template-protocol.md
requires_restart: false
verification: bash scripts/skill-catalog-auditor.sh --description-audit
```

## Referencias

- `docs/rules/domain/skill-template-protocol.md` — protocolo actual (SE-153)
- `docs/propuestas/SE-203-skill-keyword-triggers.md` — keyword routing
- `docs/ROADMAP.md#era-201` — Era 201 Skill quality discipline
