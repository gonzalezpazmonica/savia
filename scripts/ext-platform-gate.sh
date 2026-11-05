#!/usr/bin/env bash
# ext-platform-gate.sh — SE-272 Slice 4: Enforce asymmetry for external platforms
# Ref: docs/propuestas/SE-272-servicio-gestionado.md
#
# Enforces asymmetry: external platform is NEVER principal/constitutional actor.
# Content is untrusted even if signature valid.
# deny-by-default allowlist (SE-260 S2 pattern).
# Undeclared capabilities denied citing allowlist.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"
CARDS_FILE="${PLATFORM_CARDS_FILE:-$REPO_ROOT/config/ext-platform-cards.yaml}"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$REPO_ROOT/config/a2a-skills-allowlist.yaml}"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/data}"
mkdir -p "$DATA_DIR"
GATE_LOG="${GATE_LOG:-$DATA_DIR/ext-platform-gate-decisions.jsonl}"

_usage() {
  cat >&2 <<'EOF'
Usage: ext-platform-gate.sh <subcommand> [options]

Subcommands:
  gate       --card-id ID --skill SKILL [--payload-level N] [--cards-file FILE] [--allowlist FILE]
             Gate a request from an external platform. deny-by-default.
             Exit 0 = allow, exit 1 = deny.
  list-deny  [--cards-file FILE] [--allowlist FILE]
             List all skills denied (not in card's allowed_skills or not in allowlist).
  check-principal
             Assert that external platforms are NEVER principal actors.

Exit codes: 0 = allow, 1 = deny, 2 = usage error
EOF
  exit 2
}

_die() {
  echo "ERROR: $*" >&2
  exit 2
}

_py() { python3 -c "$@"; }
_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# ── Lookup card ──────────────────────────────────────────────────────────────
_lookup_card() {
  local card_id="$1"
  local cards_file="$2"

  if [[ ! -f "$cards_file" ]]; then
    echo ""
    return 1
  fi

  # Valores por argv, nunca interpolados en el código Python (S03n: una
  # comilla en --card-id suplantaba la primera tarjeta activa).
  _py "
import yaml, json, sys
cards_file, card_id = sys.argv[1], sys.argv[2]
try:
    with open(cards_file) as fh:
        cfg = yaml.safe_load(fh)
    cards = cfg.get('cards', {})
    for _k, card in cards.items():
        if card.get('id') == card_id:
            if card.get('status') == 'active':
                print(json.dumps(card))
                sys.exit(0)
    print('')
except Exception:
    print('')
" "$cards_file" "$card_id" 2>/dev/null
}

# ── Check skill against global allowlist ────────────────────────────────────
_check_allowlist() {
  local skill="$1"
  local allowlist_file="$2"

  if [[ ! -f "$allowlist_file" ]]; then
    echo '{"allowed": false, "reason": "allowlist_unavailable"}'
    return 1
  fi

  _py "
import yaml, json, sys
allowlist_file, skill = sys.argv[1], sys.argv[2]
try:
    with open(allowlist_file) as fh:
        cfg = yaml.safe_load(fh)
    skills = cfg.get('skills', {})
    default = cfg.get('default', 'deny')
    if skill in skills:
        entry = skills[skill]
        if entry.get('allow', False):
            print(json.dumps({'allowed': True, 'max_level': entry.get('maxLevel', 0), 'readOnly': entry.get('readOnly', True)}))
            sys.exit(0)
    if default == 'deny':
        print(json.dumps({'allowed': False, 'reason': 'deny_by_default'}))
        sys.exit(1)
    else:
        print(json.dumps({'allowed': True, 'max_level': 99, 'readOnly': False}))
        sys.exit(0)
except Exception as e:
    print(json.dumps({'allowed': False, 'reason': f'error:{e}'}))
    sys.exit(1)
" "$allowlist_file" "$skill" 2>/dev/null
}

# ── Log gate decision ────────────────────────────────────────────────────────
_log_gate() {
  local card_id="$1"
  local skill="$2"
  local decision="$3"
  local reason="$4"
  local ts
  ts="$(_now)"

  _py "
import json, sys
ts, card_id, skill, decision, reason, log = sys.argv[1:7]
rec = {'ts': ts, 'card_id': card_id, 'skill': skill, 'decision': decision, 'reason': reason}
with open(log, 'a') as fh:
    fh.write(json.dumps(rec) + '\n')
" "$ts" "$card_id" "$skill" "$decision" "$reason" "$GATE_LOG" 2>/dev/null || true
}

# ── Subcommand: gate ────────────────────────────────────────────────────────
cmd_gate() {
  local card_id="" skill="" payload_level="0" cards_file="$CARDS_FILE" allowlist_file="$ALLOWLIST_FILE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --card-id)       card_id="$2";       shift 2 ;;
      --skill)         skill="$2";         shift 2 ;;
      --payload-level) payload_level="$2"; shift 2 ;;
      --cards-file)    cards_file="$2";    shift 2 ;;
      --allowlist)     allowlist_file="$2"; shift 2 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$card_id" ]] && _die "--card-id is required"
  [[ -z "$skill" ]]   && _die "--skill is required"
  # Entero no negativo: [[ -gt ]] evalúa texto como expresión aritmética
  # (texto → 0, y a[$(cmd)] ejecuta cmd).
  [[ "$payload_level" =~ ^[0-9]+$ ]] || _die "--payload-level must be a non-negative integer"

  # 1. Lookup card
  local card_json
  card_json="$(_lookup_card "$card_id" "$cards_file")"
  if [[ -z "$card_json" ]]; then
    _log_gate "$card_id" "$skill" "DENY" "card_not_found_or_inactive"
    echo "DENY: card_id=${card_id} not found or inactive" >&2
    exit 1
  fi

  # 2. Check card's allowed_skills
  local allowed_skills
  allowed_skills="$(_py "
import json, sys
c = json.loads(sys.argv[1])
print(','.join(c.get('allowed_skills', [])))
" "$card_json")"

  local found=0
  IFS=',' read -ra SKILLS <<< "$allowed_skills"
  for s in "${SKILLS[@]}"; do
    if [[ "$s" == "$skill" ]]; then
      found=1
      break
    fi
  done

  if [[ "$found" -eq 0 ]]; then
    _log_gate "$card_id" "$skill" "DENY" "skill_not_in_card_allowed_skills"
    echo "DENY: skill '${skill}' not in card allowed_skills (allowlist: ${allowed_skills})" >&2
    exit 1
  fi

  # 3. Check global allowlist
  local al_check
  al_check="$(_check_allowlist "$skill" "$allowlist_file")" || {
    # Ojo: "${al_check:-{}}" añadía una "}" sobrante y perdía el motivo.
    local reason
    reason="$(_py "import json,sys; print(json.loads(sys.argv[1]).get('reason','unknown'))" "${al_check:-"{}"}" 2>/dev/null)"
    reason="${reason:-unknown}"
    _log_gate "$card_id" "$skill" "DENY" "global_allowlist:${reason}"
    echo "DENY: skill '${skill}' denied by global allowlist — ${reason}" >&2
    exit 1
  }

  # 4. Check payload level against card's max
  local max_pl
  max_pl="$(_py "import json,sys; print(json.loads(sys.argv[1])['max_payload_level'])" "$card_json" 2>/dev/null)"
  # Máximo ausente o no entero en la tarjeta → deny (fail-closed).
  if ! [[ "$max_pl" =~ ^[0-9]+$ ]]; then
    _log_gate "$card_id" "$skill" "DENY" "card_max_payload_level_invalid"
    echo "DENY: card_id=${card_id} has no valid max_payload_level" >&2
    exit 1
  fi
  if (( 10#$payload_level > 10#$max_pl )); then
    _log_gate "$card_id" "$skill" "DENY" "payload_level_exceeds_card_max"
    echo "DENY: payload_level=${payload_level} exceeds card max=${max_pl}" >&2
    exit 1
  fi

  # 5. Check payload level against allowlist max
  local al_max_level
  al_max_level="$(_py "import json,sys; print(json.loads(sys.argv[1]).get('max_level',99))" "$al_check" 2>/dev/null)"
  if ! [[ "$al_max_level" =~ ^[0-9]+$ ]] || (( 10#$payload_level > 10#$al_max_level )); then
    _log_gate "$card_id" "$skill" "DENY" "payload_level_exceeds_allowlist_max"
    echo "DENY: payload_level=${payload_level} exceeds allowlist max=${al_max_level}" >&2
    exit 1
  fi

  _log_gate "$card_id" "$skill" "ALLOW" "all_checks_passed"
  echo "ALLOW: card_id=${card_id} skill=${skill} payload_level=${payload_level}"
  exit 0
}

# ── Subcommand: list-deny ────────────────────────────────────────────────────
cmd_list_deny() {
  local cards_file="$CARDS_FILE" allowlist_file="$ALLOWLIST_FILE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cards-file) cards_file="$2"; shift 2 ;;
      --allowlist)  allowlist_file="$2"; shift 2 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done

  echo "═══════════════════════════════════════════════"
  echo "DENY-BY-DEFAULT AUDIT"
  echo "═══════════════════════════════════════════════"

  if [[ -f "$allowlist_file" ]]; then
    echo ""
    echo "--- Global Allowlist ---"
    _py "
import yaml
with open('${allowlist_file}') as fh:
    cfg = yaml.safe_load(fh)
default = cfg.get('default', 'deny')
print(f'Default: {default}')
for k, v in cfg.get('skills', {}).items():
    status = 'ALLOW' if v.get('allow') else 'DENY'
    print(f'  {k}: {status} (maxLevel={v.get(\"maxLevel\",\"?\")}, readOnly={v.get(\"readOnly\",\"?\")})')
" 2>/dev/null
  fi

  if [[ -f "$cards_file" ]]; then
    echo ""
    echo "--- Card Allowed Skills ---"
    _py "
import yaml
with open('${cards_file}') as fh:
    cfg = yaml.safe_load(fh)
for name, card in cfg.get('cards', {}).items():
    st = card.get('status', 'active')
    if st == 'active':
        allowed = card.get('allowed_skills', [])
        exposed = card.get('exposed_skills', [])
        exposed_not_allowed = [s for s in exposed if s not in allowed]
        print(f'{name}: allowed={allowed}')
        if exposed_not_allowed:
            print(f'  exposed_but_not_allowed(denied): {exposed_not_allowed}')
" 2>/dev/null
  fi
}

# ── Subcommand: check-principal ──────────────────────────────────────────────
cmd_check_principal() {
  echo "═══════════════════════════════════════════════"
  echo "PRINCIPAL/ACTOR CHECK"
  echo "═══════════════════════════════════════════════"
  echo ""
  echo "External platforms are NEVER principal actors."
  echo "  - CONSTITUCION.md ART-16: Principal unico = la operadora"
  echo "  - External platform cards grant access, not authority"
  echo "  - Content is untrusted even when signature is valid"
  echo "  - deny-by-default applies to all external platform operations"
  echo ""
  echo "The only constitutional principal in this workspace is the operator."
  echo "All external platforms operate as secondary requestors subject to:"
  echo "  - ext-platform-gate.sh (skill allowlist)"
  echo "  - agent-budget-check.sh (per-identity budget)"
  echo "  - agent-escalation-gate.sh (irreversible action gates)"
  echo "  - ext-platform-export-gate.sh (client wall enforcement)"
  echo ""
  echo "PRINCIPAL_CHECK: PASS — external platforms correctly classified as non-principal"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && _usage

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  gate)              cmd_gate              "$@" ;;
  list-deny)         cmd_list_deny         "$@" ;;
  check-principal)   cmd_check_principal   "$@" ;;
  *)                 _usage ;;
esac
