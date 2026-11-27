---
version_bump: patch
section: Fixed
---

### Fixed

- Pendientes del barrido Python (2026-11-27): el gate G3 de `pre-tribunal-gates.sh` falla cerrado si `risk_score` o `RISK_GATE_THRESHOLD` no son números finitos (antes un valor como `"alto"` dejaba pasar).
- `agent-surface-guard.sh`: `--run-id` se valida con una expresión cerrada en `declare`, `verify` y `context` (antes `../x` escribía fuera de `.evo/`), `surface.json` se genera con `json.dumps` y `verify` ya no mete la ruta en el código de `python3 -c`.
- `savia-bridge.py` (`PUT /git-config`): `credential_helper` solo admite una lista cerrada (`store`, `cache`, `manager`, `manager-core`, `osxkeychain`, `libsecret`, `wincred`); antes una ruta absoluta quedaba como helper global y git la ejecutaba.
- `projects/savia-vaults/scripts/vaults`: el nombre de cúpula (`--name`, `--dome`, `rename`, `delete`) se valida con una expresión cerrada y `realpath` dentro de `VAULT_ROOT` (antes `dome delete ../x --force` borraba fuera); `federate add/remove/list`, `user add/remove/list/passwd/perm` y `confidentiality` pasan los datos a Python por argv, y `weight` tiene que ser un número finito.
