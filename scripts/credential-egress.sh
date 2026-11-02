#!/usr/bin/env bash
# credential-egress.sh — SE-353: resolución de credenciales SOLO en el punto de egress.
# set -uo pipefail
#
# Garantiza que el valor real de una credencial NUNCA esté en el contexto del
# modelo. Los scripts usan marcadores opacos (savia:cred:<key>) que este script
# resuelve únicamente en el subproceso hijo que habla con el destino autorizado.
#
# Almacén protegido: ~/.savia/credential-store/keys.json (0600)
# CRIT-001: todo local, sin proveedor cloud.
#
# Modos:
#   store   KEY [-]             → lee el valor por stdin, cifra y almacena (0600).
#                                 El valor por argv se rechaza (visible en ps/historial).
#                                 Los saltos de línea finales se descartan.
#   resolve KEY --dest DEST     → imprime valor real solo si DEST autorizado.
#                                 Sin --dest → REFUSE (fail-closed).
#   run     [--dest DEST] CMD ARG...
#                               → sustituye savia:cred:<key> en args y ejecuta
#                                 en subproceso (valor real nunca se imprime).
#                                 Destino: --dest o el host único de las URLs
#                                 de los args; ambiguo o ausente → REFUSE.
#                                 Salvaguarda de enrutado, no barrera: el hijo
#                                 recibe el valor y puede imprimirlo.
#   status                      → keys registradas (nunca valores)
#   audit   [DIR]               → detecta credenciales en texto plano
#
# Ref: SE-353 — Sentinel Credential Substitution
set -uo pipefail

STORE_DIR="${SAVIA_CRED_STORE_DIR:-$HOME/.savia/credential-store}"
KEYS_FILE="$STORE_DIR/keys.json"
AUTH_DESTS="dev.azure.com github.com api.github.com"

_mk_store() { mkdir -p "$STORE_DIR" 2>/dev/null || { echo "ERROR: no se puede crear $STORE_DIR" >&2; exit 1; }; }

# ── Cifrado AES-256-CBC + HMAC-SHA256 (openssl CLI, sin deps externas) ────────
# Formato: iv:ciphertext:mac  — mac autentica iv+ciphertext.
_derive_key() {
  printf '%s|%s' "$(cat /etc/machine-id 2>/dev/null || hostname)" "$HOME" | sha256sum | cut -d' ' -f1
}

_encrypt() {
  local plain="$1" key iv ciph mac
  key=$(_derive_key)
  iv=$(openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p -c 64)
  ciph=$(printf '%s' "$plain" | openssl enc -aes-256-cbc -K "$key" -iv "$iv" -a -A 2>/dev/null)
  mac=$(printf '%s|%s' "$iv" "$ciph" | openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}')
  printf '%s:%s:%s' "$iv" "$ciph" "$mac"
}

_decrypt() {
  local blob="$1" iv ciph mac key mac_check
  iv="${blob%%:*}"; rest="${blob#*:}"
  ciph="${rest%%:*}"; mac="${rest#*:}"
  key=$(_derive_key)
  mac_check=$(printf '%s|%s' "$iv" "$ciph" | openssl dgst -sha256 -hmac "$key" -hex 2>/dev/null | awk '{print $NF}')
  [[ "$mac_check" == "$mac" ]] || { return 1; }
  printf '%s' "$ciph" | openssl enc -d -aes-256-cbc -K "$key" -iv "$iv" -a -A 2>/dev/null
}

# ── store: cifrar y persistir (atómico + 0600) ───────────────────────────────
cmd_store() {
  local key="${1:-}" src="${2:--}"
  [[ -z "$key" ]] && { echo "Uso: printf '%s' \"\$SECRETO\" | credential-egress.sh store KEY [-]" >&2; exit 1; }
  if [[ "$src" != "-" || $# -gt 2 ]]; then
    # El valor por argv queda en ps y en el historial del shell: no se acepta.
    echo "ERROR: 'store KEY VALUE' eliminado: el secreto por argv es visible en ps/historial." >&2
    echo "Uso: printf '%s' \"\$SECRETO\" | credential-egress.sh store KEY [-]" >&2
    exit 1
  fi
  local value
  value=$(cat)
  [[ -z "$value" ]] && { echo "ERROR: valor vacío en stdin. Nada almacenado." >&2; exit 1; }
  _mk_store
  local blob
  blob=$(_encrypt "$value")
  local tmp
  tmp=$(mktemp "${STORE_DIR}/.keys.XXXXXX")
  python3 - "$tmp" "$KEYS_FILE" "$key" "$blob" <<'PY' 2>/dev/null || { echo "ERROR: escritura falló" >&2; exit 1; }
import json, sys, os
p, store, k, b = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
d = {}
if os.path.exists(store):
    try: d = json.load(open(store))
    except Exception: d = {}
d[k] = b
json.dump(d, open(p, 'w'), indent=2)
os.chmod(p, 0o600)
PY
  mv "$tmp" "$KEYS_FILE" 2>/dev/null || { echo "ERROR: mv falló" >&2; exit 1; }
  chmod 600 "$KEYS_FILE" 2>/dev/null || true
  echo "✓ Credencial almacenada cifrada: $key"
}

# ── destino: coincidencia exacta con la allowlist (sin regex, sin subcadenas) ──
# Los nombres de host no distinguen mayúsculas: se compara en minúsculas.
_dest_authorized() {
  local dest="${1,,}" d
  [[ -n "$dest" ]] || return 1
  for d in $AUTH_DESTS; do [[ "$dest" == "$d" ]] && return 0; done
  return 1
}

# Hosts de todas las URLs (scheme://[user@]host[:port]) que aparezcan en un
# argumento, en cualquier posición: '--url=https://x', scripts de 'bash -c', etc.
# Imprime un host por línea. Devuelve 2 si alguna autoridad es ambigua
# ('\', '%', vacía o con caracteres fuera de [a-z0-9.-]): los parsers difieren
# en cómo la interpretan (p. ej. 'https://evil\@github.com').
_URL_RE='[A-Za-z][A-Za-z0-9+.-]*://([^]/?#[:space:]"'"'"'`;|&<>()[]*)'
_arg_hosts() {
  local rest="$1" auth h bad=0
  while [[ "$rest" =~ $_URL_RE ]]; do
    auth="${BASH_REMATCH[1]}"
    rest="${rest#*"${BASH_REMATCH[0]}"}"
    if [[ "$auth" == *[\\%]* ]]; then bad=1; continue; fi
    h="${auth##*@}"; h="${h%%:*}"; h="${h,,}"
    if [[ -z "$h" || ! "$h" =~ ^[a-z0-9.-]+$ ]]; then bad=1; continue; fi
    printf '%s\n' "$h"
  done
  return $(( bad ? 2 : 0 ))
}

# ── resolve: valor real solo para destino autorizado ─────────────────────────
cmd_resolve() {
  local key="${1:-}" dest=""
  shift 2>/dev/null || true
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dest) [[ $# -ge 2 ]] || { echo "ERROR: --dest sin valor. REFUSE." >&2; exit 1; }
              dest="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [[ -z "$key" ]] && { echo "Uso: credential-egress.sh resolve KEY --dest DEST" >&2; exit 1; }

  # AC-2: fail-closed — sin destino o destino no autorizado → REFUSE
  if [[ -z "$dest" ]]; then
    echo "ERROR: falta --dest. REFUSE (fail-closed)." >&2
    exit 1
  fi
  if ! _dest_authorized "$dest"; then
    echo "ERROR: destino '$dest' no autorizado. REFUSE." >&2
    exit 1
  fi
  [[ -f "$KEYS_FILE" ]] || { echo "ERROR: store no existe ($KEYS_FILE)" >&2; exit 1; }

  local blob
  blob=$(python3 - "$KEYS_FILE" "$key" <<'PY' 2>/dev/null
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
print(d.get(sys.argv[2], ''))
PY
)
  [[ -z "$blob" ]] && { echo "ERROR: marcador '$key' no registrado. REFUSE." >&2; exit 1; }

  local real
  real=$(_decrypt "$blob")
  [[ -z "$real" ]] && { echo "ERROR: descifrado falló (¿cambió machine-id?)." >&2; exit 1; }
  printf '%s\n' "$real"
}

# ── run: sustituye savia:cred:<key> en args y ejecuta en hijo ────────────────
cmd_run() {
  local dest="" arg h
  if [[ "${1:-}" == "--dest" ]]; then
    [[ $# -ge 2 ]] || { echo "ERROR: --dest sin valor. REFUSE." >&2; exit 1; }
    dest="$2"; shift 2
  fi
  [[ $# -eq 0 ]] && { echo "Uso: credential-egress.sh run [--dest DEST] CMD ARG..." >&2; exit 1; }
  # Sin marcadores no hay credencial que proteger: se ejecuta tal cual.
  local has_marker=0
  for arg in "$@"; do [[ "$arg" == savia:cred:* ]] && has_marker=1; done
  if [[ $has_marker -eq 0 ]]; then "$@"; return; fi
  # Salvaguarda de ENRUTADO, no barrera frente a un llamante hostil: todas las
  # URLs que aparezcan en los args (también dentro de '--url=...' o de un
  # script de 'bash -c') deben ser de un único host y coincidir con --dest.
  # Evita mandar la credencial por error a otro host escrito como URL. NO
  # impide que el comando la imprima por stdout ni que la envíe a un host que
  # no aparezca como 'esquema://host' (variables, ficheros, 'curl host').
  # Ver «Límites» en docs/rules/domain/secret-redaction-policy.md.
  local -a hosts=()
  local hs rc
  for arg in "$@"; do
    hs=$(_arg_hosts "$arg"); rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "ERROR: URL con autoridad ambigua en los args. REFUSE." >&2; exit 1
    fi
    while IFS= read -r h; do
      [[ -n "$h" ]] || continue
      [[ " ${hosts[*]} " == *" $h "* ]] || hosts+=("$h")
    done <<<"$hs"
  done
  if [[ ${#hosts[@]} -gt 1 ]]; then
    echo "ERROR: varios destinos en los args (${hosts[*]}). REFUSE." >&2; exit 1
  fi
  if [[ ${#hosts[@]} -eq 1 ]]; then
    if [[ -n "$dest" && "${dest,,}" != "${hosts[0]}" ]]; then
      echo "ERROR: --dest '$dest' no coincide con el host '${hosts[0]}' de los args. REFUSE." >&2; exit 1
    fi
    dest="${hosts[0]}"
  fi
  local -a args=()
  for arg in "$@"; do
    if [[ "$arg" == savia:cred:* ]]; then
      local key="${arg#savia:cred:}"
      local real
      real=$(cmd_resolve "$key" --dest "$dest") || exit 1
      args+=("$real")
    else
      args+=("$arg")
    fi
  done
  "${args[@]}"
}

# ── status: lista keys sin valores ────────────────────────────────────────────
cmd_status() {
  [[ -f "$KEYS_FILE" ]] || { echo "Store vacía: $KEYS_FILE"; return 0; }
  echo "Marcadores registrados (sin valores):"
  python3 - "$KEYS_FILE" <<'PY' 2>/dev/null
import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: d = {}
for k in d: print(f"  - {k}")
PY
}

# ── audit: detecta credenciales en texto plano ────────────────────────────────
cmd_audit() {
  local root="${1:-$PWD}"
  echo "Audit de credenciales en texto plano (localización, sin valores):"
  grep -rnE "ghp_[A-Za-z0-9]{20,}|gho_|PAT *= *[A-Za-z0-9]{40,}" \
    "$root/scripts" "$root/.claude" 2>/dev/null \
    | grep -vE "\.git/|node_modules|/tests/|pat_file|PAT_FILE|_PAT_FILE|\\\$PAT" \
    | head -10 || true
  echo "Interpolaciones directas de cat PAT_FILE (candidatas a migración):"
  grep -rn "cat \$PAT_FILE\|\$(cat \$PAT_FILE" "$root/scripts" 2>/dev/null | head -5 || true
}

case "${1:-help}" in
  store)  shift; cmd_store "$@" ;;
  resolve) shift; cmd_resolve "$@" ;;
  run)    shift; cmd_run "$@" ;;
  status) cmd_status ;;
  audit)  cmd_audit "${2:-$PWD}" ;;
  help|*) cat <<'USAGE'
credential-egress.sh {store|resolve|run|status|audit}

  store KEY [-]            → lee el valor por stdin, cifra y almacena en
                             ~/.savia/credential-store/keys.json
                             (printf '%s' "$SECRETO" | credential-egress.sh store KEY)
  resolve KEY --dest D     → imprime valor real; sin --dest o D no autorizado → REFUSE
  run [--dest D] CMD ARG... → sustituye savia:cred:<key> en args y ejecuta en hijo;
                             destino = --dest o host único de las URLs de los args.
                             Salvaguarda de enrutado: el hijo recibe el valor y
                             puede imprimirlo (ver secret-redaction-policy.md)
  status                   → lista marcadores registrados (nunca valores)
  audit [DIR]              → detecta credenciales en texto plano / cat $PAT_FILE
USAGE
    exit 0 ;;
esac
