---
version_bump: patch
section: Security
---

### Security

- auto-rebase y resolve-all-open-prs copian resolve-pr-conflicts.sh, derived.sh y derived-paths.txt de main; el resolutor ya no carga código ni la lista D de la rama que resuelve (rev-1472 P1-1).
- auto-rebase recibe la lista de PR por env: un nombre de rama con comillas ya no inyecta órdenes en el job.
- confidentiality-scan.sh --pr/--staged usa git diff --text: un .gitattributes de la PR que marca ficheros como binarios ya no oculta líneas añadidas.
- workflow-hmac-check.py pr-secrets falla también con toJSON(secrets), secrets: inherit y workflows workflow_run que nombran la clave.

