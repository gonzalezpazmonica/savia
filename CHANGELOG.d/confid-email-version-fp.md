---
version_bump: patch
section: Fixed
---

### Fixed

- Escáner de confidencialidad (Check 3): un dominio que empieza por dos etiquetas numéricas (`lib@1.0.0.js`, `react@18.2.0.min.js`) es una versión, no un email; los emails reales, incluidos los de dominio numérico de una etiqueta (`163.com`), siguen bloqueando. Desbloquea la PR #1676.
