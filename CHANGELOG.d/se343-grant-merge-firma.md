---
version_bump: patch
section: Security
---

### Security

- SE-343 (P1): un grant de merge ya no lo puede emitir Savia. `operator-grant.sh grant --scope merge` solo deja una petición; vale cuando la operadora la firma con su clave ed25519 privada (móvil o Savia Space) y `check` verifica la firma con `ssh-keygen -Y verify` contra `config/operator-grant-signers` (clave pública versionada, sin override). El hook `operator-grant.sh guard` veta a los agentes modificar ese fichero. LAW-HUMAN-002 deja de satisfacerse sin la operadora.
- SE-343 (fase 0): el grant de merge lleva id único, principal, scope, recurso (`--resource pr:<n>`) y vigencia firmados; `check` exige `--resource` y verifica cada campo; `consume`/`revoke` gastan el id y una copia guardada se rechaza (replay). `push-pr.sh` comprueba y consume el grant de su PR. El guard bloquea eventos incompletos (antes salía con 0 o 1) y los rodeos con comillas, globs o llaves.
