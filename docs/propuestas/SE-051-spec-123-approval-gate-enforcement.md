---
id: SE-051
title: SE-051 — SPEC-123 approval gate enforcement
status: IMPLEMENTED
origin: output/audit-arquitectura-20260420.md (architect audit)
author: Savia
priority: Critica
effort: S 2h
gap_link: D14 Rule #8 erosion
approved_at: "2026-04-20"
applied_at: "2026-04-20"
batches: [6]
expires: "2026-05-20"
---

# SE-051 — SPEC-123 approval gate enforcement

## Purpose

graph-temporal-ops.sh merged sin spec aprobada. Dos caminos: revert o fast-approve. Gate pre-commit detecta scripts cuya spec linked esta PROPOSED.

**Gap enlazado**: D14 Rule #8 erosion (ver audit-arquitectura-20260420.md).

## Objective

Unico y medible: cerrar el gap descrito con Slice 1 scaffolding + BATS tests.

## Slicing

- **Slice 1**: probe/scaffolding + BATS tests (≥15 tests, ≥80 auditor score).
- **Slice 2**: implementacion enforcement o integracion.
- **Slice 3**: rollout + deprecation de comportamiento anterior si aplica.

## Acceptance criteria

- Script ejecutable con --help, --json, exit codes 0/1/2.
- Tests BATS con isolation guards (read-only, no side effects en repo).
- Documentacion en docs/rules/domain/ si aplica (≤150 lineas).

## Refs

- audit-arquitectura-20260420.md §Matriz de desincronizaciones
- audit-new-specs-20260420.md §SE-051
- audit-roadmap-reprioritization-20260420.md

## Delta correctiva — resolución canónica (2026-09-08)

Causa raíz: `spec_status()` sólo buscaba en `docs/propuestas`, aunque las specs
canónicas también viven en `docs/specs` y `projects/*/specs`. Esto producía
`NOT_FOUND` al modificar código correctamente trazado. Además, los estados
`IMPLEMENTING` e `IN_PROGRESS`, posteriores a una aprobación, no se reconocían.

Criterios añadidos:

- GIVEN una única spec `IMPLEMENTING` en `docs/specs`, WHEN se audita un script
  staged que la referencia, THEN el gate resuelve la spec y permite continuar.
- GIVEN el mismo ID en dos ubicaciones canónicas, WHEN se audita su referencia,
  THEN el gate devuelve `AMBIGUOUS` y bloquea, aunque ambas copias estén aprobadas.
- La resolución permanece read-only y no amplía el allow-list explícito.
