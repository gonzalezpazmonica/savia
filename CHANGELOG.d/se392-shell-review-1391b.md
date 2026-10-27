---
version_bump: patch
section: Security
---

### Security

- SE-392 S3 (revisión de #1391): un comando Bash que el tokenizador no puede analizar se deniega siempre, en Codex y en OpenCode. Antes bastaba con añadir `<(true)` para esquivar el gate.
  - `<(…)` y `>(…)` se analizan como `$(…)`.
  - Una sustitución se juzga desde el `cd` vigente.
  - `~+` y `~-` se expanden.
  - `rm -rf "$R"/scripts` se deniega.
- Menos falsos positivos: ya no se deniegan `find … -exec cp {} /tmp/`, un `find` dentro de un gate que solo casa `__pycache__`, ni `git checkout -b`, `git restore --staged`, `git reset .` o `git rm --cached`. `xargs --max-args N` e `install -d` se interpretan bien.
