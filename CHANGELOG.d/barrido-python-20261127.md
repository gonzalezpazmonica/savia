---
version_bump: patch
section: Fixed
---

### Fixed

- Barrido de seguridad Python (2026-11-27): `pre-tribunal-gates.sh` (G3) y `agent-surface-guard.sh list` ya no meten datos externos en el código de `python3 -c` (pasan por argv); `repeat-tool-guard.py` en modo post y `cross-turn-correlation/track.py` tratan el id de sesión como nombre de fichero, nunca como ruta. Informe en `docs/evidence/barridos/20261127-barrido-python.md`.
