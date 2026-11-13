---
version_bump: patch
section: Added
---

### Added

- SE-529 (PROPOSED): spec de compactación que conserva y reinyecta de verdad; evidencia del hook PreCompact que no lee la conversación y de la reinyección sin filtro de proyecto ni tope; slices S0 medición, S5 redacción de privados, S1 extracción, S2 reinyección acotada, S4 resumen único y S3 tests con cargas medidas; paridad Claude Code/OpenCode; Q2 resuelta (el aviso explícito basta como paridad si OpenCode no entrega la conversación), Q1 y Q3 abiertas.
- SE-529: el comprobador de la spec exige la frase de confirmación pendiente por patrón de línea, confina las referencias a la raíz del repo, ancla los términos privados a palabra completa, escanea changelog, log y planning, y sale 2 con una spec no UTF-8; la spec fija un único texto de aviso y aclara que `"project":"null"` fijado no cuenta como otro proyecto.
