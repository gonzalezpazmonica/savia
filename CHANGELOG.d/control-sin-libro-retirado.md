---
version_bump: patch
section: Fixed
---

### Fixed

- `scripts/savia-control.py` deja de invocar el guion del libro de efectos, retirado con SE-493. La transición de abandono era código muerto: sin el guion un efecto preparado ya quedaba como indeterminado, y ahora queda así siempre, sin depender de que exista un fichero con ese nombre. El test que vigila la retirada vuelve a pasar en main.
- El test de `reconcile` gana cuatro casos: libro vacío, libro inexistente, estado nulo y un abandonado heredado; y un caso negativo que comprueba que un guion con el nombre retirado no se ejecuta aunque reaparezca.
