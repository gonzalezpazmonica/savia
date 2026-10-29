---
version_bump: patch
section: Fixed
---

### Fixed

- El compliance de reglas se verifica en el `pre-commit` de git (`.githooks/`). Git lo ejecuta en el repo real del commit, también en worktrees, sobre lo que de verdad va en stage y con cualquier forma de orden: `git -C`, `cd`, subshell, heredoc, script o `commit -a`. Antes, un PreToolUse deducía del texto de la orden en qué repo se hacía el commit, evaluaba el árbol equivocado y ejecutaba git en un repo que elegía la orden antes de que nadie la aprobara.
- El paso «Compliance runner» del job obligatorio «Validate workspace» de la CI ejecuta el mismo runner sobre el diff de la PR (`runner.sh --range`), así que un commit que esquive el pre-commit local no llega a main.
- El runner prioriza el repo del directorio actual sobre `CLAUDE_PROJECT_DIR`.
- El PreToolUse `compliance-gate` queda sin efecto; retirar su registro de `settings.json` es decisión de la operadora.
