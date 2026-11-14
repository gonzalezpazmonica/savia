---
version_bump: patch
section: Added
---

### Added

- SE-531: ficha de harness ejecutable. Cada programa de agente externo declara sus capacidades (aislamiento, código de salida, cuota, gasto, reanudación, limpieza, vigilancia de llamadas) y un validador falla si falta un campo; incluye la supervisión del proceso hijo (matar el grupo, cortar bucles, relanzar solo sin efectos). Tres slices (tier 2, 2-3, 3). Solo spec y test de coherencia; su aprobación consta en `se531-approved.md`.
