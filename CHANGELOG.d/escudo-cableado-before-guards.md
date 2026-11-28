---
version_bump: patch
section: Fixed
---

### Fixed

- savia-shield-check.sh: un guard solo cuenta como cableado si es elemento del array BEFORE_GUARDS (acotado a ese bloque, sin comentarios ni cadenas) y savia-foundation.ts importa BEFORE_GUARDS desde ./lib/before-guards y lo usa fuera de comentarios; antes bastaba otra lista o una mención en un comentario
