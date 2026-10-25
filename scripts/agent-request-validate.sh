#!/usr/bin/env bash
# agent-request-validate.sh — SE-272 Slice 3: Validate incoming request origin
# Ref: docs/propuestas/SE-272-servicio-gestionado.md
#
# Validates incoming request origin: {human | agent}.
# For agents: requires verified identity from external platform card (S4).
# Rejects agent requests without verifiable identity.
#
# Usage:
#   agent-request-validate.sh validate --origin human|agent [--agent-id ID] [--platform-card FILE]
#   agent-request-validate.sh identify --token TOKEN
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)}"
CARDS_FILE="${PLATFORM_CARDS_FILE:-$REPO_ROOT/config/ext-platform-cards.yaml}"
DATA_DIR="${DATA_DIR:-$REPO_ROOT/data}"
mkdir -p "$DATA_DIR"
IDENTITY_LOG="${IDENTITY_LOG:-$DATA_DIR/agent-request-identity.jsonl}"

_usage() {
  cat >&2 <<'EOF'
Usage: agent-request-validate.sh <subcommand> [options]

Subcommands:
  validate        --origin human|agent [--agent-id ID] [--platform-card FILE]
                  Validates incoming request origin. Exit 0 = valid, exit 1 = reject.
  identify        --token TOKEN
                  Identifies origin type and agent id from a token.

Exit codes:
  0 — valid request origin
  1 — invalid or rejected request
  2 — usage error
EOF
  exit 2
}

_die() {
  echo "ERROR: $*" >&2
  exit 2
}

_py() { python3 -c "$@"; }

_now() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# ── Validate card identity against platform cards registry ───────────────────
_validate_agent_card() {
  local agent_id="$1"
  local card_file="${2:-$CARDS_FILE}"

  if [[ ! -f "$card_file" ]]; then
    echo "REJECT_NO_CARDS_FILE: platform card registry not found at $card_file" >&2
    return 1
  fi

  local found
  # Los valores viajan por entorno: interpolarlos en el código Python permitía que un
  # agent_id con comillas alterase la condición y se aceptase sin tarjeta.
  found=$(CARD_FILE="$card_file" AGENT_ID="$agent_id" _py "
import os, yaml, sys
try:
    with open(os.environ['CARD_FILE']) as fh:
        cfg = yaml.safe_load(fh)
    cards = cfg.get('cards', {})
    for key, card in cards.items():
        if card.get('id') == os.environ['AGENT_ID']:
            if card.get('status') == 'active':
                print(key)
                sys.exit(0)
    print('')
except Exception as e:
    print('', file=sys.stderr)
    sys.exit(1)
" 2>/dev/null) || return 1

  if [[ -z "$found" ]]; then
    echo "REJECT_UNREGISTERED: agent_id '${agent_id}' not found or not active in platform cards" >&2
    return 1
  fi

  echo "$found"
  return 0
}

# ── Log identity validation attempt ──────────────────────────────────────────
_log_identity() {
  local origin="$1"
  local agent_id="${2:-}"
  local card_id="${3:-}"
  local decision="$4"
  local reason="${5:-}"
  local ts
  ts="$(_now)"

  REC_TS="$ts" REC_ORIGIN="$origin" REC_AGENT="$agent_id" REC_CARD="$card_id" \
  REC_DECISION="$decision" REC_REASON="$reason" REC_LOG="$IDENTITY_LOG" _py "
import json, os
e = os.environ
record = {
    'timestamp': e['REC_TS'],
    'origin': e['REC_ORIGIN'],
    'agent_id': e['REC_AGENT'],
    'card_id': e['REC_CARD'],
    'decision': e['REC_DECISION'],
    'reason': e['REC_REASON'],
}
with open(e['REC_LOG'], 'a') as fh:
    fh.write(json.dumps(record) + '\n')
" 2>/dev/null || true
}

# ── Subcommand: validate ─────────────────────────────────────────────────────
cmd_validate() {
  local origin="" agent_id="" card_file="$CARDS_FILE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --origin)         origin="$2";    shift 2 ;;
      --agent-id)       agent_id="$2";  shift 2 ;;
      --platform-card)  card_file="$2"; shift 2 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$origin" ]] && _die "--origin is required"

  case "$origin" in
    human)
      _log_identity "human" "" "" "ACCEPT" "human-origin-no-verification-needed"
      echo "ACCEPT: human origin"
      exit 0
      ;;
    agent)
      [[ -z "$agent_id" ]] && _die "--agent-id is required for agent origin"

      local card_id
      if card_id=$(_validate_agent_card "$agent_id" "$card_file"); then
        _log_identity "agent" "$agent_id" "$card_id" "ACCEPT" "verified-against-cards"
        echo "ACCEPT: agent origin verified — card_id=${card_id}"
        exit 0
      else
        _log_identity "agent" "$agent_id" "" "REJECT" "no-verifiable-identity"
        echo "REJECT: agent origin without verifiable identity — agent_id=${agent_id}" >&2
        exit 1
      fi
      ;;
    *)
      _die "Invalid origin '${origin}'. Must be 'human' or 'agent'."
      ;;
  esac
}

# ── Subcommand: identify ─────────────────────────────────────────────────────
cmd_identify() {
  local token=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --token) token="$2"; shift 2 ;;
      *) _die "Unknown option: $1" ;;
    esac
  done

  [[ -z "$token" ]] && _die "--token is required"

  # Token format: "origin:agent_id" or "human:display_name"
  local origin="${token%%:*}"
  local rest="${token#*:}"

  case "$origin" in
    human)
      echo "ORIGIN: human"
      echo "DISPLAY_NAME: ${rest:-unknown}"
      exit 0
      ;;
    agent)
      echo "ORIGIN: agent"
      echo "AGENT_ID: ${rest:-unknown}"
      exit 0
      ;;
    *)
      echo "ORIGIN: unknown"
      echo "TOKEN: ${token}"
      exit 1
      ;;
  esac
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
[[ $# -lt 1 ]] && _usage

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
  validate)  cmd_validate  "$@" ;;
  identify)  cmd_identify  "$@" ;;
  *)         _usage ;;
esac
