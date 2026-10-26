---
version_bump: patch
section: Security
---

### Security

- SE-343 (P1): un grant de merge ya no lo puede emitir Savia. `operator-grant.sh grant --scope merge` solo deja una petición; vale cuando la operadora la firma con su clave ed25519 privada (móvil o Savia Space) y `check` verifica la firma con `ssh-keygen -Y verify` contra `config/operator-grant-signers` (clave pública versionada, sin override). El hook `operator-grant.sh guard` veta a los agentes modificar ese fichero. LAW-HUMAN-002 deja de satisfacerse sin la operadora.

