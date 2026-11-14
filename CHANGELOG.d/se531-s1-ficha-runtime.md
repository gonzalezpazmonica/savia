---
version_bump: minor
section: Added
---

### Added

- SE-531 S1: ficha de runtime de harness (contracts/runtime/), validador fail-closed y lectores (scripts/harness_ficha.py); fichas de Claude Code, OpenCode, Codex y Yema con todo dato sin medir como no_medido.

- SE-531 S1: `accept_exit` falla cerrado si la regla de detección no se puede aplicar o `rc` no es un entero; la detección escanea la salida completa (por encima de 64 MB se rechaza, sin truncar); `patron` limitado a un subconjunto lineal (sin ReDoS); claves duplicadas y claves de primer nivel desconocidas rechazadas; `si`/`no` booleanos de YAML 1.1 normalizados; id de ficha = nombre de fichero; `.yml` rechazado.

- SE-531 S1: `accept_exit` rechaza si hay regla de detección y no se pasa la salida (`output=None` por defecto) y si la ficha no supera `validate_runtime`; `patron` exige `^` (por línea, re.MULTILINE) y prohíbe clases negadas y caracteres de control, con coste lineal en la salida; claves no escalares y anidamiento profundo dan «ilegible» sin traza; los booleanos YAML 1.1 (`yes`, `on`, `off`, `true`, `false`) ya no se convierten en `si`/`no`.
