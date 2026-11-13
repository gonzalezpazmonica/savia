---
version_bump: minor
section: Added
---

### Added

- SE-531 S1: ficha de runtime de harness (contracts/runtime/), validador fail-closed y lectores (scripts/harness_ficha.py); fichas de Claude Code, OpenCode, Codex y Yema con todo dato sin medir como no_medido.

- SE-531 S1 (correcciones de revisión): `accept_exit` falla cerrado si la regla de detección no se puede aplicar; `patron` limitado a un subconjunto lineal (sin ReDoS); detección sobre cabeza y cola de la salida; `si`/`no` booleanos de YAML 1.1 normalizados; id de ficha = nombre de fichero; `.yml` rechazado.
