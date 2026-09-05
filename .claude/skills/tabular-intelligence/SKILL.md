---
layer: peripheral
name: tabular-intelligence
description: "Usar cuando se analizan datos tabulares (CSV, Excel, tablas, metricas). Triggers: 'analiza esta tabla', 'metricas del sprint', 'tendencia de', 'distribucion de', 'correlacion entre', 'KPIs', 'datos financieros', 'perfil estadistico', 'resumen de datos', 'outlier'."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: analysis
  savia.context: project
  savia.maturity: stable
  savia.priority: high
  savia.tags: "tabular, datos, estadistica, analytics, csv, excel, perfil, metricas"
---

# tabular-intelligence

Analisis estadistico de datos tabulares sin pasar datos crudos al LLM.

## Pipeline

1. DETECT: identificar datos tabulares en el prompt (>5 filas)
2. EXTRACT: extraer a estructura columnar via tabular-profile.py
3. ANALYZE: computar perfil estadistico (media, std, quartiles, outliers, tendencia)
4. SUMMARIZE: generar resumen compacto (< 200 tokens)
5. REASON: el LLM interpreta el perfil, no los datos brutos

## Principios

- Zero-training: sin modelos, sin GPU, sin descargas
- Zero-hallucination: numeros exactos del computo
- Local-first: procesamiento local con Python/pandas

## Integracion

- MCP tool: tabular_query
- Self-audit: verifica uso de herramienta
- Agents: business-analyst, controlling-kpi, finance-*
