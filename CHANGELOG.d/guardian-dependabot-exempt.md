---
version_bump: patch
section: Fixed
---

### Fixed

- PR Guardian: las PR de dependabot[bot] que solo tocan ficheros de dependencias o líneas uses: de workflows quedan exentas de Gate 1 (descripción) y Gate 8 (CHANGELOG); el resto de puertas se mantiene. El workflow se ejecuta también al reabrir una PR (reopened).

