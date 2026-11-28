---
version_bump: patch
section: Added
---

### Added

- Evals L4 de comportamiento para infrastructure-agent, meeting-digest, security-guardian, test-runner y truth-tribunal-orchestrator: 5 casos por agente (al menos uno negativo) que ejecutan el hook o script real que impone su garantía (`block-infra-destructive`, `confidentiality-check`, `block-credential-leak` y `block-pat-file-write`, `test-coverage-ratchet`, `truth-tribunal.sh aggregate`) y comparan exit, salida y ficheros escritos. Nuevo ejecutor `tests/bats/l4_exec_eval.py` (`aggregate.script`), con mutantes en cada `.bats` que deben hacer fallar el caso. La cobertura L4 de comportamiento de la matriz pasa de 1/12 a 6/12. Sin llamadas a modelo.
