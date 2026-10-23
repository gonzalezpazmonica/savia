#!/usr/bin/env bash
# run-benchmark.sh — SE-384/387: Savia Self-Evolution Benchmark.
# Modos: --dry (lista) | --execute (ejecución real determinista) | --compare [run_id]
# Sin auto-merge, sin credenciales reales, sin tocar main, sin publicación.
# SE-403: hash de selección, procedencia, trazas crudas por tarea y frontera.
set -uo pipefail
ROOT="${SAVIA_BENCH_ROOT:-$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)}"
DS="${SAVIA_BENCH_DATASET:-$ROOT/tests/self-evolution/dataset}"
RES="${SAVIA_BENCH_RESULTS:-$ROOT/tests/self-evolution/results}"
# Trazas y frontera fuera del repo: pueden contener salidas N3 (CRIT-001).
BENCH_DIR="${SAVIA_BENCH_DIR:-$HOME/.savia/benchmark}"
RUNNER_VERSION=2
mkdir -p "$RES"

if [[ "${1:-}" == "--dry" ]]; then
  for t in "$DS"/*.yaml; do echo "tarea: $(basename "$t")"; done
  exit 0
fi

# Verificaciones mapeadas: "tarea|comando". SAVIA_BENCH_VERIF_FILE las sustituye (tests).
load_verif() {
  if [[ -n "${SAVIA_BENCH_VERIF_FILE:-}" ]]; then
    [[ -f "$SAVIA_BENCH_VERIF_FILE" ]] || { echo "ERROR: verif file not found: $SAVIA_BENCH_VERIF_FILE" >&2; exit 2; }
    grep -v '^[[:space:]]*\(#\|$\)' "$SAVIA_BENCH_VERIF_FILE"
    return
  fi
  cat <<EOF
task-001-hook-fantasma|bash $ROOT/scripts/guardrail-audit.sh
task-002-contadores-divergentes|bash $ROOT/scripts/release-invariants.sh
task-003-worktree-unaware-hook|bash $ROOT/tests/chaos/run-chaos-suite.sh
task-004-se-046|python3 $ROOT/scripts/capability-entropy.py --root $ROOT --check
task-005-se-077|bash $ROOT/scripts/opencode-parity-audit.sh
task-006-se-160|bash $ROOT/scripts/roadmap.sh validate
task-007-se-167|bash $ROOT/scripts/skill-maturity-audit.sh
task-010-se-270|bash $ROOT/scripts/skills-overlap-audit.sh
task-011-se-273|bash $ROOT/scripts/judge-routing-verify.sh
task-014-SE-343|bash $ROOT/scripts/operator-grant.sh list
task-017-SPEC-192|bash $ROOT/scripts/coherence-gates.sh
task-018-se-086|bash $ROOT/scripts/law-check.sh
task-020-se-162|bash $ROOT/scripts/contract-check.sh
EOF
}

# ── --execute: verificación determinista por tarea, aislada, CRIT-001 ──
if [[ "${1:-}" == "--execute" ]]; then
  VERIF_LINES=$(load_verif) || exit 2
  echo "# Benchmark EXEC $(date -u +%FT%TZ)"
  SEL=$(python3 - "$DS" "$VERIF_LINES" <<'PY'
import hashlib, json, pathlib, sys
ds, lines = pathlib.Path(sys.argv[1]), sys.argv[2].splitlines()
rows = []
for line in lines:
    task, _, cmd = line.partition("|")
    y = ds / f"{task}.yaml"
    rows.append([task, hashlib.sha256(y.read_bytes()).hexdigest() if y.is_file() else "", cmd])
for y in sorted(ds.glob("*.yaml")):
    if y.stem not in {r[0] for r in rows}:
        rows.append([y.stem, hashlib.sha256(y.read_bytes()).hexdigest(), ""])
rows.sort()
print(hashlib.sha256(json.dumps(rows, separators=(",", ":")).encode()).hexdigest())
PY
)
  RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(head -c4 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  RUN_DIR="$BENCH_DIR/runs/$RUN_ID"
  mkdir -p "$RUN_DIR"
  COMMIT=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo "")
  DIRTY=false
  # results/ está versionado y cada ejecución lo reescribe: no cuenta como árbol sucio.
  EXCL=()
  [[ "$RES" == "$ROOT"/* ]] && EXCL=(-- . ":(exclude)${RES#"$ROOT"/}")
  [[ -n "$(git -C "$ROOT" status --porcelain "${EXCL[@]}" 2>/dev/null)" ]] && DIRTY=true
  STARTED=$(date -u +%FT%TZ)
  GREEN=0; MAPPED=0
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    T="${row%%|*}"; C="${row#*|}"
    START=$(date +%s%N)
    if (cd "$ROOT" && bash -c "$C") >"$RUN_DIR/$T.stdout" 2>"$RUN_DIR/$T.stderr"; then
      ST="PASS"; RC=0; GREEN=$((GREEN+1))
    else
      RC=$?; ST="CHECK_FAIL"
    fi
    DUR=$(( ($(date +%s%N) - START) / 1000000 ))
    MAPPED=$((MAPPED+1))
    JSON=$(printf '{"task":"%s","status":"%s","exit":%d,"duration_ms":%d,"runner_version":%d,"isolated":true,"auto_merge":false,"real_credentials":false,"selection_hash":"%s","run_id":"%s"}' \
      "$T" "$ST" "$RC" "$DUR" "$RUNNER_VERSION" "$SEL" "$RUN_ID")
    echo "$JSON" > "$RUN_DIR/$T.json"
    echo "$JSON" > "$RES/last-$T.json"
    echo "- $T: $ST (${DUR}ms)"
  done <<< "$VERIF_LINES"
  for t in "$DS"/*.yaml; do
    [[ -f "$t" ]] || continue
    T=$(basename "$t" .yaml)
    [[ -f "$RUN_DIR/$T.json" ]] && continue
    printf '{"task":"%s","status":"NEEDS_AGENT_SESSION","runner_version":%d}\n' "$T" "$RUNNER_VERSION" > "$RES/last-$T.json"
  done
  python3 - "$RES" "$RUN_DIR" "$BENCH_DIR" "$RUN_ID" "$SEL" "$COMMIT" "$DIRTY" "$STARTED" "$RUNNER_VERSION" "${SAVIA_FRONTEND:-unknown}" <<'PY'
import fcntl, glob, json, os, sys, datetime
from collections import Counter
res, run_dir, bench, run_id, sel, commit, dirty, started, rv, frontend = sys.argv[1:11]
# Compatibilidad SE-387: mismo formato de aggregate.json en el repo.
rows = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(res, "last-*.json")))]
json.dump({"aggregate": dict(Counter(r["status"] for r in rows)), "total": len(rows), "tasks": rows},
          open(os.path.join(res, "aggregate.json"), "w"), indent=2)
tasks = [json.load(open(f)) for f in sorted(glob.glob(os.path.join(run_dir, "*.json")))
         if not f.endswith("manifest.json")]
passed = sum(1 for t in tasks if t["status"] == "PASS")
total_ms = sum(t["duration_ms"] for t in tasks)
manifest = {"run_id": run_id, "selection_hash": sel, "harness_commit": commit,
            "dirty": dirty == "true", "runner_version": int(rv), "frontend": frontend,
            "started_at": started,
            "finished_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "pass": passed, "tasks": len(tasks), "duration_ms": total_ms}
json.dump(manifest, open(os.path.join(run_dir, "manifest.json"), "w"), indent=2)
print(f"aggregate: pass={passed}/{len(tasks)} selection={sel[:12]} run={run_id}")
if manifest["dirty"]:
    print("frontier: skipped (dirty tree)")
    sys.exit(0)
os.makedirs(bench, exist_ok=True)
lock = open(os.path.join(bench, "frontier.lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)
path = os.path.join(bench, "frontier.json")
try:
    frontier = json.load(open(path))
except (OSError, json.JSONDecodeError):
    frontier = {}
best = frontier.get(sel)
better = best is None or (passed, -total_ms) > (best["pass"], -best["duration_ms"])
if better:
    frontier[sel] = {"run_id": run_id, "harness_commit": commit, "pass": passed,
                     "tasks": len(tasks), "duration_ms": total_ms}
    tmp = path + ".tmp"
    json.dump(frontier, open(tmp, "w"), indent=2)
    os.replace(tmp, path)
print("frontier: " + ("updated" if better else "unchanged"))
PY
  echo "-- benchmark execute: $GREEN/$MAPPED verificaciones mapeadas verdes; resto NEEDS_AGENT_SESSION"
  echo "-- trazas: $RUN_DIR"
  echo "-- aislado, sin auto-merge, sin credenciales reales, sin tocar main, cero publicación."
  exit 0
fi

# ── --compare: ejecución frente a la frontera de SU selección ──
if [[ "${1:-}" == "--compare" ]]; then
  python3 - "$BENCH_DIR" "${2:-}" <<'PY'
import json, os, sys
bench, run_id = sys.argv[1], sys.argv[2]
runs = os.path.join(bench, "runs")
ids = sorted(os.listdir(runs)) if os.path.isdir(runs) else []
if not ids:
    print("no runs archived yet"); sys.exit(1)
run_id = run_id or ids[-1]
try:
    m = json.load(open(os.path.join(runs, run_id, "manifest.json")))
except OSError:
    print(f"run not found: {run_id}"); sys.exit(1)
try:
    frontier = json.load(open(os.path.join(bench, "frontier.json")))
except (OSError, json.JSONDecodeError):
    frontier = {}
best = frontier.get(m["selection_hash"])
if best is None:
    print(f"INCOMPARABLE: no frontier for selection {m['selection_hash'][:12]} "
          f"(tareas o comandos distintos de toda ejecución limpia previa)")
    sys.exit(0)
if best["run_id"] == run_id:
    print(f"FRONTIER: {run_id} es la mejor ejecución de su selección ({m['pass']}/{m['tasks']})"); sys.exit(0)
d = m["pass"] - best["pass"]
verdict = "BETTER" if d > 0 else "WORSE" if d < 0 else "EQUAL"
print(f"{verdict}: {m['pass']}/{m['tasks']} vs frontera {best['pass']}/{best['tasks']} "
      f"({best['run_id']} @ {best['harness_commit'][:8]})")
PY
  exit $?
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
    printf '{"task":"%s","baseline":"%s","status":"READY","runner_version":%d}\n' "$ID" "$BASE" "$RUNNER_VERSION" > "$RES/last-$ID.json"
    echo "| $ID | ${BASE:0:9} | READY |"
  else
    printf '{"task":"%s","status":"INVALID_TASK","runner_version":%d}\n' "$ID" "$RUNNER_VERSION" > "$RES/last-$ID.json"
    echo "| $ID | ${BASE:-?} | INVALID |"
  fi
done
echo
echo "Ejecución real: bash tests/self-evolution/run-benchmark.sh --execute"
exit 0
