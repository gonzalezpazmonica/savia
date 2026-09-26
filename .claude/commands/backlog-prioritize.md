---
name: backlog-prioritize
description: Priorización automática RICE/WSJF con datos reales de esfuerzo y valor
developer_type: all
agent: task
context_cost: high
model_tier: mid
tier: core
---

# /backlog-prioritize

> 🦉 Savia calcula prioridad objetiva: Reach, Impact, Confidence, Effort (RICE) o Weighted Shortest Job First (WSJF).

---

## Cargar perfil

Grupo: **Backlog Intelligence** — cargar:

- `CLAUDE.md` — proyecto activo
- `projects/{proyecto}/CLAUDE.md` — config
- `company/strategy.md` — OKRs y alineación estratégica
- Backlog items desde Azure DevOps
- Histórico de Story Points (velocity)

---

## Subcomandos

- `/backlog-prioritize` — RICE score por defecto
- `/backlog-prioritize --method wsjf` — usar WSJF en lugar de RICE
- `/backlog-prioritize --strategy-aligned` — ponderar por alineación con OKRs
- `/backlog-prioritize --effort-weighted` — ponderar por esfuerzo estimado

---

## Flujo

### Paso 1 — Cargar items y datos

Cargar backlog (sin Done) + Story Points + histórico 3 sprints para velocidad media.

### Paso 2 — Calcular RICE

`RICE = (Reach × Impact × Confidence) / Effort`

- Reach (1-100): usuarios afectados, escala relativa TAM
- Impact (1-3): 1=minor, 2=medium, 3=major
- Confidence (0-100%): madurez del spec (Poor=50%, High=100%)
- Effort (1-20): Story Points históricos

Si PBI sin SP → pedir estimation antes de calcular.

### Paso 3 — Calcular WSJF (alternativa)

`WSJF = (Business Value + Time Criticality + Risk) / Job Size`

- Todos 1-5 (Business Value, Criticality, Risk Reduction, Job Size)
- Usar si equipo es SAFe o prefiere scoring cualitativo

### Paso 4 — Ponderar por estrategia (opcional)

Si se usa `--strategy-aligned`:

```
Score_final = Score_base × (1 + Strategy_weight)

Donde Strategy_weight:
  - Item NO contribuye a OKR → 0.8 (penalizar)
  - Item contribuye a 1 KR → 1.0 (neutro)
  - Item contribuye a 2+ KR → 1.3 (priorizar)
```

Leer `company/strategy.md` para vincular items a KRs.

### Paso 5 — Presentar ranking ordenado

```
# Backlog Prioritization — {proyecto}

Método: RICE | Generado: {fecha}
Velocidad media (3 sprints): {SP/sprint}

## Top 20 Items Priorizados

| Rango | PBI ID | Título | Reach | Impact | Conf. | Effort | RICE Score | Estrategia |
|-------|--------|--------|-------|--------|-------|--------|------------|-----------|
| 1 | #2341 | Feature X | 80 | 3 | 90% | 5 SP | 432 | OKR 1.2 + 2.1 |
| 2 | #2338 | Bug critical | 50 | 3 | 100% | 2 SP | 225 | Tech debt |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |

## Items en cola (21-50) — mostrar resumen solo
[Tabla comprimida con rango 21-50]

## Recomendación de capacidad actual

Capacidad sprint: NNN SP
Items para este sprint (score ≥ X): NNN SP
Items para 2-3 sprints próximos: NNN SP

## Insights

- Top 3 items cubren X% del OKR principal
- Y items sin alineación estratégica (considerar deprioritizar)
- Esfuerzo promedio top 10: Z SP/item

---

## Vincular a company/strategy.md

Si existe strategy.md:

```markdown
## Alineación Estratégica

### OKR 1: {nombre}
  Key Result 1.1 — contribuidores top:
    - #2341 (RICE 432)
    - #2342 (RICE 310)
    - #2350 (RICE 205)
  Status: 3 items, NNN SP total, contribución estimada: Y%
```

---

## Modo agente (role: "Agent")

```yaml
status: ok
action: backlog_prioritization
method: "rice"  # o "wsjf"
items_prioritized: {n}
top_item_id: {id}
top_item_score: {score}
strategy_aligned: {boolean}
file_path: "output/prioritization/YYYYMMDD-backlog-prioritize-{proyecto}.md"
recommended_sprint_items: {n}
recommended_sprint_effort_sp: {n}
```

---

## Restricciones

- **NUNCA** sobrescribir Story Points sin acuerdo del equipo
- **NUNCA** usar RICE para comparar items entre proyectos (contextos distintos)
- Reach es siempre relativo al dominio — documentar la escala asumida
- Si el 50%+ de items no tiene SP → pedir estimation sesión de planning
- Máximo 3 columnas de ponderación para no saturar tabla
