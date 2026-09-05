#!/usr/bin/env bash
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
