#!/usr/bin/env bash
set -uo pipefail
# egress-gate.sh — SE-273 S3: Egress control gate
# deny-by-default. Blocked requests are logged for S6 trajectory detection.
# Master switch: SAVIA_EGRESS_GATE=off

ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
ENGAGEMENT_DIR="${ROOT}/engagements"
ALLOWLIST="${EGRESS_ALLOWLIST:-${ENGAGEMENT_DIR}/default/egress.yaml}"
EGRESS_LOG="${ROOT}/output/egress-denials.jsonl"
PROPOSALS="${ROOT}/output/egress-proposals.md"
ACTION="${1:-}"; DOMAIN="${2:-}"; EXTRA="${3:-}"

[[ "${SAVIA_EGRESS_GATE:-on}" == "off" ]] && exit 0
mkdir -p "$(dirname "$EGRESS_LOG")" "$(dirname "$ALLOWLIST")"

ensure_allowlist() {
  if [[ ! -f "$ALLOWLIST" ]]; then
    mkdir -p "$(dirname "$ALLOWLIST")"
    cat > "$ALLOWLIST" << 'YAML'
# egress.yaml — Egress allowlist (SE-273 S3)
# deny-by-default. Operator edits this file to add domains.
# Savia proposes additions via: bash scripts/egress-gate.sh propose <domain> <reason>
domains:
  - domain: github.com
    protocols: [https]
    purpose: "Code hosting, PRs"
    added_by: operator
  - domain: api.github.com
    protocols: [https]
    purpose: "GitHub API"
    added_by: operator
  - domain: raw.githubusercontent.com
    protocols: [https]
    purpose: "Raw content"
    added_by: operator
  - domain: registry.npmjs.org
    protocols: [https]
    purpose: "npm registry"
    added_by: operator
  - domain: pypi.org
    protocols: [https]
    purpose: "PyPI"
    added_by: operator
  - domain: dev.azure.com
    protocols: [https]
    purpose: "Azure DevOps"
    added_by: operator
  - domain: localhost
    protocols: [http, https]
    purpose: "Local dev"
    added_by: operator
  - domain: 127.0.0.1
    protocols: [http, https]
    purpose: "Loopback"
    added_by: operator
isolated_by_default: false
YAML
  fi
}

# Solo nombres de host o IPv4 literales; cualquier otra cosa se deniega antes de
# tocar el allowlist (hueco G3: el dominio llegaba interpolado en código Python).
valid_domain() { [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,252})$ && "$1" != *..* ]]; }
valid_protocol() { [[ "$1" =~ ^[a-z][a-z0-9+.-]{0,15}$ ]]; }

# Fail-closed (hueco G3): YAML malformado, estructura inesperada o PyYAML
# ausente → denegado. Nada de lista de reserva permisiva.
do_check() {
  local domain="$1"
  local protocol="${2:-https}"
  if ! valid_domain "$domain" || ! valid_protocol "$protocol"; then
    echo "DENIED: dominio o protocolo con formato no válido" >&2
    return 1
  fi
  ensure_allowlist
  local rc=0
  python3 - "$ALLOWLIST" "$domain" "$protocol" <<'PYEOF' 2>/dev/null || rc=$?
import sys
try:
    import yaml
except Exception:
    sys.exit(3)
path, domain, protocol = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as f:
        config = yaml.safe_load(f)
except Exception:
    sys.exit(3)
if not isinstance(config, dict) or not isinstance(config.get("domains"), list):
    sys.exit(3)
for entry in config["domains"]:
    if not isinstance(entry, dict):
        sys.exit(3)
    protos = entry.get("protocols") or []
    if not isinstance(protos, list):
        sys.exit(3)
    if entry.get("domain", "") in (domain, "*." + domain):
        if protocol in protos or "*" in protos:
            sys.exit(0)
sys.exit(1)
PYEOF
  case "$rc" in
    0) return 0 ;;
    1) return 1 ;;
    *) echo "DENIED: allowlist ilegible o PyYAML ausente ($ALLOWLIST); fail-closed" >&2
       return 1 ;;
  esac
}

log_denial() {
  local ts d p; ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  # Solo se registran valores validados; lo demás queda como <invalid>.
  if valid_domain "$1"; then d="$1"; else d="<invalid>"; fi
  if valid_protocol "$2"; then p="$2"; else p="<invalid>"; fi
  echo "{\"ts\":\"$ts\",\"domain\":\"$d\",\"protocol\":\"$p\",\"agent\":\"${SAVIA_ACTIVE_AGENT:-unknown}\",\"verdict\":\"denied\"}" >> "$EGRESS_LOG"
}

do_propose() {
  mkdir -p "$(dirname "$PROPOSALS")"
  echo "## Proposal: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$PROPOSALS"
  echo "- **Domain:** \`$1\`" >> "$PROPOSALS"
  echo "- **Justification:** $2" >> "$PROPOSALS"
  echo "- **Status:** PENDING HUMAN APPROVAL" >> "$PROPOSALS"
  echo "" >> "$PROPOSALS"
  echo "PROPOSED: $1 — $2 (operator must approve in $ALLOWLIST)"
}

do_status() {
  ensure_allowlist
  echo "=== Egress Gate (SE-273 S3) ==="
  echo "Allowlist: $ALLOWLIST"
  local count
  count=$(python3 -c "import sys, yaml; d=yaml.safe_load(open(sys.argv[1])); print(len(d.get('domains',[])))" "$ALLOWLIST" 2>/dev/null || grep -c "domain:" "$ALLOWLIST" 2>/dev/null || echo "?")
  echo "Domains: $count"
  [[ -f "$EGRESS_LOG" ]] && echo "Denials: $(wc -l < "$EGRESS_LOG")" || echo "Denials: 0"
  [[ -f "$PROPOSALS" ]] && echo "Proposals: $PROPOSALS" || true
}

do_isolated_check() {
  [[ "${SAVIA_ISOLATED_MODE:-0}" == "1" ]] && return 0
  return 1
}

case "$ACTION" in
  check)
    [[ -z "$DOMAIN" ]] && echo "Usage: $0 check <domain> [protocol]" >&2 && exit 2
    if do_isolated_check; then
      log_denial "$DOMAIN" "${EXTRA:-https}"
      echo "ISOLATED: egress blocked" >&2; exit 1
    fi
    if do_check "$DOMAIN" "${EXTRA:-https}"; then exit 0
    else log_denial "$DOMAIN" "${EXTRA:-https}"; exit 1; fi
    ;;
  propose) do_propose "$DOMAIN" "$EXTRA" ;;
  status) do_status ;;
  isolated-check) do_isolated_check ;;
  *) echo "Usage: $0 {check|propose|status|isolated-check} [args...]" >&2; exit 2 ;;
esac
