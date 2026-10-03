#!/usr/bin/env bash
# scrapling-fetch.sh — SE-061 Slice 2 adaptive fetch wrapper.
#
# Wrapper estable sobre Scrapling (parser-only, sin Chromium required).
# Con fallback automatico a curl cuando Scrapling no esta instalado.
#
# Usage:
#   scrapling-fetch.sh URL [SELECTOR]
#   scrapling-fetch.sh URL --json
#   scrapling-fetch.sh URL --stealth
#   scrapling-fetch.sh URL --timeout 30
#   scrapling-fetch.sh URL --selector "article.content"
#   scrapling-fetch.sh URL --max-bytes 1048576
#   scrapling-fetch.sh http://127.0.0.1:8080/ --allow-private
#
# Output (default):
#   TITLE: ...
#   STATUS: 200
#   URL_FINAL: https://...
#   BACKEND: scrapling|curl
#   [ERROR: ...]            (solo si falla)
#   ---
#   <extracted text>
#
# Output (--json), tambien en errores de red, HTTP o politica:
#   {"status":200,"title":"...","url_final":"...","text":"...",
#    "text_truncated":false,"error":null,"backend":"scrapling|curl"}
#
# Exit codes:
#   0 — OK (respuesta 2xx)
#   1 — fetch error (red, timeout, 3xx sin destino, 4xx, 5xx, > --max-bytes,
#       demasiadas redirecciones, sin backend disponible)
#   2 — usage error
#   3 — destino bloqueado por la politica anti-SSRF (ver abajo)
#
# Politica de destinos (SE-376, calibracion lightpanda-browser):
#   - Solo http/https, tambien en cada salto de redireccion.
#   - Link-local (169.254.0.0/16, fe80::/10: metadatos cloud), multicast,
#     reservadas y 0.0.0.0: bloqueadas SIEMPRE.
#   - Loopback, redes privadas y demas no globales: bloqueadas salvo
#     --allow-private.
#   - Con curl se valida cada salto y se fija la IP resuelta (--resolve)
#     para que no cambie entre la validacion y la conexion.
#   - Con scrapling las redirecciones las sigue la libreria: se validan la
#     URL inicial y la final, y si la final es interna se descarta el
#     contenido (exit 3). La peticion intermedia ya se habra hecho.
#
# Ref: SE-061, docs/propuestas/SE-061-scrapling-research-backend.md
# Safety: set -uo pipefail. Egress limitado a URL del usuario.

set -uo pipefail

URL=""
SELECTOR=""
JSON=0
STEALTH=0
TIMEOUT=20
MAX_BYTES=5242880
ALLOW_PRIVATE=0
MAX_REDIRS=5
BACKEND=""

usage() {
  cat <<EOF
Usage:
  $0 URL [--selector CSS] [--json] [--stealth] [--timeout SEC]
         [--max-bytes N] [--allow-private]

Fetch URL with Scrapling (adaptive parser). Falls back to curl if unavailable.

Arguments:
  URL                    Required. Must be http(s)://
  --selector CSS         Extract only matching nodes (scrapling only; curl
                         ignores it and warns on stderr)
  --json                 Machine-readable JSON output
  --stealth              Request stealth mode (scrapling only, no-op for curl)
  --timeout SEC          Max total fetch time in seconds, >= 1 (default 20)
  --max-bytes N          Abort if the body exceeds N bytes (default 5242880)
  --allow-private        Allow loopback/private destinations (never metadata)

Exit codes: 0 OK (2xx) | 1 fetch/HTTP error | 2 usage | 3 blocked destination
Ref: SE-061 Slice 2.
EOF
}

need_value() {
  if [[ $# -lt 2 || -z "$2" ]]; then
    echo "ERROR: $1 requiere un valor" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --selector) need_value "$@"; SELECTOR="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    --stealth) STEALTH=1; shift ;;
    --timeout) need_value "$@"; TIMEOUT="$2"; shift 2 ;;
    --max-bytes) need_value "$@"; MAX_BYTES="$2"; shift 2 ;;
    --allow-private) ALLOW_PRIVATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
    *)
      if [[ -z "$URL" ]]; then URL="$1"
      elif [[ -z "$SELECTOR" ]]; then SELECTOR="$1"
      else echo "ERROR: unexpected arg '$1'" >&2; exit 2
      fi
      shift ;;
  esac
done

if [[ -z "$URL" ]]; then
  echo "ERROR: URL required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$URL" =~ ^https?:// ]]; then
  echo "ERROR: URL must start with http:// or https://" >&2
  exit 2
fi

# 0 no es valido: curl lo interpreta como "sin limite".
if ! [[ "$TIMEOUT" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --timeout must be a positive integer (>= 1)" >&2
  exit 2
fi

if ! [[ "$MAX_BYTES" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: --max-bytes must be a positive integer" >&2
  exit 2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 requerido (validacion de destino y salida JSON)" >&2
  exit 1
fi

# Detect backend: scrapling if installed, else curl
if python3 -c "import scrapling" 2>/dev/null; then
  BACKEND="scrapling"
elif command -v curl >/dev/null 2>&1; then
  BACKEND="curl"
else
  echo "ERROR: no hay backend de fetch: ni scrapling (python) ni curl instalados" >&2
  exit 1
fi

WORK=$(mktemp -d 2>/dev/null) || { echo "ERROR: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT
RESULT="$WORK/result.json"

# Helper Python: validacion de destino, extraccion HTML y salida.
# El cuerpo viaja por ficheros, nunca por argv (limite de 128 KB por argumento).
read -r -d '' PY_HELPER <<'PY' || true  # read -d '' devuelve 1 al llegar a EOF
import codecs, ipaddress, json, os, re, socket, sys, urllib.parse
from html.parser import HTMLParser

TEXT_MAX = 500000
BLOCKED = "destino bloqueado"


def check(url, allow_private):
    """Imprime 'host port ip' o sale con 3 (bloqueado) / 1 (no resuelve)."""
    p = urllib.parse.urlsplit(url)
    if p.scheme not in ("http", "https"):
        print("%s: esquema no permitido '%s' en %s" % (BLOCKED, p.scheme, url), file=sys.stderr)
        sys.exit(3)
    host = p.hostname
    if not host:
        print("%s: URL sin host: %s" % (BLOCKED, url), file=sys.stderr)
        sys.exit(3)
    try:
        port = p.port or (443 if p.scheme == "https" else 80)
    except ValueError:
        print("%s: puerto invalido en %s" % (BLOCKED, url), file=sys.stderr)
        sys.exit(3)
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except (socket.gaierror, UnicodeError) as e:
        print("no se pudo resolver %s: %s" % (host, e), file=sys.stderr)
        sys.exit(1)
    first = None
    for info in infos:
        raw = info[4][0]
        ip = ipaddress.ip_address(raw.split("%")[0])
        if ip.version == 6 and ip.ipv4_mapped:
            ip = ip.ipv4_mapped
        if ip.is_link_local or ip.is_multicast or ip.is_unspecified or ip.is_reserved:
            print("%s: %s resuelve a %s (link-local/metadatos o reservada)" % (BLOCKED, host, ip), file=sys.stderr)
            sys.exit(3)
        if not ip.is_global and not allow_private:
            print("%s: %s resuelve a %s (red interna); usa --allow-private si es intencionado" % (BLOCKED, host, ip), file=sys.stderr)
            sys.exit(3)
        if first is None:
            first = raw
    print(host, port, first)


class _Extractor(HTMLParser):
    SKIP = {"script", "style", "noscript", "template"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.skip = 0
        self.in_title = False
        self.title = []
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif tag == "title":
            self.in_title = True

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif tag == "title":
            self.in_title = False

    def handle_data(self, data):
        if self.in_title:
            self.title.append(data)
        elif not self.skip:
            chunk = " ".join(data.split())
            if chunk:
                self.parts.append(chunk)


def _charset(ctype, raw):
    cands = []
    m = re.search(r"charset=([\w.:-]+)", ctype or "", re.I)
    if m:
        cands.append(m.group(1))
    m = re.search(rb"<meta[^>]+charset=[\"']?([\w.:-]+)", raw[:4096], re.I)
    if m:
        cands.append(m.group(1).decode("ascii", "replace"))
    for c in cands:
        try:
            return codecs.lookup(c).name
        except LookupError:
            print("WARN: charset desconocido '%s', se prueba el siguiente" % c, file=sys.stderr)
    return "utf-8"


def extract(body_file, ctype, status, url_final, out):
    with open(body_file, "rb") as fh:
        raw = fh.read()
    doc = raw.decode(_charset(ctype, raw), errors="replace")
    title, text = "", doc
    if "html" in (ctype or "").lower() or re.search(r"<(html|title|body|p)\b", doc[:4096], re.I):
        ex = _Extractor()
        ex.feed(doc)
        ex.close()
        title = " ".join("".join(ex.title).split())
        text = "\n".join(ex.parts)
    res = {"status": int(status or 0), "title": title[:200], "url_final": url_final, "text": text}
    with open(out, "w", encoding="utf-8") as fh:
        json.dump(res, fh, ensure_ascii=False)


def emit(result_file, backend, error, as_json, url, status):
    d = {"status": int(status or 0), "title": "", "url_final": url, "text": ""}
    if os.path.exists(result_file) and os.path.getsize(result_file) > 0:
        with open(result_file, encoding="utf-8") as fh:
            d.update(json.load(fh))
    if error.startswith(BLOCKED):
        d["title"], d["text"] = "", ""
    text = d.get("text") or ""
    d["text_truncated"] = len(text) > TEXT_MAX
    d["text"] = text[:TEXT_MAX]
    d["error"] = error or None
    d["backend"] = backend
    if as_json == "1":
        print(json.dumps(d, ensure_ascii=False))
        return
    print("TITLE: %s" % d["title"])
    print("STATUS: %s" % d["status"])
    print("URL_FINAL: %s" % d["url_final"])
    print("BACKEND: %s" % backend)
    if error:
        print("ERROR: %s" % error)
    print("---")
    print(d["text"])


cmd = sys.argv[1]
if cmd == "check":
    check(sys.argv[2], sys.argv[3] == "1")
elif cmd == "extract":
    extract(*sys.argv[2:7])
elif cmd == "emit":
    emit(*sys.argv[2:8])
PY

py() { python3 -c "$PY_HELPER" "$@"; }

FETCH_ERROR=""
STATUS=0
URL_FINAL="$URL"
CHECK_OUT=""

# Valida un destino; deja "host port ip" en CHECK_OUT o el motivo en FETCH_ERROR.
check_target() {
  local rc
  CHECK_OUT=$(py check "$1" "$ALLOW_PRIVATE" 2>"$WORK/check.err"); rc=$?
  if [[ $rc -ne 0 ]]; then
    FETCH_ERROR=$(<"$WORK/check.err")
    [[ -n "$FETCH_ERROR" ]] || FETCH_ERROR="validacion de destino fallida para $1"
  fi
  return $rc
}

# Exit 4: scrapling importable pero sin Fetcher (instalacion rota).
fetch_with_scrapling() {
  local py_script rc meta
  read -r -d '' py_script <<'PY' || true  # EOF esperado
import json, os, sys
url = os.environ.get("FETCH_URL", "")
selector = os.environ.get("FETCH_SELECTOR", "")
stealth = os.environ.get("FETCH_STEALTH", "0") == "1"
timeout = int(os.environ.get("FETCH_TIMEOUT", "20"))
out = os.environ["FETCH_OUT"]
try:
    from scrapling import Fetcher
except ImportError as e:
    print("scrapling sin Fetcher utilizable: %s" % e, file=sys.stderr)
    sys.exit(4)
try:
    f = Fetcher.get(url, timeout=timeout, stealth=stealth) if stealth else Fetcher.get(url, timeout=timeout)
    status = int(getattr(f, "status", 0) or 0)
    url_final = getattr(f, "url", url) or url
    title_sel = f.css_first("title")
    title = title_sel.text.strip() if title_sel else ""
    if selector:
        nodes = f.css(selector)
        text = "\n".join(n.text.strip() for n in nodes if n.text)
    else:
        text = f.get_all_text(strip=True)
except Exception as e:  # la libreria propaga errores de red de varios tipos
    print("scrapling: %s: %s" % (type(e).__name__, e), file=sys.stderr)
    sys.exit(1)
with open(out, "w", encoding="utf-8") as fh:
    json.dump({"status": status, "title": title, "url_final": url_final, "text": text or ""}, fh, ensure_ascii=False)
PY
  FETCH_URL="$URL" FETCH_SELECTOR="$SELECTOR" FETCH_STEALTH="$STEALTH" \
    FETCH_TIMEOUT="$TIMEOUT" FETCH_OUT="$RESULT" \
    python3 -c "$py_script" 2>"$WORK/scrapling.err"; rc=$?
  if [[ $rc -ne 0 ]]; then
    FETCH_ERROR=$(<"$WORK/scrapling.err")
    return $rc
  fi
  meta=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("status",0)); print(d.get("url_final",""))' "$RESULT")
  STATUS="${meta%%$'\n'*}"
  URL_FINAL="${meta#*$'\n'}"
  # La libreria sigue redirecciones por su cuenta: validar el destino final.
  check_target "$URL_FINAL" || return $?
  return 0
}

fetch_with_curl() {
  local cur="$URL" hops=0 start=$SECONDS remaining meta rc host port ip
  local body="$WORK/body" ctype="" redirect=""
  if [[ -n "$SELECTOR" ]]; then
    echo "WARN: --selector ignorado con backend curl (solo scrapling lo aplica)" >&2
  fi
  while :; do
    check_target "$cur" || return $?
    read -r host port ip <<<"$CHECK_OUT"
    [[ "$ip" == *:* ]] && ip="[$ip]"
    remaining=$(( TIMEOUT - (SECONDS - start) ))
    if [[ $remaining -lt 1 ]]; then
      FETCH_ERROR="timeout: se agotaron ${TIMEOUT}s"
      return 1
    fi
    : > "$body"
    meta=$(curl -sS --proto '=http,https' --max-redirs 0 \
      --max-time "$remaining" --max-filesize "$MAX_BYTES" \
      --resolve "$host:$port:$ip" \
      -A 'Mozilla/5.0 (compatible; SaviaResearch/1.0)' \
      -o "$body" -w '%{http_code}\n%{content_type}\n%{redirect_url}' \
      "$cur" 2>"$WORK/curl.err"); rc=$?
    URL_FINAL="$cur"
    STATUS="${meta%%$'\n'*}"
    [[ "$STATUS" =~ ^[0-9]+$ ]] || STATUS=0
    case $rc in
      0) ;;
      28) FETCH_ERROR="timeout: sin respuesta completa en ${TIMEOUT}s"; return 1 ;;
      63) FETCH_ERROR="la respuesta supera --max-bytes ($MAX_BYTES bytes)"; return 1 ;;
      *) FETCH_ERROR="curl ($rc): $(<"$WORK/curl.err")"; return 1 ;;
    esac
    meta="${meta#*$'\n'}"
    ctype="${meta%%$'\n'*}"
    redirect="${meta#*$'\n'}"
    if [[ "$STATUS" =~ ^3 && -n "$redirect" ]]; then
      hops=$((hops + 1))
      if [[ $hops -gt $MAX_REDIRS ]]; then
        FETCH_ERROR="demasiadas redirecciones (> $MAX_REDIRS)"
        return 1
      fi
      cur="$redirect"
      continue
    fi
    break
  done
  py extract "$body" "$ctype" "$STATUS" "$URL_FINAL" "$RESULT"
}

EXIT_CODE=0
if [[ "$BACKEND" == "scrapling" ]]; then
  if check_target "$URL"; then
    fetch_with_scrapling || EXIT_CODE=$?
    if [[ $EXIT_CODE -eq 4 ]]; then
      if command -v curl >/dev/null 2>&1; then
        echo "WARN: ${FETCH_ERROR}; fallback a curl" >&2
        BACKEND="curl"
        FETCH_ERROR=""
        EXIT_CODE=0
        fetch_with_curl || EXIT_CODE=$?
      else
        EXIT_CODE=1
      fi
    fi
  else
    EXIT_CODE=$?
  fi
else
  fetch_with_curl || EXIT_CODE=$?
fi

if [[ $EXIT_CODE -eq 0 && ! "$STATUS" =~ ^2[0-9][0-9]$ ]]; then
  FETCH_ERROR="HTTP $STATUS"
  EXIT_CODE=1
fi
if [[ $EXIT_CODE -ne 0 && -z "$FETCH_ERROR" ]]; then
  FETCH_ERROR="fetch fallido (codigo $EXIT_CODE)"
fi
[[ $EXIT_CODE -ne 0 ]] && echo "ERROR: $FETCH_ERROR" >&2

py emit "$RESULT" "$BACKEND" "$FETCH_ERROR" "$JSON" "$URL_FINAL" "$STATUS"

exit $EXIT_CODE
