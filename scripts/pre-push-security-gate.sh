#!/usr/bin/env bash
# SE-247 — Pre-push security gate
# Hook git pre-push: escanea commits nuevos con gitleaks antes de cada push.
# Instalar: bash scripts/install-prepush-hook.sh
# Desactivar temporalmente: SAVIA_PREPUSH_SECURITY=off git push
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../.claude/hooks/lib/gate-result.sh
source "$SCRIPT_DIR/../.claude/hooks/lib/gate-result.sh"
OUTPUT_DIR="$REPO_ROOT/output/security"
FINDINGS_FILE="$OUTPUT_DIR/pre-push-findings.jsonl"
GITLEAKS_CONFIG="$REPO_ROOT/.gitleaks.toml"
DATE_TAG="$(date +%Y%m%d-%H%M%S)"

# ── 0. Opt-out global ─────────────────────────────────────────────────────────
if [[ "${SAVIA_PREPUSH_SECURITY:-on}" == "off" ]]; then
  echo "[pre-push-gate] SAVIA_PREPUSH_SECURITY=off — scan skipped." >&2
  exit 0
fi

# ── 1. Verificar que output/security/ está en .gitignore ─────────────────────
GITIGNORE="$REPO_ROOT/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if ! grep -qE '^output/' "$GITIGNORE" && ! grep -qE '^output/security' "$GITIGNORE"; then
    echo "[pre-push-gate] WARN: output/security/ no está en .gitignore — no se escribirán findings." >&2
    SKIP_WRITE=1
  fi
fi

# ── 2. Leer stdin del hook (formato git pre-push) ─────────────────────────────
# stdin: <local_ref> <local_sha> <remote_ref> <remote_sha>
LOCAL_REF=""
LOCAL_SHA=""
REMOTE_SHA=""

while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  LOCAL_REF="$local_ref"
  LOCAL_SHA="$local_sha"
  REMOTE_SHA="$remote_sha"
  break  # solo primer par
done

# Repo sin commits previos o push de rama nueva
ZERO_SHA="0000000000000000000000000000000000000000"
if [[ -z "$LOCAL_SHA" ]] || [[ "$LOCAL_SHA" == "$ZERO_SHA" ]]; then
  echo "[pre-push-gate] Sin commits nuevos que escanear." >&2
  exit 0
fi

# Rango de commits a escanear
if [[ -z "$REMOTE_SHA" ]] || [[ "$REMOTE_SHA" == "$ZERO_SHA" ]]; then
  # Rama nueva: escanear todo lo que existe localmente
  LOG_OPTS="$LOCAL_SHA"
else
  LOG_OPTS="${REMOTE_SHA}..${LOCAL_SHA}"
fi

# ── 3. Verificar gitleaks ─────────────────────────────────────────────────────
if ! command -v gitleaks &>/dev/null; then
  echo "[pre-push-gate] WARN: gitleaks no está instalado. Instalar:" >&2
  echo "  # Linux/macOS (binario):" >&2
  echo "  brew install gitleaks  # macOS" >&2
  echo "  # O descarga desde: https://github.com/gitleaks/gitleaks/releases" >&2
  # SE-453: gitleaks ausente es «desconocido», no «limpio». Ciclo de aviso (D3): el push sigue y se
  # registra como no medido; SAVIA_GATE_UNKNOWN=block lo convierte en bloqueo (exit 1).
  GATE_RESULT_LINE="$(gate_result_emit unknown "gitleaks:missing_tool")"
  echo "[pre-push-gate] $GATE_RESULT_LINE" >&2
  GATE_UNMEASURED_ROOT="$REPO_ROOT" gate_unmeasured_record "pre-push-security-gate" missing_tool
  if [[ "${SAVIA_GATE_UNKNOWN:-warn}" == "block" ]]; then
    echo "[pre-push-gate] SAVIA_GATE_UNKNOWN=block — push bloqueado: el escaneo no se ha podido ejecutar." >&2
    exit 1
  fi
  echo "[pre-push-gate] Push continúa SIN escaneo de secrets (resultado desconocido, registrado en output/unmeasured-gates.jsonl)." >&2
  exit 0
fi

# ── 4. Ejecutar gitleaks sobre el rango de commits ───────────────────────────
mkdir -p "$OUTPUT_DIR" 2>/dev/null || true

TOML_ARGS=()
if [[ -f "$GITLEAKS_CONFIG" ]]; then
  TOML_ARGS=(--config "$GITLEAKS_CONFIG")
fi

TMPFILE="$(mktemp /tmp/gitleaks-prepush-XXXXXX.json)"
trap 'rm -f "$TMPFILE"' EXIT

gitleaks detect \
  --source "$REPO_ROOT" \
  --log-opts="$LOG_OPTS" \
  --report-format json \
  --report-path "$TMPFILE" \
  "${TOML_ARGS[@]}" \
  --no-banner \
  --exit-code 1 \
  2>/dev/null
GITLEAKS_EXIT=$?

# ── 5. Evaluar resultado ─────────────────────────────────────────────────────
if [[ $GITLEAKS_EXIT -eq 0 ]]; then
  echo "[pre-push-gate] OK — sin secrets detectados en commits nuevos." >&2
  exit 0
fi

# Hay findings
echo "" >&2
echo "╔══════════════════════════════════════════════════════════════════╗" >&2
echo "║  ⚠  SAVIA PRE-PUSH SECURITY GATE — SECRETS DETECTADOS           ║" >&2
echo "╚══════════════════════════════════════════════════════════════════╝" >&2
echo "" >&2

# Mostrar findings SIN el valor del secret
if [[ -f "$TMPFILE" ]] && command -v python3 &>/dev/null; then
  python3 - "$TMPFILE" <<'PYEOF'
import json, sys
try:
    findings = json.load(open(sys.argv[1]))
    if not findings:
        sys.exit(0)
    print(f"  {len(findings)} finding(s) detectado(s):\n", file=sys.stderr)
    for f in findings:
        rule  = f.get("RuleID", f.get("Description", "unknown"))
        fpath = f.get("File", "?")
        line  = f.get("StartLine", "?")
        commit = (f.get("Commit", "") or "")[:8] or "staged"
        print(f"  [{rule}] {fpath}:{line} (commit {commit})", file=sys.stderr)
except Exception:
    pass
PYEOF
fi

echo "" >&2
echo "  Remediar antes de hacer push:" >&2
echo "  1. Elimina o rota el secret del fichero afectado." >&2
echo "  2. Si es un commit antiguo, usa: bash scripts/git-history-secret-remediate.sh" >&2
echo "  3. Para casos de falso positivo, añade excepción en .gitleaks.toml" >&2
echo "  4. Para saltar el gate (no recomendado): git push --no-verify" >&2
echo "" >&2

# Escribir findings a output/security/ si el directorio es seguro
if [[ "${SKIP_WRITE:-0}" != "1" ]]; then
  mkdir -p "$OUTPUT_DIR" 2>/dev/null || true
  if [[ -f "$TMPFILE" ]]; then
    # Convertir array JSON a JSONL
    python3 -c "
import json, sys
try:
    items = json.load(open('$TMPFILE'))
    with open('$FINDINGS_FILE', 'a') as out:
        for item in (items or []):
            item['scan_ts'] = '$DATE_TAG'
            out.write(json.dumps(item) + '\n')
except Exception:
    pass
" 2>/dev/null || true
  fi
fi

exit 1
