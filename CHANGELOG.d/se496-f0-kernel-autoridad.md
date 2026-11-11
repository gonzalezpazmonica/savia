---
version_bump: minor
section: Added
---

### Added

- SE-496 F0: kernel de autoridad determinista (`scripts/lib/authority_kernel.py`: `evaluate`, `recheck`, ledger de usos, `verify-audit`, `check-ontology`, `check-contract`), ontología operativa (`contracts/ontology/savia-operational.yaml`), descriptores `pr.create-draft`, `project.publish` y `vault.note-write`, y batería de 15 denegaciones con gemelo positivo y mutación por paso. El kernel no admite overrides por entorno (los tests inyectan en proceso), usa la lista completa de ficheros del PR para el tier y lee niveles y ontología de origin/main. Solo tests: ningún hook ni guard decide con él todavía.

