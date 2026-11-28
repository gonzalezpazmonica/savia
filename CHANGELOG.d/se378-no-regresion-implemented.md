---
bump: patch
section: Added
---

- SE-378: `roadmap.sh validate` falla si LOG.md devuelve una iniciativa de IMPLEMENTED a un estado previo. `ROADMAP-UNIFIED-20260827` queda SUPERSEDED y la spec documenta que las prioridades contradictorias siguen sin comprobarse. El estado de cada cabecera se normaliza, así que `APPROVED→IMPLEMENTED`, `(IMPLEMENTED)` e `IMPLEMENTED→APPROVED` también cuentan.
