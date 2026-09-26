---
context_tier: L2
token_budget: 1340
---
# Model alias schema — user-extensible mappings (SPEC-127 Slice 1)

> **Rule** — Agents and commands declare abstract capability tiers (`model_tier: heavy|mid|fast`)
> in their frontmatter — never `model:`. Each frontend maps the tier to a concrete model
> from the LOCAL tier definition in `~/.savia/preferences.yaml`. Zero vendor names in
> source-controlled files; `scripts/model-tier-lint.sh` enforces it.
> PV-06: cero vendor lock-in.

## Why a user-managed table

Savia ships 70+ agents and 500+ commands. Each declares a capability tier
(heavy / mid / fast), never a vendor model name. Every user's stack is
different: DeepSeek, Anthropic API, OSS hosted vendor, LocalAI on-prem,
Ollama local, enterprise vendor, custom corporate endpoint. Each user
declares **their** mappings in `~/.savia/preferences.yaml`. Agents and
commands stay clean; the repo stays neutral.

## Tier definitions

| Tier | `model_tier:` value | Semantic | Example tasks |
|---|---|---|---|
| Heavy | `heavy` | Deep reasoning, architectural decisions | Spec writing, code review, security audit |
| Mid | `mid` | Balanced — implementation, testing | Feature development, refactoring, test writing |
| Fast | `fast` | Low-latency, low-cost | Status queries, simple lookups, quick checks |

## Schema

`~/.savia/preferences.yaml` (top-level keys; managed by
`scripts/savia-preferences.sh`):

```yaml
version: 1                  # schema version (current: 1)

# Stack declaration — free-form strings. Framework branches on capabilities,
# not on vendor name.
frontend: <free-form>       # e.g. claude-code | opencode | codex | cursor | other
provider: <free-form>       # e.g. vendor name | "localai" | "ollama" | "custom-corp"

# Local tier definition, per frontend (each frontend may use another provider).
tiers:
  opencode:                          # provider-prefixed ids (SE-313)
    heavy: <provider>/<model-id>
    mid:   <provider>/<model-id>
    fast:  <provider>/<model-id>
  claude-code:                       # opus|sonnet|haiku|fable (default opus/sonnet/haiku)
    heavy: <selector>                # pin versions via ANTHROPIC_DEFAULT_*_MODEL (local env)
    mid:   <selector>
    fast:  <selector>
  codex:
    heavy: <model-id>
    mid:   <model-id>
    fast:  <model-id>

# Legacy fallback (not for claude-code) when tiers.<frontend> lacks a tier.
model_heavy: <provider>/<model-id>
model_mid:   <provider>/<model-id>
model_fast:  <provider>/<model-id>

# Capability declarations — yes / no / autodetect. autodetect uses env-var
# heuristics in scripts/savia-env.sh.
has_hooks:           <yes|no|autodetect>
has_task_fan_out:    <yes|no|autodetect>
has_slash_commands:  <yes|no|autodetect>

# Budget policy — Slice 5 reads this. "none" if the provider has no quota.
budget_kind:  <none|req-count|token-count|dollar-cap>
budget_limit: <integer-or-empty>

# Auth shape — informational. Credentials NEVER live here (use env vars / OS
# keychain / vault). The validator rejects api_key / password / secret /
# token keys outright.
auth_kind: <none|api-key|oauth|mtls|corporate-custom>
```

### Forbidden keys (rejected by validator)

- `api_key`
- `password`
- `secret`
- `token`

These belong in a credential manager, not a preferences file. The framework
will refuse to load preferences containing them.

## Resolution function (provider-agnostic)

Agents and commands declare `model_tier: heavy|mid|fast` in their frontmatter.
Each frontend resolves it at runtime:

```
resolve_model(frontend, tier) → effective_id
  preferences = read $HOME/.savia/preferences.yaml
  if preferences.tiers[frontend][tier]: return it
  if frontend != "claude-code":         return preferences.model_<tier>
  else:                                 return {heavy: opus, mid: sonnet, fast: haiku}[tier]
```

| Frontend | Adapter |
|---|---|
| Claude Code | `.claude/hooks/model-tier-inject.sh` (PreToolUse `Agent`) injects the selector as the per-invocation `model`; `claude --agent X` uses the session model |
| OpenCode | `.opencode/plugins/savia-foundation.ts` config hook sets `model` for agents and commands |
| Scripts | `savia_resolve_model <tier>` in `scripts/savia-env.sh` (frontend from `SAVIA_FRONTEND`) |
| Codex | Model from `~/.codex/config.toml`; `tiers.codex` feeds scripts that launch `codex exec` |

No vendor names in the resolution path; never rewrite sources with concrete ids.

## Examples — illustrative, NOT presets

### A — DeepSeek via OpenCode

```yaml
version: 1
frontend: opencode
provider: deepseek
model_heavy: deepseek/deepseek-v4-pro   # legacy fallback form
model_mid:   deepseek/deepseek-v4-pro
model_fast:  deepseek/deepseek-v4-flash
```

### B — Claude Code + OpenCode on different providers

```yaml
version: 1
frontend: claude-code
provider: anthropic
tiers:                     # block style only (2/4-space indent)
  claude-code:
    heavy: opus
    mid: sonnet
    fast: haiku
  opencode:
    heavy: deepseek/deepseek-v4-pro
    mid: deepseek/deepseek-v4-pro
    fast: deepseek/deepseek-v4-flash
```

## What this schema does NOT do

- Does not name any vendor in agent/command source files.
- Does not validate model ids — the user knows their provider.
- Does not store credentials — use env vars / keychain / vault.

## References

- SPEC-127 Slice 1 AC-1.3
- `scripts/savia-preferences.sh`, `scripts/savia-env.sh`, `docs/rules/domain/provider-agnostic-env.md`
