#!/usr/bin/env bash
# permissions-wildcard-audit.sh — SE-059 Slice 1 permissions wildcard audit.
#
# Audita settings.json (repo + user + local) contra patterns peligrosos:
# wildcard allows sin deny lists, defaultMode auto + skip prompts,
# Bash patterns incluyendo destructive commands, etc.
#
# Usage:
#   permissions-wildcard-audit.sh                    # all levels
#   permissions-wildcard-audit.sh --level repo|user|local
#   permissions-wildcard-audit.sh --json
#   permissions-wildcard-audit.sh --suggest          # print recommended deny list
#
# Exit codes:
#   0 — no findings
#   1 — findings present
#   2 — usage error
#
# Ref: SE-059, research/agentshield-20260420.md
# Safety: read-only. set -uo pipefail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LEVEL="all"
JSON=0
SUGGEST=0

usage() {
  cat <<EOF
Usage:
  $0 [--level repo|user|local|all] [--json] [--suggest]

Options:
  --level LEVEL   repo (.claude/settings.json), user, local, or all (default)
  --json          JSON output
  --suggest       Print recommended deny list patterns

Audita patrones wildcard permission (PERM-01..PERM-08).
Ref: SE-059.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --level) LEVEL="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --suggest) SUGGEST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

case "$LEVEL" in
  repo|user|local|all) ;;
  *) echo "ERROR: invalid level '$LEVEL'" >&2; exit 2 ;;
esac

if [[ "$SUGGEST" -eq 1 ]]; then
  cat <<SUGGEST_EOF
Recommended deny list patterns (JSON to merge into settings.json):
Include deny patterns for: destructive filesystem ops, raw eval/exec,
piped-network-to-shell, writes to system dirs and credential dirs.

See docs/rules/domain/security-scanners.md for the canonical template.
SUGGEST_EOF
  exit 0
fi

# Determine paths
SETTINGS_FILES=()
case "$LEVEL" in
  repo) [[ -f "$PROJECT_ROOT/.claude/settings.json" ]] && SETTINGS_FILES+=("$PROJECT_ROOT/.claude/settings.json") ;;
  user) [[ -f "$HOME/.claude/settings.json" ]] && SETTINGS_FILES+=("$HOME/.claude/settings.json") ;;
  local) [[ -f "$PROJECT_ROOT/.claude/settings.local.json" ]] && SETTINGS_FILES+=("$PROJECT_ROOT/.claude/settings.local.json") ;;
  all)
    [[ -f "$PROJECT_ROOT/.claude/settings.json" ]] && SETTINGS_FILES+=("$PROJECT_ROOT/.claude/settings.json")
    [[ -f "$HOME/.claude/settings.json" ]] && SETTINGS_FILES+=("$HOME/.claude/settings.json")
    [[ -f "$PROJECT_ROOT/.claude/settings.local.json" ]] && SETTINGS_FILES+=("$PROJECT_ROOT/.claude/settings.local.json")
    ;;
esac

FINDINGS=()

add_finding() {
  local rule="$1" sev="$2" detail="$3" file="$4"
  FINDINGS+=("$rule|$sev|$detail|$file")
}

audit_settings() {
  local f="$1"
  [[ ! -f "$f" ]] && return 0

  if ! python3 -c "import sys; import json; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
    add_finding "PERM-08" "MEDIUM" "Malformed JSON" "$f"
    return 0
  fi

  local allow_list deny_list default_mode skip_prompt
  allow_list=$(python3 -c "import sys
import json
d = json.load(open(sys.argv[1]))
for p in d.get('permissions',{}).get('allow',[]): print(p)
" "$f" 2>/dev/null)
  deny_list=$(python3 -c "import sys
import json
d = json.load(open(sys.argv[1]))
for p in d.get('permissions',{}).get('deny',[]): print(p)
" "$f" 2>/dev/null)
  default_mode=$(python3 -c "import sys
import json
print(json.load(open(sys.argv[1])).get('permissions',{}).get('defaultMode',''))
" "$f" 2>/dev/null)
  skip_prompt=$(python3 -c "import sys
import json
print(json.load(open(sys.argv[1])).get('skipAutoPermissionPrompt', False))
" "$f" 2>/dev/null)

  # Count non-empty lines in deny_list (avoid multi-line fallback)
  if [[ -z "$deny_list" ]]; then
    deny_count=0
  else
    deny_count=$(printf '%s\n' "$deny_list" | grep -c .)
  fi

  # PERM-01
  if echo "$allow_list" | grep -qE '^Bash\(\*\)$'; then
    if [[ "$deny_count" -eq 0 ]]; then
      add_finding "PERM-01" "HIGH" "Bash(*) allow without deny list" "$f"
    fi
  fi

  # PERM-02
  if echo "$allow_list" | grep -qE '^Write\(\*\)$'; then
    add_finding "PERM-02" "HIGH" "Write(*) allow without path restriction" "$f"
  fi

  # PERM-03
  if echo "$allow_list" | grep -qE '^WebFetch\(\*\)$'; then
    add_finding "PERM-03" "MEDIUM" "WebFetch(*) without domain allowlist" "$f"
  fi

  # PERM-04
  if [[ "$default_mode" == "auto" && "$skip_prompt" == "True" ]]; then
    add_finding "PERM-04" "HIGH" "defaultMode=auto with skipAutoPermissionPrompt=true" "$f"
  fi

  # PERM-05
  local has_wildcard=0
  echo "$allow_list" | grep -qE '\(\*\)' && has_wildcard=1
  if [[ "$has_wildcard" -eq 1 && "$deny_count" -eq 0 ]]; then
    add_finding "PERM-05" "HIGH" "Wildcard allows without any deny rules" "$f"
  fi

  # PERM-06 destructive commands in Bash allow
  if echo "$allow_list" | grep -qE 'Bash\([^)]*(\brm |\bdd |mkfs|chmod 777)'; then
    add_finding "PERM-06" "CRITICAL" "Bash allow includes destructive command without restriction" "$f"
  fi

  # PERM-07 curl POST in Bash allow
  if echo "$allow_list" | grep -qE 'Bash\([^)]*curl[^)]*-X[[:space:]]*POST'; then
    add_finding "PERM-07" "MEDIUM" "Bash allow includes curl POST without allowlist" "$f"
  fi
}

for f in "${SETTINGS_FILES[@]}"; do
  audit_settings "$f"
done

count_sev() {
  local s="$1" c=0
  for f in "${FINDINGS[@]}"; do
    [[ "$f" == *"|$s|"* ]] && c=$((c + 1))
  done
  echo "$c"
}

CRIT=$(count_sev "CRITICAL")
HIGH=$(count_sev "HIGH")
MED=$(count_sev "MEDIUM")

EXIT_CODE=0
[[ ${#FINDINGS[@]} -gt 0 ]] && EXIT_CODE=1

if [[ "$JSON" -eq 1 ]]; then
  findings_json=""
  for f in "${FINDINGS[@]}"; do
    IFS='|' read -r rule sev detail file <<< "$f"
    detail_esc=$(echo "$detail" | sed 's/"/\\"/g')
    file_esc=$(echo "$file" | sed 's/"/\\"/g')
    findings_json+="{\"rule\":\"$rule\",\"severity\":\"$sev\",\"detail\":\"$detail_esc\",\"file\":\"$file_esc\"},"
  done
  findings_json="[${findings_json%,}]"
  cat <<JSON
{"verdict":"$([ $EXIT_CODE -eq 0 ] && echo PASS || echo FAIL)","level":"$LEVEL","files_audited":${#SETTINGS_FILES[@]},"findings_count":${#FINDINGS[@]},"critical":$CRIT,"high":$HIGH,"medium":$MED,"findings":$findings_json}
JSON
else
  echo "=== SE-059 Permissions Wildcard Audit ==="
  echo ""
  echo "Level:           $LEVEL"
  echo "Files audited:   ${#SETTINGS_FILES[@]}"
  echo "Findings:        ${#FINDINGS[@]} (crit=$CRIT high=$HIGH med=$MED)"
  echo ""
  if [[ ${#FINDINGS[@]} -gt 0 ]]; then
    echo "Findings:"
    for f in "${FINDINGS[@]}"; do
      IFS='|' read -r rule sev detail file <<< "$f"
      printf "  [%s] %-9s %s\n" "$rule" "$sev" "$detail"
      printf "          file: %s\n" "$file"
    done
    echo ""
    echo "Suggestion: bash $0 --suggest para obtener deny list recomendada"
  fi
  echo "VERDICT: $([ $EXIT_CODE -eq 0 ] && echo PASS || echo FAIL)"
fi

exit $EXIT_CODE
