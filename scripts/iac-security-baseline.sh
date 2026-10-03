#!/usr/bin/env bash
# iac-security-baseline.sh — Genera .trivyignore inicial para un proyecto legacy
# SE-241: Lista las misconfiguraciones actuales como "known baseline"
# SE-376: calibrado — fail-closed y sin sobrescribir supresiones existentes.
#
# Uso:
#   bash scripts/iac-security-baseline.sh --path ./infra/ [--output <f>] [--force]
#   Por defecto escribe <path>/.trivyignore, que es lo que aplica iac-security-scan.sh.
#
# El fichero generado NO se aplica automáticamente — el humano decide si usarlo.
# Su propósito es permitir detectar regresiones en proyectos legacy sin bloquear
# el CI por misconfiguraciones ya conocidas y aceptadas.
#
# Limitación: .trivyignore suprime por ID en cualquier fichero del path escaneado.
# Una nueva aparición del mismo ID en otro fichero también queda suprimida. Cada
# entrada lista los ficheros donde se encontró para que la revisión lo vea.
#
# Exit codes:
#   0 = baseline escrito (con o sin IDs)
#   2 = error: argumentos, Trivy/Docker ausente o fallido, JSON inválido,
#       o --output ya existe sin --force. En error NO se escribe ningún fichero.
#
# Ref: docs/rules/domain/iac-security-policy.md — SE-241
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Funciones compartidas (iac_detect_runner, iac_run_trivy); no ejecuta el escaneo.
# shellcheck source=iac-security-scan.sh
source "$SCRIPT_DIR/iac-security-scan.sh"

SCAN_PATH=""
OUTPUT_FILE=""
FORCE=false
DATE="$(date +%Y%m%d)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)   need_value "$@"; SCAN_PATH="$2";   shift 2 ;;
    --output) need_value "$@"; OUTPUT_FILE="$2"; shift 2 ;;
    --force)  FORCE=true; shift ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

if [[ -z "$SCAN_PATH" ]]; then
  echo "  Ejemplo: $0 --path ./infra/   (escribe ./infra/.trivyignore)" >&2
  die "Especifica --path <dir>"
fi
[[ -d "$SCAN_PATH" ]] || die "El path no existe: $SCAN_PATH"
[[ -n "$OUTPUT_FILE" ]] || OUTPUT_FILE="$SCAN_PATH/.trivyignore"
if [[ -e "$OUTPUT_FILE" && "$FORCE" != "true" ]]; then
  die "$OUTPUT_FILE ya existe; contiene supresiones justificadas a mano. Usa --force para sobrescribirlo o --output <otro>."
fi
command -v python3 >/dev/null 2>&1 || die "python3 es necesario para leer el JSON de Trivy"
iac_detect_runner || die "Ni Trivy ni Docker disponibles. Instala Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"

echo "Generando baseline de misconfiguraciones en: $SCAN_PATH"

WORKDIR="$(mktemp -d)" || die "mktemp falló"
trap 'rm -rf "$WORKDIR"' EXIT
rc=0
iac_run_trivy config "$SCAN_PATH" "$WORKDIR/raw.json" "$WORKDIR/err" false || rc=$?
if [[ $rc -ne 0 ]]; then
  tail -5 "$WORKDIR/err" >&2
  die "Trivy ($IAC_RUNNER) falló con exit $rc. No se genera baseline: el resultado no sería fiable."
fi
[[ -s "$WORKDIR/raw.json" ]] || die "Trivy no produjo salida JSON. No se genera baseline."

# Entradas: una por ID con severidad máxima, título y ficheros afectados.
python3 - "$WORKDIR/raw.json" "$WORKDIR/entries" <<'PYEOF' || die "JSON de Trivy inválido. No se genera baseline."
import json, sys
data = json.load(open(sys.argv[1]))
if not isinstance(data, dict):
    raise SystemExit("la raíz del JSON no es un objeto")
order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
ids = {}
for res in data.get("Results") or []:
    for m in res.get("Misconfigurations") or []:
        if m.get("Status", "FAIL") != "FAIL" or not m.get("ID"):
            continue
        e = ids.setdefault(m["ID"], {"sev": "UNKNOWN", "title": m.get("Title", ""), "targets": set()})
        sev = (m.get("Severity") or "UNKNOWN").upper()
        if order.get(sev, 9) < order.get(e["sev"], 9):
            e["sev"] = sev
        e["targets"].add(res.get("Target", "?"))
with open(sys.argv[2], "w") as fh:
    for mid in sorted(ids, key=lambda k: (order.get(ids[k]["sev"], 9), k)):
        e = ids[mid]
        fh.write("# %s · %s · en: %s\n" % (e["sev"], e["title"], ", ".join(sorted(e["targets"]))))
        fh.write("# PENDIENTE: justificar (motivo + fecha de revisión) antes de commitear\n%s\n\n" % mid)
PYEOF

COUNT="$(grep -cvE '^(#|$)' "$WORKDIR/entries")"
{
  echo "# .trivyignore — Baseline generado automáticamente por iac-security-baseline.sh"
  echo "# Fecha: $DATE"
  echo "# Path escaneado: $SCAN_PATH"
  echo "#"
  echo "# IMPORTANTE: Este fichero suprime las misconfiguraciones conocidas en la fecha"
  echo "# de generación. Revisa cada ID antes de commitear — algunas pueden ser riesgosas."
  echo "# La supresión es por ID en cualquier fichero del path: una nueva aparición del"
  echo "# mismo ID en otro fichero también queda suprimida. CRITICAL requiere aprobación"
  echo "# de security-guardian. Añade 'exp:YYYY-MM-DD' tras el ID para que caduque."
  echo "#"
  echo "# Referencia: docs/rules/domain/iac-security-policy.md — SE-241"
  echo ""
  if [[ "$COUNT" -eq 0 ]]; then
    echo "# Trivy no encontró misconfiguraciones (escaneo completado correctamente)."
  else
    echo "# $COUNT misconfiguración(es) encontrada(s) — añadidas como baseline:"
    echo ""
    cat "$WORKDIR/entries"
  fi
} > "$WORKDIR/out" || die "No se pudo componer el baseline"
# Temporal junto al destino: mv dentro del mismo sistema de ficheros es atómico.
DEST_TMP="$(mktemp "$(dirname "$OUTPUT_FILE")/.trivyignore.XXXXXX")" || die "No se puede escribir junto a $OUTPUT_FILE"
cp "$WORKDIR/out" "$DEST_TMP" && mv "$DEST_TMP" "$OUTPUT_FILE" || { rm -f "$DEST_TMP"; die "No se pudo escribir $OUTPUT_FILE"; }

echo "Fichero generado: $OUTPUT_FILE ($COUNT ID(s))"
echo "SIGUIENTE PASO: Revisa $OUTPUT_FILE y decide si aplicarlo al proyecto."
echo "No se ha modificado ningún otro fichero del proyecto."
exit 0
