---
name: backlog-sync
description: "Sync local backlog with external PM tools (Azure DevOps, Jira, GitHub Issues)"
model_tier: mid
context_cost: medium
allowed-tools: [Read, Bash, Glob, Grep]
argument-hint: "<pull|push|diff> --project <name> [--provider <azure-devops|jira|github>]"
tier: core
---

# /backlog-sync

Synchronize local markdown backlog with external PM tools.

## Providers

| Provider | Adapter | Requirements |
|---|---|---|
| azure-devops | sync-adapters/azure-devops-adapter.sh | AZURE_DEVOPS_ORG_URL + PAT |
| jira | sync-adapters/jira-adapter.sh | JIRA_BASE_URL + email + token |
| github | sync-adapters/github-issues-adapter.sh | gh CLI + --repo |

## Actions

- **pull**: Download items from external tool, merge into local backlog
- **push**: Upload local PBIs to external tool (creates new, updates existing)
- **diff**: Show differences without applying changes

## Conflict Policy

- Both changed: show diff, ask PM to decide
- Only local changed: push
- Only remote changed: pull
- NEVER auto-resolve state, estimation, or assignment conflicts

## Steps

1. Detect provider from project _config.yaml or --provider flag
2. Validate credentials and connectivity
3. Execute requested action via adapter script
4. Log sync operation to output/.sync-log.jsonl
5. Show summary with counts

## Output

```
Sync: local ↔ azure-devops (project-name)
  Created: 2 | Updated: 3 | Conflicts: 0 | Skipped: 1
```
