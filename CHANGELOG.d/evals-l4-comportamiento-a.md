---
version_bump: patch
section: Added
---

### Added

- Evals L4 de comportamiento para coherence-court-orchestrator, commit-guardian, context-dome-manager, court-orchestrator y dev-orchestrator: cinco casos por agente con `aggregate` que ejecutan el script o hook real (coherence-court.sh, block-force-push.sh, dome-guard.sh, court-review.sh, savia-orchestrator-helper.sh), al menos uno negativo y mutantes que demuestran que la eval falla si se rompe el comportamiento. Se ejecutan con `tests/bats/l4_exec_eval.py` (`aggregate.script`). La matriz de cobertura L4 por comportamiento pasa de 1 a 6 de 12 agentes.
