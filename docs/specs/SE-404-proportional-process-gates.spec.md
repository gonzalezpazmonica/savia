---
status: IMPLEMENTED
approved_at: 2026-09-27
approval: "Operadora 2026-09-27: 'Redacta todas las specs que necesites y adelante con todas las propuestas en sprint nocturno'"
priority: P1
developer_type: agent-single
created: 2026-09-27
phase: B
risk: L3
related_specs: [SE-079, SE-080, SE-236, SE-275]
origin: output/research/harness-mejoras-20260927.md (P3 ODD, P4 RDD; gentle-ai)
---

# SE-404 — Proceso proporcional: G13 v2 y una corrección por revisión

## 1. Problema

### 1.1 G13 obliga a usar el override

En el sprint 2026-09-27, 5 de 6 PRs usaron `Scope-trace: skip`. La causa no es
que los PRs se salgan de alcance, sino dos defectos de G13 (`pr-plan-gates.sh`):

1. Busca la spec solo en `docs/propuestas/`. Las specs SE-3xx/4xx viven en
   `docs/specs/` → "spec referenced but file not found (gate skipped)".
2. Solo extrae tokens de criterios con formato checkbox `- [ ] AC-n`. Las specs
   con `- AC1:` o `- **AC1**` (la mayoría) no aportan ningún token → todo fichero
   es `NO MATCH`.
3. Las menciones de rutas con comodín (`docs/rules/domain/*.md`) no se reconocen.

Un override que se usa siempre deja de ser señal.

### 1.2 Arreglos de tests rotos sin spec

Un fix que repara un test que fallaba no encaja en ninguna spec: hoy entra por
override. Falta una vía ligera y verificable.

### 1.3 Ciclos de corrección sin límite efectivo

El Court permite 3 rondas de fix sobre la misma revisión (`COURT_MAX_FIX_ROUNDS`).
Cada ronda revisa un candidato distinto bajo el mismo `.review.crc`: la revisión
deja de corresponder a una versión congelada.

## 2. Diseño

### 2.1 G13 v2

- Localiza specs en `docs/propuestas/` **y** `docs/specs/`.
- Tokens de AC en los formatos `- [ ] AC-n`, `- [x] AC-n`, `- ACn:`, `- AC-n:`,
  `- **ACn**` y `ACn:` al inicio de línea.
- Rutas mencionadas con comodín (`*`, `**`) se comparan como patrón glob.
- Self-spec: tocar el propio fichero de la spec en cualquiera de los dos directorios.
- Cada uso de `Scope-trace: skip` se registra en `output/g13-overrides.jsonl`
  (fecha, rama, motivo) para medir la tasa.

### 2.2 Clase "fix trazado a test roto"

Línea en `.pr-summary.md`: `Fix-trace: <ruta de test .bats o .py>` (una o varias).
G13 acepta el PR sin override si:

1. El test existe en HEAD.
2. **Falla en la base** (`merge-base origin/main HEAD`), ejecutado en un worktree
   temporal desacoplado, con timeout (`G13_FIX_TRACE_TIMEOUT`, 300 s).
3. **Pasa en HEAD**.
4. Cada fichero cambiado es el propio test, un fichero que el test referencia
   (ruta literal en el test), un derivado de la lista blanca de G13 o un
   `CHANGELOG.d/*`.

Si falla cualquier condición → FAIL con el motivo exacto. Un test que ya pasaba
en la base no justifica nada.

### 2.3 Una corrección por revisión

- `COURT_MAX_FIX_ROUNDS` pasa de 3 a 1.
- Tras la ronda de fix, si el Court no pasa: se cierra la revisión con veredicto
  `fail` y cualquier nueva corrección abre una revisión nueva (nuevo `.review.crc`
  con `previous_review: <sha256 del anterior>`).
- `court-review.sh` rechaza un `.review.crc` con más de una ronda de fix.

## 3. Criterios de aceptación

- AC1: G13 encuentra una spec en `docs/specs/` y extrae tokens de AC en los seis formatos del §2.1.
- AC2: Un fichero mencionado por glob en la spec (`docs/rules/domain/*.md`) pasa G13.
- AC3: Cada override queda registrado en `output/g13-overrides.jsonl`.
- AC4: `Fix-trace` con un test que falla en base y pasa en HEAD, y cambios dentro de su cadena, pasa G13 sin override.
- AC5: `Fix-trace` con un test que ya pasaba en base → FAIL "test did not fail at base".
- AC6: `Fix-trace` con un fichero cambiado fuera de la cadena del test → FAIL nombrando el fichero.
- AC7: `COURT_MAX_FIX_ROUNDS=1` en las definiciones del Court (Claude Code y OpenCode) y en `code-review-court.md`.
- AC8: `court-review.sh` rechaza `.review.crc` con más de una ronda de fix.
- AC9: Tests BATS con repos git temporales; auditor ≥ 80.

## 4. Riesgo

L3: cambia un gate de `pr-plan` y el comportamiento del Court. Revisión humana
explícita del PR concreto (SE-362) antes de merge.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| G13 v2 | `scripts/pr-plan-gates.sh` | idéntico |
| Court orchestrator | `.claude/agents/court-orchestrator.md` | `.opencode/agents/court-orchestrator.md` |
| Validación crc | `scripts/court-review.sh` | idéntico |

### Verification protocol

- [ ] G13 es bash puro: mismo comportamiento en ambos frontends
- [ ] Las dos definiciones del orchestrator declaran el mismo límite (test)
- [ ] Sin hooks nuevos

### Portability classification

- [x] **DUAL_BINDING**: gates en bash común; definiciones de agente actualizadas en ambos frontends en el mismo slice.
