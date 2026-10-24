---
version_bump: patch
section: Fixed
---

### Fixed

- Calidad S03i: pruebas de comportamiento validadas por mutación para 9 ficheros de test (memory-consolidate, hybrid-search, kg-extract, git-history-secret-scan, pr-thermal-receipt, agent-git-discipline, tls-security-check + web-headers-check, blast-radius, dependency-scan).
- Fix: `kg-extract.py` fallaba con KeyError en cuanto había un router LLM (las llaves del prompt rompían `.format`), ignoraba `SKIP_PATTERNS` (versión y hash de commit entraban como entidades) y no detectaba `#1234` suelto ni porcentajes seguidos de espacio.
- Fix: `memory-consolidate.py` no reconocía las entradas SE-nnn/SPEC-nnn (regex `SE-d+` sin barra invertida) y marcaba como de prueba cualquier entrada que empezara por «decision a…/b…»; `memory-consolidate.sh` aceptaba `--help` solo como acción desconocida.
- Fix: `blast-radius.sh` informaba 1 dependiente cuando no había ninguno, imprimía una segunda línea «Risk score» vacía, no detectaba funciones bash en `--diff`, ignoraba `--file` con `--symbol` y leía el contenido relativo al cwd en vez de al proyecto.
- Fix: `pr-thermal-receipt.sh` aceptaba una ref inválida como diff vacío con salida 0, siempre contaba 0 scripts eliminados en modo rama, usaba el repo del script en vez del cwd y producía JSON inválido con `--health` sin script.
- Fix: `tls-security-check.sh` daba nota B cuando testssl no producía informe y degradaba a C por cualquier palabra con «des»; `web-headers-check.sh` rompía el JSON con comillas en cabeceras.

