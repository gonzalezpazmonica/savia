---
version_bump: minor
section: Security
---

### Security

- SE-443 S2: `scripts/mcp-security-audit.sh --osv <npx|uvx> <pkg@versión>` consulta OSV por avisos de malware `MAL-*` antes de habilitar un MCP. Envía solo `{ecosystem, name, version}`; exit 0 limpio, 1 malware, 2 ASK si OSV no es comprobable o si una opción del ejecutor (`--package`, `--from`, `--with`…) podría instalar otro paquete (nunca 0). Nombres PyPI normalizados (PEP 503); versiones solo en forma exacta y canónica (npm sin `+build`, PyPI PEP 440 sin `+local`), si no ASK; `curl -q`. Recibo JSONL en `output/mcp-osv-receipts.jsonl` construido con `jq --arg` (respaldo escapado en bash puro), sin repetir entrada cruda. 44 tests BATS sin red.

