---
version_bump: minor
section: Added
---

### Added

- SE-500 S1: fragmentos de planificación `docs/propuestas/planning.d/SE-NNN.json` y `LOG.d/SE-NNN-ESTADO.md`; dos PR que registran specs distintas ya no chocan en `planning-state.json` ni en `LOG.md`.
- `scripts/planning-view.py`: vista consolidada determinista (base + fragmentos), `consolidate` idempotente, `check` y `diff` (la base solo cambia por consolidación pura).
- `roadmap.sh` lee la vista y añade `register`, `consolidate` y `validate --diff REF`; `spec-lifecycle.sh` escribe en `LOG.d/`; `planning-transition.sh` y el informe de cobertura de `validate-ci-local.sh` leen la vista; G13 traza fragmentos solo de specs referenciadas.

