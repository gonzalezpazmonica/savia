---
name: pipeline-status
description: >
  Estado de pipelines del proyecto: últimas builds, % éxito,
  duración media y alertas de fallos recientes.
model_tier: fast
context_cost: low
tier: core
---

# Pipeline Status

**Argumentos:** $ARGUMENTS

> Uso: `/pipeline-status --project {p}` o `/pipeline-status --project {p} --pipeline {name}`

## Parámetros

- `--project {nombre}` — Proyecto de PM-Workspace (obligatorio)
- `--pipeline {nombre}` — Pipeline específica (opcional, si no: todas)
- `--last {n}` — Últimas N builds por pipeline (defecto: 5)
- `--branch {rama}` — Filtrar por rama (opcional)

## 2. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Infrastructure** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/tools.md`
   - `profiles/users/{slug}/projects.md`
3. Adaptar output según herramientas y entorno del usuario
4. Si no hay perfil → continuar con comportamiento por defecto

## 3. Contexto requerido

1. `projects/{proyecto}/CLAUDE.md` — `AZURE_REPOS_PROJECT` o nombre DevOps
2. `.opencode/skills/azure-pipelines/SKILL.md` — Referencia de estados y MCP tools

## 4. Pasos de ejecución

1. **Leer proyecto** → resolver nombre en Azure DevOps
2. **MCP `get_build_definitions`** → listar pipelines del proyecto
3. **Para cada pipeline** (o la específica si `--pipeline`):
   - MCP `get_builds` con `top=N` (defecto 5)
   - Calcular métricas:
     - % éxito (succeeded / total)
     - Duración media
     - Última ejecución (fecha + resultado)
     - Trend (mejorando / empeorando / estable)
4. **Detectar alertas:**
   - Build fallida en últimas 24h → alerta roja
   - Duración > 150% de la media → alerta amarilla
   - Pipeline sin ejecutar > 7 días → alerta gris
   - Coverage < `TEST_COVERAGE_MIN_PERCENT` → alerta naranja
5. **Presentar resumen:**

```
## Pipeline Status — {proyecto}

| Pipeline | Última build | Estado | % Éxito | Duración media | Alertas |
|---|---|---|---|---|---|
| backend-ci | #142 (hace 2h) | succeeded | 95% | 8m 23s | — |
| frontend-ci | #89 (hace 1d) | failed | 78% | 12m 10s | Build fallida |
| deploy-pre | #34 (hace 5d) | succeeded | 100% | 3m 45s | Sin ejecutar >5d |

### Alertas activas
- backend-ci: Coverage 72% (< 80% mínimo)
- frontend-ci: Build #89 fallida hace 1d — revisar con `/pipeline-logs --project {p} --build 89`
```

## 6. Integración con otros comandos

- `/pipeline-logs --build {id}` → ver logs de build fallida
- `/pipeline-run {pipeline}` → re-ejecutar pipeline
- `/kpi-dashboard` → incluye métricas de pipelines
- `/sprint-status` → muestra alertas de CI/CD si hay fallos

## 7. Restricciones

- Solo lectura — no modifica nada
- Si no hay pipelines configuradas → informar y sugerir `/pipeline-create`
- Máximo 20 pipelines mostradas (ordenar por última actividad)
