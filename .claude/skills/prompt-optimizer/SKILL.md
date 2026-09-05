---
layer: peripheral
name: prompt-optimizer
description: Usar cuando se optimiza el prompt de un skill o agente para mejorar su efectividad.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Task]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Bucle auto-optimizador de prompts para skills y agentes. Ejecuta con test fixture, puntua contra checklist, modifica, re-ejecuta. Para cuando score >= 8/10 en 3 iteraciones. Bucle auto-optimizador de prompts para skills y agentes — patron AutoResearch. Ejecuta skill con test fixture, puntua output contra checklist, modifica prompt, re-ejecuta y compara scores. Guarda cambio si mejora, revierte si empeora. Criterio de parada: score >= 8/10 en 3 iteraciones consecutivas."
  savia.tags: "optimization, autoresearch, prompt-engineering, self-improvement"
  savia.user-invocable: True
---

# Skill: Prompt Optimizer (patron AutoResearch)

> Inspirado en: AutoResearch Loop (Eric Risco / Karpathy)
> "Si los prompts son codigo, necesitan un compilador que los optimice."

## Cuando usar

- Tras crear un skill o agente nuevo, para afinar su prompt
- Cuando un skill produce outputs inconsistentes o de baja calidad
- Para calibrar agentes de digestion contra documentos reales
- Periodicamente: re-optimizar skills con mas uso

## Que necesita

### 1. Target (skill o agente a optimizar)

```
.opencode/skills/{nombre}/SKILL.md    → skill
.opencode/agents/{nombre}.md          → agente
```

### 2. Test fixture (input + checklist)

Fichero en `.opencode/skills/{nombre}/test-fixtures/` o `.opencode/agents/test-fixtures/{nombre}/`:

```yaml
# test-fixture.yaml
name: "fixture-basic"
input: |
  [El input que normalmente le pasarias al skill/agente.
   Para digest agents: ruta a un documento real.
   Para spec-writer: descripcion de una task real.
   Para NL resolver: frase en lenguaje natural.]
checklist:
  - id: CHK-01
    criterion: "Extrae todas las entidades mencionadas"
    weight: 2
  - id: CHK-02
    criterion: "Resuelve ambiguedades con contexto del proyecto"
    weight: 2
  - id: CHK-03
    criterion: "Output dentro de 150 lineas"
    weight: 1
  - id: CHK-04
    criterion: "Formato correcto segun template"
    weight: 1
  - id: CHK-05
    criterion: "No inventa datos no presentes en el input"
    weight: 3
context:
  project: "proyecto-alpha"  # opcional: proyecto para cargar contexto
```

Si no existe fixture: el comando lo crea interactivamente.

### 3. Scorer (G-Eval adaptado)

Cada item del checklist se puntua 0-10. Score global = media ponderada por weight.

## Flujo del bucle

1. Cargar target + fixture + guardar backup
2. LOOP: ejecutar → puntuar (G-Eval) → registrar
3. Si score >= 8.0 en 3 consecutivas → PARAR (exito)
4. Si score < 8.0 → analizar items bajos → proponer cambio → aplicar → re-ejecutar
5. Si score subio → guardar cambio. Si bajo → revertir, intentar otro
6. Si max_iterations → PARAR (timeout)

## Tipos de cambio que puede hacer

Cambios permitidos al prompt del skill/agente:

- Reordenar instrucciones (priorizar lo que falla)
- Añadir ejemplos concretos (few-shot para items bajos)
- Hacer explicitas restricciones implicitas
- Simplificar instrucciones redundantes
- Añadir paso de verificacion para items que fallan

Cambios PROHIBIDOS:

- Cambiar el nombre o description del frontmatter
- Cambiar tools, model o permissionMode
- Eliminar reglas de seguridad o confidencialidad
- Añadir dependencias externas no presentes

## Output

### Fichero optimizado

```
.opencode/skills/{nombre}/SKILL.optimized.md     → skill
.opencode/agents/{nombre}.optimized.md            → agente
```

El original NO se modifica. El PM decide si adoptar la version optimizada.

### Log de optimizacion

`output/prompt-optimizer/{nombre}-{timestamp}.jsonl` — una linea JSON por iteracion
con: iteration, score, scores_by_item, change_applied, change_kept, timestamp.

### Resumen en chat

Score inicial → final, items mejorados, cambios aplicados/intentados, ruta del output.

## Restricciones

```
NUNCA → Modificar el fichero original (solo crear .optimized.md)
NUNCA → Eliminar reglas de seguridad del prompt
NUNCA → Cambiar frontmatter (name, tools, model)
NUNCA → Ejecutar mas de 10 iteraciones por defecto
SIEMPRE → Guardar backup antes de empezar
SIEMPRE → Registrar cada iteracion en el log
SIEMPRE → Mostrar progreso al PM entre iteraciones
```
