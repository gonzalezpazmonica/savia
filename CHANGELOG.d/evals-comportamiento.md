---
version_bump: patch
section: Fixed
---

### Fixed

- La cobertura de evals L4 distingue evals de definicion (grep sobre el prompt del agente) de evals de comportamiento (ejecutan el agregador o script real). Solo las de comportamiento cuentan para la cobertura L4; las de definicion se siguen ejecutando y se reportan aparte (`covered_definition`). Cobertura L4 real de comportamiento: 1/12 (antes se informaba 12/12). El gate `eval-coverage-L4` queda en modo informe para el comportamiento (WARN con el numero real) y sigue bloqueando si se pierde cobertura de definicion.
