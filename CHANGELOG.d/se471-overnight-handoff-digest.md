---
version_bump: minor
section: Added
---

### Added

- SE-471: scripts/overnight-handoff-digest.sh — relevo nocturno de solo lectura que separa declarado / validado / aceptado por run y lista las decisiones con tope (sin marca con rc≠0, FALLO, OK sin validar, PARCIAL, malformada); --online consulta gh solo para URL de PR en allowlist. Se retira scripts/run-adversarial-evals.sh (sin callers; solo listaba el YAML de casos SE-255).

