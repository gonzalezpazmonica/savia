---
version_bump: patch
section: Fixed
---

### Fixed

- SE-396 I03: el runtime limita cada ejecución por deadline, solicita cancelación best-effort y conserva como ambiguos los timeouts, excepciones y resultados tardíos para impedir reintentos con efectos duplicados.
