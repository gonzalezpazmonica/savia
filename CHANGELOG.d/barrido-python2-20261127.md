---
version_bump: patch
section: Fixed
---

### Fixed

- Pendientes del barrido Python (2026-11-27): el gate G3 de `pre-tribunal-gates.sh` falla cerrado si `risk_score` o `RISK_GATE_THRESHOLD` no son números finitos (antes un valor como `"alto"` dejaba pasar).
