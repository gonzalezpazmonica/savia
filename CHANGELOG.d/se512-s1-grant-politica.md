---
version_bump: minor
section: Added
---

### Added

- SE-512 S1: merge-sprint.sh policy-plan, policy-request y policy-verify. La operadora aprueba el permiso nocturno fusionando una PR de aprobación (SE-488); policy-verify comprueba el recibo, el digest y la ventana efectiva sin fusionar nada. Sin run --policy (S2).
- SE-512 S1, tras revisión: una sola petición por política, policy-plan exige que el clon sea del repo declarado y trae la rama antes de congelar código, y los filtros de rama siguen la semántica de GitHub.

