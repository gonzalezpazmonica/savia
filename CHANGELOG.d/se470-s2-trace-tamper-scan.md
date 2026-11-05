---
version_bump: minor
section: Added
---

### Added

- SE-470 S2: `scripts/trace-tamper-scan.py`, detector determinista de manipulación en trazas de agentes (stream-json de Claude Code y eventos de OpenCode). Señala lecturas de holdout, escrituras en rutas protegidas y `sed -i`, redirección `>`, `rm` o `git checkout` sobre ellas, contra una lista explícita de rutas. Resultado SE-453 (clean/findings/unknown), fail-closed ante recibos ilegibles.

