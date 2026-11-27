---
version_bump: patch
section: Added
---

### Added

- SE-387 §17: `scripts/coherence-closure-status.py` genera `output/coherence-closure-status.{json,md}` (gates, cobertura constitucional, harness, evals, deuda, verdad derivada, benchmark y entropía) y la tabla de la Definition of Closed (§14) a partir de la evidencia ya capturada, sin repetir los gates. Fail-closed: lo no medible sale `NOT_MEASURED` y su criterio queda sin cumplir. `validate-ci-local.sh` lo regenera en cada pasada con el log de coherencia que ya tiene; `coherence-gates.sh` deja en el log la cifra medida de entropía y deuda (líneas `INFO`). `--check-policy` detecta la evidencia escrita a mano que no casa con lo medido: `coherence-gate-policy.yaml` decía «eval L4 8/8» y «constitutional 10/10» cuando lo medido es 12/12 y 14/14; corregido.
