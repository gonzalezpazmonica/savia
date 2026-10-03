---
globs: [".claude/settings.json", ".opencode/hooks/**"]
context_tier: L2
token_budget: 881
---

# Async Hooks Configuration

> Hooks that don't block the main flow run with `async: true`.

---

## Principle

Observability and logging hooks should NEVER block user interaction.
Mark them as `async: true` so they run in the background.

## Hook Classification

| Hook | Type | Async | Rationale |
|---|---|---|---|
| `session-init.sh` | Command | No | Must complete before session starts |
| `block-credential-leak.sh` | Command | No | Security gate — must block |
| `block-force-push.sh` | Command | No | Safety gate — must block |
| `validate-bash-global.sh` | Command | No | Safety gate — must block |
| `scope-guard.sh` | Command | No | Scope validation — must block |
| `tdd-gate.sh` | Command | No | Quality gate — must block |
| `prompt-hook-commit.sh` | Prompt | No | Commit validation — must block |
| `agent-hook-premerge.sh` | Agent | No | Pre-merge gate — must block |
| `agent-trace-log.sh` | Command | **Yes** | Logging only — never block |
| `context-tracker-hook.sh` | Command | **Yes** | Metrics only — never block |
| `bash-output-compress.sh` | Command | **Yes** | Output compression — never block |
| `plan-gate.sh` | Command | No | Plan approval — must block |
| `pre-commit-review.sh` | Command | No | Review gate — must block |

## Sin red ni `sleep` en primer plano (arranque blindado)

Un hook síncrono de `SessionStart`, `UserPromptSubmit` o `PreToolUse` no espera a la red ni duerme. Patrón: el sondeo corre en segundo plano (`( … ) </dev/null >/dev/null 2>&1 &`), escribe un fichero de estado `clave=valor` (escritura atómica con `mv`) y el **siguiente** arranque lo lee validando cada clave, nunca con `source`. Toda tarea de fondo redirige stdout: si lo hereda, quien espera EOF de la tubería del hook espera también a la tarea.

| Hook | Estado | Red en segundo plano |
|---|---|---|
| `session-init.sh` | `~/.savia/session-probes.state` (`SAVIA_PROBE_STATE`) | Ollama `/api/tags` + pre-carga, salud de Shield |
| `shield-autostart.sh` | `~/.savia/shield-autostart.state` (`SAVIA_SHIELD_STATE`) | `shield-launcher.py start` + salud; `flock` evita arranques dobles |

Excepción: un gate que necesita la respuesta (`pr-summary-gate.sh`) acota la espera (conexión 3 s, respuesta `PR_SUMMARY_LLM_TIMEOUT`, 90 s) y falla abierto con aviso. Es E/S síncrona deliberada. Un sondeo de más de 24 h no se anuncia como «activo».

## Implementation

In `.claude/settings.json`, async hooks use:

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Bash|Edit|Write",
      "command": ".opencode/hooks/agent-trace-log.sh",
      "async": true
    }]
  }
}
```

## Auto-Compact Configuration

```
CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=65
```

Triggers auto-compaction at 65% of effective window (~108K tokens for Opus 200K).
Set in `.claude/settings.json` env section. Previous value of 50% was too aggressive
(compacted after ~40K tokens). 65% balances session length with quality.
Note: effective window = contextWindow - 20K (output) - 13K (buffer) = ~167K.

## Environment Variables — Performance Tuning

```
BASH_MAX_OUTPUT_LENGTH=80000      # Max chars from Bash output (default 30K, upper 150K)
TASK_MAX_OUTPUT_LENGTH=80000      # Max chars from subagent output (default 32K, upper 160K)
ENABLE_TOOL_SEARCH=auto           # Deferred tool loading for 400+ tools
```

Set in `.claude/settings.json` env section. Raising output limits prevents
truncation before hooks can compress. Tool search reduces upfront context cost.

## Hook Event Coverage

| Event | Hooks | Coverage |
|---|---|---|
| SessionStart | session-init.sh | 1/1 |
| SessionEnd | session-end-memory.sh | 1/1 |
| PreToolUse | 16 hooks (8 matchers, 7 with `if`) | 16/16 |
| PostToolUse | 10 hooks (4 matchers) | 10/10 |
| PostToolUseFailure | post-tool-failure-log.sh | 1/1 |
| PreCompact | pre-compact-backup.sh | 1/1 |
| PostCompact | post-compaction.sh + memory-prime-hook.sh | 2/2 |
| Stop | 5 hooks | 5/5 |
| UserPromptSubmit | user-prompt-intercept.sh | 1/1 |
| CwdChanged | cwd-changed-hook.sh | 1/1 |
| SubagentStart | subagent-lifecycle.sh (async) | 1/1 |
| SubagentStop | subagent-lifecycle.sh (async) | 1/1 |
| TaskCreated | task-lifecycle.sh (async) | 1/1 |
| TaskCompleted | task-lifecycle.sh (async) | 1/1 |
| FileChanged | file-changed-staleness.sh (async) | 1/1 |
| InstructionsLoaded | instructions-tracker.sh (async) | 1/1 |
| ConfigChange | config-reload.sh (async) | 1/1 |
| **Total** | **55 hook instances** | **17/28 events (61%)** |

28 hook events available in Claude Code (SPEC-071). Target achieved: 17/28 (61%).
