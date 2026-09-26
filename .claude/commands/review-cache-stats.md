---
name: review-cache-stats
description: Estadísticas de la caché de code review
agent-single: azure-devops-operator
skills:
  - azure-devops-queries
model_tier: fast
context_cost: low
tier: core
---

# /review-cache-stats

Muestra estadísticas de la caché de code review automatizado.

---

## Flujo

### 1. Banner inicio

```
╔══════════════════════════════════════╗
║  📊 Review Cache Stats              ║
╚══════════════════════════════════════╝
```

### 2. Ejecutar stats

```bash
bash "$CLAUDE_PROJECT_DIR/scripts/review-cache.sh" stats
```

### 3. Información adicional

Mostrar:
- Entradas cacheadas (PASSED) y tamaño
- Hash de reglas actual y última actualización
- Estimación de tokens ahorrados
- Hit rate si hay datos disponibles

### 4. Banner fin

```
╔══════════════════════════════════════╗
║  ✅ Review Cache Stats — Completo   ║
╚══════════════════════════════════════╝
⚡ /compact
```
