---
version_bump: patch
section: Security
---

### Security

- block-force-push (bash y TS): un push a main o forzado partido con una barra invertida al final de línea (`git push origin \⏎main`, `git push \⏎--force`) pasaba, porque las reglas se evalúan línea a línea. Ahora se evalúan las líneas tal cual y además la orden con las continuaciones unidas como las une el shell (barra impar). Tests de paridad bash/sin jq/TS en `tests/test-gate-result-dual-binding.bats`.

