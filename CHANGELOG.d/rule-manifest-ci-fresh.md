---
version_bump: patch
section: Fixed
---

### Fixed

- La CI ejecuta ahora la frescura de los artefactos generados (`validate-ci-local.sh --fresh-only`): rule-manifest.json, pin de settings-hooks, INDEX de propuestas y planning-state solo se comprobaban en local, así que #1401 dejó rule-manifest.json desfasado en main sin aviso. Regenera rule-manifest.json.

- `--fresh-only` ya no puede dar falso verde: el veredicto se lee sin tuberías (un `grep -q` con `pipefail` perdía el FAIL por SIGPIPE), exige una PASS por cada comprobación lanzada, ignora la tabla sobrescrita por entorno en CI, y la CI ejecuta la suite `tests/test-validate-ci-fresh.bats`.
