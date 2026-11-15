#!/usr/bin/env bash
# savia-runs.sh — SE-349: Agent Runs Operations Ledger (ARO)
# Ledger operativo de runs autónomos: hechos durables + estado DERIVADO en lectura.
# Inspirado en Untrivial-ai/agent-orchestrator (derive, don't store status;
# "failed probes are NOT proof of death"). Rechaza su telemetría cloud (CRIT-001).
# Ref: docs/specs/SE-349-agent-runs-ledger.spec.md
#
# Subcommands:
#   init    → asegura ledger existente
#   start   <mode> <agent> <task> [--project P] [--branch B] [--url U]  → imprime run_id
#   state   <run_id> <activity_state>      spawning|active|waiting_input|blocked|exited
#   pr      <run_id> <number> [--state..] [--ci..] [--review..] [--mergeable..] [--url U]
#   pr      <run_id> clear                 → desposee el PR
#   finish  <run_id> [--force]             → guardrail de terminación
#   status  [--json]                       → board derivado
#   list    [--mode M] [--json]            → tabla de runs con estado derivado
#   show    <run_id>                       → hechos + estado derivado + traza de precedencia
#   derive  <run_id> [--receipt F]         → estado de la PR + hecho verificado (SE-530 S2), derivados, sin guardar
#   cost    <run_id> --agent A --model M --tokens-in N --tokens-out N [--usd X]  → SE-405
#   reset                                  → vacía ledger (dev/test)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}}}"
LEDGER="${SAVIA_RUNS_LEDGER:-$WORKSPACE_DIR/data/agent-runs-ledger.jsonl}"

# ── Helpers ──────────────────────────────────────────────────────────────
_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

_gen_id() {
  if command -v uuidgen &>/dev/null; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  else
    printf '%s-%s' "$(date +%s%N)" "$$"
  fi
}

_py3() { command -v python3 &>/dev/null; }

_ensure_ledger() {
  mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || true
  [[ -f "$LEDGER" ]] || touch "$LEDGER"
}

# Read a single record by run_id; echoes JSON line or empty string.
_read_record() {
  local run_id="$1"
  [[ -f "$LEDGER" ]] || return 0
  python3 - "$LEDGER" "$run_id" <<'PY'
import sys, json
ledger, run_id = sys.argv[1], sys.argv[2]
last = None
try:
    with open(ledger, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            if rec.get("run_id") == run_id:
                last = rec
except OSError:
    pass
if last:
    print(json.dumps(last, ensure_ascii=False))
PY
}

# Upsert: rewrite ledger replacing the record for run_id (append-only per run).
_upsert_record() {
  local run_id="$1"
  local new_json="$2"
  local tmp
  tmp="$(mktemp "$LEDGER.tmp.XXXXXX")"
  python3 - "$LEDGER" "$run_id" "$new_json" "$tmp" <<'PY'
import sys, json
ledger, run_id, new_json, tmp = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
replaced = False
with open(ledger, encoding="utf-8", errors="replace") as fh, open(tmp, "w", encoding="utf-8") as out:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except Exception:
            out.write(line + "\n")
            continue
        if rec.get("run_id") == run_id:
            out.write(json.dumps(json.loads(new_json), ensure_ascii=False) + "\n")
            replaced = True
        else:
            out.write(line + "\n")
    if not replaced:
        out.write(json.dumps(json.loads(new_json), ensure_ascii=False) + "\n")
PY
  if [[ $? -ne 0 ]]; then
    rm -f "$tmp"
    echo "ERROR: ledger update failed for run_id '$run_id' (ledger intacto)" >&2
    return 1
  fi
  mv "$tmp" "$LEDGER"
}

# Derive display status from durable facts — ALWAYS at read time, never stored.
# Única definición de las reglas de precedencia: show, status y list la cargan desde
# SAVIA_RUNS_DERIVE_PY (antes había 4 copias y una edición parcial reintroducía bugs).
# derive(r) -> (status, trace)
_DERIVE_PY='
def derive(r):
    if r.get("is_terminated"):
        pr = r.get("pr") or {}
        if pr.get("state") == "merged":
            return "merged", "is_terminated=true and pr.state=merged"
        return "terminated", "is_terminated=true and pr.state!='merged'"
    act = r.get("activity_state", "spawning")
    if act in ("waiting_input", "blocked"):
        return "needs_input", "activity_state=%s in (waiting_input, blocked)" % act
    pr = r.get("pr")
    if pr:
        if pr.get("state") == "merged": return "merged", "pr.state=merged"
        if pr.get("ci") == "failing": return "ci_failed", "pr.ci=failing"
        if pr.get("state") == "draft": return "draft", "pr.state=draft"
        if pr.get("review") == "changes_requested": return "changes_requested", "pr.review=changes_requested"
        if pr.get("mergeable") == "false": return "merge_conflict", "pr.mergeable=false"
        if pr.get("review") == "approved": return "approved", "pr.review=approved"
        if pr.get("review") == "requested": return "review_pending", "pr.review=requested"
        return "pr_open", "pr.state=open (no other signal)"
    if act == "active": return "working", "activity_state=active"
    return "idle", "no pr and activity_state=" + act
'
export SAVIA_RUNS_DERIVE_PY="$_DERIVE_PY"
_RUN_COLUMNS="working needs_input ci_failed changes_requested merge_conflict draft review_pending pr_open approved merged terminated idle"

# Echoes: STATUS<TAB>TRACE
_derive() {
  python3 -c '
import os, sys, json
exec(os.environ["SAVIA_RUNS_DERIVE_PY"])
s, t = derive(json.loads(sys.stdin.read()))
print(s + "\t" + t)
' <<< "$1"
}

# ── Subcommand: init ─────────────────────────────────────────────────────
cmd_init() {
  _ensure_ledger
  echo "ledger=$LEDGER"
}

# ── Subcommand: start ────────────────────────────────────────────────────
cmd_start() {
  local mode="${1:?mode required (overnight|improve|research|agent-task|sdd)}"
  local agent="${2:?agent required}"
  local task="${3:?task description required}"
  shift 3

  local project="" branch="" url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project)  project="${2:-}";  shift 2 ;;
      --branch)   branch="${2:-}";   shift 2 ;;
      --url)      url="${2:-}";      shift 2 ;;
      *) echo "ERROR: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  case "$mode" in
    overnight|improve|research|agent-task|sdd) ;;
    *) echo "ERROR: invalid mode '$mode'. Use: overnight|improve|research|agent-task|sdd" >&2; exit 1 ;;
  esac

  _ensure_ledger
  local run_id now
  run_id="$(_gen_id)"
  now="$(_now)"

  if _py3; then
    local record
    record="$(python3 -c '
import sys, json
mode, agent, task, project, branch, url, run_id, now = sys.argv[1:9]
print(json.dumps({
  "schema_version": "1",
  "run_id": run_id,
  "mode": mode,
  "agent": agent,
  "project": project or None,
  "branch": branch or None,
  "task": task,
  "url": url or None,
  "activity_state": "spawning",
  "is_terminated": False,
  "started_at": now,
  "updated_at": now,
  "ended_at": None,
  "pr": None
}, ensure_ascii=False))' "$mode" "$agent" "$task" "$project" "$branch" "$url" "$run_id" "$now")"
    echo "$record" >> "$LEDGER"
  else
    # Degradado: JSON mínimo sin python3
    echo "{\"schema_version\":\"1\",\"run_id\":\"$run_id\",\"mode\":\"$mode\",\"agent\":\"$agent\",\"project\":null,\"branch\":null,\"task\":\"$task\",\"url\":null,\"activity_state\":\"spawning\",\"is_terminated\":false,\"started_at\":\"$now\",\"updated_at\":\"$now\",\"ended_at\":null,\"pr\":null}" >> "$LEDGER"
  fi

  echo "$run_id"
}

# ── Subcommand: state ────────────────────────────────────────────────────
cmd_state() {
  local run_id="${1:?run_id required}"
  local activity="${2:?activity_state required}"

  case "$activity" in
    spawning|active|waiting_input|blocked|exited) ;;
    *) echo "ERROR: invalid activity_state '$activity'. Use: spawning|active|waiting_input|blocked|exited" >&2; exit 1 ;;
  esac

  if ! _py3; then
    echo "ERROR: python3 required for state update" >&2; exit 1
  fi

  local existing
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 1; }

  local now
  now="$(_now)"
  local updated
  updated="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
r["activity_state"] = sys.argv[1]
r["updated_at"] = sys.argv[2]
print(json.dumps(r, ensure_ascii=False))' "$activity" "$now")"

  _upsert_record "$run_id" "$updated" || { echo "ERROR: ledger update failed" >&2; exit 1; }
  echo "run_id=$run_id activity_state=$activity"
}

# ── Subcommand: pr ───────────────────────────────────────────────────────
cmd_pr() {
  local run_id="${1:?run_id required}"
  local number="${2:-}"

  if ! _py3; then
    echo "ERROR: python3 required for pr update" >&2; exit 1
  fi

  local existing
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 1; }

  # pr <run_id> clear → desposee el PR
  if [[ "$number" == "clear" ]]; then
    local now
    now="$(_now)"
    local updated
    updated="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
r["pr"] = None
r["updated_at"] = sys.argv[1]
print(json.dumps(r, ensure_ascii=False))' "$now")"
    _upsert_record "$run_id" "$updated" || { echo "ERROR: ledger update failed" >&2; exit 1; }
    echo "run_id=$run_id pr=cleared"
    return 0
  fi

  [[ "$number" =~ ^[0-9]+$ ]] || { echo "ERROR: pr number must be an integer" >&2; exit 1; }

  local state="open" ci="unknown" review="none" mergeable="unknown" url=""
  while [[ $# -gt 2 ]]; do
    case "$3" in
      --state)     state="${4:-}";     shift 2 ;;
      --ci)        ci="${4:-}";        shift 2 ;;
      --review)    review="${4:-}";    shift 2 ;;
      --mergeable) mergeable="${4:-}"; shift 2 ;;
      --url)       url="${4:-}";       shift 2 ;;
      *) echo "ERROR: unknown flag '$3'" >&2; exit 1 ;;
    esac
  done

  case "$state" in
    open|draft|merged|closed) ;;
    *) echo "ERROR: invalid pr state '$state'. Use: open|draft|merged|closed" >&2; exit 1 ;;
  esac
  case "$ci" in
    unknown|pending|passing|failing) ;;
    *) echo "ERROR: invalid ci '$ci'. Use: unknown|pending|passing|failing" >&2; exit 1 ;;
  esac
  case "$review" in
    none|requested|changes_requested|approved) ;;
    *) echo "ERROR: invalid review '$review'. Use: none|requested|changes_requested|approved" >&2; exit 1 ;;
  esac
  case "$mergeable" in
    unknown|true|false) ;;
    *) echo "ERROR: invalid mergeable '$mergeable'. Use: unknown|true|false" >&2; exit 1 ;;
  esac

  local now
  now="$(_now)"
  local updated
  updated="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
r["pr"] = {
  "number": int(sys.argv[1]),
  "state": sys.argv[2],
  "ci": sys.argv[3],
  "review": sys.argv[4],
  "mergeable": sys.argv[5],
  "url": sys.argv[6] or None
}
r["updated_at"] = sys.argv[7]
print(json.dumps(r, ensure_ascii=False))' "$number" "$state" "$ci" "$review" "$mergeable" "$url" "$now")"

  _upsert_record "$run_id" "$updated" || { echo "ERROR: ledger update failed" >&2; exit 1; }
  echo "run_id=$run_id pr=#$number state=$state ci=$ci review=$review mergeable=$mergeable"
}

# ── Subcommand: finish (guardrail) ───────────────────────────────────────
cmd_finish() {
  local run_id="${1:?run_id required}"
  local force=""
  shift || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force="1"; shift ;;
      *) echo "ERROR: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  if ! _py3; then
    echo "ERROR: python3 required for finish" >&2; exit 1
  fi

  local existing
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 1; }

  # Idempotente: ya terminado → no-op con éxito
  if echo "$existing" | python3 -c 'import sys,json; sys.exit(0 if json.load(sys.stdin).get("is_terminated") else 1)'; then
    echo "run_id=$run_id already terminated"
    return 0
  fi

  # Guardrail AO #2: failed probes are NOT proof of death.
  # Un run que posee un PR vivo (open/draft, no merged) NO es terminable.
  if [[ -z "$force" ]]; then
    local pr_line
    pr_line="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
pr = r.get("pr")
if not pr:
    sys.exit(0)
if pr.get("state") in ("open", "draft"):
    print("%s\t%s\t%s\t%s" % (pr.get("number"), pr.get("state"), pr.get("ci"), pr.get("review")))
    sys.exit(1)
sys.exit(0)')"
    if [[ $? -eq 1 ]]; then
      local num st ci rv
      num="${pr_line%%$'\t'*}"
      st="$(echo "$pr_line" | cut -f2)"
      ci="$(echo "$pr_line" | cut -f3)"
      rv="$(echo "$pr_line" | cut -f4)"
      echo "BLOCKED: run $run_id owns PR #$num (state=$st, ci=$ci, review=$rv) — still live." >&2
      echo "Termination would orphan its PR. AO guardrail: failed probes are not proof of death; an owned PR keeps the run alive." >&2
      echo "Finish it with --force only after the PR is merged/closed, or run 'savia-runs.sh pr $run_id clear' to disown it." >&2
      exit 1
    fi
  fi

  local now
  now="$(_now)"
  local updated
  updated="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
r["is_terminated"] = True
r["ended_at"] = sys.argv[1]
r["updated_at"] = sys.argv[1]
print(json.dumps(r, ensure_ascii=False))' "$now")"

  _upsert_record "$run_id" "$updated" || { echo "ERROR: ledger update failed" >&2; exit 1; }
  echo "run_id=$run_id terminated"
}

# ── Subcommand: status (board derivado) ──────────────────────────────────
cmd_status() {
  local json_mode=""
  [[ "${1:-}" == "--json" ]] && json_mode="1"
  if [[ ! -f "$LEDGER" ]]; then
    if [[ -n "$json_mode" ]]; then
      local c cols="" sep=""
      for c in $_RUN_COLUMNS; do cols+="$sep\"$c\": []"; sep=", "; done
      printf '{"as_of": "%s", "columns": {%s}, "runs": []}\n' "$(_now)" "$cols"
    else
      echo "ledger=$LEDGER (empty)"
    fi
    return 0
  fi

  if ! _py3; then
    echo "ERROR: python3 required for status" >&2; exit 1
  fi

  if [[ -n "$json_mode" ]]; then
    python3 - "$LEDGER" "$_RUN_COLUMNS" <<'PY'
import os, sys, json, datetime

exec(os.environ["SAVIA_RUNS_DERIVE_PY"])

cols = sys.argv[2].split()
runs = []
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        r["derived_status"] = derive(r)[0]
        runs.append(r)

out = {"as_of": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
       "columns": {c: [x["run_id"] for x in runs if x["derived_status"] == c] for c in cols},
       "runs": sorted(runs, key=lambda x: x.get("started_at", ""))}
print(json.dumps(out, ensure_ascii=False))
PY
    return 0
  fi

  python3 - "$LEDGER" <<'PY'
import os, sys, json, datetime

COLUMN_ORDER = [
    ("WORKING",         "working"),
    ("NEEDS YOU",       "needs_input"),
    ("NEEDS YOU",       "ci_failed"),
    ("NEEDS YOU",       "changes_requested"),
    ("NEEDS YOU",       "merge_conflict"),
    ("IN REVIEW",       "draft"),
    ("IN REVIEW",       "review_pending"),
    ("IN REVIEW",       "pr_open"),
    ("READY TO MERGE",  "approved"),
    ("DONE",            "merged"),
    ("TERMINATED",      "terminated"),
]

exec(os.environ["SAVIA_RUNS_DERIVE_PY"])

def short_task(t, n=26):
    t = t or ""
    return t if len(t) <= n else t[:n-1] + "…"

def card(r):
    parts = [r.get("run_id", "?")]
    mode = r.get("mode") or ""
    agent = r.get("agent") or ""
    parts.append("%s@%s" % (mode, agent))
    if r.get("branch"): parts.append(r["branch"])
    parts.append(short_task(r.get("task")))
    return " · ".join(parts)

runs = []
with open(sys.argv[1], encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        r["derived_status"] = derive(r)[0]
        runs.append(r)
runs.sort(key=lambda x: x.get("started_at", ""))

columns = {}
for label, st in COLUMN_ORDER:
    columns.setdefault(label, [])
    columns[label] += [r for r in runs if r["derived_status"] == st]
idle = [r for r in runs if r["derived_status"] == "idle"]

header = ["WORKING", "NEEDS YOU", "IN REVIEW", "READY TO MERGE", "DONE", "TERMINATED"]
widths = {h: max(len(h), 4) for h in header}
as_of = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

print("=== Agent Runs Board (derived) — as of %s ===" % as_of)
print("ledger: %s" % sys.argv[1])
print("")
for h in header:
    print("%-*s| " % (widths[h], "%s (%d)" % (h, len(columns.get(h, [])))), end="")
print()
print("-" * (sum(widths[h] + 2 for h in header)))
nrows = max((len(columns.get(h, [])) for h in header), default=0)
for i in range(nrows):
    for h in header:
        c = columns.get(h, [])
        cell = card(c[i]) if i < len(c) else ""
        print("%-*s| " % (widths[h], cell[:widths[h]]), end="")
    print()
if not runs:
    print("(no runs)")
if idle:
    print("")
    print("idle (sin actividad): %d" % len(idle))
    for r in idle:
        print("  " + card(r))
PY
}

# ── Subcommand: list ─────────────────────────────────────────────────────
cmd_list() {
  local mode_filter="" json_mode=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode) mode_filter="${2:-}"; shift 2 ;;
      --json) json_mode="1"; shift ;;
      *) echo "ERROR: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done

  [[ -f "$LEDGER" ]] || { echo "(no ledger)"; return 0; }
  if ! _py3; then
    echo "ERROR: python3 required for list" >&2; exit 1
  fi

  python3 - "$LEDGER" "$mode_filter" "$json_mode" <<'PY'
import os, sys, json

exec(os.environ["SAVIA_RUNS_DERIVE_PY"])

ledger, mode_filter, json_mode = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
with open(ledger, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.strip()
        if not line: continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        if mode_filter and r.get("mode") != mode_filter:
            continue
        r["derived_status"] = derive(r)[0]
        rows.append(r)
rows.sort(key=lambda x: x.get("started_at", ""))

if json_mode:
    print(json.dumps(rows, ensure_ascii=False))
    sys.exit(0)

if not rows:
    print("(no runs)%s" % (" for mode=" + mode_filter if mode_filter else ""))
    sys.exit(0)

print("%-38s %-10s %-18s %-12s %-28s %s" % ("RUN_ID", "MODE", "AGENT", "STATUS", "BRANCH", "STARTED"))
for r in rows:
    rid = r.get("run_id", "?")
    print("%-38s %-10s %-18s %-12s %-28s %s" % (
        rid[:38], (r.get("mode") or "")[:10], (r.get("agent") or "")[:18],
        r["derived_status"], (r.get("branch") or "")[:28], (r.get("started_at") or "")[:19]))
PY
}

# ── Subcommand: show ─────────────────────────────────────────────────────
cmd_show() {
  local run_id="${1:?run_id required}"
  [[ -f "$LEDGER" ]] || { echo "ERROR: no ledger at $LEDGER" >&2; exit 1; }
  if ! _py3; then
    echo "ERROR: python3 required for show" >&2; exit 1
  fi

  local existing
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 1; }

  local derived trace
  derived="$(_derive "$existing")"
  trace="${derived#*$'\t'}"
  derived="${derived%%$'\t'*}"

  echo "run_id      : $run_id"
  echo "mode        : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("mode") or "")')"
  echo "agent       : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("agent") or "")')"
  echo "project     : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("project") or "")')"
  echo "branch      : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("branch") or "")')"
  echo "task        : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("task") or "")')"
  echo "started_at  : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("started_at") or "")')"
  echo "ended_at    : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("ended_at") or "")')"
  echo "activity    : $(echo "$existing" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("activity_state") or "")')"
  echo "terminated  : $(echo "$existing" | python3 -c 'import sys,json;print("true" if json.load(sys.stdin).get("is_terminated") else "false")')"
  echo "pr          : $(echo "$existing" | python3 -c '
import sys, json
pr = json.load(sys.stdin).get("pr")
if not pr: print("(none)")
else: print("#%(number)s state=%(state)s ci=%(ci)s review=%(review)s mergeable=%(mergeable)s" % pr)')"
  echo "cost        : $(echo "$existing" | python3 -c '
import sys, json
c = json.load(sys.stdin).get("cost")
if not c: print("(none)")
else:
    line = "in=%d out=%d" % (c["tokens_in"], c["tokens_out"])
    if c.get("usd"): line += " usd=%g" % c["usd"]
    for name, a in sorted(c.get("agents", {}).items()):
        line += "\n  %s: in=%d out=%d calls=%d" % (name, a["tokens_in"], a["tokens_out"], a["calls"])
        if a.get("usd"): line += " usd=%g" % a["usd"]
    print(line)')"
  echo ""
  echo "derived_status : $derived"
  echo "trace          : $trace"
}

# ── Subcommand: derive (SE-530 S2) ───────────────────────────────────────
# Expone junto al estado de la PR el estado de «hecho verificado» del recibo del
# trabajador. Ambos se derivan en lectura; nada se escribe en el ledger. Sin recibo,
# recibo ilegible o que no valida: «declarado» (fallo cerrado), nunca «verificado».
cmd_derive() {
  local run_id="${1:?run_id required}"; shift
  local receipt=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --receipt) receipt="${2:-}"; shift 2 ;;
      *) echo "ERROR: unknown flag '$1'" >&2; exit 1 ;;
    esac
  done
  [[ -f "$LEDGER" ]] || { echo "ERROR: no ledger at $LEDGER" >&2; exit 1; }
  _py3 || { echo "ERROR: python3 required for derive" >&2; exit 1; }
  local existing derived pr_status
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 1; }
  derived="$(_derive "$existing")"
  pr_status="${derived%%$'\t'*}"
  local hv hv_out
  if [[ -z "$receipt" ]]; then
    hv_out="declarado: sin recibo"
  elif [[ ! -f "$receipt" ]]; then
    hv_out="declarado: recibo no encontrado"
  else
    hv_out="$(python3 "$SCRIPT_DIR/hecho-verificado.py" receipt "$receipt" 2>/dev/null)" || true
    [[ -z "$hv_out" ]] && hv_out="declarado: no se pudo derivar el estado del recibo"
  fi
  hv="${hv_out%%:*}"
  case "$hv" in verificado|declarado|refutado) ;; *) hv_out="declarado: salida inesperada del derivador"; hv="declarado" ;; esac
  echo "run_id           : $run_id"
  echo "derived_status   : $pr_status"
  echo "hecho_verificado : $hv"
  echo "hv_motivo        : ${hv_out#*: }"
}

# ── Subcommand: cost (SE-405 Slice 1) ────────────────────────────────────
# Adds tokens (and optional USD) consumed by one agent to a run's `cost` fact.
cmd_cost() {
  local run_id="${1:-}"; shift || true
  local agent="" model="" tin="" tout="" usd=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --agent) agent="${2:-}"; shift 2 ;;
      --model) model="${2:-}"; shift 2 ;;
      --tokens-in) tin="${2:-}"; shift 2 ;;
      --tokens-out) tout="${2:-}"; shift 2 ;;
      --usd) usd="${2:-}"; shift 2 ;;
      *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
    esac
  done
  [[ -z "$run_id" || -z "$agent" ]] && { echo "ERROR: cost <run_id> --agent A --model M --tokens-in N --tokens-out N [--usd X]" >&2; exit 2; }
  [[ "$tin" =~ ^[0-9]+$ && "$tout" =~ ^[0-9]+$ ]] || { echo "ERROR: --tokens-in/--tokens-out must be integers >= 0" >&2; exit 2; }
  [[ -z "$usd" || "$usd" =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "ERROR: --usd must be a number >= 0" >&2; exit 2; }
  _py3 || { echo "ERROR: python3 required for cost" >&2; exit 1; }
  local existing
  existing="$(_read_record "$run_id")"
  [[ -z "$existing" ]] && { echo "ERROR: run_id '$run_id' not found in $LEDGER" >&2; exit 2; }
  local updated
  updated="$(echo "$existing" | python3 -c '
import sys, json
r = json.loads(sys.stdin.read())
agent, model, tin, tout, usd, now = sys.argv[1:7]
c = r.get("cost") or {"tokens_in": 0, "tokens_out": 0, "usd": 0.0, "agents": {}}
a = c["agents"].setdefault(agent, {"tokens_in": 0, "tokens_out": 0, "usd": 0.0, "calls": 0, "models": []})
a["tokens_in"] += int(tin); a["tokens_out"] += int(tout); a["calls"] += 1
if usd: a["usd"] = round(a["usd"] + float(usd), 6); c["usd"] = round(c["usd"] + float(usd), 6)
if model and model not in a["models"]: a["models"].append(model)
c["tokens_in"] += int(tin); c["tokens_out"] += int(tout)
r["cost"] = c; r["updated_at"] = now
print(json.dumps(r, ensure_ascii=False))' "$agent" "$model" "$tin" "$tout" "$usd" "$(_now)")"
  _upsert_record "$run_id" "$updated" || { echo "ERROR: ledger update failed" >&2; exit 1; }
  echo "run_id=$run_id cost+ agent=$agent in=$tin out=$tout"
}

# ── Subcommand: capture-cost (SE-405 Slice 1, hook SubagentStop) ─────────
# Reads the SubagentStop payload on stdin; if SAVIA_RUN_ID is set, sums the
# subagent transcript usage and records it with cmd_cost. Never fails.
cmd_capture_cost() {
  [[ -z "${SAVIA_RUN_ID:-}" ]] && return 0
  local payload summary agent model tin tout
  payload=$(cat 2>/dev/null) || return 0
  summary=$(python3 - "$payload" <<'PY' 2>/dev/null
import json, sys
try:
    p = json.loads(sys.argv[1] or "{}")
except json.JSONDecodeError:
    sys.exit(0)
path = p.get("agent_transcript_path") or p.get("transcript_path")
if not path:
    sys.exit(0)
tin = tout = 0
model = ""
try:
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                m = json.loads(line).get("message") or {}
            except json.JSONDecodeError:
                continue
            u = m.get("usage") or {}
            tin += int(u.get("input_tokens", 0) or 0)
            tout += int(u.get("output_tokens", 0) or 0)
            model = m.get("model") or model
except OSError:
    sys.exit(0)
agent = p.get("agent_type") or p.get("agent_id") or "subagent"
print(f"{agent}\t{model or 'unknown'}\t{tin}\t{tout}")
PY
) || return 0
  [[ -z "$summary" ]] && return 0
  IFS=$'\t' read -r agent model tin tout <<<"$summary"
  # Cerrojo con espera corta y después del parseo del transcript: un hook no bloquea al agente.
  if ! _acquire_lock "${SAVIA_RUNS_HOOK_LOCK_WAIT:-5}"; then
    echo "WARN: capture-cost sin cerrojo del ledger; coste de '$agent' no registrado (run $SAVIA_RUN_ID)" >&2
    return 0
  fi
  # Subshell: cmd_cost exits on invalid input; the hook must never fail.
  ( cmd_cost "$SAVIA_RUN_ID" --agent "$agent" --model "$model" \
    --tokens-in "$tin" --tokens-out "$tout" ) >/dev/null 2>&1 || true
  return 0
}

# ── Subcommand: reset ────────────────────────────────────────────────────
cmd_reset() {
  : > "$LEDGER"
  echo "ledger=$LEDGER reset"
}

# ── Dispatcher ───────────────────────────────────────────────────────────
SUBCOMMAND="${1:-}"
shift || true

# Cerrojo exclusivo para todo subcomando que escribe: leer-modificar-reescribir el ledger sin él
# pierde actualizaciones cuando varios runs autónomos escriben a la vez (SE-376).
# _acquire_lock <segundos> → 0 si lo obtiene, 1 si vence la espera (no sale del proceso).
# Implementación: flock sobre <ledger>.lock; sin flock (macOS) o con SAVIA_RUNS_LOCK_IMPL=mkdir,
# un directorio <ledger>.lockdir con el PID del dueño. Un lockdir huérfano (PID muerto, o sin PID
# y con más de LOCKDIR_STALE_MIN minutos) se rompe: un SIGKILL no deja el ledger bloqueado.
LOCKDIR_STALE_MIN=2
_lockdir_is_stale() {
  local dir="$1" pid=""
  [[ -d "$dir" ]] || return 1
  pid="$(cat "$dir/pid" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill -0 "$pid" 2>/dev/null && return 1
    return 0
  fi
  [[ -n "$(find "$dir" -maxdepth 0 -mmin +"$LOCKDIR_STALE_MIN" 2>/dev/null)" ]]
}
_remove_lockdir() {
  rm -f "$1/pid" 2>/dev/null
  rmdir "$1" 2>/dev/null || true
}
_acquire_lock() {
  local wait_s="$1"
  _ensure_ledger
  if [[ "${SAVIA_RUNS_LOCK_IMPL:-}" != "mkdir" ]] && command -v flock &>/dev/null; then
    exec 9>"$LEDGER.lock"
    flock -w "$wait_s" 9 && return 0
    echo "ERROR: ledger lock timeout tras ${wait_s}s ($LEDGER.lock)" >&2
    return 1
  fi
  local dir="$LEDGER.lockdir" deadline=$(( SECONDS + ${wait_s%.*} + 1 ))
  while :; do
    if mkdir "$dir" 2>/dev/null; then
      echo "$$" > "$dir/pid"
      trap '_remove_lockdir "$LEDGER.lockdir"' EXIT
      return 0
    fi
    if _lockdir_is_stale "$dir"; then
      # Rename atómico: solo un proceso se queda con el huérfano; el resto reintenta mkdir.
      local graveyard="$dir.stale.$$"
      if mv "$dir" "$graveyard" 2>/dev/null; then
        echo "WARN: cerrojo huérfano roto ($dir, dueño $(cat "$graveyard/pid" 2>/dev/null || echo '?'))" >&2
        _remove_lockdir "$graveyard"
      fi
      continue
    fi
    (( SECONDS >= deadline )) && break
    sleep 0.1
  done
  echo "ERROR: ledger lock timeout tras ${wait_s}s ($dir, dueño PID $(cat "$dir/pid" 2>/dev/null || echo '?')). Si ese proceso ya no existe, borra el directorio $dir" >&2
  return 1
}
_lock_ledger() {
  _acquire_lock "${SAVIA_RUNS_LOCK_WAIT:-30}" || exit 1
}
# capture-cost NO va aquí: es un hook (timeout 15 s) y toma el cerrojo él mismo, solo si hay run.
case "$SUBCOMMAND" in
  init|start|state|pr|finish|cost|reset) _lock_ledger ;;
esac

case "$SUBCOMMAND" in
  init)   cmd_init   "$@" ;;
  start)  cmd_start  "$@" ;;
  state)  cmd_state  "$@" ;;
  pr)     cmd_pr     "$@" ;;
  finish) cmd_finish "$@" ;;
  status) cmd_status "$@" ;;
  list)   cmd_list   "$@" ;;
  show)   cmd_show   "$@" ;;
  derive) cmd_derive "$@" ;;
  cost)   cmd_cost   "$@" ;;
  capture-cost) cmd_capture_cost; exit 0 ;;
  reset)  cmd_reset  "$@" ;;
  *)
    echo "Usage: savia-runs.sh <init|start|state|pr|cost|capture-cost|finish|status|list|show|derive|reset> [args...]" >&2
    echo "" >&2
    echo "  init" >&2
    echo "  start   <mode> <agent> <task> [--project P] [--branch B] [--url U]   → imprime run_id" >&2
    echo "  state   <run_id> <spawning|active|waiting_input|blocked|exited>" >&2
    echo "  pr      <run_id> <number> [--state open|draft|merged|closed] [--ci passing|failing|pending|unknown]" >&2
    echo "          [--review none|requested|changes_requested|approved] [--mergeable true|false|unknown] [--url U]" >&2
    echo "  pr      <run_id> clear" >&2
    echo "  finish  <run_id> [--force]" >&2
    echo "  status  [--json]" >&2
    echo "  list    [--mode M] [--json]" >&2
    echo "  show    <run_id>" >&2
    echo "  derive  <run_id> [--receipt F]" >&2
    echo "  reset" >&2
    exit 1 ;;
esac
