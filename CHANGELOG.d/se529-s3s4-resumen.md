---
version_bump: patch
section: Added
---

### Added

- SE-529 S3+S4: el resumen que entrega PostCompact se guarda una sola vez (clave sesión + sha-256 del resumen normalizado) con estado explícito: confirmado, o «no confirmado» si falla; OpenCode, que no lo entrega, declara «no disponible». Fixtures sintéticos con la forma de S0.1 (scripts/compaction-fixtures.py).

