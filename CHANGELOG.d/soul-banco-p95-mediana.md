---
version_bump: patch
section: Fixed
---

### Fixed

- El banco de continuidad (SE-490, AC-3) mide cada escenario Q1 5 veces y usa la mediana: con 18 escenarios el p95 es el máximo y una sola parada de reloj del equipo de CI (windows-latest: 3620 ms frente a ~40 ms) suspendía el gate sin regresión de código; una lentitud real sigue suspendiendo y el informe lista los escenarios más lentos con sus medidas

