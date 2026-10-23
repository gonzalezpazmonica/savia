---
version_bump: patch
section: Fixed
---

### Fixed

- Cuatro scripts con fallos reales hallados al subir sus pruebas: telemetry-tail-sample (exit 1 de check anulado), ternary-verdict (motivo/owner con comillas corrompidos o interpolados como Python), meta-control/monitor/recalibrate (entradas no numéricas con traceback y exit 0) y ci-select-bats (NameError sin dir_rules).

