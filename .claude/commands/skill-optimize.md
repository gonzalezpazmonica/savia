---
name: skill-optimize
description: "Auto-optimizar el prompt de un skill o agente con bucle AutoResearch"
argument-hint: "{skill-name|agent-name} [--fixture nombre] [--max-iterations 10]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /skill-optimize — Prompt Optimizer (patron AutoResearch)

Ejecutar skill: `@.opencode/skills/prompt-optimizer/SKILL.md`

## Parametros

- `$ARGUMENTS` — nombre del skill o agente a optimizar
  - Si es un skill: busca en `.opencode/skills/{nombre}/SKILL.md`
  - Si es un agente: busca en `.opencode/agents/{nombre}.md`
- `--fixture {nombre}` — nombre del test fixture a usar (default: buscar en test-fixtures/)
- `--max-iterations N` — maximo de iteraciones (default: 10)

## Razonamiento

Piensa paso a paso:
1. Localizar el target (skill o agente) y verificar que existe
2. Buscar o crear test fixture con input + checklist
3. Ejecutar bucle: run → score → modify → compare → keep/revert
4. Parar cuando score >= 8.0 en 3 iteraciones consecutivas o max iterations

## Flujo

```
1. Resolver target: skill o agente
2. Buscar fixture en test-fixtures/
   Si no existe → pedir al PM: input de prueba + checklist (5-8 criterios)
   Guardar fixture para reutilizar
3. Crear backup: {target}.backup
4. Ejecutar bucle AutoResearch (ver SKILL.md)
5. Guardar resultado como {target}.optimized.md
6. Mostrar resumen: score inicial, score final, cambios aplicados
7. Preguntar al PM: "Adoptar la version optimizada?"
   Si → renombrar optimized a original (backup se mantiene)
   No → mantener original, optimized disponible para revision
```

## Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 /skill-optimize — AutoResearch Loop
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Target: {nombre}
Fixture: {fixture}
Max iteraciones: {N}
```
