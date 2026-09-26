---
name: risk-predict
description: Predicción de riesgo del sprint basada en datos históricos y señales tempranas
developer_type: all
agent: task
context_cost: high
model_tier: mid
tier: core
---

# /risk-predict

> 🦉 Savia anticipa problemas antes de que bloqueen tu sprint.

---

## Cargar perfil de usuario

Grupo: **Sprint & Daily** — cargar:

- `identity.md` — nombre
- `workflow.md` — daily_time
- `projects.md` — proyecto target
- `tone.md` — alert_style

---

## Subcomandos

- `/risk-predict` — predicción completa del sprint actual
- `/risk-predict --sprint {N}` — predicción para un sprint específico
- `/risk-predict --item {id}` — riesgo de un PBI/Task concreto

---

## Flujo

### Paso 1 — Recopilar señales

Analizar datos del sprint actual y compararlos con históricos:

1. **Burndown**: ¿la curva real diverge de la ideal? ¿Cuándo empezó?
2. **WIP**: ¿items en progreso > WIP limit? ¿Items estancados >2 días?
3. **Scope creep**: ¿se han añadido items tras el planning?
4. **Bloqueos**: ¿items bloqueados sin resolver >1 día?
5. **Velocidad de cierre**: ¿ritmo de cierre vs. ritmo necesario?
6. **Histórico**: ¿sprints anteriores con patrones similares fallaron?

### Paso 2 — Calcular probabilidades

```
📊 Risk Prediction — Sprint {N} (día {X}/{total})

  Probabilidad de completar Sprint Goal: {N}%

  Factores de riesgo:
  ├─ Burndown deviation: {N}% por debajo de ideal → {impacto}
  ├─ WIP overflow: {N} items en paralelo (limit: {N}) → {impacto}
  ├─ Scope creep: +{N} SP añadidos post-planning → {impacto}
  ├─ Stale items: {N} items sin mover >2 días → {impacto}
  └─ Historical pattern match: similar a Sprint {X} que {outcome}

  Confianza del modelo: {alta/media/baja} (basado en {N} sprints históricos)
```

### Paso 3 — Items en riesgo

| Item | Riesgo | Señal | Recomendación |
|---|---|---|---|
| PBI#1234 | 🔴 Alto | Sin avance 3 días, depende de API externa | Escalar bloqueante |
| PBI#1235 | 🟡 Medio | Estimación baja (3SP real vs 2SP estimado) | Reasignar ayuda |
| PBI#1236 | 🟢 Bajo | En track, 80% completado | Continuar |

### Paso 4 — Recomendaciones de mitigación

```
💡 Recomendaciones (ordenadas por impacto)

  1. Escalar PBI#1234 — bloqueante desde hace 3 días
  2. Renegociar scope — retirar PBI#1240 (bajo valor, añadido post-planning)
  3. Pair programming en PBI#1235 — subestimado, necesita refuerzo
  4. Si {probabilidad} < 70% → considerar reducir Sprint Goal
```

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: risk_predict
sprint: "Sprint 2026-08"
completion_probability: 72%
items_at_risk: 2
top_risk: "PBI#1234 — blocked 3 days"
recommendation: "escalate_blocker"
confidence: "medium"
```

---

## Restricciones

- **NUNCA** predecir con <3 sprints de histórico — indicar "datos insuficientes"
- **NUNCA** culpar a personas — las señales son sobre items, no sobre developers
- **NUNCA** recomendar reducir scope sin presentar alternativas
- Transparencia: siempre mostrar en qué datos se basa la predicción
- La predicción mejora con más datos — indicar confianza del modelo
