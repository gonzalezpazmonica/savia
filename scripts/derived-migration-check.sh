#!/usr/bin/env bash
# derived-migration-check.sh — SE-501 migración, paso 2 (solo lectura).
# Comprueba que:
#   1. «Confidentiality scan (PR)» está entre los contextos requeridos de main (gh api, protección clásica).
#   2. Ningún workflow disparado por pull_request o pull_request_target recibe CONFIDENTIALITY_HMAC_KEY.
# Uso: derived-migration-check.sh [--repo owner/name]
# Salida: 0 PASS · 1 FAIL · 2 error (API caída, respuesta ilegible): fail-closed.
# Entorno: SAVIA_GH (binario gh, para tests) · SAVIA_GH_REPO.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH="${SAVIA_GH:-gh}"
REPO="${SAVIA_GH_REPO:-}"
CTX="Confidentiality scan (PR)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "derived-migration-check: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
if [[ -z "$REPO" ]]; then
  REPO=$($GH repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "FAIL: no se pudo resolver el repo" >&2; exit 2; }
fi

rc=0
raw=$($GH api "repos/$REPO/branches/main/protection/required_status_checks" 2>/dev/null) \
  || { echo "FAIL: la API no devolvió los checks requeridos de main" >&2; exit 2; }
SAVIA_RAW="$raw" python3 - "$CTX" <<'PY'
import json, os, sys
ctx = sys.argv[1]
try:
    d = json.loads(os.environ["SAVIA_RAW"])
    names = set(d.get("contexts") or []) | {c.get("context") for c in (d.get("checks") or []) if isinstance(c, dict)}
except Exception:
    print("FAIL: respuesta de la API no válida", file=sys.stderr); sys.exit(2)
if ctx in names:
    print(f"PASS: «{ctx}» es contexto requerido de main"); sys.exit(0)
print(f"FAIL: «{ctx}» no está entre los contextos requeridos de main ({', '.join(sorted(n for n in names if n))})"); sys.exit(1)
PY
r=$?; (( r > rc )) && rc=$r

shopt -s nullglob
wfs=("$ROOT"/.github/workflows/*.yml "$ROOT"/.github/workflows/*.yaml)
python3 "$ROOT/scripts/workflow-secrets-check.py" pr-secrets "${wfs[@]}"
r=$?; (( r > rc )) && rc=$r
exit $rc
