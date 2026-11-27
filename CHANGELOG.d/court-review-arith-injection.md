---
version_bump: patch
section: Fixed
---

### Fixed

- Code Review Court: `court-review.sh` valida como entero decimal (sin ceros a la izquierda, máximo 6 dígitos) los contadores de `score` y las variables `COURT_SCORE_PASS`, `COURT_SCORE_CONDITIONAL`, `COURT_MAX_FIX_ROUNDS` y `COURT_MAX_LOC` antes de usarlos en aritmética; una entrada como `HOME[$(cmd)]` ya no ejecuta `cmd` y sale con código 2. `court-turn-router.sh` rechaza `--round`/`--max-round` con ceros a la izquierda, que bash leía como octal.
