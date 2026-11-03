---
version_bump: patch
section: Security
---

### Security

- validate-bash-global ya ve `git -C <ruta> commit|add`: antes su prefiltro exigía `git commit` y un commit dirigido a main con `-C` pasaba sin bloqueo.
- block-commit-to-main y validate-bash-global resuelven el repo destino real de cada git commit/add (git -C, cd encadenado con o sin comillas, variables literales) con scripts/lib/git_op_targets.py; los heredocs que mencionan git commit ya no bloquean.

- El resolvedor falla en conservador: una orden con programa no resoluble (`$SUDO git commit`), un shell con opciones (`bash --norc -c …`), órdenes que pueden ejecutar texto (awk, sed, script -c, python3 -c, rg --pre…), las sustituciones de un heredoc sin comillas y cualquier excepción del análisis cuentan como posible commit.
- Un shell que lee la orden de stdin (`bash <<EOF`, `bash <<< '…'`, `… | sh`, `sh -s`) ya bloquea: el heredoc o la here-string se analiza como script y, si stdin viene de una tubería o un fichero, cuenta el texto de toda la orden.
- Un `cd` a un directorio que el hook no ve, o relativo con `CDPATH`, deja el destino sin resolver (cwd de la orden) en lugar de dar por fallida la cadena `&&`, que dejaba pasar el commit.
- `GIT_DIR=<ruta>/.git` y `--git-dir=<ruta>/.git` literales y absolutos se resuelven a `<ruta>`; `git commit-tree` cuenta como commit.
- Límite conocido: un destino no resoluble (`git -C $X`, `--work-tree`) se evalúa con el cwd de la orden, que solo protege si ese cwd está en main. Sin Python, validate-bash-global y el guard TS también evalúan las órdenes `git -C`, pero por el cwd de la orden, no por su destino.
- El guard TS solo acepta `TEST_BRANCH` bajo `bun test` (NODE_ENV=test): una variable de entorno ya no lo desactiva.
