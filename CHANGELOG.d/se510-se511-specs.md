---
version_bump: patch
section: Added
---

### Added

- SE-510 y SE-511 PROPOSED (solo spec): guardas sin bloqueos falsos con despachador por evento, y contexto fijo por turno a 5.000 tokens o menos validado con el método de EXP-509.
- Comprobador de coherencia de las dos specs (`tests/se510_se511_spec_check.py`, BATS `tests/bats/se510-se511-spec-coherence.bats`): semilla del corpus sin entradas con dos veredictos, cada AC en un solo slice y aritmética de tokens de SE-511.
