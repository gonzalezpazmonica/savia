---
name: lesson-extract
description: Extract a cross-project lesson from the current task
argument-hint: "[--domain domain --problem \"...\" --solution \"...\"]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /lesson-extract — Extraer leccion cross-project (SE-032)

**Argumentos:** `$ARGUMENTS`

Si no se proporcionan argumentos, preguntar al usuario:
1. Dominio (error-handling, architecture, testing, security, performance, deployment, etc.)
2. Problema (1-2 frases)
3. Solucion (1-2 frases)
4. Proyectos involucrados (opcional)

Ejecutar:
```bash
bash scripts/lesson-pipeline.sh extract $ARGUMENTS
```

Mostrar resultado y ruta del fichero generado.
