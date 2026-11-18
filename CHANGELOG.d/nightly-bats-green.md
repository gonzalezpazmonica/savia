---
version_bump: patch
section: Fixed
---

### Fixed

- La suite nocturna completa de BATS vuelve a poder pasar: arregla 20 de las 31 suites que fallaban (y deja 5 más a cargo del workflow) en main desde al menos el 2026-11-12 (tests desactualizados respecto a contratos cambiados, una bomba de reloj de fecha, dos barridos de 74 s repetidos por test, un hook con supresión silenciosa y un preregistro F4 incompleto) y el workflow nocturno instala ahora las dependencias de savia-vaults, genera los derivados (SE-501) y el locale es_ES.UTF-8 que las suites necesitan.
- Los dos tests intermitentes del nocturno (SPEC-181 JSON y commit-guard sin jq) parsean solo stdout y, si fallan, dejan stdout y stderr en el TAP.

