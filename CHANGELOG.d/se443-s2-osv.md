---
version_bump: minor
section: Security
---

### Security

- SE-443 S2: `scripts/mcp-security-audit.sh --osv <npx|uvx> <pkg@versión>` consulta OSV por avisos de malware `MAL-*` antes de habilitar un MCP. Envía solo `{ecosystem, name, version}`; exit 0 limpio, 1 malware, 2 ASK si OSV no es comprobable (nunca 0). Recibo JSONL en `output/mcp-osv-receipts.jsonl`. 26 tests BATS sin red.

