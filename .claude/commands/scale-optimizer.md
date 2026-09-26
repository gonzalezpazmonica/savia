---
name: scale-optimizer
description: "Scaling optimization — analyze, benchmark, recommend improvements for growing organizations"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[analyze|benchmark|recommend|knowledge-search] [--search query]"
model_tier: mid
context_cost: medium
tier: core
---

# /scale-optimizer — Optimización de Escala

> Skill: @.opencode/skills/scaling-operations/SKILL.md
> Config: @docs/rules/domain/scaling-patterns.md

Análisis de madurez organizacional, benchmarking contra tier targets, recomendaciones de optimización, búsqueda de conocimiento.

## Subcomandos

### `/scale-optimizer analyze`

Detectar tier actual y métricas:
- Cuántos proyectos/personas
- Context usage patterns
- Meeting time
- Async/sync ratio
- Output: tier classification + gap analysis

### `/scale-optimizer benchmark`

Comparar contra tier targets:
- Scorecard por aspecto
- Discrepancias identificadas
- Output: benchmark report + ratings

### `/scale-optimizer recommend`

Plan de optimización priorizado:
- Acciones ordenadas por ROI
- Esfuerzo estimado (SP)
- Output: roadmap de mejora

### `/scale-optimizer knowledge-search --search query`

Full-text search across knowledge:
- ADRs, specs, decision-log
- Rules, agent memory
- Output: resultados + relevancia

## Datos almacenados

```
output/scaling/
├── analyze-YYYYMMDD.md
├── benchmark-YYYYMMDD.md
└── recommend-YYYYMMDD.md
```

## Integración

| Comando | Relación |
|---|---|
| `/team-orchestrator` | Input: team structure data |
| `/portfolio-overview` | Input: project metrics |
| `/enterprise-dashboard` | Input: org metrics |
