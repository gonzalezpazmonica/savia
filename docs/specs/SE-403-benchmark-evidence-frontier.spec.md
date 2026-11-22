---
status: IMPLEMENTED
approved_at: 2026-09-27
approval: "Operadora 2026-09-27: 'Redacta todas las specs que necesites y adelante con todas las propuestas en sprint nocturno'"
priority: P2
developer_type: agent-single
created: 2026-09-27
phase: C
risk: L2
related_specs: [SE-384, SE-387, SE-400]
origin: output/research/harness-mejoras-20260927.md (P1; Meta-Harness arXiv 2603.28052, hermes-agent-metaharness)
---

# SE-403 — Benchmark evidence: trazas crudas, frontera y hash de selección

## 1. Problema

`tests/self-evolution/run-benchmark.sh` (SE-384/387) ejecuta verificaciones
deterministas y escribe `last-<task>.json` con PASS/CHECK_FAIL. Tres huecos
impiden usarlo para decidir si un cambio de harness mejora Savia:

1. **Sin trazas**: se descarta stdout/stderr (`>/dev/null`). Meta-Harness muestra
   que el feedback útil está en las trazas completas, no en el resumen.
2. **Sin identidad de la selección**: nada impide comparar dos ejecuciones con
   conjuntos de tareas o comandos distintos.
3. **Sin frontera**: cada ejecución pisa la anterior; no hay "mejor conocido" contra
   el que comparar ni procedencia del candidato.

SE-384 está DEFERRED; este spec no lo reactiva: endurece el runner existente para
que, cuando se reactive, sus resultados sean comparables.

## 2. Diseño

### 2.1 Hash de selección

`selection_hash = sha256(json canónico de [(task_id, sha256(dataset/<task>.yaml), verif_cmd)] ordenado)`.
Se calcula antes de ejecutar y va en cada resultado y en el manifiesto.

### 2.2 Procedencia del candidato

Manifiesto por ejecución: `run_id` (UTC + 8 hex), `harness_commit` (`git rev-parse HEAD`),
`dirty` (bool), `runner_version` (2), `selection_hash`, `frontend` (`SAVIA_FRONTEND`
o `unknown`), `started_at`, `finished_at`.

### 2.3 Archivo de trazas

- Destino local: `${SAVIA_BENCH_DIR:-$HOME/.savia/benchmark}/runs/<run_id>/`
  (fuera del repo: las trazas pueden contener rutas y salidas N3; CRIT-001).
- Por tarea: `<task>.stdout`, `<task>.stderr`, `<task>.json` (status, exit, duración).
- `manifest.json` con §2.2 y agregado.
- El repo solo recibe `results/aggregate.json` como hoy (compatibilidad).

### 2.4 Frontera

- `${SAVIA_BENCH_DIR}/frontier.json`: por `selection_hash`, la mejor ejecución
  (más PASS; empate → menor duración total) con su `run_id` y `harness_commit`.
- Actualización atómica con `flock` sobre `frontier.lock`.
- `run-benchmark.sh --compare` imprime la ejecución actual frente a la frontera
  **solo** si coincide el `selection_hash`; si no, declara `INCOMPARABLE` y el
  motivo (tareas o comandos distintos).
- Una ejecución con `dirty=true` se archiva pero nunca entra en la frontera.

## 3. Criterios de aceptación

- AC1: Dos ejecuciones sobre el mismo dataset y comandos producen el mismo
  `selection_hash`; cambiar un comando o un YAML lo cambia.
- AC2: Cada ejecución crea un directorio de run con stdout/stderr por tarea y manifiesto.
- AC3: `--compare` devuelve `INCOMPARABLE` si difiere el `selection_hash`.
- AC4: La frontera solo se actualiza si la ejecución mejora, está limpia (`dirty=false`)
  y bajo `flock`; dos procesos concurrentes no la corrompen.
- AC5: `results/aggregate.json` conserva su formato actual (compatibilidad SE-387).
- AC6: Nada del run se escribe en el repo salvo `results/` (verificado en test).
- AC7: BATS con `SAVIA_BENCH_DIR` temporal y comandos de verificación simulados; auditor ≥ 80.

## 4. Fuera de alcance

- El agente proponente que lee trazas y propone candidatos (futuro, requiere SE-384 activo).
- Ejecución con sesiones de agente reales (`NEEDS_AGENT_SESSION` sigue igual).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Runner | `tests/self-evolution/run-benchmark.sh` | idéntico |
| Frontera / trazas | `~/.savia/benchmark/` | idéntico |

### Verification protocol

- [ ] Funciona sin frontend (bash puro)
- [ ] Tests no dependen de Claude Code ni OpenCode
- [ ] Sin hooks nuevos

### Portability classification

- [x] **PURE_BASH**: runner bash + python stdlib, sin bindings de frontend.
