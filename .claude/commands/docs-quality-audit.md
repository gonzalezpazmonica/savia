---
name: docs-quality-audit
description: "Auditar calidad de documentacion basada en feedback de agentes"
argument-hint: "[--threshold 30] [--period 30d]"
allowed-tools: [Read, Glob, Grep, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# /docs-quality-audit — Auditar Calidad de Docs

Ejecutar skill: `@.opencode/skills/doc-quality-feedback/SKILL.md`

## Flujo

1. Leer todos los JSONL en `public-docs-feedback/`
2. Agregar ratings por documento: % clear vs negativo
3. Filtrar por threshold (default: 30% negativo = flagged)
4. Generar reporte: top docs peor puntuados, tendencia, recomendaciones
5. Guardar en `output/docs-quality-audit-{fecha}.md`

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 /docs-quality-audit — Calidad de Docs
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
