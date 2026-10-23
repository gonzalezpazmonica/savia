---
version_bump: patch
section: Fixed
---

### Fixed

- Pruebas de comportamiento para 10 ficheros de test por debajo de 80 sobre scripts muy usados (block-commit-to-main, sycophancy-strip, contract-test-guard, recursion-guard, learning-recall-hook, release-invariants, cognitive-debt, memory-consolidate, slm-registry run, opencode-config-validate); 195 mutantes, 179 muertos y 16 equivalentes analizados.
- Fix: `release-invariants.sh` hacía fallar GENERATED_VIEW_DRIFT con "no se pudo regenerar" cuando /tmp no comparte dispositivo con el repo (`cp -al` entre dispositivos); ahora cae a copia real. Las fixtures no-ok no copiaban el generador completo y fallaban esa invariante de forma espuria.

