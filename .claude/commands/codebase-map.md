---
name: codebase-map
description: "Generar mapa de dependencias internas del workspace: comandos → agentes → reglas → skills"
argument-hint: "[--focus commands|agents|rules|skills] [--orphans]"
allowed-tools: [Read, Glob, Grep, Bash]
model_tier: mid
context_cost: medium
tier: core
---

# /codebase-map — Mapa de Dependencias Internas

Ejecutar skill: `@.opencode/skills/codebase-map/SKILL.md`

## Parametros

- `$ARGUMENTS`:
  - `--focus {tipo}` — filtrar por tipo: commands, agents, rules, skills
  - `--orphans` — mostrar solo componentes huerfanos (sin consumidores)

## Flujo

```
1. Escanear .opencode/commands/, agents/, rules/domain/, skills/
2. Extraer referencias @ y menciones entre componentes
3. Construir grafo de dependencias
4. Calcular hub scores y detectar huerfanos
5. Guardar en output/codebase-map-{fecha}.md
6. Mostrar resumen: hubs, huerfanos, estadisticas
```

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🗺️ /codebase-map — Dependencias Internas
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
