---
version_bump: patch
section: Changed
---

### Changed

- Calidad S03e: pruebas de comportamiento discriminantes (validadas por mutación) para 10 ficheros de test (audit-chain, spill, goal-service, savia-trace, pre-tribunal-gates, planning-transition, token-meter, review-checkpoint, implementation-readiness, dco-check). Corrige 4 fallos reales: `audit-chain-append.sh` aceptaba `entry_hash=` como atributo y rompía la cadena; `audit-chain-verify.sh` daba por buena una entrada sin `entry_hash`; `spill-save.sh` dejaba salir la sesión del root con `../`; `review-checkpoint.sh` ignoraba su directorio de salida (ahora `REVIEW_CHECKPOINT_OUTPUT_DIR`; un `OUTPUT_DIR` genérico heredado no lo redirige) y nunca detectaba el requisito AB#/BR. `spill-save.sh` rechaza además un directorio de sesión que sea symlink.
