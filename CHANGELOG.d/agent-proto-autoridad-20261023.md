---
version_bump: patch
section: Added
---

### Added

- Prototipos S0 navegables de SE-496 (contrato de delegación) y SE-508 (control previo de MCP y WebFetch), con datos de ejemplo, pendientes de confirmación de la operadora

- Test de coherencia de calendario para los prototipos S0 (`tests/test-spec-prototype-dates.bats`): una fecha con día de la semana que no cuadra, imposible o sin año deducible hace fallar el test
