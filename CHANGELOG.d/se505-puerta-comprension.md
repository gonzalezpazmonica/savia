---
version_bump: minor
section: Added
---

### Added

- SE-505 puerta de comprensión: las specs con superficie humana exigen «Lo que he entendido» con 3–5 escenas, palabras literales con fecha, listas SÍ/NO y confirmación de la persona, más un slice S0 de prototipo confirmado antes de S1. Gate fail-closed en roadmap.sh validate (scripts/comprehension-gate.py): recorre también la vista de planificación (una iniciativa en ámbito sin spec localizable es FAIL) y muestra en CI cada autoexención (EXEMPT, DECLARED-FALSE). La `evidence` de la vista solo cuenta como spec de reserva (.md con status:) y nunca la de otra iniciativa; fechas de confirmación inexistentes o futuras fallan.
