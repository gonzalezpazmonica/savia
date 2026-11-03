#!/usr/bin/env bash
# confidentiality-pr-scan.sh — SE-501: escaneo de confidencialidad del diff de la PR con el escáner de la BASE.
#
# El escáner, el generador de la blocklist, la allowlist, la librería gate-result y el .gitignore (fuente de
# la blocklist) se extraen del commit base a un directorio aparte. El diff (origin/main...HEAD) sale del
# repositorio de la PR vía GIT_DIR. Una PR que modifica el escáner no se audita con su versión modificada.
#
# Uso: confidentiality-pr-scan.sh --base <commit> [--repo <dir>] [--blocklist <fichero>]
#   --repo  checkout de la PR (por defecto, la raíz que contiene este script). La CI ejecuta una copia
#           de este script tomada de la base, fuera del checkout, y pasa --repo.
# Veredicto: solo «gate-result: {"result":"clean"…}» con código 0 da PASS (exit 0). findings, unknown,
# salida sin línea gate-result o código ≠ 0 dan FAIL (exit 1). Error de entorno: exit 2. Fail-closed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE=""; BLOCKLIST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --repo) ROOT="$(cd "${2:-}" && pwd)" || exit 2; shift 2 ;;
    --blocklist) BLOCKLIST="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "confidentiality-pr-scan: argumento desconocido: $1" >&2; exit 2 ;;
  esac
done
[[ -n "$BASE" ]] || { echo "confidentiality-pr-scan: falta --base <commit>" >&2; exit 2; }
git -C "$ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null || { echo "FAIL: commit base desconocido: $BASE" >&2; exit 2; }
GITDIR=$(git -C "$ROOT" rev-parse --absolute-git-dir) || exit 2

# Código del escáner que se toma de la base. Sin cualquiera de los obligatorios: FAIL (no se escanea con nada).
REQUIRED=(scripts/confidentiality-scan.sh .claude/hooks/lib/gate-result.sh)
OPTIONAL=(scripts/generate-blocklist.sh scripts/confidentiality-allowlist.txt .gitignore)
X=$(mktemp -d) || exit 2
trap 'rm -rf "$X"' EXIT
for f in "${REQUIRED[@]}" "${OPTIONAL[@]}"; do
  if git -C "$ROOT" cat-file -e "$BASE:$f" 2>/dev/null; then
    mkdir -p "$X/$(dirname "$f")" && git -C "$ROOT" show "$BASE:$f" > "$X/$f" || exit 2
  elif [[ " ${REQUIRED[*]} " == *" $f "* ]]; then
    echo "FAIL: la base no tiene $f; no hay escáner de confianza" >&2; exit 1
  fi
done
# Datos locales no versionados que la blocklist lee (proyectos privados, CLAUDE.local.md): no los controla
# la PR. Se enlazan si existen; en la CI no existen.
for f in projects CLAUDE.local.md; do [[ -e "$ROOT/$f" ]] && ln -s "$ROOT/$f" "$X/$f"; done

args=(--pr)
[[ -n "$BLOCKLIST" ]] && args+=(--blocklist "$BLOCKLIST")
out=$(GIT_DIR="$GITDIR" GIT_WORK_TREE="$ROOT" SAVIA_GATE_UNKNOWN=block bash "$X/scripts/confidentiality-scan.sh" "${args[@]}" 2>&1)
rc=$?
printf '%s\n' "$out"
res=$(printf '%s\n' "$out" | grep -E '^gate-result: ' | tail -1 | sed 's/^gate-result: //' \
  | python3 -c 'import json,sys
try: print(json.loads(sys.stdin.read()).get("result",""))
except Exception: print("")' 2>/dev/null)
echo "escáner: base ${BASE:0:12} · resultado: ${res:-sin gate-result} · código: $rc"
if [[ "$res" == clean && $rc -eq 0 ]]; then echo "Confidentiality scan (PR): PASS"; exit 0; fi
echo "Confidentiality scan (PR): FAIL"
exit 1
