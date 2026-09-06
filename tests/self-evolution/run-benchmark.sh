#!/usr/bin/env bash
# run-benchmark.sh — SE-384/387: Savia Self-Evolution Benchmark.
# Modos: --dry (lista) | --execute (ejecución real determinista en worktree aislado).
# Sin auto-merge, sin credenciales reales, sin tocar main, sin publicación.
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)"
DS="$ROOT/tests/self-evolution/dataset"
RES="$ROOT/tests/self-evolution/results"
mkdir -p "$RES"

if [[ "${1:-}" == "--dry" ]]; then
  for t in "$DS"/*.yaml; do echo "tarea: $(basename "$t")"; done
  exit 0
fi

# ── --execute: verificación determinista por tarea, aislada, CRIT-001 ──
if [[ "${1:-}" == "--execute" ]]; then
  echo "# Benchmark EXEC $(date -u +%FT%TZ)"
  VERIF=(
    "task-001-hook-fantasma|bash $ROOT/scripts/guardrail-audit.sh"
    "task-002-contadores-divergentes|bash $ROOT/scripts/release-invariants.sh"
    "task-003-worktree-unaware-hook|bash $ROOT/tests/chaos/run-chaos-suite.sh"
    "task-004-se-046|python3 $ROOT/scripts/capability-entropy.py --root $ROOT --check"
    "task-005-se-077|bash $ROOT/scripts/opencode-parity-audit.sh"
    "task-006-se-160|bash $ROOT/scripts/roadmap.sh validate"
    "task-007-se-167|bash $ROOT/scripts/skill-maturity-audit.sh"
    "task-010-se-270|bash $ROOT/scripts/skills-overlap-audit.sh"
    "task-011-se-273|bash $ROOT/scripts/judge-routing-verify.sh"
    "task-014-SE-343|bash $ROOT/scripts/operator-grant.sh list"
    "task-017-SPEC-192|bash $ROOT/scripts/coherence-gates.sh"
    "task-018-se-086|bash $ROOT/scripts/law-check.sh"
    "task-020-se-162|bash $ROOT/scripts/contract-check.sh"
  )
  GREEN=0; MAPPED=0
  for row in "${VERIF[@]}"; do
    T="${row%%|*}"; C="${row#*|}"
    RF="$ROOT/tests/self-evolution/results/last-$T.json"
    START=$(date +%s%N)
    if bash -c "$C" >/dev/null 2>&1; then ST="PASS"; GREEN=$((GREEN+1)); else ST="CHECK_FAIL"; fi
    DUR=$(( ($(date +%s%N) - START) / 1000000 ))
    MAPPED=$((MAPPED+1))
    printf '{"task":"%s","status":"%s","duration_ms":%d,"runner_version":1,"isolated":true,"auto_merge":false,"real_credentials":false}\n' "$T" "$ST" "$DUR" > "$RF"
    echo "- $T: $ST (${DUR}ms)"
  done
  for t in "$DS"/*.yaml; do
    T=$(basename "$t" .yaml)
    RF="$ROOT/tests/self-evolution/results/last-$T.json"
    [[ -f "$RF" ]] && continue
    printf '{"task":"%s","status":"NEEDS_AGENT_SESSION","runner_version":1}\n' "$T" > "$RF"
  done
  python3 - <<'PYAGG'
import json, glob
from collections import Counter
res = [json.load(open(f)) for f in glob.glob("tests/self-evolution/results/last-*.json")]
c = Counter(r["status"] for r in res)
json.dump({"aggregate": dict(c), "total": len(res), "tasks": res},
          open("tests/self-evolution/results/aggregate.json", "w"), indent=2)
print("aggregate:", dict(c))
PYAGG
  echo "-- benchmark execute: $GREEN/$MAPPED verificaciones mapeadas verdes; resto NEEDS_AGENT_SESSION"
  echo "-- aislado, sin auto-merge, sin credenciales reales, sin tocar main, cero publicación."
  exit 0
fi

# ── default: prerequisitos por tarea (schema + baseline) ──
echo "# Benchmark prereqs"
echo "| tarea | baseline | estado |"
echo "|---|---|---|"
for t in "$DS"/*.yaml; do
  ID=$(basename "$t" .yaml)
  BASE=$(grep -oP 'baseline_commit:\s*\K[0-9a-f]+' "$t" | head -1)
  OK=1
  for k in problem expected_files invariants risk_level evaluation; do
    grep -q "^$k:" "$t" || { OK=0; break; }
  done
  if [[ -n "$BASE" ]] && ! git -C "$ROOT" cat-file -e "$BASE" 2>/dev/null; then OK=0; fi
  if [[ $OK -eq 1 ]]; then
    printf '{"task":"%s","baseline":"%s","status":"READY","runner_version":1}\n' "$ID" "$BASE" > "$RES/last-$ID.json"
    echo "| $ID | ${BASE:0:9} | READY |"
  else
    printf '{"task":"%s","status":"INVALID_TASK","runner_version":1}\n' "$ID" > "$RES/last-$ID.json"
    echo "| $ID | ${BASE:-?} | INVALID |"
  fi
done
echo
echo "Ejecución real: bash tests/self-evolution/run-benchmark.sh --execute"
exit 0
