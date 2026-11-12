---
version_bump: patch
section: Fixed
---

### Fixed

- merge-sprint run: un manifiesto con una PR repetida en prs ya no pasa la comprobación de permutación (antes se conservaba en silencio la última entrada); el test de set -uo pipefail exige que sea la primera sentencia a nivel superior (SE-500 S3, revisión de #1526).

