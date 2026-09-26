---
name: agent-activity
description: "Show structured activity log of recent agent executions"
model_tier: fast
context_cost: low
allowed-tools: [Read, Bash, Glob]
argument-hint: "[--last N] [--format table|json]"
tier: core
---

# /agent-activity

Show recent agent activity from the structured log.

## Data source

Reads from `output/agent-runs/` directory and agent-trace logs.

## Steps

1. Scan `output/agent-runs/` for recent audit logs
2. Parse agent trace entries (JSONL format)
3. Display summary: agent name, duration, tokens, result

## Output (table format)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Agent Activity — Last 10
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
| Time | Agent | Duration | Tokens | Result |
|------|-------|----------|--------|--------|
| ... | ... | ... | ... | ... |

Total: X executions | Y tokens | Z avg duration
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Filters

- `--last N`: Show last N entries (default: 10)
- `--format json`: Output as JSON array
- `--agent NAME`: Filter by agent name
