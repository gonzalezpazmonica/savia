---
name: report-verify
description: Convene the Truth Tribunal (7 judges) to evaluate a report's reliability
argument-hint: "<report-path> [--force]"
allowed-tools: [Read, Write, Bash, Task, Glob, Grep]
model_tier: heavy
context_cost: medium
tier: core
---

# /report-verify — Truth Tribunal verification

Convenes the 7-judge Truth Tribunal (SPEC-106) on a report, aggregates verdicts,
and shows the final reliability verdict. Blocks delivery of reports with verdict
ITERATE or ESCALATE.

## Usage

```
/report-verify output/audits/yyyymmdd-security-alpha.md
/report-verify output/reports/ceo-report.md --force   # bypass cache
```

## Flow

1. **Resolve report**: validate `$1` exists. If not → error with hint.
2. **Cache check** (unless `--force`):
   ```bash
   cached=$(bash scripts/truth-tribunal.sh cache-check "$report")
   ```
   If cached and fresh → show cached verdict, exit.
3. **Detect profile**:
   ```bash
   type=$(bash scripts/truth-tribunal.sh detect-type "$report")
   tier=$(bash scripts/truth-tribunal.sh detect-tier "$report")
   ```
4. **Convene tribunal** via `truth-tribunal-orchestrator` agent (Task):
   - Pass: `report_path`, `report_type`, `destination_tier`
   - Orchestrator forks the 7 judges in parallel and writes per-judge YAML
     to `output/truth-tribunal/{run-id}/`
5. **Aggregate**:
   ```bash
   crc=$(bash scripts/truth-tribunal.sh aggregate "$report" "$judges_dir")
   ```
   Writes `{report}.truth.crc` next to the report.
6. **Cache store**:
   ```bash
   bash scripts/truth-tribunal.sh cache-store "$report" "$crc"
   ```
7. **Show verdict** (banner):

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🏛️  Truth Tribunal — {report_type}/{tier}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Verdict:  {PUBLISHABLE|CONDITIONAL|ITERATE|ESCALATE}
Vetos:    {count}
Judges:   {7 per-judge verdicts}
CRC:      {report}.truth.crc
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Verdicts and exit codes

| Verdict | Threshold | Exit | Action |
|---------|-----------|------|--------|
| PUBLISHABLE | high | 0 | Report can be delivered as-is |
| CONDITIONAL | mid | 0 | Show findings; human decides |
| ITERATE | low or veto | 1 | Block delivery; bounce back to generator |
| ESCALATE | 3rd iteration | 2 | Hand off to human |
| NOT_EVALUABLE | many abstentions | 3 | Lacks context for automated eval |

## Reference

- SPEC-106 — `docs/propuestas/SPEC-106-truth-tribunal-report-reliability.md`
- Rule — `docs/rules/domain/truth-tribunal-weights.md`
- Script — `scripts/truth-tribunal.sh`
- Orchestrator — `.opencode/agents/truth-tribunal-orchestrator.md`
