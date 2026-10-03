# Hooks — Event-Driven Pipeline Gates

pm-workspace uses hooks that cover the five lifecycle events: SessionStart, PreToolUse, PostToolUse, Stop, and SubagentStop. All hooks have 100% test coverage via BATS.

## Hook Lifecycle Events

| Event | Timing | Purpose | Max Hooks |
|---|---|---|---|
| **SessionStart** | Session initialization | Load context, detect config | 2 |
| **PreToolUse** | Before executing tool | Validate, block invalid operations | 5 |
| **PostToolUse** | After tool execution | Async logging, cleanup | 3 |
| **Stop** | Before session ends | Final validation, scope checks | 3 |
| **SubagentStop** | Before agent returns | Pre-merge quality gates | 1 |

## Hook Inventory

### Security Hooks (Block-Type: exit 2 on violation)

| Hook | Event | Type | Blocks? | Tested? | Purpose |
|---|---|---|---|---|---|
| `block-credential-leak` | PreToolUse | Security | OK Yes | OK 100% | Detect AWS keys, JWT, PATs, connection strings, private keys before execution |
| `block-force-push` | PreToolUse | Security | OK Yes | OK 100% | Block `git push --force`, direct main/master push, `--amend`, `reset --hard` |
| `block-infra-destructive` | PreToolUse | Security | OK Yes | OK 100% | Block `terraform destroy`, production `terraform apply`, resource group deletion |

### Quality Gates (Block-Type: exit 2 on requirement failure)

| Hook | Event | Type | Blocks? | Tested? | Purpose |
|---|---|---|---|---|---|
| `tdd-gate` | PreToolUse | Quality | OK Yes | OK 100% | Require test files before editing production code (.cs, .py, .ts, etc.) |
| `compliance-gate` | PreToolUse | Quality | OK Yes | OK 100% | Verify CHANGELOG links, file size limits (≤150 lines), frontmatter, README sync |
| `stop-quality-gate` | Stop | Quality | OK Yes | OK 100% | Final check for secrets in staged files before session ends |
| `pre-commit-review` | Stop | Quality | OK Yes | OK 100% | Comprehensive pre-commit: branch name, secrets, build, tests, format, code review |

### Observability/Logging Hooks (Warning-Only: exit 0 with messages)

| Hook | Event | Type | Blocks? | Tested? | Purpose |
|---|---|---|---|---|---|
| `session-init` | SessionStart | Observability | FAIL No | OK 100% | Load PAT status, active profile, git branch, Company Savia inbox notifications |
| `agent-trace-log` | PostToolUse | Observability | FAIL No | OK 100% | Log agent execution: command, model, tokens, duration, success/failure (async) |
| `post-edit-lint` | PostToolUse | Observability | FAIL No | OK 100% | Auto-lint after file edits: dotnet format, ruff, eslint, gofmt, rustfmt, etc. (async) |

### Workflow Hooks (Warning-Only: exit 0 with suggestions)

| Hook | Event | Type | Blocks? | Tested? | Purpose |
|---|---|---|---|---|---|
| `plan-gate` | PreToolUse | Workflow | FAIL No | OK 100% | Suggest `/spec-generate` if no recent .spec.md found (warning only) |
| `scope-guard` | Stop | Workflow | FAIL No | OK 100% | Warn if modified files exceed spec-declared scope (yellow warning) |

### Agent/Orchestration Hooks

| Hook | Event | Type | Blocks? | Tested? | Purpose |
|---|---|---|---|---|---|
| `agent-dispatch-validate` | PreToolUse (Task) | Orchestration | OK Yes | OK 100% | Verify subagent context: frontmatter, CHANGELOG format, dispatch checklist |
| `agent-hook-premerge` | PreToolUse (Bash) | Orchestration | OK Yes | OK 100% | Pre-merge quality gate for agent-submitted code (runs before merge) |
| `agent-trace-log` | PostToolUse (Task) | Observability | FAIL No | OK 100% | Register agent execution in trace log (async, doesn't block) |
| `validate-bash-global` | PreToolUse (Bash) | Quality | OK Yes | OK 100% | Syntax check: `set -uo pipefail` presence, no unquoted vars, loop safety |
| `prompt-hook-commit` | PreToolUse (Bash) | Quality | WARN Warn | OK 100% | Semantic warning: Is commit message describing actual changes? (exit 0, warns) |
| `memory-auto-capture` | PostToolUse (Edit) | Observability | FAIL No | OK 100% | Auto-capture patterns from code edits to agent memory (async) |

## Hook Types Explained

### Block-Type Hooks (exit 2: prevents operation)
- Non-negotiable: security violations, spec requirements, compliance rules
- Used in `PreToolUse` before execution, `Stop` for final checks
- Example: `block-credential-leak` detects hardcoded API keys and halts operation

### Warning-Type Hooks (exit 0: informs, doesn't block)
- Informational or suggestive
- User can ignore or act upon suggestion
- Example: `plan-gate` suggests spec if none found, but allows edit anyway

### Async Hooks
- Background execution: don't block main flow
- Logging, linting, memory capture
- Examples: `post-edit-lint`, `agent-trace-log`, `memory-auto-capture`

## Exit Codes

| Code | Meaning | Action |
|---|---|---|
| **0** | Allow / Success | Operation proceeds (or async hook completes) |
| **2** | Block / Failure | Operation blocked, user must fix |
| **1** | Error | Script error (should not happen in hooks) |

## Hook Grouping by Phase

### Validation Phase (What's being attempted?)
- `validate-bash-global` (Bash syntax)
- `plan-gate` (Spec exists?)

### Security Phase (Is it safe?)
- `block-credential-leak` (Hardcoded secrets?)
- `block-force-push` (Dangerous git ops?)
- `block-infra-destructive` (Infrastructure destruction?)

### Quality Phase (Does it meet standards?)
- `tdd-gate` (Tests exist for code?)
- `compliance-gate` (Files ≤150 lines, CHANGELOG links, frontmatter?)
- `stop-quality-gate` (No secrets in staging?)
- `pre-commit-review` (Comprehensive: tests, format, review, branch)

### Observability Phase (What happened?)
- `session-init` (Initialize context)
- `agent-trace-log` (Log agent activity)
- `memory-auto-capture` (Learn from edits)
- `post-edit-lint` (Check formatting)

### Orchestration Phase (Agent execution)
- `agent-dispatch-validate` (Valid agent context?)
- `agent-hook-premerge` (Quality before merge)

## Configuration (settings.json)

Hooks are defined in `.claude/settings.json` under `hooks` key, organized by event:

```json
{
  "hooks": {
    "SessionStart": [ ... ],      // 2 hooks
    "PreToolUse": [ ... ],        // Matcher: Bash, Task, Edit|Write
    "PostToolUse": [ ... ],       // Async: true
    "Stop": [ ... ],              // Final checks
    "SubagentStop": [ ... ]       // (Currently unused)
  }
}
```

### `blocking: true` (fail-closed en Savia Space)

Los guards de seguridad de PreToolUse llevan `"blocking": true`. En modo mediado de
Savia Space, si un hook así falla, se cuelga o no se puede lanzar, la herramienta se
bloquea (D23-5). Claude Code y OpenCode ignoran la clave. La lista, la exclusión de
`data-sovereignty-gate` y la política de regresión están en
`docs/rules/domain/hooks-blocking-guards.md`; el auditor es
`bash scripts/hooks-integrity-check.sh --blocking`.

## Testing Coverage

All hooks have BATS tests in `tests/hooks/`:
- Unit tests for each hook's logic
- Integration tests for typical flows
- Edge cases (empty input, missing files, timeouts)
- Exit code verification

Run tests: `bash scripts/test-hooks.sh` or `bats tests/hooks/*.bats`

## Performance Notes

- SessionStart hooks: max 15s timeout
- PreToolUse hooks: max 5-30s depending on complexity
- PostToolUse async hooks: don't impact user flow
- Stop hooks: max 10-30s (final validation)
- Safety net: Session init never blocks (5s timeout, fallback on error)

## Key Principles

1. **Fail safely**: Hooks never crash Claude Code / OpenCode session (exit 0 fallback)
2. **No false positives**: Extensive whitelisting to avoid blocking legitimate code
3. **Context aware**: Hooks respect file types, extensions, paths (excludes tests, migrations, configs)
4. **Composable**: Multiple hooks work together without interference (correct exit codes)
5. **Async where possible**: Observability hooks don't slow down user interaction
6. **100% tested**: Every hook has BATS coverage, edge case handling verified

## Debugging a Hook

To debug hook behavior:

```bash
# Test a hook directly
bash .opencode/hooks/block-credential-leak.sh < test-input.json

# With debug output
bash -x .opencode/hooks/block-credential-leak.sh < test-input.json

# Run BATS tests for a specific hook
bats tests/hooks/test-block-credential-leak.sh
```

Check hook output in Claude Code / OpenCode console or task execution logs.
