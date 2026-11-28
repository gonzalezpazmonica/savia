---
version_bump: patch
section: Fixed
---

### Fixed

- `emergency-status.sh` informa «GPU no disponible» cuando `nvidia-smi` falla o no existe, y `test-sovereignty-auditor.bats` lo prueba con un `nvidia-smi` falso y con un PATH hermético sin el binario (RESTO-455-a)
