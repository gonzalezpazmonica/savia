---
name: memory-rotate
description: Execute context rotation manually — daily, weekly, monthly cycles
argument-hint: "[daily|weekly|monthly|status]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read]
tier: core
---

# /memory-rotate — Rotacion manual de contexto (SE-033)

**Argumentos:** `$ARGUMENTS` (default: `status`)

## Modos

| Modo | Que hace |
|------|----------|
| `status` | Muestra tamano, edad session-hot, entries, ultimo weekly |
| `daily` | Rota session-hot.md si tiene >24h (archiva a archive/sessions/) |
| `weekly` | Archiva memorias project >7d, genera resumen semanal |
| `monthly` | Ejecuta memory-hygiene + consolida + verifica cap 25KB |

## Ejecucion

```bash
bash scripts/context-rotation.sh ${ARGUMENTS:-status}
```

Mostrar output completo al usuario. Si el modo es `monthly` y el tamano
supera 25KB, informar cuantas entries se archivaron.

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /memory-rotate — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
