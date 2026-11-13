---
version_bump: patch
section: Fixed
---

### Fixed

- SE-515 S1 (refutación Codex PR #1523): learning-recall.sh distingue error del buscador (exit 4, outcome=error) de «sin aciertos»; el guard de OpenCode no inyecta sin fila de emisión y rechaza aciertos malformados; el arnés P10 no acepta emisiones sin traza; learning-metric.sh emite JSON válido con «.7» y el orquestador no declara «medido» si no puede leer L.

