# SE-381 — Risk-Weighted Behavioral Eval Matrix

**Estado:** SUPERSEDED — propuesta de Savia del 2026-11-09: el gate de bloqueo pendiente pasa a SE-468; vale al fusionar la PR. Estado anterior, DEFERRED, y aprobación original: Mónica (operadora), 2026-09-05: "Apruebo todas, implementa, pr y merge"
**Prioridad:** P1 · **Developer Type:** agent-team · **Context Risk:** medium
**Origen:** auditoría externa §12 (PARTIALLY_ALREADY_SOLVED)

## 1. Motivación

La infraestructura de evals es fuerte y debe REUTILIZARSE (no hay framework nuevo): `tests/evals/` con baselines+golden+paired-delta, `evals-ci.yaml`, gates G16 (eval-lint golden sets) y G18 (RCA eval ≥80) en pr-plan, `run-adversarial-evals.sh`. Lo que falta: cobertura conductual **proporcional al riesgo** por capability y un informe que distinga cobertura estructural / conductual / safety.

## 2. Matriz mínima por risk_level

| Nivel | Cobertura exigida |
|---|---|
| L0 | Smoke test |
| L1 | Golden scenarios |
| L2 | Golden + edge cases |
| L3 | Golden + adversarial + regression baseline |
| L4 | L3 + negative safety tests + deterministic enforcement tests + unsafe-action test + bypass attempts |

## 3. Reglas

- Reutilizar paired-delta existente; regresiones bloquean cuando corresponde.
- Oracle determinista preferente; LLM judge solo donde no exista oracle fiable.
- Judge model suficientemente capaz respecto al sistema evaluado (LEC-3: diversidad documentada si aplica).
- Baseline versionado en repo (plain-text inspeccionable — CRIT-001, todo local).

## 4. Criterios de aceptación

- 100% de capabilities L3/L4 con su fila de matriz completa.
- CI muestra cobertura ponderada por riesgo (informe JSON + markdown).
- El informe distingue las tres coberturas; regresiones paired-delta bloquean merge.
- Ningún framework de eval nuevo creado; gaps cubiertos extendiendo el actual.

## 5. OpenCode Implementation Plan

### Clasificación
- **Tier:** 2 · **Agent-capable:** yes
- **Slices:** S1 eval-coverage-matrix.py (riesgo×cobertura desde registry+tests/) · S2 informe JSON+md · S3 gate de bloqueo diferido hasta 100% datos

## Referencias

- Auditoría externa §12 · `tests/evals/` · `evals-ci.yaml` · `run-adversarial-evals.sh` · SE-375
