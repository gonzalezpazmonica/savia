#!/usr/bin/env bash
# confidentiality-main-verify.sh — SE-501 I2: prueba de que un commit de main pasó la auditoría completa.
#
# La prueba es una ejecución de .github/workflows/confidentiality-main.yml con event=push,
# head_branch=main, head_sha=<X> y conclusion=success. Un commit status o un check publicado por una PR
# no cuentan: una PR con statuses: write podría falsificarlos; una ejecución push en main no.
#
# Uso: confidentiality-main-verify.sh <sha|ref> [--repo owner/name]
# Salida: 0 hay prueba · 1 no la hay · 2 error (API caída, respuesta no JSON, sha ilegible). Fail-closed.
# Entorno: SAVIA_GH (binario gh, para tests) · SAVIA_GH_REPO (repo por defecto).
set -uo pipefail

GH="${SAVIA_GH:-gh}"
WF=".github/workflows/confidentiality-main.yml"
REF=""; REPO="${SAVIA_GH_REPO:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) REF="$1"; shift ;;
  esac
done
[[ -n "$REF" ]] || { echo "uso: confidentiality-main-verify.sh <sha|ref>" >&2; exit 2; }
if [[ "$REF" =~ ^[0-9a-f]{40}$ ]]; then SHA="$REF"
else SHA=$(git rev-parse -q --verify "$REF^{commit}" 2>/dev/null) || { echo "FAIL: ref ilegible: $REF" >&2; exit 2; }; fi
if [[ -z "$REPO" ]]; then
  REPO=$($GH repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || { echo "FAIL: no se pudo resolver el repo" >&2; exit 2; }
fi

raw=$($GH api "repos/$REPO/actions/runs?head_sha=$SHA&per_page=100" 2>/dev/null) \
  || { echo "FAIL: la API de GitHub no respondió; sin prueba para ${SHA:0:12}" >&2; exit 2; }
SAVIA_RAW="$raw" python3 - "$SHA" "$WF" <<'PY'
import json, os, sys
sha, wf = sys.argv[1], sys.argv[2]
try:
    runs = json.loads(os.environ["SAVIA_RAW"])["workflow_runs"]
    assert isinstance(runs, list)
except Exception:
    print("FAIL: respuesta de la API no válida", file=sys.stderr); sys.exit(2)
ok = [r for r in runs if isinstance(r, dict) and r.get("path") == wf and r.get("event") == "push"
      and r.get("head_branch") == "main" and r.get("head_sha") == sha and r.get("conclusion") == "success"]
if ok:
    print(f"PASS: {sha[:12]} auditado en main (run {ok[0].get('id')})"); sys.exit(0)
print(f"FAIL: ninguna ejecución push de {wf} en main con éxito para {sha[:12]}"); sys.exit(1)
PY
