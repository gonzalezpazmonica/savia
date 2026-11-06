---
version_bump: patch
section: Security
---

### Security

- S03n: ext-platform-gate.sh ya no interpola --card-id/--skill en código Python (una comilla en --card-id daba ALLOW con los permisos de otra tarjeta activa) y rechaza --payload-level no entero (antes valía 0 y admitía inyección aritmética); el motivo de denegación de la allowlist ya no se pierde
- S03n: ext-platform-gate.sh acota --payload-level, max_payload_level y maxLevel a 6 dígitos (la aritmética de bash daba la vuelta en 64 bits: 2^64 valía 0 y daba ALLOW) y list-deny ya no interpola rutas en Python
- S03n: focal-checkin.sh valida nido e intervalo y no informa éxito con el lock ocupado; skills-lint.sh --json sin la orden suelta que ensuciaba stderr
- S03n: pruebas de comportamiento discriminante para 8 ficheros de test (focal-checkin, prompt-security-scan, skills-lint, ext-platform-gate, validate-agent-permissions, risk-tier, transcriptor-scan, agents-catalog-sync)

- S03n: ext-platform-gate.sh avisa por stderr cuando no puede escribir el log de auditoría (antes se perdía en silencio); el test de comilla en --skill ya llega a la allowlist global
