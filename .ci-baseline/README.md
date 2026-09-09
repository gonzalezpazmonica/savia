# CI Baseline counters

> Ratchet pattern: SE-037/038/039 Slice 3 enforcement gates compare
> current violation count against the frozen baseline. Gates fail if
> current > baseline. When remediation lands, the committer MUST
> update the baseline to lock in the improvement (this prevents
> regression re-entry).

## Files

| File | Source | Semantics |
|---|---|---|
| `agent-size-violations.count` | `scripts/agent-size-audit.sh` | Count of `.opencode/agents/*.md` > 4KB without `size_exception` |
| `hook-critical-violations.count` | `scripts/hook-bench-all.sh --runs 5` | Count of critical hooks with p50 > 20ms |
| `bats-compliance-min.pct` | `scripts/audit-all-bats.sh` | Minimum test-auditor compliance % (≥ value) |

## Update workflow (when remediation reduces violations)

```bash
# After fixing some violations in a PR:
bash scripts/agent-size-audit.sh --quiet
new_count=$(grep -oP 'Violations: \K\d+' output/agent-size-report-*.md | tail -1)
echo "$new_count" > .ci-baseline/agent-size-violations.count
git add .ci-baseline/agent-size-violations.count
```

## Update workflow (when a new exception is legitimately granted)

- Add `size_exception: <motivo>` to the agent frontmatter
- Re-run the probe; count decreases automatically
- Update baseline

## Anti-pattern (forbidden)

- Never increase a baseline number. Baselines only ratchet down.
- Never add to `.gitignore`: these files MUST travel with the repo.
- Never skip updating the baseline after remediation — that leaves slack the next contributor will consume.

## Provenance exception — 2026-09-09

The hook baseline was restored from 0 to the last valid value, 5. Commit
`a67571fe` changed discovery from the real `.claude/hooks` directory to the
`.opencode/hooks` symlink without enabling link traversal, then recorded 0 from
an empty measurement. Three repeated five-run measurements after repairing
discovery found the same five registered hot-path violations. This is a
measurement-universe correction, not ratchet slack; future updates remain
decrease-only.
