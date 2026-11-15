---
version_bump: patch
section: Removed
---

### Removed

- SE-513 retirada: eliminadas la admisión duradera y la cola SE-075 sobre la que se apoyaba (scripts/lib/task-queue.py, 773 líneas, y sus 1.192 líneas de pruebas), sin ningún consumidor. La spec SE-513 pasa a RETIRED; SE-075 queda con una nota (Slice 1 retirado). El prototipo S0 y su prueba de coherencia se conservan. Prueba de retirada: tests/structure/test-se513-admision-retirada.bats.

