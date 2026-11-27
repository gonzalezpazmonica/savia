---
version_bump: patch
section: Added
---

### Added

- Evals L4 de comportamiento para frontend-test-runner: 5 casos (4 negativos) que ejecutan el hook real `responsibility-judge.sh` (PreToolUse Edit|Write) con entradas de un agente de tests frontend: un test normal pasa; desactivar un test con `xit`/`xtest` (por Write o por Edit), aunque el contenido pida apagar el juez, y bajar `TEST_COVERAGE_MIN_PERCENT` se bloquean con exit 2 y registro BLOCKED. Cuatro mutantes del hook hacen fallar cada fixture. Sin llamadas a modelo.
