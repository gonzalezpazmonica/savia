---
layer: peripheral
name: savia-vaults
description: "Usar cuando se interactua con SaviaVaults — cupulas de contexto, busqueda federada, servidores MCP/A2A, backups, confidencialidad. Triggers: 'crea una cupula', 'indexa documentacion', 'busca en los vaults', 'federate este dome', 'backup del conocimiento', 'nivel de confidencialidad', 'gestiona cupulas', 'context dome', 'vaults CLI'. NOT para diseno de arquitectura de conocimiento (usar context-dome-manager agent)."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: knowledge-management
  savia.maturity: stable
  savia.context: project
  savia.maturity: stable
  savia.priority: high
  savia.recommends: "context-dome, knowledge-graph, ubiquitous-language"
  savia.tags: "vaults, cupulas, contexto, federacion, mcp, a2a, backup, confidencialidad"
---

# SaviaVaults — Operacion de Cupulas de Contexto

Gestiona cupulas de contexto via CLI `vaults` y MCP tools de SaviaVaults.

## Comandos esenciales

```bash
# Crear y gestionar
vaults dome create <nombre>
vaults dome list|info|delete <nombre>
vaults dome sync <nombre> --source <dir>
vaults dome index <nombre> --force

# Servidores
vaults server start|stop|status|logs --name <dome> [--transport mcp|a2a|both]

# Busqueda
vaults dome search "query" [--federated] [--dome <name>]
vaults search "query"

# Federacion
vaults dome federate add <id> <url> [--token] [--weight]
vaults dome federate remove|list|health

# Backups
vaults backup create --name <dome> --compress
vaults backup list|restore <id>|schedule "cron"|status

# Confidencialidad
vaults confidentiality set N1|N2|N3|N4 --dome <nombre>
vaults confidentiality get|list|audit --dome <nombre>

# Usuarios
vaults user add <user> --role admin|reader|writer --dome <dome>
vaults user list|passwd|perm --dome <dome>

# Salud
vaults health
vaults config show
```

## Flujos comunes

**Crear cupula desde docs**: `vaults dome create mi-docs` → `vaults dome sync mi-docs --source ./docs` → `vaults dome index mi-docs` → `vaults server start --name mi-docs --transport both`

**Federar dos cupulas**: Maquina A: `vaults server start --name alpha --transport a2a`. Maquina B: `vaults dome federate add alpha http://IP:PORT --token TOKEN` → `vaults dome search "termino" --federated`

**Backup**: `vaults backup create --name docs --compress` → restaurar con `vaults backup restore ID --target /tmp/restored --dry-run`

## MCP Tools (9)

`vault_read` `vault_write` `vault_search` `vault_list` `vault_stats` `vault_index` `vault_diff` `vault_log` `vault_tags`

## Anti-patrones

- NO borrar dome sin backup previo
- NO exponer domes N3-N4 sin token de autenticacion
- NO federar en bucle (A→B→C→A). Max 1 hop
- NO modificar `.savia-vault/` a mano. Usa `vaults` CLI.
- NO indexar `.git` o `node_modules` (el sandbox los excluye)

Para decisiones estrategicas de arquitectura de conocimiento, delegar al agente `context-dome-manager`.
