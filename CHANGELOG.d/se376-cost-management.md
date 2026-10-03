---
version_bump: patch
section: Fixed
---

### Fixed

- cost-management: los rates (información salarial) no estaban en .gitignore pese a la promesa de seguridad; se ignoran .flow-data/rates.json y **/.rates.local.json, se corrige el signo de CPI en billing-model, el validador test-cost-center.sh vuelve a pasar y se añade tests/test-cost-management.bats (auditor 92).

