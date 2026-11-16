---
version_bump: minor
section: Added
---

### Added

- SE-498 F0: `scripts/savia-control.py`, plano de control local con época de revocación monótona, `stop_seq`, diario encadenado, marca de instalación y las órdenes pause, revoke, quarantine, reconcile, resume, check, status, epoch y publish-epoch; `config/control/` pasa a gobernanza tier 4; check de CI de época monótona ejecutado desde la base, que evalúa exactamente la cabeza del evento. El diario tolera solo una última línea truncada (la aparta al escribir); estado, diario y marca con tipos incorrectos son ilegibles (fail-closed); `resume --via-pr` pagina gh y rechaza PR ambiguas o nombres con espacios; `publish-epoch` reutiliza su rama si `gh pr create` falló.

