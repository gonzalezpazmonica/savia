---
version_bump: patch
section: Fixed
---

### Fixed

- session-init exporta PM_WORKSPACE_ROOT con la raíz real del proyecto (antes $HOME/claude, inexistente) y update.sh la deduce de su ubicación; /update check ya no sale con versión unknown.

