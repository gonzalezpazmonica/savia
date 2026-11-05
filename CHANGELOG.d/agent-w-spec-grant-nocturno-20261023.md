---
version_bump: patch
section: Added
---

### Added

- SE-512 PROPOSED: grant de política para el sprint nocturno (una firma con ventana, tope y alcance; modo nocturno sin avisos de permiso). Solo spec.

- SE-512: comprobador de coherencia de la spec (`tests/se512_spec_check.py`, `tests/bats/se512-spec-coherence.bats`) con las reglas de la tercera ronda de revisión.

- SE-512 (cuarta ronda): la clave privada del grant de política solo vive en el móvil o en Savia Space (LAW-HUMAN-002); sondeo de `main` con minutos convertidos a segundos; activación bloqueada hasta la enmienda humana de S4; la exclusión forzosa incluye el código que ejecutan los workflows, con cierre transitivo y STOP si no se puede derivar. Reglas R-KEY, R-ACTIVATION y R-WFEXEC en el comprobador.

- SE-512 (quinta ronda): el cierre de la exclusión por workflows sigue imports de Python, `source` de bash y rutas relativas, y excluye el directorio entero ante lo que no puede resolver; manifiestos de dependencias y tests de los gates excluidos; el guard nocturno niega también `gh api .../merge` y los push a `main`; identidad de la autora y tope C3 definidos. Reglas R-WFIMPORT, R-GUARDVIAS, R-AUTHOR y R-C3WIN.
