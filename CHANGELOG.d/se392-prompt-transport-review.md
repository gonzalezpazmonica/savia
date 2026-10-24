---
version_bump: patch
section: Security
---

### Security

- **SE-392 AC6, revisión de #1356**: un commit con heredoc o `-m` multilínea ya no se salta los gates de commit; los matchers casan cruzando saltos de línea en Codex y en OpenCode. El evaluador `prompt` no hereda `CLAUDE_JSON_INPUT` ni `SAVIA_PROMPT_HOOK_MODEL` del padre. OpenCode rechaza veredictos con claves duplicadas o números no finitos, y un timeout inválido da `INVALID_HOOK_CONFIGURATION`, como en Codex. El corpus pasa de 10 a 16 casos. CI instala Bun y fija `SAVIA_DUAL_CLI_STRICT=1`, así que la paridad TS ya no se salta en silencio.

