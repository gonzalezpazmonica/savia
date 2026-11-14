---
version_bump: minor
section: Changed
---

### Changed

- SE-531 S1b: las fichas de runtime de Claude Code (uso y flujo de llamadas) y OpenCode (rc no_fiable con su regla de detección, uso y flujo) pasan de no_medido a datos medidos con fuente y version_cli; el validador avisa (sin fallar) con `check --versiones` si la versión instalada difiere de la medida (scripts/harness_ficha_version.py).

