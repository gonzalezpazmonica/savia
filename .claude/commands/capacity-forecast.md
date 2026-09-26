---
name: capacity-forecast
description: Previsión de capacidad a medio plazo — planifica recursos para los próximos 3-6 sprints
developer_type: all
agent: task
context_cost: high
model_tier: mid
tier: core
---

# /capacity-forecast

> 🦉 Savia te dice si tienes equipo suficiente para lo que viene.

---

## Cargar perfil de usuario

Grupo: **Reporting** — cargar:

- `identity.md` — nombre, rol
- `preferences.md` — language, detail_level
- `projects.md` — proyecto(s)
- `tone.md` — formality

---

## Subcomandos

- `/capacity-forecast` — previsión para los próximos 3 sprints
- `/capacity-forecast --sprints {N}` — previsión para N sprints
- `/capacity-forecast --scenario hire` — simula contratar +1 persona
- `/capacity-forecast --scenario leave {nombre}` — simula baja de una persona

---

## Flujo

### Paso 1 — Calcular capacidad base

Para cada sprint futuro:

1. Miembros del equipo activos
2. Restar vacaciones planificadas, festivos, formaciones
3. Aplicar factor de dedicación (si no es 100%)
4. Multiplicar por velocity por persona (histórico)

### Paso 2 — Calcular demanda del backlog

1. PBIs pendientes priorizados con estimación
2. Roadmap comprometido: features con deadline
3. Deuda técnica presupuestada
4. Buffer para bugs/urgencias (histórico: ~{N}% de capacidad)

### Paso 3 — Comparar oferta vs demanda

```
📊 Capacity Forecast — {proyecto}

  Sprint    | Capacidad | Demanda | Balance | Estado
  ──────────|───────────|─────────|─────────|──────────
  Sprint 8  | 42 SP     | 38 SP   | +4 SP   | 🟢 OK
  Sprint 9  | 35 SP     | 45 SP   | -10 SP  | 🔴 Déficit
  Sprint 10 | 42 SP     | 40 SP   | -2 SP   | 🟡 Ajustado

  ⚠️ Sprint 9: vacaciones de 2 personas + feature comprometida
```

### Paso 4 — Simulaciones what-if

```
💡 Escenarios

  Escenario A — Contratar +1 dev (ramp-up 2 sprints):
    Sprint 9: -10 SP → -5 SP (parcial)
    Sprint 10: -2 SP → +6 SP (plena capacidad)

  Escenario B — Renegociar deadline Feature X:
    Sprint 9: -10 SP → +2 SP (mover 12 SP a Sprint 10)
    Sprint 10: -2 SP → -14 SP (acumulación)

  Escenario C — Reducir debt budget 15% → 5%:
    Sprint 9: -10 SP → -6 SP (gana 4 SP, acumula deuda)
```

### Paso 5 — Recomendación

Evaluar trade-offs y sugerir la opción con mejor balance riesgo/beneficio.

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: capacity_forecast
project: "sala-reservas"
sprints_forecasted: 3
deficit_sprints: 1
total_deficit_sp: -10
recommendation: "renegotiate_deadline"
```

---

## Restricciones

- **NUNCA** recomendar reducir calidad o eliminar testing para ganar capacidad
- **NUNCA** sugerir overtime como solución sostenible
- **NUNCA** usar capacity forecast para microgestión individual
- Las previsiones más allá de 3 sprints tienen baja confianza — indicarlo
- Siempre presentar múltiples escenarios, nunca una sola opción
