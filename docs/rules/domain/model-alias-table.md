---
context_tier: L2
token_budget: 420
---

# Model alias table — provider-agnostic resolution

> **Rule** — Agents and commands declare abstract capability tiers
> (`model_tier: heavy|mid|fast`) in their frontmatter, never `model:`.
> Each frontend maps the tier to a concrete model from the LOCAL tier
> definition (`~/.savia/preferences.yaml` → `tiers.<frontend>`).
> Vendor model names in source files are a violation (`scripts/model-tier-lint.sh`).
> Full schema and adapters: `docs/rules/domain/model-alias-schema.md`.

## Resolution flow

```
agent/command frontmatter        ~/.savia/preferences.yaml (local, per user)
┌─────────────────────┐          ┌───────────────────────────────┐
│ model_tier: heavy    │─────────▶ tiers.<frontend>.heavy
│ model_tier: mid      │─────────▶ tiers.<frontend>.mid
│ model_tier: fast     │─────────▶ tiers.<frontend>.fast
└─────────────────────┘          │ fallback: model_<tier> (no CC) │
                                 └───────────────────────────────┘
```

`<frontend>` = `claude-code` | `opencode` | `codex`. Each frontend may point
to a different provider; the repo never knows which.

## Tier semantics

| Tier | Semantic | Tasks |
|---|---|---|
| `heavy` | Deep reasoning | Architecture, spec writing, security audit, code review |
| `mid` | Balanced | Feature implementation, refactoring, testing |
| `fast` | Low latency, low cost | Status queries, lookups, simple operations |

## What this rule does NOT do

- It does not hardcode any vendor model name in source-controlled files.
- It does not auto-update — the user manages `~/.savia/preferences.yaml`.
- It does not validate model ids — the user knows their provider.
