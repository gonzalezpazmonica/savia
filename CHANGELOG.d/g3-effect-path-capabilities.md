---
version_bump: patch
section: Security
---

### Security

- Hueco G3: frontend-probe.sh marca DECLARED (no NATIVE) las capacidades de control sin hook en .claude/settings.json ni guard en el plugin de OpenCode; hoy network_policy y durable_handoff en Claude, y además external_effect_control en OpenCode.
- Hueco G3: coherence-gates.sh deja de dar PASS al cierre del harness por existir los scripts; PASS solo si un hook o un workflow de CI los invoca. eval-coverage L4 bloquea si la matriz no es evaluable y muestra el recuento real.
- Hueco G3: egress-gate.sh pasa dominio y protocolo por argv validados (antes interpolados en código Python) y deniega ante YAML malformado o con estructura inesperada en vez de usar una lista de reserva permisiva.

