---
version_bump: patch
section: Security
---

### Security

- validate-bash-global ya ve `git -C <ruta> commit|add`: antes su prefiltro exigía `git commit` y un commit dirigido a main con `-C` pasaba sin bloqueo.
- block-commit-to-main y validate-bash-global resuelven el repo destino real de cada git commit/add (git -C, cd encadenado con o sin comillas, variables literales) con scripts/lib/git_op_targets.py; los heredocs que mencionan git commit ya no bloquean.

