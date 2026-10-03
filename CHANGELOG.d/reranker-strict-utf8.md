---
version_bump: patch
section: Fixed
---

### Fixed

- El reranker rechaza UTF-8 inválido en stdin incluso cuando Python usa `surrogateescape`, sin emitir un resultado válido ni traceback.
