---
version_bump: patch
section: Security
---

### Security

- **SE-392 AC6 handlers prompt y gates de commit en OpenCode**: savia-gates no casaba nunca `Bash(git commit*)` (lo leía como regex), así que block-commit-to-main, compliance-gate y pr-summary-gate no corrían en OpenCode; el núcleo Codex no aceptaba estrellas interiores (`Bash(bash*memory-store*save*)`). Ahora `Herramienta(orden)` es un glob literal en ambos, con cero divergencias sobre todos los matchers de settings.json. Los handlers `prompt` se ejecutan con el evaluador de `SAVIA_PROMPT_HOOK_CMD` y bloquean ante ausencia, fallo, timeout o veredicto mal formado (mismo corpus de 10 casos en Codex y OpenCode). `PROTECTED_GATE_PATH` también en OpenCode sin `SAVIA_GATES_PIN`.

