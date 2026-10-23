---
version_bump: patch
section: Fixed
---

### Fixed

- **SE-453 block-force-push, falso positivo de `--amend`**: el hook bash y el puerto TS bloqueaban cualquier `git commit` que mencionara `--amend` en el mensaje (`-m "explica --amend"`) o tras un separador (`&& echo --amend`), y dejaban pasar los prefijos que git acepta (`--am`, `--amen`). Ahora `--amend` tiene que ser un argumento propio de esa orden, detectado con un tokenizador de shell (comillas, escapes, `$(…)`, `<(…)`, `2>&1`, comentarios) igual en bash y TS; si la orden no se puede tokenizar o pasa de 16 384 caracteres, una coincidencia gruesa bloquea (falla cerrado). Revisión #1355: la primera versión, con regex de palabras, dejaba pasar `git commit -m $(date) --amend`. TS evalúa las reglas línea a línea como grep y ambos unen las continuaciones `\⏎`. Casos de paridad bash/sin jq/TS en `tests/test-gate-result-dual-binding.bats`.
- **SE-453 por demanda, `iac-security-scan.sh`**: emite `gate-result` (última línea en tabla; `result` y `gaps` dentro del objeto en `--format json`). Sin python3, Trivy ni Docker es `unknown/missing_tool`; Trivy roto o JSON ilegible, `unknown/unreadable`; en `--format json`, si no se puede fusionar el resultado en el report sale 2 con `unknown/report:unreadable` (antes stdout vacío). Resto de códigos de salida sin cambios.
- **SE-453 por demanda, `prompt-security-scan.sh`**: PS-11 (caracteres de ancho cero) dependía de python3 y sin él se omitía en silencio; ahora busca los bytes UTF-8 con `grep` y corre siempre. Un fichero o directorio ilegible es `unknown/unreadable` (exit 2) en vez de limpio. Todas las reglas usan `grep -a`: un byte NUL ya no oculta hallazgos. Emite `gate-result`; `gate_result_emit` sustituye los caracteres de control del check por `_`.

