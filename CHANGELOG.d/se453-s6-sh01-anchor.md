---
version_bump: patch
section: Fixed
---

### Fixed

- Savia Shield (SE-453 S6): la lista «parece código» que rebaja un bloqueo a aviso en ficheros de código casa ahora con la entidad entera, solo con tipos de nombre y sin claves de secreto. Antes bastaba que una entidad empezara por `Microsoft`, `from `, `HTTP`, `github`…, terminara en `:8080` o contuviera `timeout=` para ocultar un dato real. Lógica en `scripts/lib/sh01-code-allowlist.sh`; tests cruzados de Claude y Codex.
