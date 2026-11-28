#!/usr/bin/env bash
# data-sovereignty-gate.sh — Savia Shield unified gate hook (-e omitted: grep returns 1)
# Profile tier: security
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Desactivar en entornos sin proyectos privados
[[ "${SAVIA_SHIELD_ENABLED:-true}" == "false" ]] && exit 0

SHIELD_PORT="${SAVIA_SHIELD_PORT:-8444}"
SHIELD_URL="http://127.0.0.1:${SHIELD_PORT}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
AUDIT_LOG="$PROJECT_DIR/output/data-sovereignty-audit.jsonl"
mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null

# Read hook input from stdin
INPUT=""
if [[ ! -t 0 ]]; then
  if command -v timeout >/dev/null 2>&1 && timeout --version >/dev/null 2>&1; then
    INPUT=$(timeout 3 cat 2>/dev/null) || true
  else
    INPUT=$(cat 2>/dev/null) || true
  fi
fi
[[ -z "$INPUT" ]] && exit 0

# Load auth token
SHIELD_TOKEN=""
[[ -f "$HOME/.savia/shield-token" ]] && SHIELD_TOKEN=$(cat "$HOME/.savia/shield-token" 2>/dev/null)
TOKEN_HEADER=""
[[ -n "$SHIELD_TOKEN" ]] && TOKEN_HEADER="-H X-Shield-Token:$SHIELD_TOKEN"

# Extract file path FIRST — skip private destinations before any scanning
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || exit 0
[[ -z "$FILE_PATH" ]] && exit 0
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Destino N3/N4 (local protegido): en estos destinos los nombres propios son
# legítimos (CRIT-001: nada N3+ sale del workspace; escribirlos localmente es el
# uso previsto). Detectamos por path (vaults/labs) o por tool de vault (MCP).
is_protected_tier_dest() {
  case "$1" in
    */vaults/*|vaults/*|*/labs/*|labs/*) return 0 ;;
  esac
  case "$TOOL_NAME" in
    *vault_write*|*vault*) return 0 ;;
  esac
  return 1
}

# Normalize path (resolve ../ traversal + Windows backslashes)
NORM_PATH="$FILE_PATH"
if command -v python3 >/dev/null 2>&1; then
  NORM_PATH=$(python3 -c "import os,sys;print(os.path.normpath(sys.argv[1]).replace(chr(92),'/'))" "$FILE_PATH" 2>/dev/null) || NORM_PATH="$FILE_PATH"
fi

# Skip private destinations — BEFORE daemon call (N4/N4b never scanned)
# Includes tenant paths (SE-002: tenants/ are N4-isolated per tenant)
# Includes hook self-edits and BATS tests for hooks (infrastructure code,
# not leak targets — they legitimately contain hook tokens, regex patterns,
# and field names that Presidio mis-classifies as PII).
case "$NORM_PATH" in
  */projects/*|projects/*|*/tenants/*|tenants/*|*.local.*|*/output/*|*private-agent-memory*|*/config.local/*|*/.savia/*|*/.claude/sessions/*|*settings.local.json*) exit 0 ;;
  */.opencode/hooks/*|.opencode/hooks/*) exit 0 ;;
  */.opencode/plugins/*|.opencode/plugins/*) exit 0 ;;  # SE-221: plugin TS infra, igual semantica que hooks/
  */tests/hooks/*|tests/hooks/*) exit 0 ;;
esac

CONTENT=$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // .tool_input.new_string // "")[:20000]' 2>/dev/null) || exit 0

# Try daemon /gate (fast path: one HTTP call does everything)
if curl -sf --max-time 2 "$SHIELD_URL/health" >/dev/null 2>&1; then
  RESULT=$(curl -s --max-time 10 \
    -X POST "$SHIELD_URL/gate" \
    -H "Content-Type: application/json" \
    $TOKEN_HEADER \
    -d "$INPUT" 2>/dev/null)

  if [[ -n "$RESULT" ]]; then
    if echo "$RESULT" | grep -q '"BLOCK"'; then
      # SPEC-SH01: code-pattern allowlist override
      # If BLOCK was caused only by code-like tokens (kwargs, method names,
      # framework types) in a script file, downgrade to WARN.
      SH01_ALLOW=false
      case "$NORM_PATH" in
        *.py|*.sh|*.ps1|*.js|*.mjs|*.ts|*.tsx|*.tool|*/scripts/*|*/hooks/*|*/tools/*|*/tests/*)
          # SE-453 S6: cada patrón casa con la entidad ENTERA, solo tipos NER de nombre y fail-closed
          # (scripts/lib/sh01-code-allowlist.sh). Sin la librería no hay rebaja: el BLOCK se mantiene.
          SH01_LIB="$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/sh01-code-allowlist.sh"
          # shellcheck source=/dev/null
          if [[ -f "$SH01_LIB" ]] && source "$SH01_LIB" && sh01_all_code_like "$RESULT"; then
            SH01_ALLOW=true
          fi
          ;;
      esac
      if [[ "$SH01_ALLOW" == "true" ]]; then
        echo "WARNING [Savia Shield SH01]: code-token allowlist override en $FILE_PATH" >&2
        echo "$RESULT" | jq -c '. + {ts:now|todate,layer:"gate",override:"sh01_allowlist"}' >> "$AUDIT_LOG" 2>/dev/null
        exit 0
      fi
      # N3/N4 (destino local protegido): permitir nombres propios, mantener
      # bloqueo de credenciales/identificadores (CREDIT_CARD, EMAIL, PHONE,
      # NATIONAL_ID, IBAN, KEY/TOKEN/SECRET, URL...). Solo se relaja si TODAS
      # las entidades son tipo nombre (PERSON/ORG/LOC/GPE/DATE/TIME/...).
      if is_protected_tier_dest "$NORM_PATH"; then
        NAME_TYPES="^(PERSON|PERSON_ES|ORG|ORGANIZATION|LOCATION|GPE|DATE|TIME|NRP|EVENT|PRODUCT|WORK_OF_ART|MISC|LAW|LANGUAGE|ORDINAL|CARDINAL|QUANTITY|PERCENT|MONEY)$"
        BAD_TYPE=$(echo "$RESULT" | jq -r '[.entities[].type] | unique[]' 2>/dev/null \
          | grep -viE "$NAME_TYPES" | grep -v '^$' | head -1)
        if [[ -z "$BAD_TYPE" ]]; then
          echo "WARNING [Savia Shield]: nombres propios permitidos en destino N3/N4 ($FILE_PATH)" >&2
          echo "$RESULT" | jq -c '. + {ts:now|todate,layer:"gate",override:"n3n4_names"}' >> "$AUDIT_LOG" 2>/dev/null
          exit 0
        fi
      fi
      echo "$RESULT" | jq -r '.entities[]? | "  [\(.type)] \(.text)"' 2>/dev/null | head -5 >&2
      echo "BLOQUEADO [Savia Shield]: PII detectado en fichero publico" >&2
      echo "$RESULT" | jq -c '. + {ts:now|todate,layer:"gate"}' >> "$AUDIT_LOG" 2>/dev/null
      exit 2
    fi
    exit 0
  fi
fi

# Fallback: daemon down — inline regex (path + private skip already done above)
# Whitelist specific sovereignty/shield files
case "$NORM_PATH" in
  *scripts/data-sovereignty*|*scripts/ollama-classify*|*scripts/shield-ner*|*scripts/savia-shield*|*scripts/pre-commit-sovereignty*|*scripts/sovereignty-classify*|*tests/test-data-sovereignty*|*docs/propuestas/SE-314*|*config/telemetry-*|*config/classifier/*|*config/sovereignty-thresholds.yaml) exit 0 ;;
  *hooks/data-sovereignty*|*hooks/ollama-classify*|*hooks/shield-ner*) exit 0 ;;
esac

# Helper: block and log
block_fallback() {
  local reason="$1"
  echo "BLOQUEADO [fallback]: ${reason} en $FILE_PATH" >&2
  printf '{"ts":"%s","layer":"fallback","verdict":"BLOCKED","reason":"%s","file":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")" "$reason" "$FILE_PATH" \
    >> "$AUDIT_LOG" 2>/dev/null
  exit 2
}

# NFKC normalize content if python3 available (catches fullwidth digits)
NORM_CONTENT="$CONTENT"
if command -v python3 >/dev/null 2>&1; then
  NORM_CONTENT=$(printf '%s' "$CONTENT" | python3 -c "import sys,unicodedata;print(unicodedata.normalize('NFKC',sys.stdin.read()))" 2>/dev/null) || NORM_CONTENT="$CONTENT"
fi

# Cross-write: if file exists, combine existing + new content for split detection
CROSSWRITE_PAT='Server=.*[Pp]assword=|[Pp]assword=.*Server='
if [[ -f "$FILE_PATH" ]]; then
  EXISTING=$(head -c 10000 "$FILE_PATH" 2>/dev/null) || true
  if [[ -n "$EXISTING" ]]; then
    COMBINED="${EXISTING} ${NORM_CONTENT}"
    if echo "$COMBINED" | grep -qiE "$CROSSWRITE_PAT"; then
      block_fallback "split_write"
    fi
  fi
fi

# Base64 decode check: find long base64 blobs and scan decoded content
if command -v base64 >/dev/null 2>&1; then
  B64_BLOBS=$(echo "$NORM_CONTENT" | grep -oE '[A-Za-z0-9+/]{40,}={0,2}' | head -3)
  for blob in $B64_BLOBS; do
    DECODED=$(echo "$blob" | base64 -d 2>/dev/null) || continue
    if echo "$DECODED" | grep -qiE "(jdbc:|mongodb|AKIA[0-9A-Z]{16})"; then
      block_fallback "base64_credential"
    fi
  done
fi

# Inline regex on normalized content
CRED_CONN='(jdbc:|mongodb[+]srv://)'
if echo "$NORM_CONTENT" | grep -qiE "$CRED_CONN"; then
  block_fallback "connection_string"
elif echo "$NORM_CONTENT" | grep -qiE "$CROSSWRITE_PAT"; then
  block_fallback "connection_string"
elif echo "$NORM_CONTENT" | grep -qE "AKIA[0-9A-Z]{16}"; then
  block_fallback "aws_key"
elif echo "$NORM_CONTENT" | grep -qE '(ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{82,})'; then
  block_fallback "github_token"
elif echo "$NORM_CONTENT" | grep -qE 'sk-(proj-)?[A-Za-z0-9]{32,}'; then
  block_fallback "openai_key"
elif echo "$NORM_CONTENT" | grep -qE 'sv=20[0-9]{2}-'; then
  block_fallback "azure_sas"
elif echo "$NORM_CONTENT" | grep -qiE -- '-----BEGIN.*PRIV[AEIOU]*TE KEY-----'; then
  block_fallback "private_key"
elif echo "$NORM_CONTENT" | grep -qE '(192\.168\.[0-9]+\.[0-9]+|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]+\.[0-9]+)'; then
  block_fallback "internal_ip"
fi

# Layer 2: classification (SE-314) for long content that passed regex
# N1 destinations (public repo files) get WARN on AMBIGUOUS, not BLOCK.
# Only CONFIDENTIAL blocks N1 files (real secrets must never leak).
# SE-314 S5: usar sovereignty-classify.sh (determinista + umbral) en vez de
# ollama-classify.sh (binario no determinista). Decide por confidence.
IS_N1_DEST=false
case "$NORM_PATH" in
  */docs/*|*/.claude/rules/*|*/.opencode/skills/*|*/.opencode/agents/*|*/.opencode/commands/*|*/.opencode/hooks/*|*/scripts/*|*/tests/*|*/.github/*|*/CLAUDE.md|*/CHANGELOG.md|*/README*|*/public-agent-memory/*|docs/*|.claude/rules/*|.opencode/skills/*|.opencode/agents/*|.opencode/commands/*|.opencode/hooks/*|scripts/*|tests/*|.github/*|CLAUDE.md|CHANGELOG.md|README*|public-agent-memory/*) IS_N1_DEST=true ;;
esac

CLASSIFY="$PROJECT_DIR/scripts/sovereignty-classify.sh"
DECIDE="$PROJECT_DIR/scripts/sovereignty-decide.sh"
EMIT="$PROJECT_DIR/scripts/otel-emit.sh"
if [[ -x "$CLASSIFY" ]] && [[ -x "$DECIDE" ]] && [[ ${#NORM_CONTENT} -gt 50 ]]; then
  CLASS_OUT=$(printf '%s' "$NORM_CONTENT" | bash "$CLASSIFY" --context-path "$NORM_PATH" 2>/dev/null)
  if [[ -n "$CLASS_OUT" ]] && echo "$CLASS_OUT" | jq -e . >/dev/null 2>&1; then
    DEST="n4"; [[ "$IS_N1_DEST" == "true" ]] && DEST="n1"
    DEC=$(printf '%s' "$CLASS_OUT" | bash "$DECIDE" --dest "$DEST" 2>/dev/null)
    ACTION=$(printf '%s' "$DEC" | jq -r '.action // "ALLOW"' 2>/dev/null)
    REASON=$(printf '%s' "$DEC" | jq -r '.reason // ""' 2>/dev/null)
    LABEL=$(printf '%s' "$CLASS_OUT" | jq -r '.label // ""' 2>/dev/null)
    CONF=$(printf '%s' "$CLASS_OUT" | jq -r '.confidence // 0' 2>/dev/null)
    # Telemetría SE-313/SE-314: classifier.verdict|block
    if [[ -x "$EMIT" ]]; then
      if [[ "$ACTION" == "BLOCK" ]]; then
        "$EMIT" classifier.block agent_name=gate label="$LABEL" confidence="$CONF" reason="$REASON" \
          target="$NORM_PATH" retention_days=180 >/dev/null 2>&1 || true
      else
        "$EMIT" classifier.verdict agent_name=gate label="$LABEL" confidence="$CONF" action="$ACTION" \
          reason="$REASON" target="$NORM_PATH" retention_days=180 >/dev/null 2>&1 || true
      fi
    fi
    # Destino N3/N4 protegido (Labs/cúpulas, privados): solo se exime
    # confidential_high_confidence; hard_block_deterministic y las regex de
    # secretos de arriba siguen bloqueando. Nunca en un destino N1 (público).
    if [[ "$ACTION" == "BLOCK" && "$REASON" == "confidential_high_confidence" && "$IS_N1_DEST" != "true" ]] \
       && is_protected_tier_dest "$NORM_PATH"; then
      echo "WARNING [Savia Shield]: ${LABEL} (conf ${CONF}) en $FILE_PATH (destino protegido, permitido)" >&2
      printf '{"ts":"%s","layer":"fallback","verdict":"WARN","reason":"classifier_confidential_protected","dest":"protected","label":"%s","confidence":"%s","file":"%s"}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")" "$LABEL" "$CONF" "$FILE_PATH" \
        >> "$AUDIT_LOG" 2>/dev/null
      exit 0
    fi
    case "$ACTION" in
      BLOCK)
        block_fallback "classifier_${REASON}"
        ;;
      WARN)
        # N1: warn but allow (content already passed regex determinista)
        echo "WARNING [Savia Shield]: ${LABEL} (conf ${CONF}) en $FILE_PATH ($DEST dest, permitido)" >&2
        printf '{"ts":"%s","layer":"fallback","verdict":"WARN","reason":"classifier_warn","label":"%s","confidence":"%s","file":"%s"}\n' \
          "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "unknown")" "$LABEL" "$CONF" "$FILE_PATH" \
          >> "$AUDIT_LOG" 2>/dev/null
        ;;
      ALLOW|*)
        : # allow
        ;;
    esac
  fi
fi

exit 0
