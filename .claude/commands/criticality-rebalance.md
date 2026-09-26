---
name: criticality-rebalance
description: "Redistribuir carga de trabajo del equipo respetando criticidad y capacidad"
argument-hint: "[--project nombre] [--team equipo] [--dry-run]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /criticality-rebalance — Rebalanceo por Criticidad

Ejecutar skill: `@.opencode/skills/smart-calendar/SKILL.md`
Spec: `@.opencode/skills/smart-calendar/spec-task-criticality.md`

## Cuando usar

- Tras cambio de prioridades (nuevo P0, deadline adelantado)
- Persona sobrecargada con items criticos
- Desequilibrio detectado por `/team-workload` o `/criticality-dashboard`
- Sprint mid-point si hay desviacion significativa

## Razonamiento

Piensa paso a paso:
1. Primero: snapshot actual de asignaciones + criticality_score por item
2. Luego: detectar desequilibrios (persona con >2 P0, persona sin P0 con holgura)
3. Finalmente: proponer reasignaciones respetando skills y capacidad

## Flujo

1. Recopilar items activos con criticality_score (usa `/criticality-dashboard`)
2. Recopilar capacidad por persona: horas disponibles, skills, WIP actual
3. Detectar desequilibrios:
   - Persona con >2 items P0/P1 simultaneos
   - Persona con WIP >2 items activos
   - Items P0 sin asignar o asignados a persona sin capacidad
   - Items P0 asignados a persona sin skill requerido
4. Proponer reasignaciones:
   - Mover items P2/P3 de personas sobrecargadas a personas con holgura
   - Reasignar items P0 a persona con skill + capacidad disponible
   - NO mover items en progreso avanzado (>50% completado)
5. Si `--dry-run`: solo mostrar propuesta sin aplicar
6. Si no dry-run: confirmar con PM antes de aplicar cambios

## Restricciones

- NUNCA reasignar sin confirmacion del PM
- NUNCA mover items en progreso avanzado sin justificacion
- Respetar skills requeridos (no asignar backend a frontend-only)
- Respetar WIP limit de 2 items activos por persona
- Items Expedite (P0 auto) tienen prioridad absoluta en asignacion

## Template de Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 Criticality Rebalance — [proyecto]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 Estado actual:
   alice: 3 items (2×P0, 1×P1) — SOBRECARGADA
   bob:   1 item  (1×P2)       — CON HOLGURA

🔀 Propuesta de reasignacion:
   1. AB#101 (P1, 3SP) alice → bob  | Motivo: alice tiene 2×P0
   2. AB#205 (P0, sin asignar) → bob | Motivo: skill match + capacidad

📋 Resultado proyectado:
   alice: 2 items (2×P0)  — EN LIMITE
   bob:   2 items (1×P0, 1×P1) — EQUILIBRADO

¿Aplicar cambios? [S/n]
```

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔄 /criticality-rebalance — Equilibrar por Criticidad
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
