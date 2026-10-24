---
version_bump: patch
section: Fixed
---

### Fixed

- Pruebas de comportamiento para 10 ficheros de test por debajo de 80 sobre scripts muy usados (block-commit-to-main, sycophancy-strip, contract-test-guard, recursion-guard, learning-recall-hook, release-invariants, cognitive-debt, memory-consolidate, slm-registry run, opencode-config-validate); 195 mutantes, 179 muertos y 16 equivalentes analizados.
- Fix: `release-invariants.sh` hacía fallar GENERATED_VIEW_DRIFT con "no se pudo regenerar" cuando /tmp no comparte dispositivo con el repo (`cp -al` entre dispositivos); ahora cae a copia real. Las fixtures no-ok no copiaban el generador completo y fallaban esa invariante de forma espuria.
- Revisión independiente: aserciones negadas `! cmd` a mitad de test (inertes bajo `set -e`) sustituidas por comprobaciones que pueden fallar en test-cognitive-debt y release-invariants; el test de `disable` verifica ahora también que no queda el hook de telemetría en PostToolUse. La sonda de copia de `release-invariants.sh` pasa a respaldo por directorio (`cp -al` y, si falla, `cp -a`), con test que fuerza ese camino.
