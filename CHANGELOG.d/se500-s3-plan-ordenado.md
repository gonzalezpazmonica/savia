---
version_bump: minor
section: Added
---

### Added

- merge-sprint: plan ordenado (SE-500 S3). plan predice choques por pares con git merge-tree entre los heads revisados, sin registros ni derivados; fija order y collisions en el manifiesto (cubiertos por el digest) y avisa «#A chocará con #B en f». run sigue order y para con anomalía si no es una permutación exacta de las PR.

