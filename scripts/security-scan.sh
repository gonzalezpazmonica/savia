#!/usr/bin/env bash
# security-scan.sh — Security audit for pm-workspace
# Scans for: leaked credentials, hardcoded URLs, insecure patterns, missing security files
#
# Usage: bash scripts/security-scan.sh [--ci | --verbose]
set -uo pipefail

MODE="${1:---summary}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FINDINGS=0
WARNINGS=0
# SE-453: la última línea de stdout es el resultado (clean|findings|unknown). Códigos sin renumerar:
# sin --ci sale 0; con --ci, 1 si hay hallazgos. Un grep que no pudo leer el árbol es un hueco.
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
GAPS=()
# grep_root <check> <args de grep...> → deja las coincidencias en GREP_OUT; rc ≥ 2 = hueco unreadable.
grep_root() {
  local check="$1" rc; shift
  GREP_OUT="$(grep "$@" 2>/dev/null)"; rc=$?
  [[ $rc -ge 2 ]] && GAPS+=("$check:unreadable")
  return 0
}

finding() { FINDINGS=$((FINDINGS + 1)); echo "  🔴 FINDING: $1"; }
warning() { WARNINGS=$((WARNINGS + 1)); echo "  🟡 WARNING: $1"; }
pass()    { [ "$MODE" = "--verbose" ] && echo "  ✅ PASS: $1"; true; }

echo "═══════════════════════════════════════════════════"
echo "  🔒 Security Scan — pm-workspace"
echo "═══════════════════════════════════════════════════"
echo ""

# ── 1. Credential patterns ──
echo "--- Scanning for credential patterns ---"

# Real PAT tokens (52+ char base64, not in mock/example context)
grep_root base64_tokens -rn --include="*.sh" --include="*.md" --include="*.json" --include="*.yml" \
  -E '[A-Za-z0-9/+]{52,}' "$ROOT" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="output"
if printf '%s\n' "$GREP_OUT" | grep -v "mock" | grep -v "example" | grep -v "placeholder" | grep -v "CHANGELOG" | grep -v "test-data" | head -3 | grep -q .; then
  warning "Potential base64 token pattern found (may be false positive)"
else
  pass "No PAT-length base64 tokens found"
fi

# Hardcoded passwords
grep_root passwords -rn --include="*.sh" --include="*.json" \
  -E '(password|passwd|pwd)\s*[:=]\s*["\x27][^"\x27]{8,}' "$ROOT" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="test-data" --exclude-dir="projects" --exclude-dir="tests" --exclude-dir="rules" --exclude-dir="docs"
if printf '%s\n' "$GREP_OUT" | grep -v "mock" | grep -v "example" | grep -v "placeholder" | grep -v "CHANGELOG" | grep -v "ENV_" \
  | grep -v "hook-multihandler-baseline" \
  | head -3 | grep -q .; then
  finding "Hardcoded password pattern found"
else
  pass "No hardcoded passwords found"
fi

# AWS keys (exclude test files and EXAMPLE keys)
grep_root aws_keys -rn --include="*.sh" --include="*.md" --include="*.json" \
  -E 'AKIA[0-9A-Z]{16}' "$ROOT" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="test-data" --exclude-dir="projects" --exclude-dir="tests" --exclude-dir="rules"
if printf '%s\n' "$GREP_OUT" | grep -v "test-" | grep -v "EXAMPLE" | head -1 | grep -q .; then
  finding "AWS access key pattern (AKIA...) found"
else
  pass "No AWS keys found"
fi

# Private keys (exclude test/project/docs directories)
grep_root private_keys -rn --include="*.sh" --include="*.pem" --include="*.key" \
  -E 'BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY' "$ROOT" \
  --exclude-dir=".git" --exclude-dir="node_modules" --exclude-dir="tests" --exclude-dir="projects" --exclude-dir="docs" --exclude-dir="rules"
if printf '%s\n' "$GREP_OUT" | grep -v "test-" | head -1 | grep -q .; then
  finding "Private key found in repository"
else
  pass "No private keys found"
fi

echo ""

# ── 2. Hardcoded URLs ──
echo "--- Scanning for hardcoded sensitive URLs ---"

grep_root azure_urls -rn --include="*.sh" --include="*.md" \
  "dev.azure.com" "$ROOT" \
  --exclude-dir=".git" --exclude-dir="node_modules"
if printf '%s\n' "$GREP_OUT" | grep -v "TU-ORGANIZACION" | grep -v "YOUR-ORG" | grep -v "miempresa" \
  | grep -v "example" | grep -v "SETUP" | grep -v "README" | grep -v "CHANGELOG" | grep -v "CONTRIBUTING" | head -3 | grep -q .; then
  warning "Real Azure DevOps org URL may be present"
else
  pass "No hardcoded Azure DevOps URLs"
fi

echo ""

# ── 3. Security files ──
echo "--- Checking security infrastructure ---"

[ -f "$ROOT/SECURITY.md" ] && pass "SECURITY.md exists" || finding "Missing SECURITY.md"
[ -f "$ROOT/.opencode/hooks/block-credential-leak.sh" ] && pass "Credential leak hook exists" || finding "Missing credential leak hook"
[ -f "$ROOT/.opencode/hooks/block-force-push.sh" ] && pass "Force push hook exists" || finding "Missing force push hook"
[ -f "$ROOT/.opencode/hooks/block-infra-destructive.sh" ] && pass "Infra destructive hook exists" || finding "Missing infra destructive hook"

echo ""

# ── 4. Hook coverage ──
echo "--- Checking hook test coverage ---"
# Sin hooks legibles el bucle no comprobaría nada: hueco, no «todo cubierto».
compgen -G "$ROOT/.opencode/hooks/*.sh" >/dev/null || GAPS+=("hooks:unreadable")
for h in "$ROOT/.opencode/hooks/"*.sh; do
  [ -f "$h" ] || continue
  name=$(basename "$h" .sh)
  if ls "$ROOT"/tests/hooks/test-"$name"*.bats 2>/dev/null | grep -q .; then
    pass "Hook $name has BATS tests"
  else
    warning "Hook $name has no BATS tests"
  fi
done

echo ""

# ── 5. Sensitive file patterns in .gitignore ──
echo "--- Checking .gitignore coverage ---"
if [ -f "$ROOT/.gitignore" ]; then
  for pattern in ".env" "*.pem" "*.key" "credentials" "secrets"; do
    if grep -q "$pattern" "$ROOT/.gitignore" 2>/dev/null; then
      pass ".gitignore covers $pattern"
    else
      warning ".gitignore missing pattern: $pattern"
    fi
  done
else
  finding "No .gitignore file found"
fi

echo ""
echo "═══════════════════════════════════════════════════"
echo "  Results: $FINDINGS findings, $WARNINGS warnings"
echo "═══════════════════════════════════════════════════"

RESULT="clean"
if [ "$FINDINGS" -gt 0 ]; then RESULT="findings"; elif [ "${#GAPS[@]}" -gt 0 ]; then RESULT="unknown"; fi
[ "$RESULT" = "unknown" ] && GATE_UNMEASURED_ROOT="$ROOT" gate_unmeasured_record "security-scan" unreadable
RC=0
if [ "$MODE" = "--ci" ]; then
  if [ "$FINDINGS" -gt 0 ]; then
    echo "FAIL: $FINDINGS security findings"
    RC=1
  elif [ "$RESULT" = "unknown" ]; then
    # D3: un ciclo de aviso; SAVIA_GATE_UNKNOWN=block lo convierte en fallo.
    if [ "${SAVIA_GATE_UNKNOWN:-warn}" = "block" ]; then
      echo "FAIL: scan incompleto (resultado desconocido, SAVIA_GATE_UNKNOWN=block)"
      RC=1
    else
      echo "WARN: scan incompleto (resultado desconocido, registrado en output/unmeasured-gates.jsonl)"
    fi
  else
    echo "PASS: No critical security findings"
  fi
fi
gate_result_emit "$RESULT" "${GAPS[@]}"
exit "$RC"
