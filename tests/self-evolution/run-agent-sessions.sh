#!/usr/bin/env bash
<<<<<<< HEAD
# SE-387 — ejecutor serial de agent sessions del benchmark (NEEDS_AGENT_SESSION).
# Una sesión aislada por tarea (worktree propio), gates activos, sin auto-merge,
# sin credenciales, sin publicar. Estados: PASS/FAIL/BLOCKED/NEEDS_HUMAN/INFRA_FAILURE.
set -o pipefail
ROOT="$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)"
RES="$ROOT/tests/self-evolution/results"
TIMEOUT_PER_TASK="${BENCH_TIMEOUT_SECS:-900}"
PASS=0; FAIL=0; BLK=0; HUM=0; INFRA=0
if ! command -v opencode >/dev/null 2>&1; then
  echo "INFRA_FAILURE: opencode CLI ausente — sesiones no ejecutables en este entorno"
  exit 4
fi
for rf in "$RES"/last-*.json; do
  T=$(python3 -c "import json;print(json.load(open('$rf')).get('task','?'))" 2>/dev/null)
  ST=$(python3 -c "import json;print(json.load(open('$rf')).get('status','?'))" 2>/dev/null)
  [[ "$ST" != "NEEDS_AGENT_SESSION" ]] && continue
  YT="$ROOT/tests/self-evolution/dataset/$T.yaml"
  PROMPT="Ejecuta la tarea benchmark $T según $YT en $(pwd). Respeta gates. No hagas commit ni merge."
  echo "== sesión: $T (timeout ${TIMEOUT_PER_TASK}s)"
  ( cd "$ROOT" && timeout "$TIMEOUT_PER_TASK" opencode run "$PROMPT" >/dev/null 2>&1 )
  rc=$?
  case $rc in
    0) S=PASS; P=$((P+1));;
    124) S=INFRA_FAILURE; I=$((I+1));;
    283|282) S=BLOCKED; B=$((B+1));;
    *) S=FAIL; F=$((F+1));;
  esac
  python3 -c "import json;d=json.load(open('$rf'));d['agent_session']='$S';json.dump(d,open('$rf','w'),indent=2)"
  echo "- $T: $S"
done
echo "-- sesiones: PASS=$P FAIL=$F BLOCKED=$B NEEDS_HUMAN=$HUM INFRA=$INFRA"
=======
# SE-387 — agent sessions benchmark v2 (CHANGES_REQUIRED aplicado):
# worktree efímero por tarea desde su baseline, stdout/stderr capturados,
# verificador específico post-sesión, clasificación desde evidencia,
# worktree destruido al final. Estados: PASS/FAIL/BLOCKED/NEEDS_HUMAN/INFRA_FAILURE.
set -o pipefail
ROOT="$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)"
RES="$ROOT/tests/self-evolution/results"
WT_BASE="${SAVIA_BENCH_WT:-/tmp/savia-bench}"
PASS=0; FAIL=0; BLOCKED=0; NEEDS_HUMAN=0; INFRA=0
command -v opencode >/dev/null 2>&1 || { echo "INFRA_FAILURE: opencode CLI ausente"; exit 4; }
mkdir -p "$RES"

run_session() { # task-id, baseline, verifier-cmd
  local id="$1" baseline="$2" verifier="$3"
  local wt="$WT_BASE/$id" start rc
  git -C "$ROOT" worktree add --detach "$wt" "${baseline:-HEAD}" >/dev/null 2>&1 || {
    printf '{"task":"%s","status":"INFRA_FAILURE","reason":"worktree"}' "$id" > "$RES/last-$id.json"
    INFRA=$((INFRA+1)); echo "INFRA_FAILURE $id (worktree)"; return; }
  mkdir -p "$RES/logs"
  start=$(date +%s%N)
  ( cd "$wt" && timeout "${BENCH_TIMEOUT_SECS:-900}" opencode run "Ejecuta la tarea benchmark $id según tests/self-evolution/dataset/$id.yaml del repo. Respeta gates. Sin commit ni merge." \
      > "$RES/logs/$id.out" 2> "$RES/logs/$id.err" )
  rc=$?
  local sess="FAIL"
  [[ $rc -eq 0 ]] && sess="PASS"
  [[ $rc -eq 124 ]] && sess="INFRA_FAILURE"
  # verificador específico post-sesión (evidencia, no sólo exit code)
  local verdict
  if [[ -n "$verifier" ]] && bash -c "cd '$wt' && $verifier" >/dev/null 2>&1; then
    verdict="PASS"
  elif [[ $rc -eq 124 ]]; then
    verdict="INFRA_FAILURE"
  elif [[ -n "$verifier" ]]; then
    verdict="FAIL"
  else
    verdict="NEEDS_HUMAN"
  fi
  local dur=$(( ($(date +%s%N) - start) / 1000000 ))
  printf '{"task":"%s","status":"%s","session_exit":%d,"verifier_verdict":"%s","duration_ms":%d,"isolated_worktree":true,"auto_merge":false,"stdout":"logs/%s.out","stderr":"logs/%s.err"}\n' \
    "$id" "$verdict" "$rc" "$verdict" "$dur" "$id" "$id" > "$RES/last-$id.json"
  echo "- $id: $verdict (session=$sess ${dur}ms)"
  git -C "$ROOT" worktree remove "$wt" --force >/dev/null 2>&1
}

# verificador por tarea (evidencia determinista, CRIT-001 local)
VERIF=(
  "task-001-hook-fantasma|bash scripts/guardrail-audit.sh && test -f output/guardrail-audit/gap-report.md"
  "task-002-contadores-divergentes|bash scripts/release-invariants.sh"
  "task-003-worktree-unaware-hook|bash tests/chaos/run-chaos-suite.sh"
  "task-004-se-046|python3 scripts/capability-entropy.py --check"
  "task-005-se-077|bash scripts/opencode-parity-audit.sh"
  "task-006-se-160|bash scripts/roadmap.sh validate"
  "task-007-se-167|bash scripts/skill-maturity-audit.sh"
  "task-010-se-270|bash scripts/skills-overlap-audit.sh"
  "task-011-se-273|bash scripts/judge-routing-verify.sh"
  "task-014-SE-343|bash scripts/operator-grant.sh list"
  "task-017-SPEC-192|bash scripts/coherence-gates.sh"
  "task-018-se-086|bash scripts/law-check.sh"
  "task-020-se-162|bash scripts/contract-check.sh"
)
for t in "$DS"/*.yaml; do :; done
for id in $(ls "$RES"/last-*.json 2>/dev/null | sed 's/.*last-//;s/\.json//' ); do
  base=""
  case "$id" in
    task-001*) base="5e8abb879c175ac60359a9f0fe3f2d71b61e5598";;
    task-002*) base="2e3a258b";;
    task-003*) base="2d8d8239";;
  esac
  vcmd=""
  for row in "${VERIF[@]}"; do
    [[ "$row" == "$id|"* ]] && vcmd="${row#*|}"
  done
  run_session "$id" "$base" "$vcmd"
done

echo "-- sesiones: PASS=$PASS FAIL=$FAIL BLOCKED=$BLOCKED NEEDS_HUMAN=$NEEDS_HUMAN INFRA=$INFRA"
exit 0
>>>>>>> origin/main
