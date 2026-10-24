---
version_bump: patch
section: Security
---

### Security

- SE-453 S3 tanda 2: prompt-security-scan, mcp-security-audit, iac-security-scan, security-audit-all y confidentiality-scan emiten el resultado clean/findings/unknown; un hueco (herramienta ausente, diff imposible, sub-escáner ilegible) queda registrado como no medido.
- security-audit-all ya no pierde los hallazgos de un sub-escáner que sale 1; confidentiality-scan detecta de nuevo ficheros prohibidos (Check 4) y no da «No content to scan» si git no calcula el diff; mcp-security-audit sin python3 sale 2 en vez de un falso MCP-00.
- Revisión de #1385: el Check 4 de confidentiality-scan ve un .p12 binario o un .env vacío (antes CLEAN) y ya no excluye tests/ ni pentesting/; security-audit-all normaliza motivos ajenos de sus sub-escáneres (JSON agregado roto) y `SAVIA_GATE_UNKNOWN=block` bloquea con huecos aunque haya hallazgos menores; prompt-security-scan y mcp-security-audit respetan `block`; mcp-security-audit sin ninguna config ⇒ unknown.
