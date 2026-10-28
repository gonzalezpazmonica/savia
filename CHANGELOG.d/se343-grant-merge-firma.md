---
version_bump: patch
section: Security
---

### Security

- SE-343 (P1): un grant de merge ya no lo puede emitir Savia. `operator-grant.sh grant --scope merge` solo deja una petición; vale cuando la operadora la firma con su clave ed25519 privada (móvil o Savia Space) y `check` verifica la firma con `ssh-keygen -Y verify` contra `config/operator-grant-signers` (clave pública versionada, sin override). El hook `operator-grant.sh guard` veta a los agentes modificar ese fichero. LAW-HUMAN-002 deja de satisfacerse sin la operadora.
- SE-343 (fase 0): el grant de merge lleva id único, principal, scope, recurso (`--resource pr:<n>`) y vigencia firmados; `check` exige `--resource` y verifica cada campo; `consume`/`revoke` gastan el id y una copia guardada se rechaza (replay). `push-pr.sh` comprueba y consume el grant de su PR. El guard bloquea eventos incompletos (antes salía con 0 o 1) y los rodeos con comillas, globs o llaves.
- SE-343 (segunda revisión): el grant de merge firma también el repositorio (remoto `origin`), así que un grant de A#41 no vale en B#41; `revoke` invalida también la petición pendiente; el verificador corre con `python3 -I` y PATH fijo. El guard resuelve comillas ANSI-C (`$'\x69'`), continuaciones y escapes de printf, y cualquier error suyo sale con 2 (antes un `RecursionError` salía con 1 y dejaba pasar la orden). `push-pr.sh --merge` ya no aborta por `ROOT` sin definir, marca el merge por REST y no anuncia un consumo que falló.
- SE-343 (tercera revisión): `push-pr.sh --merge` ya no programa un auto-merge (`gh pr merge --auto`) que GitHub ejecutaría aunque el grant se revocara o caducara después: merge inmediato con el grant comprobado justo antes; si no se puede mergear todavía, sale con 1 sin gastar el grant. `gh` actúa con `-R` sobre el repo de `origin` y sin `GH_REPO`/`GH_HOST` (antes un grant de A#42 mergeaba B#42). El número del PR se extrae del URL (la ruta REST añadía ` (updated)` y rechazaba el grant legítimo). El guard expande secuencias de llaves y resuelve rutas tras `cd`/`-C`; `python3` y `git` se invocan por ruta absoluta, así que una función exportada no sustituye al verificador.
- fix(se-343): el grant de merge firma `head_sha` (cabeza del PR); `check` falla si la cabeza cambió y el merge usa `--match-head-commit`; `push-pr.sh --merge` no mergea tras un push propio.
- fix(se-343): el merge pasa a GitHub el `head_sha` firmado (`check --print-head`), no la cabeza local; `SAVIA_GH_BIN` solo se acepta con `SAVIA_GRANT_TEST_MODE=1` y `push-pr.sh --merge` rechaza ese modo.
