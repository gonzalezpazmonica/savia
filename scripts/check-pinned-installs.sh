#!/usr/bin/env bash
# check-pinned-installs.sh — SE-465 S5. Falla ante instalaciones sin fijar.
#
# Recorre `*.sh`, `Dockerfile*` y `.github/workflows/*` y reporta, con fichero
# y línea, cada orden que ejecuta código de terceros sin versión ni hash:
#
#   FROM_UNPINNED   FROM sin @sha256:<64 hex> (solo Dockerfile*)
#   PIPE_SHELL      curl/wget canalizado a sh/bash (o bash <(curl ...), sh -c "$(curl ...)")
#   PIPE_PYTHON     curl/wget canalizado a python sin `-c "<literal>"` ni `-m json.tool`
#                   (incluye `python3`, `python3 -` y `python3 /dev/stdin`)
#   NPM_INSTALL     `npm install` sin -g (debe ser `npm ci`)
#   NPM_G_UNPINNED  `npm install -g` con algún paquete sin @versión exacta
#   PIP_NO_HASHES   `pip install` sin --require-hashes
#
# Solo cuenta lo que está en posición de orden (inicio de línea o tras ; && || | ( $( `
# y prefijos como RUN, run:, sudo, then, VAR=x). Comentarios, mensajes de echo y
# patrones entre comillas no se reportan.
#
# Uso:
#   check-pinned-installs.sh [--root DIR] [--exceptions FILE | --no-exceptions] [--summary]
#
# Salida: `ruta:línea: KIND: texto` por hallazgo, y al final una línea
#   SUMMARY G1=n G2=n G4=n G5=n total=n
# Códigos de salida: 0 limpio · 1 hallazgos · 2 error (fichero ilegible, opción
# desconocida, excepción mal formada o sin motivo, ningún fichero que analizar).
# Fail-closed: ante lo que no sabe clasificar (FROM con variable, `npm i -g` sin
# paquete, versión con rango) reporta hallazgo; ante un error no da PASS.
#
# Excepciones: fichero con líneas `ruta :: KIND :: fragmento :: motivo`
# (fragmento = texto contenido en la orden, o `*` para cualquiera de ese KIND en
# ese fichero). El motivo es obligatorio. Una excepción sin motivo es error.
#
# Límites conocidos: análisis textual; una orden dentro de una comilla se ve solo
# en `bash -c "..."`, `sh -c "$(...)"` y `run "..."`. `python -c "..."` multilínea
# se evalúa con la primera línea.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_EXC="$SCRIPT_DIR/pinned-installs-exceptions.txt"

ROOT="$DEFAULT_ROOT"
EXC_FILE="$DEFAULT_EXC"
EXC_EXPLICIT=0
NO_EXC=0

die() { echo "ERROR: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die "--root requiere un valor"; ROOT="$2"; shift 2 ;;
    --exceptions) [ $# -ge 2 ] || die "--exceptions requiere un valor"; EXC_FILE="$2"; EXC_EXPLICIT=1; shift 2 ;;
    --no-exceptions) NO_EXC=1; shift ;;
    --summary) shift ;;
    -h|--help) sed -n '2,36p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
done

[ -d "$ROOT" ] || die "root no es un directorio: $ROOT"
ROOT="$(cd "$ROOT" && pwd)"
command -v awk >/dev/null 2>&1 || die "awk no disponible"

TMP="$(mktemp -d)" || die "mktemp falló"
trap 'rm -rf "$TMP"' EXIT

# --- 1. ficheros a analizar -------------------------------------------------
is_target() {
  case "$1" in
    *.sh|Dockerfile*|*/Dockerfile*|.github/workflows/*|*/.github/workflows/*) return 0 ;;
  esac
  return 1
}

: > "$TMP/files0"
if top="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" && [ "$top" = "$ROOT" ]; then
  git -C "$ROOT" ls-files -z --cached --others --exclude-standard > "$TMP/all0" \
    || die "git ls-files falló en $ROOT"
else
  ( cd "$ROOT" && find . \( -name .git -o -name node_modules -o -name target -o -name .venv \) -prune \
      -o -type f -print0 ) > "$TMP/all0" || die "find falló en $ROOT"
fi
while IFS= read -r -d '' f; do
  f="${f#./}"
  is_target "$f" || continue
  if [ -L "$ROOT/$f" ] && [ ! -e "$ROOT/$f" ]; then continue; fi  # enlace roto
  [ -e "$ROOT/$f" ] || continue                                   # borrado sin commit
  [ -f "$ROOT/$f" ] || continue
  [ -r "$ROOT/$f" ] || die "fichero ilegible: $f"
  printf '%s\0' "$f" >> "$TMP/files0"
done < "$TMP/all0"
[ -s "$TMP/files0" ] || die "ningún fichero que analizar bajo $ROOT"

# --- 2. excepciones ---------------------------------------------------------
KINDS=" FROM_UNPINNED PIPE_SHELL PIPE_PYTHON NPM_INSTALL NPM_G_UNPINNED PIP_NO_HASHES "
: > "$TMP/exc"
if [ "$NO_EXC" -eq 0 ]; then
  if [ ! -f "$EXC_FILE" ]; then
    die "fichero de excepciones no encontrado: $EXC_FILE"
  fi
  [ -r "$EXC_FILE" ] || die "fichero de excepciones ilegible: $EXC_FILE"
  ln=0
  while IFS= read -r raw || [ -n "$raw" ]; do
    ln=$((ln + 1))
    case "$raw" in ''|[[:space:]]*'#'*|'#'*) continue ;; esac
    [ -n "${raw//[[:space:]]/}" ] || continue
    rest="$raw"
    fields=()
    for _ in 1 2 3; do
      case "$rest" in
        *' :: '*) fields+=("${rest%%' :: '*}"); rest="${rest#*' :: '}" ;;
        *) die "$EXC_FILE:$ln: excepción mal formada (ruta :: KIND :: fragmento :: motivo)" ;;
      esac
    done
    fields+=("$rest")
    for i in 0 1 2 3; do
      v="${fields[$i]}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      fields[$i]="$v"
    done
    [ -n "${fields[3]}" ] || die "$EXC_FILE:$ln: excepción sin motivo"
    [ -n "${fields[0]}" ] && [ -n "${fields[1]}" ] && [ -n "${fields[2]}" ] \
      || die "$EXC_FILE:$ln: campos vacíos"
    case "$KINDS" in *" ${fields[1]} "*) ;; *) die "$EXC_FILE:$ln: KIND desconocido: ${fields[1]}" ;; esac
    printf '%s\t%s\t%s\t%s\n' "${fields[0]}" "${fields[1]}" "${fields[2]}" "${fields[3]}" >> "$TMP/exc"
  done < "$EXC_FILE"
fi

# --- 3. análisis ------------------------------------------------------------
cat > "$TMP/analyze.awk" <<'AWK'
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function ltrim(s) { sub(/^[[:space:]]+/, "", s); return s }
function emit(ln, kind, txt) {
  gsub(/\t/, " ", txt)
  printf "%s\t%d\t%s\t%s\n", fname, ln, kind, trim(txt)
}
function strip_comment(s) { sub(/[[:space:]]#([[:space:]].*)?$/, "", s); return s }
function unquote(s) { gsub(/^["']+|["')]+$/, "", s); return s }

# Descompone en órdenes respetando comillas y $( ); rellena cs/ce/cp (inicio, fin, separador).
function scan(s,    len, i, c, nx, sp, top) {
  nc = 0; len = length(s); sp = 0; ctx[0] = "N"
  newcmd(1, len, "^")
  i = 1
  while (i <= len) {
    c = substr(s, i, 1); nx = substr(s, i + 1, 1); top = ctx[sp]
    if (top == "S") { if (c == "'") sp--; i++; continue }
    if (c == "\\") { i += 2; continue }
    if (top == "D") {
      if (c == "\"") sp--
      else if (c == "$" && nx == "(") { endcmd(i - 1); sp++; ctx[sp] = "P"; newcmd(i + 2, len, "("); i++ }
      i++; continue
    }
    if (c == "'") { sp++; ctx[sp] = "S" }
    else if (c == "\"") { sp++; ctx[sp] = "D" }
    else if (c == "`") { endcmd(i - 1); newcmd(i + 1, len, "`") }
    else if (c == "(") { endcmd(i - 1); sp++; ctx[sp] = "P"; newcmd(i + 1, len, "(") }
    else if (c == ")") {
      endcmd(i - 1)
      if (ctx[sp] == "P") sp--; else newcmd(i + 1, len, ")")
    }
    else if (c == ";") { endcmd(i - 1); newcmd(i + 1, len, ";") }
    else if (c == "&" && nx == "&") { endcmd(i - 1); newcmd(i + 2, len, "&&"); i++ }
    else if (c == "|") {
      endcmd(i - 1)
      if (nx == "|") { newcmd(i + 2, len, "||"); i++ } else newcmd(i + 1, len, "|")
    }
    i++
  }
}
function newcmd(st, len, sep) { nc++; cs[nc] = st; ce[nc] = len; cp[nc] = sep; open[nc] = 1 }
function endcmd(pos,    k) {
  for (k = nc; k >= 1; k--) if (open[k]) { ce[k] = pos; open[k] = 0; return }
}

# Quita prefijos de orden (RUN, run:, sudo, VAR=x, then...). Devuelve el resto.
# Si el prefijo abre un literal ejecutable (bash -c "..", run ".."), fija inner.
function norm(t, k,    prev, ch, m) {
  inner = ""
  t = ltrim(t)
  ch = 1
  while (ch) {
    ch = 0
    if (match(t, /^-[[:space:]]+/)) { t = substr(t, RLENGTH + 1); ch = 1 }
    if (match(t, /^run:[[:space:]]*/)) { t = substr(t, RLENGTH + 1); ch = 1; continue }
    if (match(t, /^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'[^']*'|[^[:space:]]*)[[:space:]]*/)) {
      t = substr(t, RLENGTH + 1); ch = 1; continue
    }
    if (match(t, /^(sudo|exec|time|then|do|else|if|elif|while|until|!|\{|nohup|RUN)([[:space:]]+|$)/)) {
      prev = substr(t, 1, RLENGTH); t = substr(t, RLENGTH + 1); ch = 1
      if (prev ~ /^(sudo|RUN)/) {
        while (match(t, /^--?[A-Za-z][-A-Za-z0-9=_,.:\/]*[[:space:]]+/)) t = substr(t, RLENGTH + 1)
      }
      continue
    }
    if (match(t, /^(sudo[[:space:]]+)?(ba|z|da)?sh[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-[A-Za-z]*c[[:space:]]+["']/)) {
      inner = substr(t, RLENGTH + 1); return ""
    }
    if (match(t, /^run[[:space:]]+["']/)) { inner = substr(t, RLENGTH + 1); return "" }
    if (match(t, /^run[[:space:]]+/)) { t = substr(t, RLENGTH + 1); ch = 1; continue }
  }
  return t
}

function is_shell_word(t) {
  return t ~ /^(sudo[[:space:]]+(-[A-Za-z]+[[:space:]]+)*)?(env[[:space:]]+([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*)?(\/[^[:space:]]*\/)?(ba|z|da|k|a)?sh([[:space:]"')]|$)/
}

# ¿es literal el programa de `python -c`? rest = texto desde "-c ..."
function py_literal_c(rest,    q, body, e) {
  sub(/^-c[[:space:]]+/, "", rest)
  q = substr(rest, 1, 1)
  if (q == "'") return 1
  if (q != "\"") return 0
  body = substr(rest, 2)
  e = match(body, /[^\\]"/)
  if (e) body = substr(body, 1, e)
  return (body !~ /[$`]/)
}

# python como consumidor de una descarga: devuelve 1 si ejecuta lo descargado.
function py_executes(t,    rest, f) {
  rest = t
  sub(/^sudo[[:space:]]+(-[A-Za-z]+[[:space:]]+)*/, "", rest)
  if (rest !~ /^(\/[^[:space:]]*\/)?python[0-9.]*([[:space:]]|$|\))/) return -1
  sub(/^(\/[^[:space:]]*\/)?python[0-9.]*[[:space:]]*/, "", rest)
  while (match(rest, /^-[IuBsESO]+[[:space:]]+/)) rest = substr(rest, RLENGTH + 1)
  if (rest ~ /^-m[[:space:]]+json\.tool([[:space:]]|$|\))/) return 0
  if (rest ~ /^-c[[:space:]]+["']/) return py_literal_c(rest) ? 0 : 1
  return 1
}

function npm_pinned(p) {
  return (p ~ /^(@[A-Za-z0-9._~-]+\/)?[A-Za-z0-9._~-]+@[0-9]+\.[0-9]+\.[0-9]+([-+][A-Za-z0-9.+-]*)?$/)
}

function check_npm(t, ln, orig,    seg, n, a, i, g, np, bad, tok) {
  seg = t; sub(/^npm[[:space:]]+(install|i|add)[[:space:]]*/, "", seg)
  n = split(seg, a, /[[:space:]]+/); g = 0; np = 0; bad = 0
  for (i = 1; i <= n; i++) {
    tok = a[i]
    if (tok == "") continue
    if (tok ~ /^[0-9&]*[<>]/) continue
    if (tok == "-g" || tok == "--global" || tok == "--location=global") { g = 1; continue }
    if (tok ~ /^--(prefix|registry|cache|tag|loglevel|userconfig|workspace)$/ || tok == "-w") { i++; continue }
    if (tok ~ /^-/) continue
    tok = unquote(tok)
    if (tok == "") continue
    np++
    if (!npm_pinned(tok)) bad = 1
  }
  if (g) { if (np == 0 || bad) emit(ln, "NPM_G_UNPINNED", orig) }
  else emit(ln, "NPM_INSTALL", orig)
}

function check_from(t, ln, orig,    n, a, i, image, hex) {
  n = split(t, a, /[[:space:]]+/)
  i = 2
  while (i <= n && a[i] ~ /^--/) i++
  image = a[i]
  isal = (tolower(image) in alias)
  if (toupper(a[i + 1]) == "AS" && a[i + 2] != "") alias[tolower(a[i + 2])] = 1
  if (image == "") { emit(ln, "FROM_UNPINNED", orig); return }
  if (isal) return
  if (tolower(image) == "scratch") return
  if (match(image, /@sha256:[0-9a-f]+$/) && (RLENGTH == 72)) return
  emit(ln, "FROM_UNPINNED", orig)
}

function analyze(s, ln, depth,    k, t, chain, sepk, r, kind, cmdtext, prevtxt, nn, save_cs, save_ce, save_cp, save_open, sv, innerline) {
  if (depth > 3) return
  scan(s)
  # copiar para recursión segura
  nn = nc
  for (k = 1; k <= nn; k++) { Cs[depth, k] = cs[k]; Ce[depth, k] = ce[k]; Cp[depth, k] = cp[k] }
  chain = 0
  for (k = 1; k <= nn; k++) {
    cmdtext = substr(s, Cs[depth, k], Ce[depth, k] - Cs[depth, k] + 1)
    sepk = Cp[depth, k]
    t = norm(cmdtext, k)
    if (inner != "") {
      innerline = inner; sub(/["'][[:space:]]*$/, "", innerline)
      analyze(innerline, ln, depth + 1)
      chain = 0
      continue
    }
    if (sepk != "|") chain = 0
    # sh -c "$(curl ...)" y bash <(curl ...)
    if (k < nn && Cp[depth, k + 1] == "(") {
      nxt = norm(substr(s, Cs[depth, k + 1], Ce[depth, k + 1] - Cs[depth, k + 1] + 1), k + 1)
      if (nxt ~ /^(curl|wget)([[:space:]]|$)/ && cmdtext ~ /^[[:space:]]*(sudo[[:space:]]+)?(ba|z|da)?sh[[:space:]]+(-[A-Za-z]+[[:space:]]+)*(<|-[A-Za-z]*c[[:space:]]+["']?\$?)$/)
        emit(ln, "PIPE_SHELL", s)
    }
    if (sepk == "|" && chain) {
      if (is_shell_word(t)) { emit(ln, "PIPE_SHELL", s); chain = 0 }
      else {
        r = py_executes(norm(substr(s, Cs[depth, k]), k))
        if (r == 1) { emit(ln, "PIPE_PYTHON", s); chain = 0 }
      }
    }
    if (t ~ /^(curl|wget)([[:space:]]|$)/) chain = 1
    if (isdock && k == 1 && toupper(substr(t, 1, 5)) == "FROM ") check_from(t, ln, s)
    else if (t ~ /^npm[[:space:]]+(install|i|add)([[:space:]]|$)/) check_npm(t, ln, s)
    else if (t ~ /^(("?\$\{?[A-Za-z_][A-Za-z0-9_]*\}?"?|[^[:space:]]*python[0-9.]*)[[:space:]]+-m[[:space:]]+pip|([^[:space:]]*\/)?pip[0-9.]*|uv[[:space:]]+pip)[[:space:]]+install([[:space:]]|$)/) {
      if (t !~ /--require-hashes/) emit(ln, "PIP_NO_HASHES", s)
    }
  }
}

function finish_line() {
  if (buf != "") analyze(buf, startln, 0)
  buf = ""; cont = 0
}

FNR == 1 {
  if (NR > 1) finish_line()
  fname = FILENAME; base = fname; sub(/.*\//, "", base)
  isdock = (base ~ /^Dockerfile/)
  split("", alias)
  buf = ""; cont = 0
}
{
  line = $0; sub(/\r$/, "", line)
  piece = ltrim(line)
  if (!cont && piece ~ /^#/) next
  piece = strip_comment(piece)
  if (!cont) { startln = FNR; buf = "" }
  c2 = 0
  if (piece ~ /\\[[:space:]]*$/) { sub(/[[:space:]]*\\[[:space:]]*$/, "", piece); c2 = 1 }
  else if (piece ~ /(^|[^|])\|[[:space:]]*$/) { c2 = 1 }
  buf = (buf == "" ? piece : buf " " piece)
  if (c2) { cont = 1; next }
  finish_line()
}
END { finish_line() }
AWK

: > "$TMP/raw"
( cd "$ROOT" && xargs -0 -n 400 awk -f "$TMP/analyze.awk" < "$TMP/files0" ) >> "$TMP/raw" 2>"$TMP/awk.err" \
  || { cat "$TMP/awk.err" >&2; die "el análisis falló (fichero ilegible o error interno)"; }
# xargs -n parte la lista: cada trozo se analiza en su propia ejecución de awk (FNR==1 reinicia el estado)

# --- 4. excepciones aplicadas y salida --------------------------------------
sort -t$'\t' -k1,1 -k2,2n "$TMP/raw" > "$TMP/sorted"
awk -F'\t' -v excf="$TMP/exc" '
  BEGIN {
    while ((getline l < excf) > 0) { n++; split(l, f, "\t"); ep[n]=f[1]; ek[n]=f[2]; ef[n]=f[3]; used[n]=0 }
  }
  {
    skip = 0
    for (i = 1; i <= n; i++)
      if (ep[i] == $1 && ek[i] == $3 && (ef[i] == "*" || index($4, ef[i]) > 0)) { skip = 1; used[i] = 1; break }
    if (skip) { excused++; next }
    printf "%s:%s: %s: %s\n", $1, $2, $3, $4
    total++
    if ($3 == "FROM_UNPINNED") g1++
    else if ($3 == "PIPE_SHELL" || $3 == "PIPE_PYTHON") g2++
    else if ($3 ~ /^NPM_/) g4++
    else if ($3 == "PIP_NO_HASHES") g5++
  }
  END {
    for (i = 1; i <= n; i++) if (!used[i]) printf "AVISO: excepción sin uso: %s :: %s :: %s\n", ep[i], ek[i], ef[i] > "/dev/stderr"
    printf "SUMMARY G1=%d G2=%d G4=%d G5=%d total=%d excepciones_aplicadas=%d\n", g1, g2, g4, g5, total, excused
    exit (total > 0 ? 1 : 0)
  }
' "$TMP/sorted"
exit $?
