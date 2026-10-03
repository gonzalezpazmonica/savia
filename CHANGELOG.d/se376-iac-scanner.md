---
version_bump: patch
section: Fixed
---

### Fixed

- iac-security-scanner: el scan ya no confunde un fallo de Trivy con hallazgos (exit 2 = error, nunca PASS), aplica el .trivyignore de forma coherente y visible (antes el gate lo ignoraba o usaba el del directorio actual), arregla el fallback Docker y las rutas con espacios, valida --severity/--format y muestra MEDIUM/LOW como informativos; el baseline deja de declarar «IaC limpio» cuando Trivy falla y no sobrescribe supresiones existentes sin --force.

