---
version_bump: minor
section: Changed
---

### Changed

- SE-501 (opción B): la firma de confidencialidad, el .scm generado, docs/rules/INDEX.md y rule-manifest.json dejan de versionarse; se generan con scripts/derived.sh ensure. Gate G20 / «Derived paths absent», escaneo de la PR con el escáner de la base («Confidentiality scan (PR)»), auditoría completa de cada commit de main (confidentiality-main.yml, solo lectura) y firma retirada del flujo de PR.

