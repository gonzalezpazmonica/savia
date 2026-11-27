#!/usr/bin/env bash
# federation-discover.sh — SCL-009: auto-descubrimiento de instancias federadas.
#
# Gestiona el FederationRegistry de SaviaVaults (.savia-vault/federation.json):
#   --add <id> <url>   registra una instancia (retro-compatible con registry.ts)
#   --remove <id>      la elimina
#   --list             lista instancias con su estado
#   --check            health-checkea via /health y actualiza status
#   --pool FILE        (con --check) lee candidatas nuevas y las añade si faltan
#
# PURE_BASH, sin red fuera de los endpoints del pool, timeouts <= 3s (CRIT-001).
# Solo toca federation.json — nunca CRITERIO/CONSTITUCION/lecciones (RN-01).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="${SCL_FEDERATION_REGISTRY:-$ROOT/.savia-vault/federation.json}"
POOL="${SCL_FEDERATION_POOL:-$ROOT/config/federation-pool.txt}"
HEALTH_TIMEOUT="${SCL_FEDERATION_TIMEOUT:-3}"

MODE=""
A1=""; A2=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    # Validate arity before shifting: `shift N` with fewer than N args fails
    # without shifting, and the loop then spun forever on the same flag.
    --add) [[ $# -ge 3 ]] || { echo "ERROR: --add necesita ID y URL" >&2; exit 2; }
      MODE="add"; A1="$2"; A2="$3"; shift 3 ;;
    --remove) [[ $# -ge 2 ]] || { echo "ERROR: --remove necesita ID" >&2; exit 2; }
      MODE="remove"; A1="$2"; shift 2 ;;
    --list) MODE="list"; shift ;;
    --check) MODE="check"; shift ;;
    --pool) [[ $# -ge 2 ]] || { echo "ERROR: --pool necesita un fichero" >&2; exit 2; }
      POOL="$2"; shift 2 ;;
    *) echo "usage: $0 --add ID URL | --remove ID | --list | --check [--pool F]" >&2; exit 2 ;;
  esac
done
[[ -z "$MODE" ]] && { echo "usage: $0 --add ID URL | --remove ID | --list | --check" >&2; exit 2; }
if [[ "$MODE" == "add" && ( -z "$A1" || -z "$A2" ) ]]; then
  echo "ERROR: --add necesita ID y URL" >&2; exit 2
fi

mkdir -p "$(dirname "$REGISTRY")"

# Helper python para leer/escribir el registry en el mismo formato del TS.
load_registry() {
  if [[ -f "$REGISTRY" ]]; then python3 -c "import sys; import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))" "$REGISTRY" 2>/dev/null || echo "[]"; else echo "[]"; fi
}

add() {
  local id="$1" url="$2"
  [[ -z "$id" || -z "$url" ]] && { echo "ERROR: --add necesita ID y URL" >&2; exit 2; }
  python3 - "$REGISTRY" "$id" "$url" <<'PYEOF'
import json, sys, os
reg, id_, url = sys.argv[1], sys.argv[2], sys.argv[3]
data = []
if os.path.exists(reg):
    try: data = json.load(open(reg))
    except Exception: data = []
found = next((d for d in data if d.get('id')==id_), None)
if found:
    found['url'] = url
else:
    data.append({'id': id_, 'name': id_, 'url': url, 'timeout': 5000, 'enabled': True, 'weight': 1.0, 'tags': [], 'status': 'unknown'})
os.makedirs(os.path.dirname(reg), exist_ok=True)
json.dump(data, open(reg, 'w'), indent=2)
PYEOF
  echo "REGISTERED $id -> $url"
}

remove() {
  local id="$1"
  python3 - "$REGISTRY" "$id" <<'PYEOF'
import json, sys, os
reg, id_ = sys.argv[1], sys.argv[2]
if not os.path.exists(reg): sys.exit(0)
data = json.load(open(reg))
data = [d for d in data if d.get('id') != id_]
json.dump(data, open(reg, 'w'), indent=2)
PYEOF
  echo "REMOVED $id"
}

list_instances() {
  python3 - "$REGISTRY" <<'PYEOF'
import json, sys, os
if not os.path.exists(sys.argv[1]): print("(registry vacío — usa --add o --check con --pool)"); sys.exit(0)
data = json.load(open(sys.argv[1]))
if not data: print("(registry vacío)")
for d in data:
    print(f"{d.get('id','?')}\t{d.get('url','?')}\t{d.get('status','unknown')}\tlast={d.get('lastHealthCheck','-')}")
PYEOF
}

check() {
  # 1) pool → registrar candidatas nuevas que falten
  if [[ -f "$POOL" ]]; then
    while IFS=, read -r id url _tok; do
      [[ -z "$id" || -z "$url" ]] && continue
      # si no existe, añadir
      if ! python3 - "$REGISTRY" "$id" <<'PYEOF' 2>/dev/null
import json, sys, os
if os.path.exists(sys.argv[1]):
    d = json.load(open(sys.argv[1]))
    sys.exit(0 if any(x.get('id')==sys.argv[2] for x in d) else 1)
else:
    sys.exit(1)
PYEOF
      then
        add "$id" "$url"
      fi
    done < "$POOL"
  fi

  # 2) health-check de todas las registradas
  python3 - "$REGISTRY" "$HEALTH_TIMEOUT" <<'PYEOF'
import json, sys, os, urllib.request, urllib.error, datetime
reg, timeout = sys.argv[1], float(sys.argv[2])
if not os.path.exists(reg): print("(registry vacío)"); sys.exit(0)
data = json.load(open(reg))
ts = datetime.datetime.now(datetime.timezone.utc).isoformat()
for d in data:
    url = d.get('url','')
    ok = False
    if url:
        try:
            req = urllib.request.Request(url.rstrip('/') + '/health', headers={'User-Agent': 'savia-scl009'})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                body = r.read(64).decode('utf-8', 'ignore')
                ok = (r.status == 200 and 'ok' in body.lower())
        except Exception:
            ok = False
    d['status'] = 'healthy' if ok else 'unhealthy'
    d['lastHealthCheck'] = ts
json.dump(data, open(reg, 'w'), indent=2)
for d in data:
    print(f"{d.get('id','?')}: {d.get('status')}")
PYEOF
}

case "$MODE" in
  add)    add "$A1" "$A2" ;;
  remove) remove "$A1" ;;
  list)   list_instances ;;
  check)  check ;;
esac