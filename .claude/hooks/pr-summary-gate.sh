#!/usr/bin/env bash
set -uo pipefail
# pr-summary-gate.sh — Bloquea gh pr create si .pr-summary.md no pasa revision LLM
# Ref: docs/rules/domain/pr-natural-language-summary.md
# Hook type: command (PreToolUse, matcher: Bash(gh pr create*))
# Exits: 0 = ok (o skip), 2 = blocked
# Red acotada: conexion <= 3s (un proxy inexistente o caido no bloquea) y
# respuesta <= PR_SUMMARY_LLM_TIMEOUT (90s por defecto, entero 1-90: sin datos
# de latencia del proxy no se acorta el plazo del modelo). Si el proxy no contesta a tiempo, el gate se omite con
# ADVERTENCIA (fail-open); las comprobaciones locales 1-3 siempre bloquean.

source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$SAVIA_WORKSPACE_DIR}"

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  source "$LIB_DIR/profile-gate.sh" && profile_gate "standard"
fi

ROOT="${CLAUDE_PROJECT_DIR:-.}"
SUMMARY_FILE="$ROOT/.pr-summary.md"
PROXY_URL="${ANTHROPIC_BASE_URL:-https://api.anthropic.com}"
LLM_TIMEOUT="${PR_SUMMARY_LLM_TIMEOUT:-90}"
if ! [[ "$LLM_TIMEOUT" =~ ^[0-9]+$ ]] || (( LLM_TIMEOUT < 1 || LLM_TIMEOUT > 90 )); then
  LLM_TIMEOUT=90
fi

# ── 0. Solo actuar en gh pr create ────────────────────────────────────────
INPUT="${CLAUDE_TOOL_INPUT:-}"
if ! echo "$INPUT" | grep -qE 'gh pr create'; then
  exit 0
fi

# ── 1. Existencia ─────────────────────────────────────────────────────────
if [[ ! -f "$SUMMARY_FILE" ]]; then
  echo "BLOQUEADO: falta .pr-summary.md" >&2
  echo "  Escribe un parrafo en lenguaje natural antes de abrir el PR." >&2
  echo "  Regla: docs/rules/domain/pr-natural-language-summary.md" >&2
  exit 2
fi

# ── 2. Heading canonico ───────────────────────────────────────────────────
if ! python3 -c "
import sys, unicodedata
text = open(sys.argv[1]).read()
def norm(s): return unicodedata.normalize('NFC', s)
expected = norm('## Qu\u00e9 hace este PR (en lenguaje no t\u00e9cnico)')
if expected in norm(text): sys.exit(0)
sys.exit(1)
" "$SUMMARY_FILE" 2>/dev/null; then
  echo "BLOQUEADO: .pr-summary.md no tiene el heading obligatorio." >&2
  printf "  Requerido: '## Qu\u00e9 hace este PR (en lenguaje no t\u00e9cnico)'\n" >&2
  exit 2
fi

# ── 3. Mtime — debe haberse escrito en las ultimas 24h ────────────────────
SUMMARY_AGE=$(( $(date +%s) - $(stat -c %Y "$SUMMARY_FILE") ))
if [[ $SUMMARY_AGE -gt 86400 ]]; then
  HOURS=$(( SUMMARY_AGE / 3600 ))
  echo "BLOQUEADO: .pr-summary.md tiene ${HOURS}h de antiguedad (max 24h)." >&2
  echo "  Actualizalo para reflejar los cambios de este PR." >&2
  exit 2
fi

# ── 4. Revision LLM via proxy ─────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
  echo "ADVERTENCIA: curl no disponible — revision LLM omitida." >&2
  exit 0
fi

# Extraer solo la seccion narrativa (hasta el proximo heading o EOF)
SECTION=$(python3 -c "
import sys, re
text = open(sys.argv[1]).read()
m = re.search(r'##\s*Qu[^\n]+\n(.*?)(?=\n##|\Z)', text, re.DOTALL)
section = m.group(1).strip()[:600] if m else text[:600]
print(section)
" "$SUMMARY_FILE" 2>/dev/null || head -c 600 "$SUMMARY_FILE")

# Construir payload — prompt compacto para reducir thinking en modelos locales.
# La seccion viaja por entorno: un fichero fijo en /tmp lo compartian (y se
# pisaban) todas las sesiones concurrentes.
PAYLOAD=$(PR_SUMMARY_SECTION="$SECTION" python3 << 'INNERPY'
import json, os
section = os.environ.get("PR_SUMMARY_SECTION", "")
prompt = (
    "PR summary reviewer. Output ONLY valid JSON, no other text.\n\n"
    "FAILS if text contains: spec IDs (SE-nnn, SPEC-nnn), script/tool names "
    "(hooks, BATS, JSONL, frontmatter, gates, ratchets, tiers), "
    "internal metrics (test counts, score numbers), "
    "implementation details instead of user-facing behavior.\n\n"
    "PASSES if text: explains what changes for the user in plain language, "
    "gives a concrete reason it matters, is readable prose.\n\n"
    "TEXT:\n" + section +
    "\n\nOutput ONLY: {\"ok\": true} or {\"ok\": false, \"reason\": \"brief explanation in Spanish\"}. "
    "No other text."
)
payload = {
    "model": "deepseek/deepseek-v4-flash",
    "max_tokens": 2000,
    "messages": [{"role": "user", "content": prompt}]
}
print(json.dumps(payload))
INNERPY
)

if [[ -z "$PAYLOAD" ]]; then
  echo "ADVERTENCIA: no se pudo construir payload LLM — gate omitido." >&2
  exit 0
fi

LLM_RESPONSE=$(curl -s --connect-timeout 3 --max-time "$LLM_TIMEOUT" \
  "${PROXY_URL}/v1/messages" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${ANTHROPIC_API_KEY:-placeholder}" \
  -H "anthropic-version: 2023-06-01" \
  -d "$PAYLOAD" 2>/dev/null)
CURL_RC=$?

if [[ -z "$LLM_RESPONSE" ]]; then
  case "$CURL_RC" in
    28) echo "ADVERTENCIA: proxy LLM no respondio en ${LLM_TIMEOUT}s — gate omitido." >&2 ;;
    7)  echo "ADVERTENCIA: proxy LLM no accesible (${PROXY_URL}, conexion rechazada) — gate omitido." >&2 ;;
    *)  echo "ADVERTENCIA: proxy LLM no respondio (curl ${CURL_RC}) — gate omitido." >&2 ;;
  esac
  exit 0
fi

# Extraer bloque text (puede haber bloque thinking previo en modelos locales)
JSON_BLOCK=$(python3 -c "
import sys, json, re
try:
    d = json.load(sys.stdin)
    for block in d.get('content', []):
        if block.get('type') == 'text':
            text = block['text'].strip()
            m = re.search(r'\{[^{}]+\}', text)
            if m:
                print(m.group(0))
                sys.exit(0)
    sys.exit(1)
except Exception:
    sys.exit(1)
" <<< "$LLM_RESPONSE" 2>/dev/null || true)

if [[ -z "$JSON_BLOCK" ]]; then
  echo "ADVERTENCIA: respuesta LLM no parseable — gate omitido." >&2
  exit 0
fi

OK=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print('true' if d.get('ok') else 'false')
except Exception:
    print('unknown')
" "$JSON_BLOCK" 2>/dev/null || echo "unknown")

REASON=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get('reason', ''))
except Exception:
    print('')
" "$JSON_BLOCK" 2>/dev/null || true)

if [[ "$OK" == "true" ]]; then
  echo "PR summary OK — revision LLM superada." >&2
  exit 0
elif [[ "$OK" == "false" ]]; then
  echo "BLOQUEADO: .pr-summary.md no supera la revision de calidad." >&2
  echo "" >&2
  echo "  Motivo: ${REASON}" >&2
  echo "" >&2
  printf "  Reescribe '## Qu\u00e9 hace este PR (en lenguaje no t\u00e9cnico)'\n" >&2
  echo "  y vuelve a ejecutar gh pr create." >&2
  exit 2
else
  echo "ADVERTENCIA: resultado LLM ambiguo — gate omitido." >&2
  exit 0
fi
