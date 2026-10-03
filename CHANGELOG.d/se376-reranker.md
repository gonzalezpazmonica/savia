---
version_bump: patch
section: Fixed
---

### Fixed

- reranker: rerank.py rechaza entradas inválidas sin traceback (raíz no objeto, query/text no string, cosine no numérico, stdin no UTF-8), cae al fallback ante cualquier fallo del cross-encoder registrándolo, marca relevance null en los fallbacks; la sonda ya no rebaja BLOCKED a NEEDS_INSTALL; SKILL.md, DOMAIN.md y SE-032 alineados con el comportamiento real.

