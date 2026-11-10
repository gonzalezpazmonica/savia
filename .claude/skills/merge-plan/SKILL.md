---
layer: peripheral
name: merge-plan
description: "Prepara el plan ordenado de un merge-sprint y lee sus choques previstos. Usar cuando se va a pedir un grant de merge, se revisa el orden del manifiesto, o aparece «#A chocará con #B»."
metadata:
  savia.agent: dev-orchestrator
  savia.category: pm-operations
  savia.context: standalone
  savia.context_cost: low
  savia.loop_level: L1  # L0=draft | L1=report-only | L2=assisted | L3=unattended — ver docs/rules/domain/loop-phasing.md
  savia.maturity: beta
  savia.priority: medium
  savia.summary: "Plan ordenado de merge-sprint (SE-500 S3): order y collisions en el manifiesto, cubiertos por el digest; avisos de choque para la pregunta del grant."
  savia.tags: "merge-sprint, grant, plan, se-500, se-433"
  savia.trigger_keywords: "merge-plan, plan del merge-sprint, orden del manifiesto, chocará con"
---

# Skill: merge-plan (SE-500 S3)

Ordena las candidatas de un merge-sprint para fusionar más y avisa de los choques previstos antes del grant.

## Authoritative Paths

| Para | Lee este path |
|---|---|
| Ejecutor (`plan`, `render-question`, `run`) | `scripts/merge-sprint.sh` (función `plan_order`) |
| Spec | `docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md` § S3 |
| Regla del flujo y del grant | `docs/rules/domain/autonomous-safety-merge-sprint.md` |
| Tests de referencia | `tests/test-merge-sprint-se500.bats` (AC-17 a AC-20) |

Si un path no existe, aborta y reporta.

## Cuándo usar

- Vas a pedir un grant de merge-sprint y necesitas el orden y los choques previstos.
- `plan` imprimió «#A chocará con #B en f» y hay que decidir qué hacer antes del grant.
- Quieres saber por qué `run` fusiona en un orden que no es el ascendente.

## Cuándo NO usar

- Para fusionar: eso es `run` bajo un grant firmado, nunca esta skill.
- Para resolver conflictos: los decide `run` (resync y equivalencia de S2).

## Qué hace `plan` (S3)

1. Por cada par de candidatas, `git merge-tree --write-tree --name-only` entre sus heads revisados.
2. Descarta registros y derivados (mismo criterio que el resolutor): no generan aviso (AC-19).
3. Orden: primero un conjunto sin choques entre sí, voraz por grado ascendente y luego número; después las que chocan, por número.
4. Escribe `order` y `collisions` (`{pr, with, files}`) en el manifiesto; el digest los cubre (AC-20).
5. Imprime `orden: #…`, «#A chocará con #B en f1, f2», solapamientos sin conflicto y pares no calculables.

## Decision Checklist

1. ¿Hay líneas «chocará con»? → si sí: llévalas literales a la pregunta del grant; la operadora puede excluir PR o pedir antes un trabajador.
2. ¿Hay «colisión no calculable»? → el head no está en el repo; no lo des por independiente: dilo en la pregunta.
3. ¿Se editó el manifiesto tras `plan`? → no se concede: hay que repetir `plan`; `run` para si el digest no coincide.

## Límites

- Heurística por pares: no simula la secuencia real contra `main`; admite falsos positivos y negativos.
- El orden solo mejora cuando una PR choca con varias (estrella); en par aislado o cadena no gana nada (AC-17b).
- Modifica SE-433 §2.5 (orden ascendente); el orden sigue congelado bajo el grant y `run` no reordena.

## Related

- Rule: `docs/rules/domain/autonomous-safety-merge-grant.md`
- Spec previa: SE-433 (merge-sprint)
