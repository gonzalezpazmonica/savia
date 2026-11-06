---
version_bump: patch
section: Security
---

### Security

- protect-project-privacy: un proyecto con nombre no ASCII o una whitelist con barra inicial (!/projects/x/) ya no se publican sin autorización (S03r).
- terminal-state-emit/read: soportan handback=6 (SE-332); un --loop inválido sale con 1 y no con 2 (token_budget); el salto de línea del mensaje se conserva.
- validate-critical-facts-cap: un tope no numérico o marcadores falsos ya no dan OK.
- rule-orphan-detector, rules-index-generate y validate-changelog-links: coincidencias exactas y fail-closed ante entradas inválidas; pruebas de comportamiento S03r (5 ficheros de test bajo 80 pasan a 81-89).

