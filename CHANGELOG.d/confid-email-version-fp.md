---
version_bump: patch
section: Fixed
---

### Fixed

- Escáner de confidencialidad (Check 3): una versión numérica seguida de una extensión de código al final (`lib@1.0.0.js`, `react@18.2.0.min.js`, `lib@1.0.0.js.map`) ya no se toma por un email; los emails reales siguen bloqueando, también los de dominio numérico (`x@163.com`) o subdominio numérico (`a@1.2.example.org`). El job de la PR ejecuta el escáner de main: una vez fusionado este cambio en main, la PR #1676 deja de bloquearse por la URL de CDN de su guía.
