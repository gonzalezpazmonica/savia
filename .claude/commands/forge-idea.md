---
name: forge-idea
description: Forja una idea mediante interrogatorio socratico con veredicto ternario ENDURECIDA/MAS_CLARA/MUERTA (SE-269 S1)
model_tier: mid
context_cost: medium
tier: core
---

Forjar una idea antes de que se convierta en spec.

## Flujo

1. Recibir la idea del usuario (texto o fichero)
2. Ejecutar: `bash scripts/forge-idea.sh --idea "<texto>" [--adversarial]`
3. El script verifica linea_roja (CRITERIO.md) y emite veredicto ternario
4. Interpretar el veredicto:
   - **ENDURECIDA**: la idea esta lista para alimentar spec-generate
   - **MAS_CLARA**: la idea avanzo pero tiene preguntas abiertas
   - **MUERTA**: la idea contradice un CRIT linea_roja — murio barata, es exito del comando

## Modo adversarial

Invocar con `--adversarial` para que la forja busque activamente el fallo:
supuestos no verificados, costes ocultos, alternativas mas simples, evidencia contraria.

## Contraste automatico

Si el proyecto tiene Knowledge Graph activo, la forja contrasta las afirmaciones
de la idea contra el KG y las specs archivadas. Una idea que contradice un CRIT
linea_roja muere en la forja sin llegar a spec (AC-1.3).

## Residuo de decision

Cada sesion deja su residuo en `output/forge-residue.jsonl` con >=1 decision y su motivo.
El residuo es recuperable por el contexto de la cupula activa (engrams SE-256, AC-1.5).

## Limite de turnos

Maximo 20 turnos por defecto. Al agotarse, veredicto MAS_CLARA con preguntas abiertas registradas (AC-1.6).
