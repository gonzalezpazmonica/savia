---
version_bump: patch
section: Removed
---

### Removed

- SE-493 retirada: eliminados el libro de efectos (scripts/effect-ledger.py, scripts/effect-ops.json) y sus 1.038 líneas de pruebas, sin consumidor en el último mes (132 fusiones, ninguna de resultado incierto). La spec pasa a RETIRED; el contrato vivo de reservas de fusión sigue siendo scripts/f5-state.sh. Prueba de retirada: tests/bats/se493-libro-efectos-retirada.bats. Los casos de los guards de f5-state.sh (clave con recorrido de rutas, op distinta de pr.merge) que vivían en las pruebas del libro se conservan en tests/bats/test-f5-state-guards.bats.

