---
name: kpi-dora
description: >
  Dashboard de métricas DORA: deployment frequency, lead time for changes,
  change failure rate, MTTR y reliability.
model_tier: mid
context_cost: medium
tier: core
---

# KPI DORA

**Argumentos:** $ARGUMENTS

> Uso: `/kpi-dora --project {p}` o `/kpi-dora --project {p} --sprints 10`

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🚀 /kpi-dora — Métricas DORA
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Reporting** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/preferences.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `preferences.language`, `preferences.detail_level`, `preferences.report_format` y `tone.formality`
4. Si no hay perfil → continuar con comportamiento por defecto

## 3. Parámetros

- `--project {nombre}` — Proyecto (obligatorio)
- `--sprints {n}` — Período de análisis (defecto: 5)
- `--pipeline {nombre}` — Pipeline específica (opcional)
- `--compare {proyecto2}` — Comparar con otro proyecto
- `--export` — Guardar informe en `output/dora/`

Si falta `--project`:
```
❌ Falta parámetro obligatorio: --project {nombre}
   Proyectos disponibles: [listar]
   Uso: /kpi-dora --project nombre
```

## 4. Verificar prerequisitos

```
Verificando requisitos para métricas DORA...
  ✅ Proyecto: projects/{proyecto}/CLAUDE.md
  ✅ Azure DevOps: PAT válido
  ⚠️ Pipelines: Se verificará disponibilidad de datos
```

Si no hay PAT → modo interactivo o error claro.

## 4. Ejecución con progreso

```
📋 Paso 1/4 — Obteniendo historial de pipelines...
📋 Paso 2/4 — Filtrando deploys a producción...
📋 Paso 3/4 — Calculando métricas DORA...
📋 Paso 4/4 — Clasificando rendimiento...
```

### Métricas calculadas

| Métrica | Fuente | Cálculo |
|---|---|---|
| Deployment Frequency | MCP `get_builds` | Deploys PRO por semana/mes |
| Lead Time for Changes | MCP `get_builds` + repos | Commit → deploy PRO |
| Change Failure Rate | MCP `get_builds` | Builds fallidas PRO / total |
| MTTR | MCP `get_builds` | Tiempo fallo → fix en PRO |
| Reliability | Sentry + pipelines | Uptime estimado |

### Benchmarks DORA 2025

| Métrica | Elite | High | Medium | Low |
|---|---|---|---|---|
| Deploy Frequency | Multi/día | 1/sem-1/mes | 1/mes-6/mes | < 1/6m |
| Lead Time | < 1 día | 1d-1sem | 1sem-1mes | > 1 mes |
| Change Failure Rate | < 5% | 5-10% | 10-15% | > 15% |
| MTTR | < 1 hora | < 1 día | < 1 semana | > 1 sem |

## 5. Mostrar resultado

```
## DORA Metrics — {proyecto} — Últimos {n} sprints

| Métrica | Valor | Clasificación | Tendencia |
|---|---|---|---|
| Deploy Frequency | 3.2/semana | Elite | 📈 +15% |
| Lead Time | 2.1 días | High | 📉 -0.5d |
| Change Failure Rate | 8% | High | → estable |
| MTTR | 45 min | Elite | 📉 -12min |

Clasificación global: HIGH PERFORMER

Recomendación: Reducir lead time automatizando merge → deploy
```

Si `--export` → guardar en `output/dora/YYYYMMDD-dora-{proyecto}.md`

## 6. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /kpi-dora — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Clasificación: {ELITE/HIGH/MEDIUM/LOW} PERFORMER
```

## Integración

- `/kpi-dashboard` → incluye resumen DORA
- `/pipeline-status` → datos fuente
- `/project-audit` → usa DORA para evaluar madurez CI/CD
- `/report-executive` → incluye DORA en informe directivo

## Restricciones

- Requiere historial de pipelines (mínimo 1 sprint con deploys)
- Si no hay pipeline PRO → informar y calcular sobre DEV/PRE
- Benchmarks DORA 2025 como referencia, no objetivo rígido
