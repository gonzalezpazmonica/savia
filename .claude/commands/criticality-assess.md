---
name: criticality-assess
description: "Evaluar criticidad de un item con desglose de 5 dimensiones y perfil CoD"
argument-hint: "{item-id} [--project nombre]"
allowed-tools: [Read, Bash, Glob, Grep]
model_tier: mid
context_cost: low
tier: core
---

# /criticality-assess — Evaluacion de Criticidad

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`
Spec: `@.opencode/skills/smart-calendar/spec-task-criticality.md`

## Flujo

1. Resolver item: buscar por ID en Azure DevOps, Savia Flow o backlog local
2. Recopilar datos del item: titulo, estado, asignado, SP, deadline, dependencias
3. Calcular cada dimension:
   - **Impacto** (0.30): valoracion de negocio (manual o inferida de Kano/priority)
   - **Urgencia** (0.25): dias hasta deadline + perfil CoD + auto-escalado
   - **Dependencias** (0.20): contar items/personas bloqueados downstream
   - **Confianza** (0.15): fecha ultima validacion × confidence_decay
   - **Esfuerzo inv** (0.10): 6 - min(5, ceil(SP/4))
4. Calcular score: sum(dimension × peso)
5. Clasificar: P0/P1/P2/P3
6. Identificar perfil Cost of Delay: Standard/Fixed-date/Expedite/Intangible
7. Sugerir accion segun clasificacion

## Template de Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Criticality Assessment — AB#XXXX
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 [Titulo del item]
   Proyecto: [nombre] | Estado: [estado] | SP: [n] | Asignado: [persona]

📊 Desglose de Criticidad:
   Impacto de negocio  ████░ 4/5  × 0.30 = 1.20
   Urgencia temporal   ███░░ 3/5  × 0.25 = 0.75
   Dependencias        ██░░░ 2/5  × 0.20 = 0.40
   Confianza           ████░ 4/5  × 0.15 = 0.60
   Esfuerzo inverso    ███░░ 3/5  × 0.10 = 0.30
                                   ──────────
   Score total:                      3.25

🏷️ Clasificacion: P1 High
📈 Perfil CoD: Fixed-date (deadline: 2026-04-01)
⚡ Accion: Resolver en este sprint. 13 dias hasta deadline.
```

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 /criticality-assess — Evaluacion Individual
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
