---
version_bump: patch
section: Fixed
---

### Fixed

- `.githooks/pre-commit` rechaza commits en main/master desde git (cubre script escrito en la misma orden y git con otro nombre, que el guard de Claude Code no ve); bypass registrado con `SAVIA_ALLOW_MAIN_COMMIT=1`; `scripts/install-git-hooks.sh --hooks-path` lo activa en repos sin `core.hooksPath`.

