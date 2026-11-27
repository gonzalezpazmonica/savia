#!/usr/bin/env bash
# savia-shield-check.sh — SPEC-OC-01
set -uo pipefail
#
# Verifica el estado del Savia Shield para sesiones OpenCode.
# Detecta si los plugins de sovereignty están activos, que el hook
# context-sanitize-input.sh existe, y que block-credential-leak está
# registrado en la configuración de plugins.
#
# Output (--json): JSON a stdout
#   {"shield_status":"active|partial|inactive","components":[...],"missing":[...]}
#
# Exit codes:
#   0 — shield active (all components found)
#   1 — shield partial (some components missing)
#   2 — shield inactive (critical components missing)
#
# Usage:
#   bash scripts/savia-shield-check.sh
#   bash scripts/savia-shield-check.sh --json
#
# Reference: SPEC-OC-01, docs/rules/domain/savia-shield-opencode.md

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS_CANDIDATE="${SAVIA_WORKSPACE_DIR:-${CLAUDE_PROJECT_DIR:-${OPENCODE_PROJECT_DIR:-"$SCRIPT_DIR/.."}}}"
if ! WORKSPACE_DIR="$(cd "$WS_CANDIDATE" 2>/dev/null && pwd)" || [[ -z "$WORKSPACE_DIR" ]]; then
  echo "ERROR: workspace directory not found: $WS_CANDIDATE" >&2
  exit 2
fi

JSON_MODE=0
[[ "${1:-}" == "--json" ]] && JSON_MODE=1

# ── Component definitions ─────────────────────────────────────────────────────

declare -a COMPONENTS=()
declare -a MISSING=()

check_component() {
  local name="$1" path="$2" critical="${3:-false}"
  if [[ -f "$path" ]]; then
    COMPONENTS+=("$name")
  else
    MISSING+=("$name")
  fi
}

# ── Check 1: data-sovereignty-gate.ts ────────────────────────────────────────
check_component \
  "data-sovereignty-gate" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/data-sovereignty-gate.ts" \
  "true"

# ── Check 2: data-sovereignty-audit.ts ───────────────────────────────────────
check_component \
  "data-sovereignty-audit" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/data-sovereignty-audit.ts" \
  "true"

# ── Check 3: sovereignty-patterns.ts (lib) ───────────────────────────────────
check_component \
  "sovereignty-patterns" \
  "$WORKSPACE_DIR/.opencode/plugins/lib/sovereignty-patterns.ts" \
  "true"

# ── Check 4: block-credential-leak.ts ────────────────────────────────────────
check_component \
  "block-credential-leak" \
  "$WORKSPACE_DIR/.opencode/plugins/guards/block-credential-leak.ts" \
  "true"

# ── Check 5: context-sanitize-input.sh (OpenCode hook) ───────────────────────
check_component \
  "context-sanitize-input" \
  "$WORKSPACE_DIR/.opencode/hooks/context-sanitize-input.sh" \
  "true"

# ── Check 6: savia-foundation.ts wires the guards ────────────────────────────
# «Cableado» (fallo cerrado ante cualquier duda): el guard es elemento (identificador
# desnudo) del array BEFORE_GUARDS de lib/before-guards.ts, acotado a ese bloque y sin
# comentarios ni cadenas, Y savia-foundation.ts importa BEFORE_GUARDS (sin alias ni
# `import type`) desde ./lib/before-guards(.ts) y lo usa fuera de comentarios y cadenas.
# Un guard importado o listado en otro array no protege nada.
# Ambiguo = inactivo: `${` dentro de un template o `/` en posición de operando (posible
# regex) en cualquiera de los dos ficheros, comentarios o cadenas sin cierre, sin python3.
# LÍMITE: «usa BEFORE_GUARDS» es heurístico (identificador fuera de comentarios y cadenas).
# Un uso sombreado (`(BEFORE_GUARDS) => ...`) o código muerto (`if (false) BEFORE_GUARDS`)
# lo satisface; no se puede demostrar estáticamente que la lista llegue a ejecutarse.
FOUNDATION="$WORKSPACE_DIR/.opencode/plugins/savia-foundation.ts"
BEFORE_GUARDS_FILE="$WORKSPACE_DIR/.opencode/plugins/lib/before-guards.ts"
guard_registered() {
  [[ -f "$FOUNDATION" && -f "$BEFORE_GUARDS_FILE" ]] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 -I - "$FOUNDATION" "$BEFORE_GUARDS_FILE" "$1" 2>/dev/null <<'PY'
import re
import sys
from pathlib import Path


REGEX_PREV = set("(,=:[!&|?{};+-*%<>~^")
REGEX_WORDS = ("return", "typeof", "case", "in", "of", "void", "delete", "throw", "else", "do")


def scan(src):
    """Texto de la misma longitud: comentarios y contenido de cadenas pasan a espacios
    (se conservan saltos de línea y comillas). Ambiguo (ValueError): `${` en un template,
    `/` en posición de operando (posible regex), comentario o cadena sin cierre."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                out.append(" ")
                i += 1
        elif two == "/*":
            j = src.find("*/", i + 2)
            if j < 0:
                raise ValueError("comentario sin cierre")
            out.append("".join(ch if ch == "\n" else " " for ch in src[i:j + 2]))
            i = j + 2
        elif c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                if c == "`" and src[j:j + 2] == "${":
                    raise ValueError("interpolación en template")
                j += 2 if src[j] == "\\" else 1
            if j >= n:
                raise ValueError("cadena sin cierre")
            out.append(c + "".join(ch if ch == "\n" else " " for ch in src[i + 1:j]) + c)
            i = j + 1
        elif c == "/":
            prev = "".join(out).rstrip()
            word = re.search(r"[A-Za-z_$][\w$]*$", prev)
            if not prev or prev[-1] in REGEX_PREV or (word and word.group(0) in REGEX_WORDS):
                raise ValueError("posible literal regex")
            out.append(c)
            i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def guards_in_list(src):
    decl = list(re.finditer(r"\bBEFORE_GUARDS\b", src))
    m = re.search(r"\bexport\s+const\s+BEFORE_GUARDS\s*(?::[^=;]*)?=\s*\[", src)
    if not m or len(decl) != 1:
        raise ValueError("BEFORE_GUARDS ausente o ambigua")
    depth, j, start = 1, m.end(), m.end()
    items, buf = [], []
    while j < len(src) and depth:
        ch = src[j]
        if ch in "[({":
            depth += 1
        elif ch in "])}":
            depth -= 1
            if depth == 0:
                break
        if ch == "," and depth == 1:
            items.append("".join(buf))
            buf = []
        else:
            buf.append(ch)
        j += 1
    if depth:
        raise ValueError("lista sin cierre")
    items.append("".join(buf))
    return {t.strip() for t in items if re.fullmatch(r"\s*[A-Za-z_$][\w$]*\s*", t)}


foundation, guards_file, guard = sys.argv[1:4]
try:
    if guard not in guards_in_list(scan(Path(guards_file).read_text())):
        sys.exit(1)
    orig = Path(foundation).read_text()
    blank = scan(orig)
    # El import se localiza sobre el texto con cadenas vaciadas (un import escrito dentro
    # de una cadena no cuenta) y el especificador se lee del original en esas posiciones.
    imp = re.compile(r"(?<![\w$.])import\s*\{([^}]*)\}\s*from\s*([\"'])\s*\2")
    spec = re.compile(r"from\s*([\"'])\./lib/before-guards(?:\.ts)?\1\Z")
    imports = [m for m in imp.finditer(blank)
               if any(t.strip() == "BEFORE_GUARDS" for t in m.group(1).split(","))
               and spec.search(orig[m.start():m.end()])]
    if len(imports) != 1:
        sys.exit(1)
    a, b = imports[0].span()
    body = blank[:a] + " " * (b - a) + blank[b:]
    if re.search(r"\b(?:const|let|var|function|class)\s+BEFORE_GUARDS\b", body):
        sys.exit(1)
    if not re.search(r"(?<![\w$.])BEFORE_GUARDS\b(?!\s*:)", body):
        sys.exit(1)
except Exception:
    sys.exit(1)
sys.exit(0)
PY
}
if guard_registered "dataSovereigntyGate"; then
  COMPONENTS+=("savia-foundation-wired")
else
  MISSING+=("savia-foundation-wired")
fi

# ── Check 7: block-credential-leak wired (mismo criterio que el check 6) ─────
if guard_registered "blockCredentialLeak"; then
  COMPONENTS+=("block-credential-leak-wired")
else
  MISSING+=("block-credential-leak-wired")
fi

# ── Check 8: savia-shield-opencode.md documentation ─────────────────────────
check_component \
  "savia-shield-opencode-doc" \
  "$WORKSPACE_DIR/docs/rules/domain/savia-shield-opencode.md" \
  "false"

# ── Determine shield status ───────────────────────────────────────────────────

CRITICAL_COMPONENTS=(
  "data-sovereignty-gate"
  "data-sovereignty-audit"
  "sovereignty-patterns"
  "block-credential-leak"
  "context-sanitize-input"
  "savia-foundation-wired"
  "block-credential-leak-wired"
)

CRITICAL_MISSING=0
for c in "${CRITICAL_COMPONENTS[@]}"; do
  found=0
  for comp in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    [[ "$comp" == "$c" ]] && found=1 && break
  done
  (( found == 0 )) && CRITICAL_MISSING=$((CRITICAL_MISSING + 1))
done

if (( CRITICAL_MISSING == 0 && ${#MISSING[@]} == 0 )); then
  STATUS="active"
  EXIT_CODE=0
elif (( CRITICAL_MISSING == 0 )); then
  STATUS="partial"
  EXIT_CODE=1
else
  STATUS="inactive"
  EXIT_CODE=2
fi

# ── Output ────────────────────────────────────────────────────────────────────

if (( JSON_MODE == 1 )); then
  # Build JSON arrays
  comp_json="["
  first=1
  for c in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    (( first )) || comp_json+=","
    comp_json+="\"$c\""
    first=0
  done
  comp_json+="]"

  miss_json="["
  first=1
  for m in ${MISSING[@]+"${MISSING[@]}"}; do
    (( first )) || miss_json+=","
    miss_json+="\"$m\""
    first=0
  done
  miss_json+="]"

  printf '{"shield_status":"%s","components":%s,"missing":%s}\n' \
    "$STATUS" "$comp_json" "$miss_json"
else
  printf 'Savia Shield Status: %s\n' "$STATUS"
  printf 'Components found (%d):\n' "${#COMPONENTS[@]}"
  for c in ${COMPONENTS[@]+"${COMPONENTS[@]}"}; do
    printf '  + %s\n' "$c"
  done
  if (( ${#MISSING[@]} > 0 )); then
    printf 'Missing (%d):\n' "${#MISSING[@]}"
    for m in "${MISSING[@]}"; do
      printf '  - %s\n' "$m"
    done
  fi
fi

exit "$EXIT_CODE"
