---
version_bump: patch
section: Security
---

### Security

- SE-501 fail-closed (seguimiento de #1472): el paso «Derived paths absent» de ci.yml falla si la base no trae derived.sh gate; ya no usa el gate de la propia PR.
- SE-501: EXCLUDE_PATHS del escáner de confidencialidad con rutas exactas o directorios anclados en la raíz; un fichero cuyo nombre contiene una ruta excluida ya no se salta.
- SE-501: risk-tier.py lee scripts/derived-paths.txt de la base (--base, por defecto origin/main); una PR que se añade a la lista no rebaja su tier.
- SE-501: push-pr.sh --merge escanea con el escáner de origin/main (--pr-base); sin origin/main o sin ese modo, no hay merge.

- SE-501 (revisión de #1488): push-pr.sh --merge pasa al escáner de la base una blocklist generada por el generador de origin/main sobre las fuentes locales no versionadas (projects/, CLAUDE.local.md, TEAM.md, identity.md); antes solo veía la lista estática. Sin generador en la base, o sin el veredicto «Confidentiality scan (PR): PASS», no hay merge.
