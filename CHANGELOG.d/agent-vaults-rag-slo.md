---
version_bump: patch
section: Fixed
---

### Fixed

- savia-vaults: el SLO de RAG falla (slo.ok=false, exit 2) con lagHours >= 24 o con una cúpula indexada y rag.enabled=false; rag sync --all sale distinto de 0 con ALERTA en stderr y evento alert en rag.jsonl si hay cúpulas indexadas deshabilitadas (L32 P7); nuevo rag drop <cúpula> para limpiar el índice huérfano, alertas sin duplicar en stdout/stderr ni repetir el mismo día en rag.jsonl
