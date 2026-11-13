---
version_bump: patch
section: Fixed
---

### Fixed

- memory-store: la redacción de `<private>` ahora es multilínea, no codiciosa y fail-closed (sin cierre redacta hasta el final); antes un bloque de varias líneas se guardaba sin redactar.

