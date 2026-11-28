---
version_bump: patch
section: Changed
---

### Changed

- Un solo ejecutor para las evals L4 de comportamiento que corren un script o hook: `tests/bats/l4_exec_eval.py` admite ahora `cwd`, listas de regex, `stdout_empty` y `json` (rutas jq), y aísla del entorno las variables del operador que cambian la decisión de los hooks. Los fixtures de coherence-court-orchestrator, commit-guardian, context-dome-manager, court-orchestrator y dev-orchestrator pasan a ese formato sin perder casos ni mutantes; se retira `tests/bats/l4-script-cases-lib.bash`. Nuevo `tests/bats/test-l4-exec-eval.bats` que fija el formato común.
