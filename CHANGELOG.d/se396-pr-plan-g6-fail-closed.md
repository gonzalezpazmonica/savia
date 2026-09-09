---
category: Fixed
spec: SE-396
---
- Hace que G6 falle ante timeout, crash o salida BATS incompleta y ejecuta de
  forma acotada las suites modificadas, en vez de convertir un timeout de la
  suite serial completa en `PASS (ok)`.
