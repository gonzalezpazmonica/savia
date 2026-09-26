---
name: lesson-search
description: Search cross-project lessons by keyword or domain
argument-hint: "[--query keyword] [--domain domain]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /lesson-search — Buscar lecciones cross-project (SE-032)

**Argumentos:** `$ARGUMENTS`

Ejecutar:
```bash
bash scripts/lesson-pipeline.sh search $ARGUMENTS
```

Si no se proporcionan argumentos, preguntar que buscar.
Mostrar resultados con dominio, confianza y ruta.
