---
name: tribunal-status
description: Show Truth Tribunal queue depth, recent verdicts, and pending evaluations
argument-hint: "[--clean] [--process N]"
allowed-tools: [Read, Bash, Glob]
model_tier: fast
context_cost: low
tier: core
---

# /tribunal-status — Truth Tribunal dashboard

Surface the state of the async Truth Tribunal queue (SPEC-106 Phase 2):
how many reports are pending evaluation, how many have a `.truth.crc` or
`.truth.pending` marker, and recent worker activity.

## Usage

```
/tribunal-status              # show queue + recent verdicts
/tribunal-status --process 5  # process up to 5 pending requests now
/tribunal-status --clean      # remove .done files older than 7 days
```

## Flow

1. **Queue depth** — `bash scripts/truth-tribunal-worker.sh status`
2. **Pending markers** — find all `*.truth.pending` under `output/` (max 20)
3. **Recent verdicts** — find all `*.truth.crc` under `output/`, parse
   their `verdict:` field, group by verdict
4. **Banner** — show summary + suggested next actions

## Output banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏛️  Truth Tribunal — Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Queue:       N pending  |  M in-progress  |  K done
Pending:     X reports awaiting /report-verify
Verdicts:    Y PUBLISHABLE | Z CONDITIONAL | W ITERATE | V ESCALATE

Pending list (run /report-verify <path> for each):
  - output/audits/yyyymmdd-foo.md
  - output/reports/bar.md
  ...

Recent verdicts (last 5):
  PUBLISHABLE  output/audits/yyyymmdd-baz.md
  ITERATE      output/reports/qux.md
  ...
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Implementation notes

- Pending list scans `**/*.truth.pending` (max depth 4 under repo root).
- Verdict list scans `**/*.truth.crc`, parses `verdict:` line via awk.
- If `--process N` passed: invokes `truth-tribunal-worker.sh process --max N`.
- If `--clean` passed: invokes `truth-tribunal-worker.sh clean`.
- Always end with the auto-compact reminder per Rule #16.

## Reference

- SPEC-106 Phase 2 — `docs/propuestas/SPEC-106-truth-tribunal-report-reliability.md`
- Worker — `scripts/truth-tribunal-worker.sh`
- Hook — `.opencode/hooks/post-report-write.sh`
- Sync entry point — `/report-verify <path>`
