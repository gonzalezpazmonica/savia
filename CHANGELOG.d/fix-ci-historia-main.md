---
version_bump: patch
section: Fixed
---

### Fixed

- CI: `roadmap validate` descarga el historial completo de main sin blobs en lugar de una ventana de 300 commits; la PR de SE-402 había salido de la ventana y main estaba en rojo sin cambio alguno
- Tests de CI (`test-compliance-gate.bats`): leen las opciones reales del fetch de historial de `ci.yml` y comprueban que se conservan más de 300 commits de main
