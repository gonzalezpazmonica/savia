#!/usr/bin/env bash
set -uo pipefail
# confidentiality-scan.sh — Scan for PII, credentials, real project names.
# Exit 0 = clean, Exit 1 = violations, Exit 2 = error
# Usage: [--staged|--pr|--full-repo] [--blocklist <file>]
#   --staged:    scan staged changes only (pre-commit)
#   --pr:        scan PR diff vs origin/main
#   --full-repo: scan ALL tracked file contents (periodic audit)
#   --blocklist: path to dynamically generated blocklist
# SE-453: la última línea de stdout es `gate-result: {...}` (clean|findings|unknown). Un diff que git
# no pudo calcular (p. ej. sin origin/main) o una blocklist pedida que no se pudo leer es un hueco,
# nunca «No content to scan»/CLEAN. Códigos sin renumerar: con hueco y sin violaciones sale 0
# (D3: ciclo de aviso, registrado en output/unmeasured-gates.jsonl); SAVIA_GATE_UNKNOWN=block ⇒ 2.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOWLIST="$ROOT_DIR/scripts/confidentiality-allowlist.txt"
FAILS=0; WARNS=0; MODE="--staged"; DYN_BLOCKLIST=""
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()
add_gap() { [[ " ${GAPS[*]} " == *" $1 "* ]] || GAPS+=("$1"); }

# finish — resultado del contrato SE-453 y exit code (sin renumerar).
finish() {
  local result="clean" rc=0
  if [ "$FAILS" -gt 0 ]; then result="findings"; rc=1
  elif [ "${#GAPS[@]}" -gt 0 ]; then
    result="unknown"
    GATE_UNMEASURED_ROOT="$ROOT_DIR" gate_unmeasured_record "confidentiality-scan" "${GAPS[0]#*:}"
    echo "WARN: escaneo incompleto (resultado desconocido): ${GAPS[*]}"
    [ "${SAVIA_GATE_UNKNOWN:-warn}" = "block" ] && rc=2
  fi
  gate_result_emit "$result" "${GAPS[@]}"
  exit "$rc"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --staged|--pr|--full-repo) MODE="$1"; shift ;;
    --blocklist) DYN_BLOCKLIST="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Confidentiality Scanner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXCLUDE_FILES="confidentiality-scan.sh|confidentiality-check.sh|confidentiality-blocklist"
EXCLUDE_FILES="$EXCLUDE_FILES|security-check-patterns.md|test-stress-hooks.sh|pentest-lab"
EXCLUDE_FILES="$EXCLUDE_FILES|confidentiality-gate.yml|confidentiality-allowlist.txt"
EXCLUDE_FILES="$EXCLUDE_FILES|generate-blocklist.sh|confidentiality-sign.sh"
EXCLUDE_FILES="$EXCLUDE_FILES|confidentiality-auditor.md|pii-sanitization.md"
EXCLUDE_FILES="$EXCLUDE_FILES|tests/|test-.*\.sh|community-protocol.md"
EXCLUDE_FILES="$EXCLUDE_FILES|security-guardian.md|block-credential-leak.sh"
EXCLUDE_FILES="$EXCLUDE_FILES|contribute.sh|validate-privacy"
EXCLUDE_FILES="$EXCLUDE_FILES|credential-scan.md|agent-hook-premerge.sh"
EXCLUDE_FILES="$EXCLUDE_FILES|messaging-subject-safety.md|confidentiality-strategies.md"
EXCLUDE_FILES="$EXCLUDE_FILES|pentesting/|checklists.md"
EXCLUDE_FILES="$EXCLUDE_FILES|credential-proxy.sh|managed-agents-patterns.md"
EXCLUDE_FILES="$EXCLUDE_FILES|session-event-log.sh"
# OpenCode TS hook ports (same self-referential exclusion as block-credential-leak.sh)
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/.*\.test\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/lib/credential-patterns\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/lib/injection-patterns\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/lib/leakage-patterns\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/lib/sovereignty-patterns\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|docs/propuestas/SPEC-OC-01-savia-shield-opencode-adaptation\.md$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/block-credential-leak\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/block-gitignored-references\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/prompt-injection-guard\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|\.opencode/plugins/validate-bash-global\.ts$"
EXCLUDE_FILES="$EXCLUDE_FILES|docs/propuestas/SPEC-142-pretooluse-input-modification\.md$"
EXCLUDE_FILES="$EXCLUDE_FILES|docs/rules/domain/savia-shield-opencode\.md|hook-multihandler-baseline\.sh"

get_lines() {
  cd "$ROOT_DIR" || exit 2
  case "$MODE" in
    --staged)
      git diff --cached --diff-filter=ACMR -U0 \
        | awk -v exc="$EXCLUDE_FILES" '/^diff --git/{skip=0; if(match($0,exc)) skip=1} !skip{print}' \
        | grep "^+" | grep -v "^+++"
      ;;
    --pr)
      git diff origin/main...HEAD --diff-filter=ACMR -U0 \
        | awk -v exc="$EXCLUDE_FILES" '/^diff --git/{skip=0; if(match($0,exc)) skip=1} !skip{print}' \
        | grep "^+" | grep -v "^+++"
      ;;
    --full-repo)
      # Scan ALL content of ALL tracked files (excluding self-referencing ones)
      git ls-files \
        | grep -vE "$EXCLUDE_FILES" \
        | while IFS= read -r f; do
            [ -f "$f" ] && sed "s/^/+/" "$f"
          done
      ;;
  esac
}

# changed_files — ficheros añadidos o modificados del modo actual (Check 4), con las mismas exclusiones.
changed_files() {
  cd "$ROOT_DIR" || exit 2
  case "$MODE" in
    --staged) git diff --cached --diff-filter=ACMR --name-only ;;
    --pr)     git diff origin/main...HEAD --diff-filter=ACMR --name-only ;;
  esac | grep -vE "$EXCLUDE_FILES"
}

# git_source_ok — 0 si git puede calcular la fuente del modo actual (diff o lista de ficheros).
git_source_ok() {
  local rc=0
  case "$MODE" in
    --staged) git -C "$ROOT_DIR" diff --cached --quiet >/dev/null 2>&1 || rc=$? ;;
    --pr)     git -C "$ROOT_DIR" diff --quiet origin/main...HEAD >/dev/null 2>&1 || rc=$? ;;
    --full-repo) git -C "$ROOT_DIR" ls-files >/dev/null 2>&1 || rc=2 ;;
  esac
  [ "$rc" -le 1 ]
}

if ! git_source_ok; then
  echo "ERROR: git no pudo calcular el contenido a escanear (mode: $MODE). No se ha escaneado nada." >&2
  add_gap "git-diff:unreadable"
  finish
fi
ADDED_LINES=$(get_lines 2>/dev/null || true)
if [ -z "$ADDED_LINES" ]; then echo "No content to scan."; finish; fi
LINE_COUNT=$(echo "$ADDED_LINES" | wc -l)
echo "Scanning $LINE_COUNT lines (mode: $MODE)"

# ── Check 1: Blocklist (dynamic or fallback to static) ─────────────────────
echo "-- Check 1: Blocklist"
if [ -z "$DYN_BLOCKLIST" ]; then
  GEN="$SCRIPT_DIR/generate-blocklist.sh"
  if [ -f "$GEN" ]; then
    DYN_BLOCKLIST=$(mktemp)
    bash "$GEN" > "$DYN_BLOCKLIST" 2>/dev/null || add_gap "blocklist:unreadable"
    trap "rm -f '$DYN_BLOCKLIST'" EXIT
    echo "  (auto-generated $(wc -l < "$DYN_BLOCKLIST") patterns from workspace)"
  else
    add_gap "blocklist:missing_tool"
  fi
elif [ ! -f "$DYN_BLOCKLIST" ] || [ ! -r "$DYN_BLOCKLIST" ]; then
  echo "  ERROR: --blocklist no existe o no se puede leer: $DYN_BLOCKLIST" >&2
  add_gap "blocklist:unreadable"
fi
ALL_PATTERNS=""
if [ -n "$DYN_BLOCKLIST" ] && [ -f "$DYN_BLOCKLIST" ]; then
  ALL_PATTERNS=$(grep -v "^#" "$DYN_BLOCKLIST" | grep -v "^$" | tr '\n' '|' | sed 's/|$//')
fi
if [ -n "$ALL_PATTERNS" ]; then
  MATCHES=$(echo "$ADDED_LINES" | grep -iE "$ALL_PATTERNS" || true)
  if [ -n "$MATCHES" ]; then
    MATCH_COUNT=$(echo "$MATCHES" | wc -l)
    echo "::error::BLOCKED: Blocklist terms found ($MATCH_COUNT lines)"
    echo "$MATCHES" | head -15 | while read -r l; do echo "  FAIL $l"; done
    [ "$MATCH_COUNT" -gt 15 ] && echo "  ... and $((MATCH_COUNT - 15)) more"
    FAILS=$((FAILS + 1))
  else echo "  OK"; fi
else echo "  WARN: No blocklist patterns (generate-blocklist.sh missing?)"; fi

# ── Check 2: Credentials ──────────────────────────────────────────────────
echo "-- Check 2: Credentials"
CRED=$(echo "$ADDED_LINES" | grep -iE \
  "(AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_|AIza[0-9A-Za-z_-]{35}|-----BEGIN.*(PRIVATE|RSA).*KEY)" \
  | grep -v "regex\|pattern\|detect\|example\|pentest\|grep\|SECRETS_PATTERN" \
  | grep -v "VALIDATE\|validate\|PRIVATE_KEY:" \
  | grep -v "BEGIN.*KEY-----$\|'.*KEY.*'\|\".*KEY.*\"" \
  | grep -v "\\\\|sed\\|awk\\|echo.*test\\|-E '" \
  | grep -vE "rx:[[:space:]]*/|kind:[[:space:]]*\"(github-pat|openai-key|anthropic-key|azure-sas)|\`(ghp_|github_pat_|AIza|AKIA)|GITHUB_PAT_FILE=|\"kind\":\"github-pat" \
  | grep -vE "(SEC-[0-9]+|Credencial|token_type|prefix =|ya-detectados|conn strings|tokens,|token real|tokens real)" \
  | grep -vE "CHANGELOG\.d/|hook-multihandler-baseline|savia-shield-opencode|security-guardian\.md" || true)
if [ -n "$CRED" ]; then
  echo "::error::BLOCKED: Credentials detected"
  echo "$CRED" | head -5 | while read -r l; do echo "  FAIL $l"; done
  FAILS=$((FAILS + 1))
else echo "  OK"; fi

# ── Check 3: Real emails ──────────────────────────────────────────────────
echo "-- Check 3: Emails"
EMAILS=$(echo "$ADDED_LINES" | grep -oiE "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}" \
  | grep -v "@example\.\|@test\.\|@contoso\.\|@miorganizacion\.\|@anthropic\.\|@github\.\|@savia\.dev\|@empresa\.\|@cliente\." \
  | grep -v "@domain\.\|@org\.\|@co\.\|@company\.\|@cliente-alpha\.\|@cliente-beta\.\|@acme\." \
  | grep -v "\.example$\|\.invalid$\|\.test$" \
  | grep -vE "^@[a-z]+\.[a-z]+$" \
  | grep -vE "@kotlinx\.|@orders\.|@router\.|@app\.|@pytest\.|@override|@mcp\.|@server\." \
  | grep -vE "^i@izs\.me$" `# SE-425: aviso público de npm (deprecated de glob) en package-lock.json` \
  | sort -u || true)
if [ -n "$EMAILS" ]; then
  echo "::error::BLOCKED: Real emails found"
  echo "$EMAILS" | while read -r e; do echo "  FAIL $e"; done
  FAILS=$((FAILS + 1))
else echo "  OK"; fi

# ── Check 4: Forbidden files (skip for full-repo — files already committed) ─
if [ "$MODE" != "--full-repo" ]; then
  echo "-- Check 4: Forbidden files"
  CHANGED=$(changed_files 2>/dev/null || true)
  FORBID=$(echo "$CHANGED" | grep -iE "\.(env|pat|secret|pem|p12|pfx|key)$|id_rsa|id_ed25519" || true)
  if [ -n "$FORBID" ]; then
    echo "::error::BLOCKED: Forbidden file types"
    echo "$FORBID" | while read -r f; do echo "  FAIL $f"; done
    FAILS=$((FAILS + 1))
  else echo "  OK"; fi
else
  echo "-- Check 4: Forbidden files (skipped in full-repo mode)"
fi

# ── Check 5: Merge conflict markers ───────────────────────────────────────
echo "-- Check 5: Conflict markers"
if echo "$ADDED_LINES" | grep -qE "^\+<{7}|^\+>{7}|^\+={7}"; then
  echo "::error::BLOCKED: Merge conflict markers"; FAILS=$((FAILS + 1))
else echo "  OK"; fi

# ── Check 6: Proper noun heuristic ────────────────────────────────────────
echo "-- Check 6: Proper nouns"
NOUNS=$(echo "$ADDED_LINES" | grep -v "^+#\|^+//\|^+\*\|import \|class " \
  | grep -oE "\b[A-Z][a-z]+\s+[A-Z][a-z]+(\s+[A-Z][a-z]+)?" | sort -u || true)
if [ -n "$NOUNS" ]; then
  ALLOW=""; [ -f "$ALLOWLIST" ] && ALLOW=$(grep -v "^#" "$ALLOWLIST" | grep -v "^$" | tr '\n' '|' | sed 's/|$//')
  FLAGGED="$NOUNS"; [ -n "$ALLOW" ] && FLAGGED=$(echo "$NOUNS" | grep -vE "$ALLOW" || true)
  if [ -n "$FLAGGED" ]; then
    NOUN_COUNT=$(echo "$FLAGGED" | wc -l)
    echo "  WARN: $NOUN_COUNT proper nouns not in allowlist (top 10):"
    echo "$FLAGGED" | head -10 | while read -r n; do echo "    ? $n"; done
    WARNS=$((WARNS + 1))
  else echo "  OK"; fi
else echo "  OK"; fi

# ── Check 7: Private IPs ──────────────────────────────────────────────────
echo "-- Check 7: Private IPs"
IPS=$(echo "$ADDED_LINES" | grep -oE "(192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+)" | sort -u || true)
if [ -n "$IPS" ]; then
  echo "  WARN: Private IPs:"; echo "$IPS" | while read -r i; do echo "    ? $i"; done
  WARNS=$((WARNS + 1))
else echo "  OK"; fi

# ── Check 8: Real project paths ───────────────────────────────────────────
echo "-- Check 8: Project paths"
GENERIC="proyecto-alpha|proyecto-beta|sala-reservas|example|test|demo|sample|template"
PROJS=$(echo "$ADDED_LINES" | grep -oiE "projects/[a-z][a-z0-9_-]+" \
  | grep -v "projects/\*\|projects/{" | grep -viE "$GENERIC" | sort -u || true)
if [ -n "$PROJS" ]; then
  echo "  WARN: Non-generic project paths:"
  echo "$PROJS" | head -10 | while read -r p; do echo "    ? $p"; done
  WARNS=$((WARNS + 1))
else echo "  OK"; fi

# ── Results ────────────────────────────────────────────────────────────────
echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $FAILS -gt 0 ]; then echo "BLOCKED — $FAILS violation(s), $WARNS warning(s)"
elif [ ${#GAPS[@]} -gt 0 ]; then echo "UNKNOWN — escaneo incompleto, $WARNS warning(s)"
elif [ $WARNS -gt 0 ]; then echo "PASSED with $WARNS warning(s)"
else echo "CLEAN — no violations"; fi
finish
