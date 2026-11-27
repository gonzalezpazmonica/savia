---
version_bump: patch
section: Security
---

### Security

- Alerta #116 (js/polynomial-redos): el guard de rutas protegidas de OpenCode (`savia-gates/lib/shell-targets.ts`) y su gemelo de Codex (`scripts/dual-cli/shell_targets.py`) casan los globs de `find -name` con un matcher lineal sin retroceso. Antes `find .claude -name 'a*a*…*b' -delete` colgaba el guard contra un nombre largo; ahora 30 `*` contra 5 000 caracteres resuelven en milisegundos con las mismas respuestas que la regex anterior.
