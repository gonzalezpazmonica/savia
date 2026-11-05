---
version_bump: patch
section: Changed
---

### Changed

- SE-501 rev-1472: consolidación sin superficie nueva (entropía 1628 → 1623): derived-drop.sh pasa a «derived.sh drop», derived-migration-check.sh a «derived.sh migration-check», confidentiality-main-verify.sh a «confidentiality-sign.sh verify-main» y confidentiality-pr-scan.sh a «confidentiality-scan.sh --pr-base» (la CI sigue ejecutando el envoltorio de la base); se retira el envoltorio heredado generate-capability-map.sh (entrada: derived.sh ensure --only scm). Las opciones con valor ya no cuelgan el bucle si falta el valor.

