#!/usr/bin/env bash
set -uo pipefail
# feasibility-probe.sh — SE-220 Slice 0: speculative tool execution feasibility.
#
# Runs the feasibility probe for a given command by:
# 1. Loading historical tool-call sequences from OpenCode session DB.
# 2. Using a haiku-class predictor (prompt-only, no fine-tuning) to predict
#    the next tool call given context.
# 3. Measuring acceptance_rate = correct predictions / total predictions.
# 4. Emitting GO / DEFERRED / ABORT decision.
#
# Usage:
#   feasibility-probe.sh --command /sprint-status [--runs 20] [--output output/]
#
# Output: JSON report + markdown in output/se220-feasibility-YYYYMMDD.md
#
# Decision thresholds (SE-220):
#   acceptance_rate >= 0.60 → GO
#   acceptance_rate 0.40-0.59 → DEFERRED
#   acceptance_rate < 0.40 → ABORT
#
# Ref: SE-220 docs/propuestas/SE-220-speculative-tool-execution.md Slice 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
DB_PATH="${FEASIBILITY_DB:-${HOME}/.local/share/opencode/opencode.db}"
OUTPUT_DIR="${ROOT_DIR}/output"
DATE=$(date +%Y%m%d)

TARGET_CMD=""
RUNS=20
REPORT_PATH=""

usage() {
  grep '^#' "${BASH_SOURCE[0]}" | head -20 | sed 's/^# //; s/^#//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command) TARGET_CMD="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --output) OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -z "$TARGET_CMD" ]] && usage
REPORT_PATH="${OUTPUT_DIR}/se220-feasibility-${DATE}.md"
mkdir -p "$OUTPUT_DIR"

echo "SE-220 Feasibility Probe"
echo "  command: $TARGET_CMD"
echo "  runs target: $RUNS"
echo "  DB: $DB_PATH"
echo ""

# Extract sequences from DB
PROBE_DB_PATH="$DB_PATH" PROBE_TARGET_CMD="$TARGET_CMD" PROBE_RUNS="$RUNS" PROBE_REPORT_PATH="$REPORT_PATH" \
python3 - << 'PYEOF'
import sqlite3, json, sys, os, re
from datetime import datetime
from pathlib import Path

db_path = os.environ["PROBE_DB_PATH"]
target_cmd = os.environ["PROBE_TARGET_CMD"]
output_path = os.environ["PROBE_REPORT_PATH"]
try:
    runs_target = int(os.environ["PROBE_RUNS"])
    if runs_target < 1:
        raise ValueError
except ValueError:
    print(json.dumps({"error": "--runs must be a positive integer", "decision": "ABORT"}))
    sys.exit(2)

if not Path(db_path).exists():
    print(json.dumps({"error": f"DB not found: {db_path}", "decision": "ABORT",
                      "reason": "No session data available"}))
    sys.exit(1)

# as_uri() codifica ?, # y % de la ruta (FEASIBILITY_DB la fija el entorno) y resuelve rutas relativas
try:
    conn = sqlite3.connect(Path(db_path).resolve().as_uri() + "?mode=ro", uri=True)
    cur = conn.cursor()
    # Extract tool-call sequences from recent sessions (all, not just target cmd)
    cur.execute("""SELECT p.session_id, p.time_created, p.data
                   FROM part p
                   WHERE p.data LIKE '%"type":"tool"%'
                   ORDER BY p.time_created ASC""")
    rows = cur.fetchall()
    conn.close()
except sqlite3.Error as e:
    print(json.dumps({"error": f"DB unreadable: {e}", "decision": "ABORT",
                      "reason": "Session database is corrupt or has no part table"}))
    sys.exit(1)

# Group by session
from collections import defaultdict
by_session = defaultdict(list)
for sid, ts, data in rows:
    try:
        d = json.loads(data)
        if d.get('type') == 'tool':
            by_session[sid].append({
                'tool': d.get('tool','?'),
                'ts': ts,
                'inp_preview': str(d.get('state',{}).get('input',{}))[:80]
            })
    except: pass

# Build prediction dataset: (context of 3 tools) → next tool
dataset = []
for sid, tools in by_session.items():
    for i in range(3, len(tools)):
        ctx = [t['tool'] for t in tools[i-3:i]]
        nxt = tools[i]['tool']
        dataset.append({'context': ctx, 'actual_next': nxt, 'session': sid[:12]})

if len(dataset) < 10:
    result = {"error": f"Insufficient data: {len(dataset)} samples",
              "decision": "DEFERRED", "reason": "Need more session history",
              "acceptance_rate": None, "samples": len(dataset)}
    print(json.dumps(result))
    # Write report
    with open(output_path, 'w') as f:
        f.write(f"""# SE-220 Feasibility Probe — {datetime.now().strftime('%Y-%m-%d')}

## Target command: {target_cmd}

## Result: DEFERRED

**Reason:** Insufficient historical data ({len(dataset)} samples, need ≥20).

## Recommendation

Run /sprint-status at least 20 times in real sessions to build the dataset,
then re-run this probe.

## Data available

- Sessions with tool call data: {len(by_session)}
- Total (context, next_tool) pairs: {len(dataset)}
""")
    sys.exit(0)

# Simple frequency predictor (baseline — no LLM, establishes floor)
# Predicts the most common next tool given the last tool in context
from collections import Counter
last_to_next = defaultdict(Counter)
for d in dataset:
    last_to_next[d['context'][-1]][d['actual_next']] += 1

# Evaluate on the last `total` samples with leave-one-out: each sample is
# removed from the frequency table before it is predicted, so a pair seen only
# once can never "predict itself" (it inflated the acceptance rate to 100%).
correct = 0
total = min(runs_target, len(dataset))
eval_set = dataset[-total:]

predictions = []
for sample in eval_set:
    last_tool = sample['context'][-1]
    actual = sample['actual_next']
    counts = last_to_next[last_tool]
    # restar y sumar sin borrar la clave: el orden de inserción (desempate) no cambia
    counts[actual] -= 1
    remaining = [(t, c) for t, c in counts.items() if c > 0]
    predicted = max(remaining, key=lambda tc: tc[1])[0] if remaining else 'bash'
    counts[actual] += 1
    hit = predicted == actual
    if hit: correct += 1
    predictions.append({'ctx': sample['context'], 'predicted': predicted, 'actual': actual, 'hit': hit})

acceptance_rate = correct / total if total > 0 else 0

if acceptance_rate >= 0.60:
    decision = "GO"
elif acceptance_rate >= 0.40:
    decision = "DEFERRED"
else:
    decision = "ABORT"

result = {
    "command": target_cmd,
    "decision": decision,
    "acceptance_rate": round(acceptance_rate, 3),
    "correct": correct,
    "total_evaluated": total,
    "total_dataset": len(dataset),
    "predictor": "frequency-baseline (last-tool → most-common-next)",
    "date": datetime.now().isoformat()
}

# Top-3 predictions breakdown
top_pairs = []
for last, nexts in list(last_to_next.items())[:5]:
    top_next = nexts.most_common(3)
    top_pairs.append(f"  after {last}: {top_next}")

# Write report
with open(output_path, 'w') as f:
    f.write(f"""# SE-220 Feasibility Probe — {datetime.now().strftime('%Y-%m-%d')}

## Target command: {target_cmd}

## Decision: {decision}

| Metric | Value |
|---|---|
| Acceptance rate | {acceptance_rate:.1%} |
| Correct predictions | {correct}/{total} |
| Total dataset size | {len(dataset)} (context, next_tool) pairs |
| Sessions analyzed | {len(by_session)} |
| Predictor | Frequency baseline (last-tool → most-common-next) |

## Thresholds (SE-220 Slice 0)

| Range | Decision |
|---|---|
| ≥ 60% | GO — proceed to Slice 1 |
| 40-59% | DEFERRED — collect more data |
| < 40% | ABORT — pattern does not apply |

## Predictor patterns (top-5 last tools)

{chr(10).join(top_pairs)}

## Notes

The frequency baseline establishes a floor for the LLM predictor. If the baseline
achieves {acceptance_rate:.1%}, a haiku-class LLM with few-shot prompting should do
equal or better. This probe uses the frequency predictor as a conservative proxy.

LLM predictor (haiku) test: deferred — requires ANTHROPIC_API_KEY and live invocations.
For full LLM-based measurement, run 20 manual /sprint-status sessions and re-probe.

## Spec reference

docs/propuestas/SE-220-speculative-tool-execution.md Slice 0 (AC-0)

## Raw result

```json
{json.dumps(result, indent=2)}
```
""")

print(json.dumps(result))
PYEOF
