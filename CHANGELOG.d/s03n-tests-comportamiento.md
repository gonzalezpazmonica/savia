---
version_bump: patch
section: Security
---

### Security

- S03n: ext-platform-gate.sh ya no interpola --card-id/--skill en código Python (una comilla en --card-id daba ALLOW con los permisos de otra tarjeta activa) y rechaza --payload-level no entero (antes valía 0 y admitía inyección aritmética); el motivo de denegación de la allowlist ya no se pierde
- S03n: focal-checkin.sh valida nido e intervalo y no informa éxito con el lock ocupado; skills-lint.sh --json sin la orden suelta que ensuciaba stderr
- S03n: pruebas de comportamiento discriminante para 8 ficheros de test (focal-checkin, prompt-security-scan, skills-lint, ext-platform-gate, validate-agent-permissions, risk-tier, transcriptor-scan, agents-catalog-sync)

