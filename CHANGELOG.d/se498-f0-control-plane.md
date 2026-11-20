---
version_bump: minor
section: Added
---

### Added

- SE-498 F0: `scripts/savia-control.py`, plano de control local con época de revocación monótona, `stop_seq`, diario encadenado, marca de instalación y las órdenes pause, revoke, quarantine, reconcile, resume, check, status, epoch y publish-epoch; `config/control/` pasa a gobernanza tier 4; check de CI de época monótona ejecutado desde la base, que evalúa exactamente la cabeza del evento. El diario tolera solo una última línea truncada (la aparta al escribir); estado, diario y marca con tipos incorrectos son ilegibles (fail-closed); `resume --via-pr` pagina gh y rechaza PR ambiguas o nombres con espacios; `publish-epoch` reutiliza su rama si `gh pr create` falló.


### Fixed

- SE-498 F0 (refutación de #1593): `savia-control.py` descarta las variables de Git que redirigen el repositorio (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_CONFIG_*`...), de modo que `check` ya no ignora la marca de revocación; `reconcile` falla con LEDGER_UNREADABLE si faltan efectos INDETERMINATE ya reconocidos, fusiona los registros del mismo efecto sin perder su ámbito y trata un efecto sin atribución como cubierto por todos los ámbitos; reconcile en instalación nueva materializa el estado; `revoke`/`pause` persisten la parada aunque `executors.json` sea ilegible; la época usa `fullmatch`, `check` escapa el motivo, la salida no UTF-8 no da traceback y un renombrado desde `config/control/` cuenta con su nombre antiguo para el tier.
- SE-498 F0 (revisiones de seguridad y corrección sobre 9b59a736b): ámbitos y login de la operadora se validan con `fullmatch` (un `\n` final ya no pasa); `publish-epoch` ignora las PR de época que vienen de un fork; una aprobación de `resume` con `epoch` o `stop_seq` no enteros (`true`, `1.0`) es APPROVAL_INVALID; `reconcile` solo arrastra los inciertos del último reconcile de cada ámbito, de modo que uno ya resuelto no bloquea la parada para siempre.
- SE-498 F0 (revisiones sobre 382d87ab8): `savia-control.py` descarta también `GH_REPO` y `GH_HOST`, de modo que las consultas de `resume --via-pr` y `publish-epoch` no van a otro repositorio; las rutas del ledger de efectos y del ledger del merge-sprint quedan fijadas en la marca de instalación (otro valor por entorno sale 2 PATH_MISMATCH); un incierto que un reconcile por ámbito resolvió ya no bloquea desde el último reconcile global.
- SE-498 F0 (refutación sobre fbb5eb6c5): `reconcile` mantiene un incierto pendiente hasta que un reconcile lo resuelva o un `resume` lo acepte, de modo que renovar la parada y perder el ledger ya no lo descarga; la atribución de un efecto se acumula entre registros (un `executor: null` o un cambio de ejecutor no lo sacan de un ámbito, y un tipo malformado cuenta en todos); estado, sonda, recibo y compensación salen solo del intento más alto, así que la sonda de un intento anterior no da REJECTED; `attempt` no natural es LEDGER_UNREADABLE. Se descartan además `GIT_CONFIG_GLOBAL` y `GIT_CONFIG_SYSTEM`, y `epoch`/`status` avisan EPOCH_CHECK_SOURCE_UNPINNED si el check de época obligatorio no fija la app de GitHub Actions.
