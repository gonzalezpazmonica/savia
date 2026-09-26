---
name: ai-exposure-audit
description: "Auditoría de exposición IA por rol — observed exposure, riesgo de desplazamiento, reskilling"
developer_type: all
agent: task
context_cost: high
model_tier: mid
argument-hint: "[--team equipo] [--role rol] [--threshold 50] [--lang es|en]"
tier: core
---

# /ai-exposure-audit — Auditoría de Exposición IA

> 🦉 Savia mide cuánto de cada rol ya está siendo automatizado vs. cuánto podría estarlo.
> Fuente: Anthropic "Labor Market Impacts of AI" (2026) — observed exposure framework.

---

## Cargar perfil de usuario

Grupo: **Team & Strategy** — cargar:

- `identity.md` — nombre, rol
- `projects.md` — proyecto(s)
- `preferences.md` — language, detail_level
- `equipo.md` — miembros, roles, seniority

---

## Subcomandos

- `/ai-exposure-audit` — auditoría completa del equipo
- `/ai-exposure-audit --role {rol}` — análisis de un rol específico
- `/ai-exposure-audit --team {equipo}` — análisis de un equipo
- `/ai-exposure-audit --threshold {N}` — solo roles con exposición > N%
- `/ai-exposure-audit reskilling` — plan de reconversión por rol

---

## Flujo

### Paso 1 — Mapear tareas por rol

Para cada rol del equipo, descomponer en tareas O*NET-style:

1. Listar tareas core del rol (6-12 por rol)
2. Clasificar cada tarea: cognitive-routine, cognitive-nonroutine, manual
3. Asignar peso relativo (% del tiempo dedicado)

### Paso 2 — Calcular exposición teórica vs. observada

Para cada tarea:

```
┌──────────────────────────────────────────────────────────┐
│  EXPOSICIÓN TEÓRICA   = ¿Puede la IA hacer esta tarea?  │
│  EXPOSICIÓN OBSERVADA = ¿Ya se está automatizando?       │
│  GAP DE ADOPCIÓN      = Teórica - Observada              │
└──────────────────────────────────────────────────────────┘
```

Escala 0-100 por tarea. Score del rol = media ponderada por peso.

### Paso 3 — Clasificar riesgo de desplazamiento

```
🦉 AI Exposure Audit — {equipo}

  Rol           | Teórica | Observada | Gap  | Riesgo
  ──────────────|─────────|───────────|──────|────────
  Data Entry    | 85%     | 67%       | 18%  | 🔴 Alto
  QA Manual     | 72%     | 45%       | 27%  | 🔴 Alto
  Dev Backend   | 65%     | 33%       | 32%  | 🟡 Medio
  PM/Scrum      | 40%     | 15%       | 25%  | 🟢 Bajo
  Architect     | 30%     | 10%       | 20%  | 🟢 Bajo

  🔴 Alto (>60% observada): Desplazamiento activo
  🟡 Medio (30-60%): Transición en curso
  🟢 Bajo (<30%): Augmentation predominante
```

### Paso 4 — Análisis augmentation vs. automation

Para cada rol, clasificar el uso actual de IA:

- **Automation** — la IA reemplaza la tarea (el humano ya no la hace)
- **Augmentation** — la IA amplifica al humano (más rápido, mejor calidad)

Ratio: `augmentation_pct / (augmentation_pct + automation_pct)`

### Paso 5 — Plan de reskilling

Para roles con riesgo 🔴 o 🟡, generar rutas concretas:

```
🎯 Reskilling — Data Entry (riesgo 🔴)

  Habilidades actuales    → Habilidades objetivo
  ─────────────────────────────────────────────
  Entrada de datos        → Data quality assurance
  Validación manual       → Diseño de reglas de validación
  Formato documentos      → Prompt engineering para templates

  Plazo estimado: 8-12 semanas
  Recursos: ai-competency-framework nivel 2 → 3
```

Output guardado en: `output/analytics/ai-exposure-YYYYMMDD.md`

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: ai_exposure_audit
team_size: 8
roles_analyzed: 5
high_risk_roles: 2
medium_risk_roles: 1
low_risk_roles: 2
avg_theoretical_exposure: 58
avg_observed_exposure: 34
adoption_gap: 24
augmentation_ratio: 0.65
reskilling_plans_generated: 3
```

---

## Restricciones

- **NUNCA** usar como justificación para despidos — es herramienta de planificación
- **NUNCA** compartir scores individuales sin consentimiento del afectado
- **NUNCA** asumir que alta exposición = rol innecesario (augmentation ≠ replacement)
- Objetivo: anticipar y preparar, no alarmar
- Siempre incluir rutas de reskilling junto al diagnóstico de riesgo
- Citar fuente Anthropic cuando se use el framework de observed exposure

---

## Referencias

- Anthropic, "The Labor Market Impacts of AI" (2026) — observed exposure
- O*NET Task Framework — descomposición de tareas por ocupación
- @docs/rules/domain/ai-exposure-metrics.md — métricas de exposición
- @docs/rules/domain/ai-competency-framework.md — niveles de competencia IA
