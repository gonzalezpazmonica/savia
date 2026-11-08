---
version_bump: patch
section: Fixed
---

### Fixed

- Seguridad: la suite adversarial de contención (SE-292) daba verde con un contenedor que filtraba secretos (lógica invertida) y atacaba con un docker run propio; ahora ataca por containment-run.sh y falla cerrada sin motor o imagen (S03q, SE-376).
- review-policy-parse.py ya no trunca REVIEW.md: important completo, exclusiones con continuación unidas, nit_cap con el número en negrita y sin prosa como pass.
- ci-test-quality-gate.sh imprime por fin la lista de tests bajo umbral (el bloque Python llegaba roto) y no dice PASS si el auditor no midió; acepta umbrales decimales y ya no interpola SAVIA_QUALITY_GATE_FIXED_MIN como código Python.
- language-boundary-check.sh cuenta usos de jq (no líneas), solo en scripts nuevos (también renombrados con cambios) y funciona desde subdirectorios.
- Tests de comportamiento para credential-egress.sh y comprehension-gate.py que matan mutantes supervivientes.

