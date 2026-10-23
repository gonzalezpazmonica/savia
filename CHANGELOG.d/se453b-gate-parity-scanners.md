---
version_bump: patch
section: Fixed
---
- **SE-453 paridad OpenCode de block-force-push**: el puerto nativo (`.opencode/plugins/guards/block-force-push.ts`) dejaba pasar el force-push con opciones globales de git (`git -C dir push`) y el amend, que el hook bash bloquea, y bloqueaba `git push origin main-fix`. Usa el mismo ancla `GIT_AT`; `tests/test-gate-result-dual-binding.bats` compara bash (con y sin `jq`) y TS con las mismas entradas y corre en CI con runtime TypeScript obligatorio. Tras la revisión, ambos bindings bloquean también la orden en la segunda línea de un bloque, envuelta en `bash -c`/`sh -c`/`eval`/`then`/`{`/`xargs`, y un `--force` aunque otra parte lleve `--force-with-lease`; `--force-with-lease` a `main-fix` deja de bloquear.
- **SE-453 S3 lote 2, `security-audit-all.sh`**: un escáner que salía 1 (hallazgos) dejaba `{}` pegado tras su JSON y se contaba como 0 hallazgos (un FAIL se leía PASS). Ahora cuenta sus hallazgos, y un escáner ausente, roto o con salida ilegible es un hueco: sin hallazgos sobre el umbral sale 2 `UNKNOWN`. `result`, `verdict` y el exit siguen el mismo criterio. `--json` lleva `result` y `gaps`.
- **SE-453 S3 lote 2, `mcp-security-audit.sh`**: sin python3 cada config salía como hallazgo MCP-00; ahora sale 2 con `unknown/python3:missing_tool`. `--json` lleva `result` y `gaps`.
