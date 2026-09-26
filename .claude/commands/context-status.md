---
name: context-status
description: "Show context window usage, model tier, and optimization recommendations"
model_tier: fast
context_cost: low
allowed-tools: [Read, Bash, Glob]
argument-hint: "[--json]"
tier: core
---

# /context-status

Show current context window status and recommendations.

## Steps

1. Read SAVIA_* env vars (set by model-capability-resolver at session start)
2. Count loaded rules, skills, and agents in current session
3. Calculate estimated token usage
4. Show optimization recommendation

## Output format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Context Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Model ................ {SAVIA_DETECTED_MODEL}
  Context window ....... {SAVIA_CONTEXT_WINDOW} tokens
  Tier ................. {SAVIA_MODEL_TIER}
  Compact threshold .... {SAVIA_COMPACT_THRESHOLD}%
  Strategy ............. {lazy_loading level}
  Recommendation ....... {action}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

If `--json` argument, output as JSON instead.

## Recommendations

- If tier=fast: "Consider /compact frequently — 200K window fills fast"
- If tier=high: "Normal operation — /compact at ~65%"
- If tier=max: "Full capacity — /compact only if performance degrades"
