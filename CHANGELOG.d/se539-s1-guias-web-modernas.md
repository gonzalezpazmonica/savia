---
version_bump: minor
section: Added
---
- **`scripts/web-guidance-import.sh`, `scripts/web-guidance.sh`, `references/modern-web-guidance/`** (SE-539 S1): copia fija y sin código de las 211 guías de GoogleChrome/modern-web-guidance en el commit 2b4aa13a, con importador defensivo (commit de 40 hexadecimales, sin enlaces, solo .md, tope 300 ficheros y 4 MB, referencias cruzadas reescritas a enlaces relativos) y búsqueda local sin red. Tests en `tests/bats/web-guidance.bats`.
