---
version_bump: patch
section: Fixed
---

### Fixed

- post-compaction.sh respeta el tope de bytes contando el salto final, no reinyecta entradas sustituidas (SPEC-034) y solo marca como «Fijado» lo de origen owner/agent (SE-352).
- Si la línea de sesión no cabe, salen las fijadas y session-hot.md se conserva.
- memory-store.sh: --max-bytes sin valor falla y ya no avisa con la entrada vacía.

