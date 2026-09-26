---
name: criticality-dashboard
description: "Vista cross-project de items criticos P0-P3 con heatmap por equipo"
argument-hint: "[--project nombre] [--level portfolio|project|team|person]"
allowed-tools: [Read, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /criticality-dashboard — Panel de Criticidad

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`
Spec: `@.opencode/skills/smart-calendar/spec-task-criticality.md`

## Razonamiento

Piensa paso a paso:
1. Primero: recopilar items de todas las fuentes (Azure DevOps, Savia Flow, calendar)
2. Luego: calcular criticality_score con 5 dimensiones + auto-escalado temporal
3. Finalmente: presentar dashboard con alertas por nivel

## Flujo

1. Detectar nivel solicitado (default: portfolio si multi-proyecto, project si uno)
2. Recopilar items activos de todas las fuentes de datos:
   - Azure DevOps / Savia Flow: PBIs, tasks en sprint activo
   - Calendar: deadlines proximos (7/14/30 dias)
   - Meeting-digest: action items comprometidos
3. Para cada item, calcular criticality_score:
   - impacto (0.30) + urgencia (0.25) + dependencias (0.20) + confianza (0.15) + esfuerzo_inv (0.10)
   - Aplicar auto-escalado temporal segun dias hasta deadline
   - Aplicar confidence_decay segun dias sin validacion
   - Clasificar perfil CoD: Standard / Fixed-date / Expedite / Intangible
4. Clasificar: P0 (>=4.0), P1 (3.0-3.9), P2 (2.0-2.9), P3 (<2.0)
5. Verificar reglas de negocio:
   - P0 sin asignar → alerta inmediata
   - >3 P0 simultaneos → alerta capacidad critica
   - P3 con confidence <0.3 → candidatos eliminacion
6. Presentar dashboard por nivel solicitado

## Template de Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Criticality Dashboard — [fecha]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 P0 Critical (X items)
  AB#XXXX | [titulo] | score: X.X | [proyecto] | [asignado]

🟠 P1 High (X items)
  AB#XXXX | [titulo] | score: X.X | [proyecto] | [asignado]

🟡 P2 Medium (X items) — resumen
🟢 P3 Low (X items) — resumen

⚠️ Alertas:
  - [alertas de reglas de negocio]

📊 Heatmap: [proyecto1: 2P0 1P1] [proyecto2: 0P0 3P1]
```

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 /criticality-dashboard — Panel de Criticidad
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
