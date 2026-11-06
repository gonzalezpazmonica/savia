#!/usr/bin/env bash
# capex-phase-gate.sh — SE-272 S1 Phase gate recorder
# Records phase transitions as dated+signed events in engagement ledger.
# Ensures work before capitalizable phase is excluded from capitalization.
#
# Usage:
#   capex-phase-gate.sh record
#     --asset-id ID --asset-name NAME
#     --from-phase PHASE --to-phase PHASE
#     --engagement CLIENT/ENGAGEMENT
#     [--actor NAME] [--evidence-dir DIR]
#   capex-phase-gate.sh history
#     --asset-id ID --engagement CLIENT/ENGAGEMENT
#   capex-phase-gate.sh check
#     --asset-id ID --engagement CLIENT/ENGAGEMENT
#     --date DATE
#
# Gate rules from rules/capitalization.rules.yaml:
#   investigation, design_planning → NOT capitalizable
#   development, deployment → capitalizable

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
RULES_FILE="${REPO_ROOT}/rules/capitalization.rules.yaml"

usage() {
  cat <<'USAGE'
capex-phase-gate.sh — SE-272 S1 Phase gate recorder

Usage:
  capex-phase-gate.sh record
    --asset-id ID --asset-name NAME
    --from-phase PHASE --to-phase PHASE
    --engagement CLIENT/ENGAGEMENT
    [--actor NAME] [--evidence-dir DIR]

  capex-phase-gate.sh history
    --asset-id ID --engagement CLIENT/ENGAGEMENT

  capex-phase-gate.sh check
    --asset-id ID --engagement CLIENT/ENGAGEMENT
    --date DATE

Records phase transitions as dated+signed events.
Ignores work before capitalizable phase per IAS 38.
USAGE
  exit 0
}

die() { echo "ERROR: $*" >&2; exit 1; }

sha256_str() {
  printf '%s' "$1" | sha256sum | cut -d' ' -f1
}

timestamp_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# CLIENTE/ENGAGEMENT con caracteres seguros y sin "..": el engagement forma una ruta bajo engagements/.
# Antes "../../x" escribía el ledger fuera del árbol de engagements.
validate_engagement() {
  local e="$1"
  [[ "$e" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || die "--engagement must be CLIENT/ENGAGEMENT (letters, digits, . _ -): $e"
  [[ "/$e/" == *"/../"* || "/$e/" == *"/./"* ]] && die "--engagement must not contain . or .. components: $e"
  return 0
}

# Lee el ledger como JSON: "asset_id<TAB>ts<TAB>from<TAB>to<TAB>cap_before<TAB>cap_after" por cada
# transición del activo. Antes se extraían campos con grep|head -1, así que un asset_name con
# '","to_phase":"development' falseaba la fase leída por history y check.
ledger_rows() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, asset = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    for n, line in enumerate(fh, 1):
        if not line.strip():
            continue
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            print(f"ERROR: phase-gates ledger line {n} is not valid JSON", file=sys.stderr)
            sys.exit(3)
        if not isinstance(e, dict) or e.get("asset_id") != asset:
            continue
        print("\t".join(str(e.get(k, "")).replace("\t", " ") for k in
                        ("ts", "from_phase", "to_phase", "capitalizable_before", "capitalizable_after")))
PY
}

read_rules_phases() {
  if [[ ! -f "$RULES_FILE" ]]; then
    echo "investigation=false design_planning=false development=true deployment=true operation=false"
    return
  fi
  local phases
  phases="$(grep -A10 "phases:" "$RULES_FILE" | grep "capitalizable:" | head -20)"
  echo "$phases"
}

is_capitalizable_phase() {
  local phase="$1"
  if [[ ! -f "$RULES_FILE" ]]; then
    case "$phase" in
      development|deployment) return 0 ;;
      *) return 1 ;;
    esac
  fi
  local cap
  cap="$(grep -A10 "^  ${phase}:" "$RULES_FILE" | grep "capitalizable:" | grep -o "true\|false" | head -1 || echo "false")"
  [[ "$cap" == "true" ]]
}

get_prev_hash() {
  local file="$1"
  if [[ ! -f "$file" ]] || [[ ! -s "$file" ]]; then
    echo "0000000000000000000000000000000000000000000000000000000000000000"
    return
  fi
  local h
  h="$(tail -n 1 "$file" | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get("hash",""))
except Exception: print("")' 2>/dev/null)"
  echo "${h:-0000000000000000000000000000000000000000000000000000000000000000}"
}

# ── Subcommand: record ──────────────────────────────────────────────

cmd_record() {
  local asset_id="" asset_name="" from_phase="" to_phase=""
  local engagement="" actor="${USER:-unknown}" evidence_dir=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --asset-id)     asset_id="$2";     shift 2 ;;
      --asset-name)   asset_name="$2";   shift 2 ;;
      --from-phase)   from_phase="$2";   shift 2 ;;
      --to-phase)     to_phase="$2";     shift 2 ;;
      --engagement)   engagement="$2";   shift 2 ;;
      --actor)        actor="$2";        shift 2 ;;
      --evidence-dir) evidence_dir="$2"; shift 2 ;;
      *) die "record: unknown argument: $1" ;;
    esac
  done

  [[ -z "$asset_id"   ]] && die "record: --asset-id is required"
  [[ -z "$asset_name" ]] && die "record: --asset-name is required"
  [[ -z "$from_phase" ]] && die "record: --from-phase is required"
  [[ -z "$to_phase"   ]] && die "record: --to-phase is required"
  [[ -z "$engagement" ]] && die "record: --engagement is required"

  # Comparación exacta: con grep, "develop.ent", "d.*" o "development deployment" pasaban por fases válidas.
  local valid_phases="investigation design_planning development deployment operation"
  case "$from_phase" in
    investigation|design_planning|development|deployment|operation) ;;
    *) die "record: --from-phase must be one of: ${valid_phases}" ;;
  esac
  case "$to_phase" in
    investigation|design_planning|development|deployment|operation) ;;
    *) die "record: --to-phase must be one of: ${valid_phases}" ;;
  esac

  validate_engagement "$engagement"
  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local eng_dir="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}"
  mkdir -p "$eng_dir"
  local gate_file="${eng_dir}/phase-gates.jsonl"

  local ts
  ts="$(timestamp_utc)"
  local prev_hash
  prev_hash="$(get_prev_hash "$gate_file")"

  local chain_input="${ts}${asset_id}${asset_name}${from_phase}${to_phase}${actor}${prev_hash}"
  local hash
  hash="sha256:$(sha256_str "$chain_input")"

  local cap_from="non-capitalizable"
  local cap_to="non-capitalizable"
  if is_capitalizable_phase "$from_phase"; then cap_from="capitalizable"; fi
  if is_capitalizable_phase "$to_phase";   then cap_to="capitalizable";   fi

  # JSON real (json.dumps), no interpolación: comillas en nombre o actor no pueden inyectar campos.
  local entry
  entry="$(TS="$ts" AID="$asset_id" ANAME="$asset_name" FROM="$from_phase" TO="$to_phase" \
    CAPF="$cap_from" CAPT="$cap_to" ACTOR="$actor" PREV="$prev_hash" HASH="$hash" EVD="$evidence_dir" \
    python3 -c 'import json, os
e = os.environ
d = {"ts": e["TS"], "asset_id": e["AID"], "asset_name": e["ANAME"], "from_phase": e["FROM"],
     "to_phase": e["TO"], "capitalizable_before": e["CAPF"], "capitalizable_after": e["CAPT"],
     "actor": e["ACTOR"], "prev_hash": e["PREV"], "hash": e["HASH"]}
if e["EVD"]:
    d["evidence_dir"] = e["EVD"]
print(json.dumps(d, ensure_ascii=False, separators=(",", ":")))')" || die "record: could not build ledger entry"
  echo "$entry" >> "$gate_file"

  printf '%s' "$entry" | python3 -c 'import json,sys; d=json.load(sys.stdin); d.pop("evidence_dir", None); print(json.dumps(d, ensure_ascii=False, indent=2))'

  echo ""
  echo "Transition recorded: ${from_phase} → ${to_phase}"
  echo "  Capitalizable before: ${cap_from}"
  echo "  Capitalizable after:  ${cap_to}"

  if [[ "$cap_from" == "non-capitalizable" && "$cap_to" == "capitalizable" ]]; then
    echo "  NOTE: Work before $(date -u +%Y-%m-%dT%H:%M:%SZ) is excluded from capitalization."
  fi

  if [[ "$cap_to" == "non-capitalizable" ]]; then
    echo "  NOTE: Expenditure from this point is OPEX."
  fi
}

# ── Subcommand: history ─────────────────────────────────────────────

cmd_history() {
  local asset_id="" engagement=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --asset-id)   asset_id="$2";   shift 2 ;;
      --engagement) engagement="$2"; shift 2 ;;
      *) die "history: unknown argument: $1" ;;
    esac
  done

  [[ -z "$asset_id"   ]] && die "history: --asset-id is required"
  [[ -z "$engagement" ]] && die "history: --engagement is required"

  validate_engagement "$engagement"
  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local gate_file="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}/phase-gates.jsonl"

  if [[ ! -f "$gate_file" ]]; then
    echo "No phase gates recorded for ${engagement}"
    exit 0
  fi

  echo "# Phase Gate History — Asset: ${asset_id} — Engagement: ${engagement}"
  echo ""
  printf "%-22s %-18s %-18s %-16s %-16s\n" "Timestamp" "From Phase" "To Phase" "Cap Before" "Cap After"
  printf "%-22s %-18s %-18s %-16s %-16s\n" "---------" "----------" "--------" "---------" "--------"

  local found=0 rows ts_val from to cap_before cap_after
  rows="$(ledger_rows "$gate_file" "$asset_id")" || die "history: corrupt ledger $gate_file"
  while IFS=$'\t' read -r ts_val from to cap_before cap_after; do
    [[ -z "$ts_val" ]] && continue
    printf "%-22s %-18s %-18s %-16s %-16s\n" "${ts_val}" "${from}" "${to}" "${cap_before}" "${cap_after}"
    found=1
  done <<< "$rows"
  if [[ "$found" -eq 0 ]]; then
    echo "(no phase transitions for asset ${asset_id})"
  fi
}

# ── Subcommand: check ───────────────────────────────────────────────

cmd_check() {
  local asset_id="" engagement="" date=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --asset-id)   asset_id="$2";   shift 2 ;;
      --engagement) engagement="$2"; shift 2 ;;
      --date)       date="$2";       shift 2 ;;
      *) die "check: unknown argument: $1" ;;
    esac
  done

  [[ -z "$asset_id"   ]] && die "check: --asset-id is required"
  [[ -z "$engagement" ]] && die "check: --engagement is required"
  [[ -z "$date"       ]] && die "check: --date is required (YYYY-MM-DD)"
  # Fecha real en formato YYYY-MM-DD: la comparación es de cadenas, «2026-7-1» u «hoy» daban otra fase.
  [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -u -d "$date" +%F >/dev/null 2>&1 \
    || die "check: --date must be a valid YYYY-MM-DD date: $date"
  validate_engagement "$engagement"

  local client_eng="${engagement%/*}"
  local eng_slug="${engagement#*/}"
  local gate_file="${REPO_ROOT}/engagements/${client_eng}/${eng_slug}/phase-gates.jsonl"

  if [[ ! -f "$gate_file" ]]; then
    echo "No phase gates for ${asset_id} in ${engagement}"
    echo "Not capitalizable (no gates recorded)"
    exit 1
  fi

  local last_phase="investigation" rows ts_val from to cap_before cap_after
  rows="$(ledger_rows "$gate_file" "$asset_id")" || die "check: corrupt ledger $gate_file"
  while IFS=$'\t' read -r ts_val from to cap_before cap_after; do
    [[ -z "$ts_val" ]] && continue
    local entry_date="${ts_val%%T*}"
    if [[ "$entry_date" == "$date" ]] || [[ "$entry_date" < "$date" ]]; then
      last_phase="$to"
    fi
  done <<< "$rows"

  echo "Asset:    ${asset_id}"
  echo "Date:     ${date}"
  echo "Phase as of date: ${last_phase}"

  if is_capitalizable_phase "$last_phase"; then
    echo "Status:   CAPITALIZABLE — expenditure from this point may be capitalized"
    return 0
  else
    echo "Status:   NON-CAPITALIZABLE — expenditure must be expensed"
    return 1
  fi
}

# ── Dispatch ─────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
  usage
fi

subcmd="$1"
shift

case "$subcmd" in
  record)  cmd_record "$@" ;;
  history) cmd_history "$@" ;;
  check)   cmd_check "$@" ;;
  -h|--help) usage ;;
  *) echo "ERROR: unknown subcommand: ${subcmd}" >&2
     echo "Run with --help for usage." >&2
     exit 2 ;;
esac
