---
version_bump: patch
section: Fixed
---

### Fixed

- perf(hooks): memory-auto-capture y session-end-snapshot sin forks en el camino común (p50 41→5 ms y 14→7 ms en local); causa raíz del ratchet de latencia (check 9) fallando en todas las PR

