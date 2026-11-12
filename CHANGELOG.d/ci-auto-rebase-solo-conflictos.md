---
version_bump: patch
section: Fixed
---

### Fixed

- CI: el auto-rebase solo integra main en las PR con conflicto real (CONFLICTING/DIRTY); las de mergeabilidad UNKNOWN se re-sondean y, si siguen sin calcular, no se tocan (`scripts/auto-rebase-targets.sh`).

