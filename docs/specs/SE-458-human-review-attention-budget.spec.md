---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-433, SE-445, SE-362, SE-376]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entradas 8 y 40)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-458 — Presupuesto de atención humana: tope de PRs esperando revisión, lotes y prioridad

## Problema

Savia limita el trabajo **en curso** (`route.wip_limit.savia_implementing: 4` en
`docs/propuestas/planning-state.json`, comprobado por `scripts/roadmap.sh`), pero no limita el trabajo
**que espera a una persona**. La revisión humana es el gate obligatorio (Rule 8,
`docs/rules/domain/autonomous-safety.md`) y es el recurso más escaso del sistema. Medido el
2026-10-23 sobre el repositorio:

- 20 PRs abiertas, las 20 en borrador, 15 creadas ese mismo día, con una sola revisora elegible.
- Búsqueda de `max_open_prs`, `review_budget`, «presupuesto de revisión/atención» y «PRs en espera»
  en `scripts/` y `docs/rules/domain/`: sin resultados. El único límite WIP es el de iniciativas.
- `scripts/merge-sprint.sh` (SE-433) acelera la salida (merges en serie bajo grant), pero no frena la
  entrada: cuanto más rápido abren PRs los agentes, más crece la cola que nadie entiende.

Un agente puede generar cambios más deprisa de lo que la persona puede comprenderlos y justificarlos.
Lo que se fusiona sin comprenderse es deuda aunque pase CI.

## Valor y evidencia

- «Comprehension debt»: coste diferido cuando la producción asistida supera la capacidad de explicar,
  probar, modificar y justificar (Mahmoud, arXiv 2609.29473, 24-sep-2026, revisión integradora; el
  término procede de Ahmad, arXiv 2604.13277). Verificado: la definición; no hay cifras trasladables.
- Anthropic, «How employment is changing at Anthropic» (16-oct-2026): describe más trabajo humano de
  vigilancia y coordinación de agentes. Verificado solo por resumen; estudio descriptivo de una
  empresa, no extrapolable. No se usan sus cifras.
- Evidencia propia, la que manda: la cola medida arriba.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | `scripts/review-budget.sh status|check` lee las PRs abiertas que esperan a una persona (borrador o pendientes de revisión, autor agente o rama `agent/*`) y compara con `route.review_budget.max_waiting` en `planning-state.json` (propuesta: 6). `check` sale 0 si hay hueco, 1 si está lleno, 2 si no puede saberlo (sin `gh`, sin red): contrato de SE-453, nunca «limpio» por defecto. |
| S2 | Gate en la creación de PR de agentes: el paso de PR de `pr-plan` y el cierre de los workers llaman a `check`. Lleno → no se abre la PR; el trabajo queda en su rama `agent/*` publicada y se registra en una cola (`~/.savia/review-queue.jsonl`, fuera del repo) con prioridad y tamaño. Desconocido → no se abre (fail-closed) y se dice por qué. |
| S3 | Lotes y prioridad: `review-budget.sh next` propone el siguiente lote para la revisora ordenado por prioridad (P0 primero), riesgo (tier SE-362) y tamaño (diff pequeño primero dentro de la misma prioridad); `promote` abre la PR del siguiente elemento de la cola cuando hay hueco. |
| S4 | Indicador visible: `roadmap.sh current` muestra `Revisión N/M` junto a `WIP`. |

## Fuera de alcance

- Cerrar o fusionar PRs automáticamente para liberar hueco.
- Medir comprensión real de la revisora (encuestas, telemetría de lectura).
- PRs humanas: el tope cuenta solo las de agentes.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | BATS con `gh` simulado (fixture JSON con 7 PRs de agente en espera y tope 6): `check` sale 1 y nombra el tope y el número. |
| AC2 | Mismo fixture con 5 PRs: `check` sale 0. |
| AC3 | Negativo: `gh` ausente o con error → `check` sale 2, no 0; el gate de S2 no abre la PR. |
| AC4 | Negativo: PRs humanas (sin rama `agent/*` ni autor agente) no cuentan; fixture con 10 humanas y 0 de agente → sale 0. |
| AC5 | Con el tope lleno, el cierre de worker deja la rama publicada, añade una línea a la cola con `branch`, `priority`, `tier`, `diff_lines` y no invoca `gh pr create` (espía en el test). |
| AC6 | `next` ordena un fixture de 4 elementos por prioridad, tier y tamaño; el test fija el orden esperado y falla si se invierte el criterio de tamaño. |
| AC7 | `roadmap.sh validate` PASS con `route.review_budget` presente y rechaza un valor no entero. |

## Riesgos

- Ralentiza a los agentes. Es el objetivo: el cuello real es la revisión. El tope lo fija la operadora.
- Cola fuera del repo que se pierde. Mitigación: la rama publicada es la fuente de verdad; la cola es
  un índice reconstruible desde `git ls-remote` de ramas `agent/*` sin PR.
- Contar mal por cambios de API de `gh`: el resultado desconocido bloquea, no deja pasar.

## Decisiones de la operadora

- **D1**: tope inicial (propuesta: 6 PRs de agente esperando revisión).
- **D2**: ¿excepción para P0 de seguridad por encima del tope? (propuesta: sí, una, y se registra).
- **D3**: ¿el plan intensivo hereda el tope o tiene uno propio temporal? (propuesta: el mismo).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `review-budget.sh` | script bash, sin frontend | el mismo |
| Gate de creación de PR | llamado desde `pr-plan` y el cierre de workers | el mismo script, invocado por los mismos comandos |

### Verification protocol

- [ ] Los tests corren sin frontend y con `gh` simulado.
- [ ] Sin hooks nuevos: el gate vive en el flujo de PR, no en PreToolUse.

### Portability classification

- [x] **PURE_BASH**: script y tests independientes del frontend.
