---
version_bump: patch
section: Security
---

### Security

- SE-501 rev-1472: generate-blocklist.sh perdía en un subshell las fuentes 2-6 (la lista estática nunca llegaba al escaneo); el escaneo de PR lee la lista estática de la base, no enlaza datos del checkout de la PR y falla con blocklist vacía; un regex inválido en la blocklist es gap (unknown), no OK.
- SE-501 rev-1472: push-pr.sh --merge re-escanea la cabeza en vez de verificar la firma retirada; el gate de derivados de la CI usa derived.sh y la lista D de la base; derived-migration-check.sh exige que salgan los checks retirados y el chequeo de workflows (workflow-hmac-check.py) por fin se versiona.

