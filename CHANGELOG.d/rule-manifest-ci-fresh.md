---
version_bump: patch
section: Fixed
---

### Fixed

- La CI ejecuta ahora la frescura de los artefactos generados (`validate-ci-local.sh --fresh-only`): rule-manifest.json, pin de settings-hooks, INDEX de propuestas y planning-state solo se comprobaban en local, así que #1401 dejó rule-manifest.json desfasado en main sin aviso. Regenera rule-manifest.json.

