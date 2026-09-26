---
name: skill-propose
description: "Proponer nuevo skill desde un workflow repetitivo — auto-genera scaffold si 3+ observaciones"
argument-hint: "{nombre} [--from-pattern descripcion]"
allowed-tools: [Read, Write, Glob, Grep, Bash, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /skill-propose — Proponer Skill desde Workflow Repetitivo

Regla: `@docs/rules/domain/skill-lifecycle.md`

## Flujo

1. Recibir nombre y descripcion del workflow repetitivo
2. Buscar si ya existe skill similar (por tags, nombre, descripcion)
3. Si existe: sugerir usar el existente
4. Si no existe: generar scaffold:
   - `.opencode/skills/{nombre}/SKILL.md` con frontmatter completo
   - `.opencode/skills/{nombre}/DOMAIN.md` con why/concepts/rules
5. Validar con consensus si disponible (score >= 0.75 = aprobado)
6. Mostrar resultado y preguntar si adoptar

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
💡 /skill-propose — Nuevo Skill
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
