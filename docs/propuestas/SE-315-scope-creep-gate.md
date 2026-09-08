---
id: SE-315
title: "SE-315 — Scope Creep Gate: detección de diffs fuera de alcance de la spec"
status: IMPLEMENTED
priority: media
timeline:
  - from: "2026-08-10"
    learned: "2026-08-10"
    value: "IMPLEMENTED"
    source: "PR #955 — scope-declare.sh + scope-creep-check.sh + gate G17"
---

# SE-315 — Scope Creep Gate: detección de diffs fuera de alcance de la spec

**Status:** PROPOSED
**Fecha:** 2026-08-09
**Area:** Agent governance / Code review / CI gates
**Branch sugerida:** `agent/se315-scope-creep-gate`
**Estimacion total:** ~20h (3 slices)
**Inspiracion:** `Shubhamsaboo/awesome-llm-apps` → agent_skills/scope-creep-detector

---

## Contexto y evidencia (2026-08-09)

El workspace ejecuta SDD con specs aprobadas y gates de calidad (commit-guardian,
ast-quality-gate, pr-plan G0-G15). Estos gates verifican formato, confidencialidad,
tamaño y schema — pero **ninguno verifica que el diff del PR corresponda al
alcance declarado en la spec que lo motiva**.

Evidencia del gap:

- Un dev (humano o agente) puede tocar ficheros ajenos a la spec en el mismo
  commit; los gates actuales no lo detectan.
- Los fixes de CI (como los de este PR #952) mezclan cambios de specs, agentes y
  scanner en commits cuyo scope difiere del título. Es la norma, no la excepción.
- `scope-creep-detector` de awesome-llm-apps resuelve esto para Claude Code:
  compara el diff contra la declaración de intención y recomienda *keep / split /
  justify*. Savia no tiene equivalente.

**El hueco.** El commit-guardian valida *reglas*, no *intención*. Un diff que
excede la spec pasa todos los gates verdes sin que nadie lo señale.

---

## Objetivo

Añadir un gate determinista que compare el diff de un PR contra el alcance
declarado de su spec (paths declarados, ficheros tocados, dependencias) y emita
veredicto `IN_SCOPE | EXTRA_FILES | MIXED_SCOPE` con recomendación accionable
(keep / split / justify).

---

## Out of scope

- NO bloquear PRs en primera versión (report-only hasta calibración).
- NO analizar *semántica* del cambio (eso es code-review E1 humano).
- NO tocar el pipeline SDD de generación de specs.

---

## Diseno

### S1 — Extracción de alcance declarado

`scripts/scope-declare.sh <spec-file>` extrae de una spec SE-XXX aprobada:
paths de ficheros esperados (secciones `ficheros`, `archivos`, ACs con rutas),
directorios raíz y dependencias declaradas. Output JSON.

### S2 — Comparador diff vs alcance

`scripts/scope-creep-check.sh --spec <spec> --base <main> --head <HEAD>`:
compara `git diff --name-only` contra el alcance extraído. Clasifica cada
fichero en `declared | related (mismo dir) | unrelated`. Emite:
- `IN_SCOPE` (todo declared/related)
- `EXTRA_FILES` (unrelated, con lista)
- `MIXED_SCOPE` (declared + unrelated en el mismo PR)

Recomendación: keep (justificado por changelog), split (commit separado),
o justify (comentario en PR).

### S3 — Integración como gate report-only

- Hook en `pr-plan-gates.sh` (nuevo check G17) y en CI como job `Scope Creep`
  inicialmente `continue-on-error: true`.
- Reporte a `output/scope-creep-{pr}.json` + resumen en el body del PR.
- Telemetría SE-313: evento `scope.verdict` con veredicto y nº de files extra.

---

## Criterios de aceptacion

### AC-S1: Extracción de alcance

- [x] AC-S1.1: `scope-declare.sh` extrae paths de una spec SE-XXX real
  (fixture) y emite JSON con `declared_paths` y `root_dirs`.
- [x] AC-S1.2: spec sin sección de ficheros → `declared_paths: []` y WARN.

### AC-S2: Comparador

- [x] AC-S2.1: diff 100% declared → `IN_SCOPE`.
- [x] AC-S2.2: diff con 1 fichero unrelated → `EXTRA_FILES` listándolo.
- [x] AC-S2.3: diff declared + unrelated → `MIXED_SCOPE` con ambos grupos.
- [x] AC-S2.4: exit codes 0 (in-scope) / 0 (report-only, con veredicto no-cero
  en JSON) / 2 (usage).

### AC-S3: Integración

- [x] AC-S3.1: check G17 en `pr-plan-gates.sh` ejecuta el comparador y reporta.
- [x] AC-S3.2: CI job `Scope Creep` corre en PRs y no bloquea (report-only).
- [ ] AC-S3.3: `scope.verdict` aparece en `output/telemetry-events.jsonl`.
- [ ] AC-S3.4: 5 PRs históricos probados producen veredicto coherente con
  inspección manual (documentado en spec o reporte).

### Delta correctivo 2026-09-08 — resolución consistente de specs

**RCA:** G17 local y el job CI solo buscaban en `docs/propuestas/` y después
en `projects/*/specs/`; omitían `docs/specs/` y elegían silenciosamente la
primera coincidencia. El gate de aprobación ya usa los tres espacios y falla
ante IDs ambiguos, por lo que los diagnósticos divergían.

- [x] AC-S3.5: un único resolver cubre `docs/propuestas/`, `docs/specs/` y
  `projects/*/specs/` tanto en G17 como en CI.
- [x] AC-S3.6: un ID duplicado produce `AMBIGUOUS` y nunca selección por orden.
- [x] AC-S3.7: una referencia de ruta exacta desambigua de forma explícita.

**Implantación:** `scripts/spec-resolve.sh` es la fuente compartida para G17,
CI y el gate de aprobación. Pruebas: `tests/test-spec-resolve.bats` y
`tests/test-spec-approval-gate.bats` (2026-09-08). Revisión E1 pendiente.

---

## Ref

- `Shubhamsaboo/awesome-llm-apps` → `agent_skills/scope-creep-detector`
- `scripts/pr-plan-gates.sh`, `docs/rules/domain/agent-skill-rubric.md` (SE-274)
