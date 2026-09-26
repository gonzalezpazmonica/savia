---
name: ceremony-health
description: Métricas de salud de ceremonias — duración, participación, resolution rate
agent: task
context_cost: medium
model_tier: mid
tier: core
---

# /ceremony-health

> 🦉 Audita salud de ceremonias Scrum: duración real vs. target, participación, resolution rate.

---

## Parámetros

- `--project {nombre}` — Proyecto (obligatorio)
- `--sprint {nombre}` — Sprint específico (defecto: actual)
- `--sprints {n}` — Análisis últimas N ceremonias (defecto: 4)
- `--ceremony {planning|review|retro|standup|refinement}` — Ceremonias (defecto: todas)
- `--metric {duration|participation|items|resolution}` — Métrica (defecto: todas)

---

## Contexto requerido

1. `projects/{proyecto}/CLAUDE.md` — Config duración target
2. `projects/{proyecto}/team.md` — Equipo para participación
3. Histórico: Azure DevOps, Google Calendar, `ceremonies/*.md`

---

## Ejecución

### 1. Recolectar datos (por cada sprint)
- Planning: duración, PBIs, decisiones
- Daily: frecuencia, duración, participación
- Review: duración, asistentes, demos
- Retro: duración, temas, action items
- Refinement: duración, PBIs refinadas

### 2. Calcular métricas por ceremonia
- **Duración**: real vs target (100% si ≤ target)
- **Participación**: % asistencia (100% si ≥ 80%)
- **Ítems**: PBIs/hora, bloqueantes, acción items
- **Score**: promedio 0-10 (≥8 bueno, 5-7 mejorable, <5 crítico)

### 3. Detectar problemas
- Duración > target × 1.5
- Participación < 70%
- Reunión sin output
- Action items sin owner
- Actions retro anterior no completadas

### 4. Generar reporte
Salida en `output/ceremony-health/YYYYMMDD-health-{proyecto}.md`:
- Resumen: score por ceremonia (emoji + nota)
- Tabla: problemas detectados con causa sugerida
- Recomendaciones por plazo (corto/medio/largo)

---

## Integración

- `/sprint-review` → health check automático de ceremonia
- `/sprint-retro` → incluir check de retro anterior
- `/health-dashboard` → subsección ceremony-health

---

## Restricciones

- Read-only: NUNCA modificar datos históricos
- Recomendaciones son sugerencias
- Si participación < 50%: datos insuficientes
