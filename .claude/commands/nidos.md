---
name: nidos
description: Manage parallel terminal isolation with named git worktrees (Savia Nidos)
argument-hint: "[create <name>|list|enter <name>|remove <name>|status]"
allowed-tools: [Bash, Read]
model_tier: fast
context_cost: low
tier: core
---

# /nidos

Manage Savia Nidos — isolated git worktrees for running multiple Claude Code terminals in parallel without conflicts. Worktrees are stored in `~/.savia/nidos/` (local disk, outside cloud sync).

## Usage

```
/nidos                      # list active nidos
/nidos create feat-auth     # create nido with branch nido/feat-auth
/nidos create fix --branch fix/login  # custom branch
/nidos enter feat-auth      # show path to cd into
/nidos remove feat-auth     # clean up after merge
/nidos status               # detect current nido
```

## Execution

Run the command:

```bash
bash scripts/nidos.sh $ARGUMENTS
```

If no arguments, run:

```bash
bash scripts/nidos.sh list
```

## Quick reference

| Subcommand | Action |
|------------|--------|
| `create <name>` | New worktree + branch |
| `list` | Active nidos with branches |
| `enter <name>` | Print nido path |
| `remove <name>` | Delete worktree + branch |
| `status` | Detect current nido |

## Convention

See `@docs/rules/domain/nidos-protocol.md` for naming, lifecycle, and scope rules.
