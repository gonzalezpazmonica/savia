---
version_bump: patch
section: Fixed
---
- **`scripts/savia-shield-check.sh`**: reconoce los guards cableados en `lib/before-guards.ts` (SE-510 AC-7), no solo en `savia-foundation.ts`; el escudo ya no se reporta inactivo por error.
- **`tests/test-caveman-always.bats`, `tests/test-spec-142-auto-redact.bats`**: leen la lista de guards de su nueva ubicación (`lib/before-guards.ts`), con las mismas aserciones.
- **`tests/bats/test-se253-command-tiers.bats`**: el suelo del recuento de órdenes pasa a 557 tras las retiradas deliberadas de #1658 y #1660 (10 órdenes).
