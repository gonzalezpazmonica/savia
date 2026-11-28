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
#
# ── Alcance y amenaza ────────────────────────────────────────────────────────
# Decisión de la operadora, 2026-11-28 (pregunta interactiva): «Delimitar el alcance
# (Recommended)». Este comprobador detecta configuraciones ACCIDENTALES (un guard retirado
# de BEFORE_GUARDS, un import huérfano, un comentario que aparenta cableado). NO es una
# defensa adversaria: quien puede escribir savia-foundation.ts o lib/before-guards.ts puede
# quitar los guards sin más. El contrato es: errores plausibles + fallo cerrado ante lo
# ambiguo (checks 6 y 7: forma canónica estricta; cualquier duda = inactivo).
# Límites conocidos, documentados y no perseguidos:
#   - «usa BEFORE_GUARDS» es heurístico: no se demuestra que la lista llegue a ejecutarse.
#   - Sombreado (`(BEFORE_GUARDS) => ...`) y código muerto (`if (false) ...`) lo satisfacen.
#   - runGuardsOnVariants se identifica por nombre: una función local homónima también vale.
#   - Construcciones deliberadamente ofuscadas o sabotaje semántico arbitrario (el escáner
#     no es un parser de JS completo) quedan fuera del contrato.

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
# «Cableado» = FORMA CANÓNICA ESTRICTA, fallo cerrado ante cualquier desviación:
#  - before-guards.ts: línea `export const BEFORE_GUARDS = [`, después solo líneas
#    `<espacios>id,` (comentarios y líneas vacías aparte) y cierre `]` o `] as const`
#    con `;` opcional y nada más; cada id importado en ese fichero con una línea
#    `import { id } from "../guards/x.ts";` al principio de línea.
#  - savia-foundation.ts: línea `import { BEFORE_GUARDS } from "./lib/before-guards(.ts)";`
#    al principio de línea y en estado «código», y un uso fuera de comentarios, cadenas
#    y `typeof BEFORE_GUARDS`.
# Un guard importado o listado en otro array no protege nada.
# Ambiguo = inactivo: `${` dentro de un template o `/` en posición de operando (posible
# regex) en cualquiera de los dos ficheros, comentarios o cadenas sin cierre, sin python3.
# Cualquier terminador de línea que no sea \n o \r\n, o un `\` fuera de cadenas, es ambiguo.
# Toda `/` fuera de comentario/cadena que no siga a [A-Za-z0-9_$)\] (o siga a una palabra
# reservada de JS) es ambigua. Mutar o reasignar BEFORE_GUARDS en la fundación se rechaza.
# Ambiguo también: `#!` al inicio, `<!--`/`-->` o cualquier no ASCII fuera de comentarios y
# cadenas, ficheros de más de 200 kB. BEFORE_GUARDS solo puede usarse como primer argumento
# de runGuardsOnVariants( (ni spread, ni copia, ni Array.prototype.x.call).
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
import unicodedata
from pathlib import Path


JS_WORDS = frozenset("""await break case catch class const continue debugger default delete do else
enum export extends false finally for function if import in instanceof new null return super
switch this throw true try typeof var void while with yield let static implements interface
package private protected public of async get set""".split())


def read_src(path):
    """Texto del fichero; terminador de línea distinto de \n o \r\n = ambiguo (JS los
    cuenta: U+2028, U+2029; un \r suelto también)."""
    raw = Path(path).read_bytes()
    if len(raw) > 200000:  # tope: el análisis es O(n²) en el peor caso; ambiguo = inactivo
        raise ValueError("fichero demasiado grande")
    text = raw.decode("utf-8").replace("\r\n", "\n")
    if text[:1] == "\ufeff":
        text = text[1:]
    # Control ASCII (salvo \t y \n) en cualquier parte: Python los trata como espacio
    # (split/strip/\s) y JS no.
    if any((ord(ch) < 32 and ch not in "\t\n") or ord(ch) == 127 for ch in text):
        raise ValueError("carácter de control")
    if text.startswith("#!"):
        raise ValueError("shebang")
    if any(ch in text for ch in ("\r", "\u2028", "\u2029", "\x85")):
        raise ValueError("terminador de línea no estándar")
    # BOM o cualquier carácter de formato Unicode (Cf) fuera de la posición 0: ambiguo.
    if any(unicodedata.category(ch) == "Cf" for ch in text[1:]):
        raise ValueError("carácter de formato Unicode")
    return text


def _tail(out, size=256):
    acc, n = [], 0
    for item in reversed(out):
        acc.append(item)
        n += len(item)
        if n >= size and item.strip():
            break
    return "".join(reversed(acc))


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
                if c != "`" and (src[j] == "\n" or src[j:j + 2] == "\\\n"):
                    raise ValueError("cadena simple con salto de línea")
                j += 2 if src[j] == "\\" else 1
            if j >= n:
                raise ValueError("cadena sin cierre")
            out.append(c + "".join(ch if ch == "\n" else " " for ch in src[i + 1:j]) + c)
            i = j + 1
        elif c == "/":
            # Regla general: una `/` solo es división si va justo tras [A-Za-z0-9_$)\]]
            # (ignorando espacios) y, si es un identificador, no es palabra reservada.
            tail = _tail(out).rstrip()
            word = re.search(r"(?a)[A-Za-z0-9_$]+$", tail)
            if not tail or tail[-1] not in ")]" and not word:
                raise ValueError("posible literal regex")
            if word and word.group(0) in JS_WORDS:
                raise ValueError("barra tras palabra reservada")
            # `break etiqueta` / `continue etiqueta` + salto de línea (ASI): la barra abre una regex.
            if word and re.search(r"(?a)\b(?:break|continue)\s+$", tail[:word.start()]):
                raise ValueError("barra tras etiqueta de break/continue")
            if tail[-1] == ")" and after_paren_is_regex("".join(out).rstrip()):
                raise ValueError("posible regex tras paréntesis")
            out.append(c)
            i += 1
        else:
            out.append(c)
            i += 1
    res = "".join(out)
    if "\\" in res:
        raise ValueError("escape fuera de cadenas")
    if not res.isascii():
        raise ValueError("carácter no ASCII fuera de comentarios y cadenas")
    if "<!--" in res or "-->" in res:
        raise ValueError("comentario HTML")
    return res


def after_paren_is_regex(out):
    """`out` termina en `)`: busca el `(` que le corresponde y mira la palabra anterior."""
    depth = 0
    for k in range(len(out) - 1, -1, -1):
        if out[k] == ")":
            depth += 1
        elif out[k] == "(":
            depth -= 1
            if depth == 0:
                before = "".join(out[:k]).rstrip()
                word = re.search(r"(?a)[A-Za-z_$][\w$]*$", before)
                if word and word.group(0) == "await":  # for await (...)
                    before = before[:word.start()].rstrip()
                    word = re.search(r"(?a)[A-Za-z_$][\w$]*$", before)
                    return bool(word and word.group(0) == "for")
                return bool(word and word.group(0) in ("if", "while", "for", "with"))
    return True


IDENT = r"[A-Za-z_$][\w$]*"


def canonical_list(blank_lines):
    """Forma canónica estricta del bloque BEFORE_GUARDS: apertura exacta, líneas
    `<espacios>id,` (comentarios ya vaciados) y cierre `]`/`] as const` con `;` opcional."""
    opens = [k for k, ln in enumerate(blank_lines) if "BEFORE_GUARDS" in ln]
    if len(opens) != 1 or blank_lines[opens[0]].rstrip() != "export const BEFORE_GUARDS = [":
        raise ValueError("apertura no canónica")
    # Tras el cierre, nada. Antes de la lista, nada que reabra el módulo (import * / import()
    # / require / export): una autoimportación podría mutar la lista. El resto de líneas
    # ajenas se juzga por guard (el import canónico del guard concreto).
    for ln in blank_lines[:opens[0]]:
        if re.search(r"(?a)\bimport\s*(?:\*|\()|\brequire\s*\(|\bexport\b", ln):
            raise ValueError("referencia al módulo antes de la lista")
    ids = []
    for k in range(opens[0] + 1, len(blank_lines)):
        ln = blank_lines[k]
        if re.fullmatch(r"(?a)\s*", ln):
            continue
        m = re.fullmatch(r"(?a)\s*(" + IDENT + r")\s*,\s*", ln)
        if m:
            ids.append(m.group(1))
            continue
        if re.fullmatch(r"(?a)\](?: as const)?;?\s*", ln):
            if ";" not in ln:
                # Sin `;` la sentencia puede continuar en la línea siguiente (ASI): la
                # siguiente línea de código debe empezar por un identificador que no sea
                # un operador (`.filter`, `[0]`, `(`, `in`, `instanceof`, `as`...).
                nxt = next((r.lstrip() for r in blank_lines[k + 1:] if r.strip()), "")
                if nxt and not re.match(r"(?a)(?!(?:instanceof|in|as|satisfies)(?![\w$]))[A-Za-z_$]", nxt):
                    raise ValueError("el cierre de la lista continúa en la línea siguiente")
            return ids
        raise ValueError("línea no canónica en la lista")
    raise ValueError("lista sin cierre")


foundation, guards_file, guard = sys.argv[1:4]
try:
    g_orig = read_src(guards_file).split("\n")
    g_blank = scan("\n".join(g_orig)).split("\n")
    if guard not in canonical_list(g_blank):
        sys.exit(1)
    # El guard debe estar importado en el mismo fichero con una línea canónica.
    kebab = re.sub(r"(?a)(?<!^)([A-Z])", lambda m: "-" + m.group(1).lower(), guard[0].lower() + guard[1:])
    imp_g = re.compile(r"(?a)import \{ " + re.escape(guard) + r" \} from \"\.\./guards/" + re.escape(kebab) + r"\.ts\";\s*(?://.*)?")
    if sum(1 for o, b in zip(g_orig, g_blank)
           if re.fullmatch(r"(?a)import \{ " + re.escape(guard) + r" \} from \"\s*\";\s*", b)
           and imp_g.fullmatch(o)) != 1:
        sys.exit(1)

    f_orig = read_src(foundation).split("\n")
    f_blank = scan("\n".join(f_orig)).split("\n")
    # La línea del import se localiza sobre el texto con cadenas vaciadas (estado «código»)
    # y el especificador se lee del original en esa misma línea.
    imp_f = re.compile(r"(?a)import \{ BEFORE_GUARDS \} from \"\./lib/before-guards(?:\.ts)?\";\s*(?://.*)?")
    hits = [k for k, (o, b) in enumerate(zip(f_orig, f_blank))
            if re.fullmatch(r"(?a)import \{ BEFORE_GUARDS \} from \"\s*\";\s*", b) and imp_f.fullmatch(o)]
    if len(hits) != 1:
        sys.exit(1)
    body = "\n".join("" if k == hits[0] else ln for k, ln in enumerate(f_blank))
    # Ninguna otra referencia al módulo de la lista: import * / import() / require(, ni una
    # cadena de código que nombre before-guards (los comentarios se admiten).
    if re.search(r"(?a)\bimport\s*(?:\*|\()|\brequire\s*\(", body):
        sys.exit(1)
    for k, (o, b) in enumerate(zip(f_orig, f_blank)):
        if k != hits[0] and "before-guards" in o and re.search(r"[\"'`]", b):
            sys.exit(1)
    B = r"(?<![\w$])BEFORE_GUARDS(?![\w$])"
    if re.search(r"(?a)" + B + r"\s*(?:\?\.|\.|\[|=(?!=))", body):
        sys.exit(1)
    if re.search(r"(?a)\b(?:const|let|var|function|class)\s+BEFORE_GUARDS(?![\w$])", body):
        sys.exit(1)
    body = re.sub(r"(?a)(?<![\w$])typeof\s+BEFORE_GUARDS(?![\w$])", " ", body)
    uses = re.findall(r"(?a)" + B + r"(?!\s*:)", body)
    ok_uses = re.findall(r"(?a)(?<![\w$.])runGuardsOnVariants\(\s*BEFORE_GUARDS(?![\w$])\s*[,)]", body)
    if not uses or len(uses) != len(ok_uses):
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
