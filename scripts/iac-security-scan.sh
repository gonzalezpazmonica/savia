#!/usr/bin/env bash
# iac-security-scan.sh — IaC Security Scanning con Trivy
# SE-241: Escanea Terraform, Bicep, Dockerfiles, docker-compose y Kubernetes con trivy config.
# SE-376: calibrado — una sola ejecución de Trivy, clasificación propia y fail-closed.
#
# Uso:
#   bash scripts/iac-security-scan.sh --path ./infra/ [--severity CRITICAL,HIGH] [--format table|json]
#   bash scripts/iac-security-scan.sh --image myapp:latest [--severity CRITICAL,HIGH]
#   Opciones: --ignorefile <f> (por defecto <path>/.trivyignore) · --skip-update
#
# --severity es el conjunto BLOQUEANTE. El resto de severidades se informa como
# INFO y no bloquea. Las supresiones del ignorefile se aplican aquí y se listan.
# --format json deja en stdout el report normalizado (el de --path si hay ambos).
#
# Salida:
#   output/security/iac-scan-YYYYMMDD.json        (report normalizado, --path)
#   output/security/iac-image-scan-YYYYMMDD.json  (report normalizado, --image)
#   output/security/iac-scan-YYYYMMDD.md          (summary Markdown)
#
# Exit codes:
#   0 = sin hallazgos bloqueantes (PASS) o sin IaC que escanear (NO_IAC)
#   1 = hallazgos en las severidades bloqueantes (bloquea CI)
#   2 = error: argumentos inválidos, Trivy/Docker ausente o fallido, JSON inválido
#
# También es la librería de iac-security-baseline.sh: al hacer `source` no se
# ejecuta el escaneo (guarda BASH_SOURCE tras las funciones).
#
# Ref: docs/rules/domain/iac-security-policy.md
set -uo pipefail

# ── Funciones compartidas (scan + baseline) ──────────────────────────────────
# Contrato: Trivy se ejecuta UNA vez por objetivo, con todas las severidades,
# --exit-code 0 y un ignorefile vacío. Así un exit != 0 significa fallo de la
# herramienta (nunca "hay hallazgos") y el .trivyignore implícito del
# directorio actual no suprime nada a escondidas. La clasificación
# (bloqueante / informativo / suprimido) se hace sobre el JSON.

die() { echo "ERROR: $*" >&2; exit 2; }
need_value() { [[ $# -ge 2 && -n "${2:-}" && "${2:-}" != --* ]] || die "$1 requiere un valor"; }

IAC_ALL_SEVERITIES="UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL"
IAC_RUNNER=""

# iac_detect_runner — fija IAC_RUNNER a "trivy" o "docker"; 1 si no hay ninguno.
iac_detect_runner() {
  if command -v trivy >/dev/null 2>&1; then
    IAC_RUNNER="trivy"
  elif command -v docker >/dev/null 2>&1; then
    IAC_RUNNER="docker"
    echo "WARN: Trivy no instalado localmente. Usando fallback Docker (aquasec/trivy:latest)." >&2
  else
    IAC_RUNNER=""
    return 1
  fi
}

# iac_run_trivy <config|image> <objetivo> <json_salida> <stderr_salida> <skip_update>
# Devuelve el exit code de Trivy (o de Docker).
iac_run_trivy() {
  local mode="$1" target="$2" json_out="$3" err_out="$4" skip="$5"
  local flags=(--severity "$IAC_ALL_SEVERITIES" --exit-code 0 --format json)
  if [[ "$skip" == "true" ]]; then
    if [[ "$mode" == "config" ]]; then flags+=(--skip-check-update)
    else flags+=(--skip-db-update); fi
  fi
  local rc=0
  if [[ "$IAC_RUNNER" == "trivy" ]]; then
    local empty_ignore
    empty_ignore="$(mktemp)"
    trivy "$mode" "${flags[@]}" --ignorefile "$empty_ignore" "$target" \
      >"$json_out" 2>"$err_out" || rc=$?
    rm -f "$empty_ignore"
  else
    local cache="${HOME:-/tmp}/.cache/trivy"
    if [[ "$mode" == "config" ]]; then
      local abs
      abs="$(cd "$target" && pwd)" || return 2
      docker run --rm -v "$abs:/workspace:ro" -v "$cache:/root/.cache/trivy" \
        aquasec/trivy:latest config "${flags[@]}" --ignorefile /dev/null /workspace \
        >"$json_out" 2>"$err_out" || rc=$?
    else
      docker run --rm -v "$cache:/root/.cache/trivy" \
        aquasec/trivy:latest image "${flags[@]}" --ignorefile /dev/null "$target" \
        >"$json_out" 2>"$err_out" || rc=$?
    fi
  fi
  return "$rc"
}

# iac_detect_types <dir> — tipos IaC presentes (tolera espacios en rutas).
iac_detect_types() {
  local path="$1" types=()
  local -a common=("$path" -maxdepth 5 -type f)
  find "${common[@]}" -name '*.tf' -print -quit 2>/dev/null | grep -q . && types+=("terraform")
  find "${common[@]}" -name '*.bicep' -print -quit 2>/dev/null | grep -q . && types+=("bicep")
  find "${common[@]}" -name 'Dockerfile*' -print -quit 2>/dev/null | grep -q . && types+=("dockerfile")
  find "${common[@]}" \( -name 'docker-compose*.yml' -o -name 'docker-compose*.yaml' \
    -o -name 'compose.yml' -o -name 'compose.yaml' \) -print -quit 2>/dev/null | grep -q . \
    && types+=("docker-compose")
  find "${common[@]}" \( -name '*.yaml' -o -name '*.yml' \) -print0 2>/dev/null \
    | xargs -0 -r grep -lE '^kind:[[:space:]]*[A-Za-z]' 2>/dev/null | grep -q . && types+=("kubernetes")
  echo "${types[*]:-}"
}

# iac_evaluate <raw_json> <ignorefile|""> <bloqueantes> <report_json> <texto_salida> <kind> <objetivo>
# Exit: 0 sin bloqueantes, 1 con bloqueantes, 3 JSON inválido.
iac_evaluate() {
  python3 - "$@" <<'PYEOF'
import datetime, json, os, re, sys


def _fail(exc_type, exc, tb):
    # Cualquier excepción no prevista es ERROR (3), nunca "hay hallazgos" (1).
    sys.stderr.write("ERROR: evaluación del JSON de Trivy fallida: %s: %s\n" % (exc_type.__name__, exc))
    sys.stderr.flush()
    os._exit(3)


sys.excepthook = _fail
raw, ignore_path, blocking_arg, report_path, text_path, kind, target = sys.argv[1:8]
blocking = [s for s in blocking_arg.split(",") if s]
try:
    with open(raw) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        raise ValueError("la raíz del JSON no es un objeto")
    results = data.get("Results") or []
    if not isinstance(results, list):
        raise ValueError("Results no es una lista")
except (OSError, ValueError) as exc:
    sys.stderr.write("ERROR: salida JSON de Trivy inválida (%s)\n" % exc)
    sys.exit(3)

today = datetime.date.today().isoformat()
active, expired, bad_exp = {}, [], []
if ignore_path:
    with open(ignore_path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            exp = next((p[4:] for p in parts[1:] if p.startswith("exp:")), "")
            if any(p.startswith("exp:") for p in parts[1:]) and not re.fullmatch(r"\d{4}-\d{2}-\d{2}", exp):
                bad_exp.append(parts[0])
            elif exp and exp < today:
                expired.append(parts[0])
            else:
                active[parts[0]] = 0

findings = []
for res in results:
    if not isinstance(res, dict):
        continue
    tgt = res.get("Target", "")
    for m in res.get("Misconfigurations") or []:
        if m.get("Status", "FAIL") != "FAIL":
            continue
        findings.append({"target": tgt, "id": m.get("ID", ""), "avdid": m.get("AVDID", ""),
                         "severity": (m.get("Severity") or "UNKNOWN").upper(),
                         "title": m.get("Title", "")})
    for v in res.get("Vulnerabilities") or []:
        findings.append({"target": tgt, "id": v.get("VulnerabilityID", ""), "avdid": "",
                         "severity": (v.get("Severity") or "UNKNOWN").upper(),
                         "title": "%s %s" % (v.get("PkgName", ""), v.get("InstalledVersion", ""))})

for f in findings:
    hit = next((k for k in (f["id"], f["avdid"]) if k and k in active), None)
    f["suppressed"] = hit is not None
    if hit:
        active[hit] += 1
    f["blocking"] = (not f["suppressed"]) and f["severity"] in blocking

n_block = sum(f["blocking"] for f in findings)
supp = [f for f in findings if f["suppressed"]]
summary = {
    "blocking": n_block,
    "informative": sum((not f["blocking"]) and (not f["suppressed"]) for f in findings),
    "suppressed": len(supp),
    "suppressed_critical": sum(f["severity"] == "CRITICAL" for f in supp),
    "expired_ignores": sorted(set(expired)),
    "invalid_exp_ignores": sorted(set(bad_exp)),
    "unused_ignores": sorted(k for k, n in active.items() if n == 0),
}
report = {"tool": "trivy", "kind": kind, "target": target,
          "blocking_severities": blocking, "ignorefile": ignore_path or None,
          "status": "FAIL" if n_block else "PASS", "summary": summary, "findings": findings}
with open(report_path, "w") as fh:
    json.dump(report, fh, indent=2, ensure_ascii=False)

order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
with open(text_path, "w") as fh:
    for f in sorted(findings, key=lambda x: (order.get(x["severity"], 9), x["target"], x["id"])):
        tag = "SUPRIMIDO" if f["suppressed"] else ("BLOQUEA" if f["blocking"] else "INFO")
        fh.write("  [%s] %-8s %-14s %s — %s\n" % (tag, f["severity"], f["id"], f["target"], f["title"]))
    fh.write("Bloqueantes: %d · Informativos: %d · Suprimidos: %d\n"
             % (n_block, summary["informative"], summary["suppressed"]))
    if summary["suppressed_critical"]:
        fh.write("WARN: %d hallazgo(s) CRITICAL suprimidos por .trivyignore — requieren "
                 "aprobación de security-guardian.\n" % summary["suppressed_critical"])
    if expired:
        fh.write("WARN: supresiones caducadas (no aplicadas): %s\n" % ", ".join(summary["expired_ignores"]))
    if bad_exp:
        fh.write("WARN: supresiones con exp: inválido (formato YYYY-MM-DD; no aplicadas): %s\n"
                 % ", ".join(summary["invalid_exp_ignores"]))
    if summary["unused_ignores"]:
        fh.write("INFO: supresiones sin hallazgo asociado (candidatas a borrar): %s\n"
                 % ", ".join(summary["unused_ignores"]))
sys.exit(1 if n_block else 0)
PYEOF
}

# Al hacer `source` (iac-security-baseline.sh) solo se cargan las funciones.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

# ── Escaneo ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCAN_PATH=""
IMAGE_TARGET=""
SEVERITY="CRITICAL,HIGH"
FORMAT="table"
IGNOREFILE=""
SKIP_UPDATE=false
DATE="$(date +%Y%m%d)"
OUTPUT_DIR="$ROOT/output/security"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)        need_value "$@"; SCAN_PATH="$2";    shift 2 ;;
    --image)       need_value "$@"; IMAGE_TARGET="$2"; shift 2 ;;
    --severity)    [[ $# -ge 2 ]] || die "--severity requiere un valor"; SEVERITY="$2"; shift 2 ;;
    --format)      need_value "$@"; FORMAT="$2";       shift 2 ;;
    --ignorefile)  need_value "$@"; IGNOREFILE="$2";   shift 2 ;;
    --skip-update) SKIP_UPDATE=true; shift ;;
    *) die "Argumento desconocido: $1" ;;
  esac
done

if [[ -z "$SCAN_PATH" && -z "$IMAGE_TARGET" ]]; then
  echo "Ejemplo: $0 --path ./infra/ --severity CRITICAL,HIGH" >&2
  die "Especifica --path <dir> o --image <imagen>"
fi

SEVERITY="$(printf '%s' "$SEVERITY" | tr '[:lower:]' '[:upper:]' | tr -d ' ')"
[[ -n "$SEVERITY" ]] || die "--severity vacío"
IFS=',' read -r -a _sevs <<< "$SEVERITY"
for s in "${_sevs[@]}"; do
  [[ ",$IAC_ALL_SEVERITIES," == *",$s,"* ]] || die "Severidad inválida: '$s' (válidas: $IAC_ALL_SEVERITIES)"
done
[[ "$FORMAT" == "table" || "$FORMAT" == "json" ]] || die "--format debe ser table o json"
[[ -z "$SCAN_PATH" || -d "$SCAN_PATH" ]] || die "El path no existe: $SCAN_PATH"
if [[ -n "$IGNOREFILE" ]]; then
  [[ -f "$IGNOREFILE" ]] || die "--ignorefile no existe: $IGNOREFILE"
elif [[ -n "$SCAN_PATH" && -f "$SCAN_PATH/.trivyignore" ]]; then
  IGNOREFILE="$SCAN_PATH/.trivyignore"
fi
command -v python3 >/dev/null 2>&1 || die "python3 es necesario para evaluar el JSON de Trivy"
if ! iac_detect_runner; then
  die "Ni Trivy ni Docker disponibles. Instala Trivy: https://aquasecurity.github.io/trivy/latest/getting-started/installation/"
fi

mkdir -p "$OUTPUT_DIR" || die "No se pudo crear $OUTPUT_DIR"
REPORT_JSON="$OUTPUT_DIR/iac-scan-${DATE}.json"
IMAGE_JSON="$OUTPUT_DIR/iac-image-scan-${DATE}.json"
REPORT_MD="$OUTPUT_DIR/iac-scan-${DATE}.md"
WORKDIR="$(mktemp -d)" || die "mktemp falló"
trap 'rm -rf "$WORKDIR"' EXIT

# En --format json, stdout queda reservado al report: los mensajes van a stderr.
say() { if [[ "$FORMAT" == "json" ]]; then echo "$*" >&2; else echo "$*"; fi; }
status_of() { case "$1" in 0) echo PASS ;; 1) echo FAIL ;; *) echo ERROR ;; esac; }

# error_report <report> <kind> <objetivo> <motivo> — un report del mismo día no
# debe seguir diciendo PASS si el escaneo actual falla.
error_report() {
  python3 - "$@" <<'PYEOF'
import json, sys
report, kind, target, reason = sys.argv[1:5]
json.dump({"tool": "trivy", "kind": kind, "target": target, "status": "ERROR",
           "error": reason, "findings": []}, open(report, "w"), indent=2, ensure_ascii=False)
PYEOF
}

# scan_target <config|image> <objetivo> <report>  → 0 PASS · 1 FAIL · 2 ERROR
scan_target() {
  local mode="$1" target="$2" report="$3"
  local raw="$WORKDIR/$mode.raw.json" err="$WORKDIR/$mode.err" text="$WORKDIR/$mode.txt"
  local rc=0
  iac_run_trivy "$mode" "$target" "$raw" "$err" "$SKIP_UPDATE" || rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "ERROR: Trivy ($IAC_RUNNER) falló con exit $rc al escanear $target. El escaneo NO es válido." >&2
    tail -5 "$err" >&2
    error_report "$report" "$mode" "$target" "trivy exit $rc"
    return 2
  fi
  if [[ ! -s "$raw" ]]; then
    echo "ERROR: Trivy no produjo salida JSON para $target. El escaneo NO es válido." >&2
    error_report "$report" "$mode" "$target" "salida vacía"
    return 2
  fi
  rc=0
  iac_evaluate "$raw" "$IGNOREFILE" "$SEVERITY" "$report.tmp" "$text" "$mode" "$target" || rc=$?
  if [[ $rc -ne 0 && $rc -ne 1 ]]; then
    rm -f "$report.tmp"
    echo "ERROR: no se pudo evaluar la salida de Trivy para $target (JSON inválido o ilegible)." >&2
    error_report "$report" "$mode" "$target" "JSON inválido"
    return 2
  fi
  mv "$report.tmp" "$report"
  [[ "$FORMAT" == "table" ]] && cat "$text"
  cp "$text" "$WORKDIR/$mode.summary"
  return "$rc"
}

OVERALL_EXIT=0
NO_IAC=false
TYPES=""

if [[ -n "$SCAN_PATH" ]]; then
  TYPES="$(iac_detect_types "$SCAN_PATH")"
  say "Escaneando IaC en: $SCAN_PATH"
  say "Tipos detectados: ${TYPES:-ninguno}"
  say "Severidades bloqueantes: $SEVERITY · Ignorefile: ${IGNOREFILE:-ninguno}"
  rc=0; scan_target config "$SCAN_PATH" "$REPORT_JSON" || rc=$?
  # Sin IaC reconocible y sin hallazgos: no se validó nada; no se presenta como PASS.
  if [[ $rc -eq 0 && -z "$TYPES" ]] && python3 - "$REPORT_JSON" <<'PYEOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
if d["findings"]:
    sys.exit(1)
d["status"] = "NO_IAC"
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PYEOF
  then
    NO_IAC=true
  fi
  (( rc > OVERALL_EXIT )) && OVERALL_EXIT=$rc
  say "Resultado config: $([[ $NO_IAC == true ]] && echo NO_IAC || status_of "$rc")"
fi

if [[ -n "$IMAGE_TARGET" ]]; then
  say "Escaneando imagen Docker: $IMAGE_TARGET"
  rc=0; scan_target image "$IMAGE_TARGET" "$IMAGE_JSON" || rc=$?
  (( rc > OVERALL_EXIT )) && OVERALL_EXIT=$rc
  say "Resultado imagen: $(status_of "$rc")"
fi

case $OVERALL_EXIT in
  0) if [[ $NO_IAC == true && -z "$IMAGE_TARGET" ]]; then
       VERDICT="NO_IAC — no se detectó IaC en $SCAN_PATH; no hay nada que validar."
     else
       VERDICT="PASS — sin hallazgos en severidades bloqueantes ($SEVERITY)."
     fi ;;
  1) VERDICT="FAIL — hallazgos en severidades bloqueantes ($SEVERITY). El pipeline CI debe bloquearse." ;;
  *) VERDICT="ERROR — el escaneo no se completó; el resultado NO es válido y no se ha verificado nada." ;;
esac

{
  echo "# IaC Security Scan — $DATE"
  echo
  echo "## Configuración"
  echo
  echo "- **Severidades bloqueantes**: $SEVERITY (el resto: informativo)"
  echo "- **Ignorefile**: ${IGNOREFILE:-ninguno}"
  if [[ -n "$SCAN_PATH" ]]; then
    echo "- **Path escaneado**: $SCAN_PATH"
    echo "- **Tipos IaC detectados**: ${TYPES:-ninguno}"
  fi
  [[ -n "$IMAGE_TARGET" ]] && echo "- **Imagen escaneada**: $IMAGE_TARGET"
  echo
  echo "## Resultado"
  echo
  echo "**$VERDICT**"
  echo
  for f in "$WORKDIR"/*.summary; do
    [[ -f "$f" ]] || continue
    echo '```'; cat "$f"; echo '```'
  done
  echo
  echo "## Archivos"
  echo
  [[ -n "$SCAN_PATH" ]] && echo "- Report JSON: \`$REPORT_JSON\`"
  [[ -n "$IMAGE_TARGET" ]] && echo "- Report imagen: \`$IMAGE_JSON\`"
  echo
  echo "Supresiones: \`.trivyignore\` del path o \`--ignorefile\`; baseline con \`scripts/iac-security-baseline.sh\`."
  echo
  echo "---"
  echo "*Ref: docs/rules/domain/iac-security-policy.md — SE-241*"
} > "$REPORT_MD"

if [[ "$FORMAT" == "json" && $OVERALL_EXIT -lt 2 ]]; then
  if [[ -n "$SCAN_PATH" ]]; then cat "$REPORT_JSON"; else cat "$IMAGE_JSON"; fi
fi
say ""
say "$VERDICT"
say "Summary: $REPORT_MD"
exit "$OVERALL_EXIT"
