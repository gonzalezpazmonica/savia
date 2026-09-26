---
name: agent-memory
description: Inspect and manage persistent memory fragments for subagents.
argument-hint: "[agent-name] [--clear] [--list]"
allowed-tools: [Read, Write, Edit, Glob, Grep, Bash]
model_tier: fast
context_cost: low
tier: core
---

# /agent-memory — Agent Memory Manager

Manage persistent memory for subagents across sessions.

## Usage

- `/agent-memory` — List all agents with memory and their fragment count
- `/agent-memory {agent-name}` — Show memory contents for a specific agent
- `/agent-memory --list` — Summary table of all agent memories
- `/agent-memory {agent-name} --clear` — Clear memory for an agent (with confirmation)

## Behavior

### List mode (default or `--list`)

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 /agent-memory — Agent Memory Overview
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

1. Scan `.claude/agent-memory/` for directories
2. For each agent directory, count non-empty sections in MEMORY.md
3. Display table:

| Agent | Scope | Sections | Last Modified |
|---|---|---|---|
| architect | project | 3 | 2026-03-03 |

### Show mode (`/agent-memory {name}`)

1. Read `.claude/agent-memory/{name}/MEMORY.md`
2. Display contents with section headers
3. If agent has local memory too: note `(+ local memory exists)`

### Clear mode (`/agent-memory {name} --clear`)

1. Confirm with user: "Clear all memory for {name}? This cannot be undone."
2. If confirmed: reset MEMORY.md to template (headers only, no content)
3. Show confirmation

## Memory Scopes

| Scope | Path | Git | Purpose |
|---|---|---|---|
| project | `.claude/agent-memory/{name}/` | tracked | Shared team knowledge |
| local | `.claude/agent-memory-local/{name}/` | ignored | Personal insights |
| user | `~/.claude/agent-memory/{name}/` | N/A | Cross-project personal |

## Rules

- NEVER delete the MEMORY.md file — only clear its content sections
- NEVER expose local/user memory contents to other team members
- Memory files follow the 150-line limit
- Agents populate their own memory during normal operation
