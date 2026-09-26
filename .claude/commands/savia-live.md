---
name: savia-live
description: "Show what Savia is working on right now — live task queue and recent activity"
model_tier: fast
allowed-tools: [Bash, Read]
context_cost: low
complexity_tier: mode1
tier: core
---

# /savia-live

Show the current Savia work status: active task, queue, and recent tool activity.

## Execution

Run the status script and display its output:

```bash
bash scripts/savia-status.sh
```

Display the output to the user as-is. No additional commentary needed.
