---
version_bump: minor
section: Added
---

### Added

- SE-498 F0: `scripts/savia-control.py`, plano de control local con época de revocación monótona, `stop_seq`, diario encadenado, marca de instalación y las órdenes pause, revoke, quarantine, reconcile, resume, check, status, epoch y publish-epoch; `config/control/` pasa a gobernanza tier 4; check de CI de época monótona ejecutado desde la base, que evalúa exactamente la cabeza del evento. El diario tolera solo una última línea truncada (la aparta al escribir); estado, diario y marca con tipos incorrectos son ilegibles (fail-closed); `resume --via-pr` pagina gh y rechaza PR ambiguas o nombres con espacios; `publish-epoch` reutiliza su rama si `gh pr create` falló.


### Fixed

- SE-498 F0 (refutación de #1593): `savia-control.py` descarta las variables de Git que redirigen el repositorio (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_CONFIG_*`...), de modo que `check` ya no ignora la marca de revocación; `reconcile` falla con LEDGER_UNREADABLE si faltan efectos INDETERMINATE ya reconocidos, fusiona los registros del mismo efecto sin perder su ámbito y trata un efecto sin atribución como cubierto por todos los ámbitos; reconcile en instalación nueva materializa el estado; `revoke`/`pause` persisten la parada aunque `executors.json` sea ilegible; la época usa `fullmatch`, `check` escapa el motivo, la salida no UTF-8 no da traceback y un renombrado desde `config/control/` cuenta con su nombre antiguo para el tier.
