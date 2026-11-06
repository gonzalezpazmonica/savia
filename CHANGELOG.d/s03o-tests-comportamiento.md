---
version_bump: patch
section: Security
---

### Security

- S03o: mind-virus scan-memory.sh nunca contaba los ficheros malicious, así que el load gate de SessionStart no avisaba ni bloqueaba; ahora cuenta malicious y errores de lectura, y falla (exit 2) si el detector falta o falla
- S03o: capex-phase-gate.sh escribe y lee el ledger de fases como JSON real (un asset_name con comillas falseaba la fase y daba CAPITALIZABLE) y valida engagement, fase y fecha
- S03o: corporate-monotonicity-gate.sh da exit 2 ante entries que no son lista de objetos (antes PASS), normaliza ids inmunes (crit-026) y detecta señales con tildes
- S03o: dag-gate-cost-checker.sh lee stdin (antes siempre «DAG vacío»), respeta gate_type multilínea y da exit 2 ante JSON inválido; graphrag-quality-gates.sh mira first_seen/last_seen en el check de fechas futuras; install-git-hooks.sh (modo clásico) apunta al repo correcto y entiende worktrees
- S03o: pruebas de comportamiento para 8 ficheros de test (auditor 53-76 → 83-91, mutantes manuales 25/174 → 173/174; el superviviente es equivalente)

