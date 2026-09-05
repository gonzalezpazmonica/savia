---
layer: peripheral
name: doc-quality-feedback
description: Usar cuando se recopila feedback de calidad de documentación tras usar skills y reglas.
allowed-tools: [Read, Write, Glob, Grep, Bash]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: experimental
  savia.priority: medium
  savia.summary: Sistema de feedback de calidad de documentacion. Los agentes puntuan skills y reglas tras usarlas. Agregacion mensual detecta docs de baja calidad para reescritura. Sistema de feedback de calidad de documentacion. Los agentes puntuan skills y reglas tras usarlas. Aggregacion mensual detecta docs de baja calidad para reescritura.
  savia.tags: "feedback, documentation, self-improvement"
  savia.user-invocable: True
---

# Skill: Doc Quality Feedback

> Inspirado en Context Hub: agent annotations que persisten entre sesiones.
> Loop auto-mejora: agentes usan doc → puntuan → aggregacion → reescritura.

## Cuando usar

- Despues de que un agente usa una skill o regla (automatico via protocol)
- Mensualmente para auditar calidad de documentacion
- Cuando un skill produce outputs inconsistentes (posible doc confusa)

## Como funciona

### Rating por agentes

Cuando un agente usa un skill/regla y termina, puede emitir un rating:

```json
{
  "doc": ".opencode/skills/codebase-map/SKILL.md",
  "agent": "architect",
  "rating": "clear",
  "note": "Instructions were unambiguous",
  "timestamp": "2026-03-19T02:00:00Z"
}
```

Ratings posibles:
- **clear**: instrucciones claras, output correcto al primer intento
- **confusing**: instrucciones ambiguas, requirio re-interpretacion
- **incomplete**: falta informacion para completar la tarea
- **outdated**: informacion desactualizada que causo error
- **wrong**: informacion incorrecta

### Almacenamiento

`public-docs-feedback/{doc-name-sanitized}.jsonl` — una linea JSON por rating.
Ejemplo: `public-docs-feedback/skills--codebase-map--SKILL.jsonl`

### Aggregacion

`/docs-quality-audit` lee todos los JSONL y produce:
- Score por doc: % ratings positivos (clear) vs negativos (confusing+incomplete+outdated+wrong)
- Docs con >30% ratings negativos → flagged para reescritura
- Tendencia: ¿mejoran o empeoran los docs con el tiempo?
- Top 5 docs mas usados (por numero de ratings)
- Top 5 docs peor puntuados (candidatos a `/skill-optimize`)

### Protocolo de emision

Los agentes NO estan obligados a emitir rating en cada ejecucion.
El rating es voluntario y se emite cuando el agente detecta una de las condiciones:
- Tuvo que re-interpretar una instruccion ambigua → confusing
- No encontro informacion que necesitaba → incomplete
- Encontro informacion incorrecta → wrong/outdated
- Todo funciono sin friccion → clear (emitir 1 de cada 5 veces para no saturar)

## Formato del JSONL

```json
{"doc":"path","agent":"name","rating":"clear|confusing|incomplete|outdated|wrong","note":"...","ts":"ISO"}
```

## Integracion

- **skill-auto-activation**: docs con rating bajo pierden prioridad de sugerencia
- **skill-optimize**: docs con rating bajo son candidatos prioritarios
- **hub-audit**: cruzar ratings con hub score para priorizar reescrituras
- **session-init**: si hay docs criticos (>50% negativo), alertar al PM
