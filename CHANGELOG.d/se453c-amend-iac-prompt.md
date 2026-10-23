---
version_bump: patch
section: Fixed
---

### Fixed

- **SE-453 block-force-push, falso positivo de `--amend`**: el hook bash y el puerto TS bloqueaban cualquier `git commit` que mencionara `--amend` en el mensaje (`-m "explica --amend"`) o tras un separador (`&& echo --amend`), y dejaban pasar los prefijos que git acepta (`--am`, `--amen`). Ahora `--amend` tiene que ser un argumento propio de esa orden; dos casos de paridad bash/sin jq/TS en `tests/test-gate-result-dual-binding.bats`.
- **SE-453 por demanda, `iac-security-scan.sh`**: emite `gate-result` (última línea en tabla; `result` y `gaps` dentro del objeto en `--format json`). Sin python3, Trivy ni Docker es `unknown/missing_tool`; Trivy roto o JSON ilegible, `unknown/unreadable`. Códigos de salida sin cambios.
- **SE-453 por demanda, `prompt-security-scan.sh`**: PS-11 (caracteres de ancho cero) dependía de python3 y sin él se omitía en silencio; ahora busca los bytes UTF-8 con `grep` y corre siempre. Un fichero o directorio ilegible es `unknown/unreadable` (exit 2) en vez de limpio. Emite `gate-result`.

