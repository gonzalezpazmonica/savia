---
version_bump: patch
section: Fixed
---

### Fixed

- agent-code-map: refresh-agent-maps.sh emite JSON válido (escapado de barras, comillas y controles; asunto truncado por git respetando UTF-8), no marca stale-no-checkout un checkout con una sola entrada, no pisa las citas del cuerpo del .acm, reporta missing-acm y missing-repo con exit 1, rechaza slug/repo con path traversal (exit 2) escribe con temporal único seguro en concurrencia (también INDEX.acm) y falla con status error y exit 1 si un .acm no se puede escribir, sin tocar INDEX.acm ni imprimir OK. SKILL.md alineado: los comandos /codemap:* no existen.

