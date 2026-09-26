---
name: policy-check
description: "Verificar politicas de agente para un proyecto — mostrar permisos y restricciones"
argument-hint: "[--project nombre]"
allowed-tools: [Read, Glob, Grep]
model_tier: fast
context_cost: low
tier: core
---

# /policy-check — Politicas de Agentes del Proyecto

Regla: `@docs/rules/domain/agent-policies.md`

## Flujo

1. Resolver proyecto (argumento o proyecto activo)
2. Buscar `projects/{proyecto}/agent-policies.yaml`
3. Si existe: mostrar politicas activas (paths, actions, limits, network)
4. Si no existe: mostrar defaults conservadores
5. Listar violaciones recientes de `output/policy-violations.jsonl` (si hay)

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ /policy-check — Politicas de Agentes
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
