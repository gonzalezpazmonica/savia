---
version_bump: patch
section: Security
---

### Security

- savia-gates (OpenCode) deja de pasar a sus hooks los interruptores que apagan hooks de seguridad (SAVIA_PAT_BLOCK, SAVIA_SHIELD_ENABLED, SAVIA_HOOK_PROFILE), igual que el núcleo Codex.
- PROTECTED_GATE_PATH cubre opencode.json y .opencode/package.json en los dos núcleos y, en OpenCode, las ediciones de notebook por notebook_path.
- El motivo de un handler prompt se corta por puntos de código en OpenCode, como en Python; los tests de paridad comprueban el motivo de las rutas protegidas y fallan en CI si falta jq o bun.

