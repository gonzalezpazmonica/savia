---
version_bump: patch
section: Security
---

### Security

- validate-bash-global ya ve `git -C <ruta> commit|add`: antes su prefiltro exigía `git commit` y un commit dirigido a main con `-C` pasaba sin bloqueo.
- block-commit-to-main y validate-bash-global resuelven el repo destino real de cada git commit/add (git -C, cd encadenado con o sin comillas, variables literales) con scripts/lib/git_op_targets.py; los heredocs que mencionan git commit ya no bloquean.

- El resolvedor falla en conservador: una orden con programa no resoluble (`$SUDO git commit`), un shell con opciones (`bash --norc -c …`), órdenes que pueden ejecutar texto (awk, sed, script -c, python3 -c…), las sustituciones de un heredoc sin comillas y cualquier excepción del análisis cuentan como posible commit. Sin Python o si el resolvedor falla, validate-bash-global y el guard TS aplican el criterio conservador también a `git -C`.
- El guard TS solo acepta `TEST_BRANCH` bajo `bun test` (NODE_ENV=test): una variable de entorno ya no lo desactiva.
