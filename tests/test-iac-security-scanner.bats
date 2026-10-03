#!/usr/bin/env bats
# SE-376 — iac-security-scanner: comportamiento real de iac-security-scan.sh e
# iac-security-baseline.sh con un trivy y un docker falsos (sin red, sin instalar nada).
# Ref: docs/rules/domain/iac-security-policy.md · docs/propuestas/SE-241-iac-security-scanning.md
# Ref: .claude/skills/iac-security-scanner/SKILL.md
set -uo pipefail

SCRIPT="scripts/iac-security-scan.sh"
BASELINE="scripts/iac-security-baseline.sh"
bats_require_minimum_version 1.5.0

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "${BATS_TEST_TMPDIR:-/tmp}")"
  # Proyecto aislado: los informes van a $WORK/proj/output/security, nunca al repo real.
  mkdir -p "$WORK/proj/scripts" "$WORK/stub" "$WORK/sys" "$WORK/cwd"
  cp "$REPO_ROOT/$SCRIPT" "$REPO_ROOT/$BASELINE" "$WORK/proj/scripts/"
  SCAN="$WORK/proj/scripts/iac-security-scan.sh"
  BASE="$WORK/proj/scripts/iac-security-baseline.sh"
  OUT="$WORK/proj/output/security"
  # PATH controlado: solo utilidades básicas (ni trivy ni docker reales del runner).
  for b in bash python3 find grep xargs mkdir mktemp mv cp rm date cat dirname basename \
           sort head tail wc tr sed awk env ls chmod ln; do
    p="$(command -v "$b")" && ln -sf "$p" "$WORK/sys/$b"
  done
  # trivy falso: apunta argumentos, escribe $TRIVY_JSON (o $TRIVY_RAW) y respeta --exit-code/--output.
  cat > "$WORK/stub/trivy" <<'STUB'
#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
open(os.environ["TRIVY_LOG"], "a").write("\t".join(a) + "\n")
if os.environ.get("TRIVY_FAIL") == "1":
    sys.stderr.write("FATAL: stub failure\n"); sys.exit(1)
raw = os.environ.get("TRIVY_RAW")
txt = raw if raw is not None else open(os.environ["TRIVY_JSON"]).read()
out = a[a.index("--output") + 1] if "--output" in a else None
fmt = a[a.index("--format") + 1] if "--format" in a else "table"
ec = int(a[a.index("--exit-code") + 1]) if "--exit-code" in a else 0
if fmt == "json":
    (open(out, "w").write(txt) if out else sys.stdout.write(txt))
try:
    n = sum(len(r.get("Misconfigurations") or []) for r in json.loads(txt).get("Results") or [])
except Exception as exc:
    sys.stderr.write("stub: %s\n" % exc); n = 0
sys.exit(ec if n else 0)
STUB
  chmod +x "$WORK/stub/trivy"
  ORIG_PATH="$PATH"
  export TRIVY_LOG="$WORK/trivy.log" PATH="$WORK/stub:$WORK/sys"
  : > "$TRIVY_LOG"
  INFRA="$WORK/mi proyecto/infra"
  mkdir -p "$INFRA"
  printf 'resource "aws_s3_bucket" "b" { acl = "public-read" }\n' > "$INFRA/main.tf"
  printf 'FROM alpine\n' > "$INFRA/Dockerfile"
  findings_json > "$WORK/findings.json"
  export TRIVY_JSON="$WORK/findings.json"
  cd "$WORK/cwd" || return 1
}

teardown() { export PATH="$ORIG_PATH"; cd "$REPO_ROOT" || true; rm -rf "$WORK"; }

mis() { printf '{"ID":"%s","AVDID":"%s","Title":"%s","Severity":"%s","Status":"%s"}' "$1" "$2" "$3" "$4" "${5:-FAIL}"; }
findings_json() {
  printf '{"SchemaVersion":2,"Results":[{"Target":"main.tf","Misconfigurations":[%s,%s,%s]},' \
    "$(mis AVD-AWS-0089 AVD-AWS-0089 'S3 public ACL' HIGH)" "$(mis AVD-AWS-0057 AVD-AWS-0057 'IAM wildcard' CRITICAL)" \
    "$(mis AVD-AWS-0086 AVD-AWS-0086 'Block public acls' MEDIUM)"
  printf '{"Target":"Dockerfile","Misconfigurations":[%s,%s]}]}' \
    "$(mis DS002 AVD-DS-0002 'Root user' HIGH)" "$(mis DS026 AVD-DS-0026 'No healthcheck' LOW)"
}
only() { printf '{"Results":[{"Target":"main.tf","Misconfigurations":[%s]}]}' "$1" > "$WORK/only.json"; export TRIVY_JSON="$WORK/only.json"; }
report() { ls "$OUT"/iac-scan-*.json; }
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$@"; }

# ── Seguridad del propio script ──────────────────────────────────────────────

@test "safety: ambos scripts declaran set -uo pipefail y pasan bash -n" {
  for s in "$SCRIPT" "$BASELINE"; do
    grep -q "set -uo pipefail" "$REPO_ROOT/$s"
    run bash -n "$REPO_ROOT/$s"
    [ "$status" -eq 0 ]
  done
}

# ── Positivos: severidades y umbrales ────────────────────────────────────────

@test "scan: IaC limpio (Results vacío) ⇒ exit 0, PASS y report JSON válido" {
  printf '{"Results":[]}' > "$WORK/clean.json"
  TRIVY_JSON="$WORK/clean.json" run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  [ "$(jget "$(report)" 'd["status"]')" = "PASS" ]
}

@test "scan: CRITICAL y HIGH ⇒ exit 1 y el report cuenta 3 bloqueantes" {
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
  [ "$(jget "$(report)" 'd["summary"]["blocking"]')" = "3" ]
  [ "$(jget "$(report)" 'd["status"]')" = "FAIL" ]
}

@test "scan: MEDIUM y LOW se muestran como informativos y no bloquean (exit 0)" {
  printf '{"Results":[{"Target":"main.tf","Misconfigurations":[%s,%s]}]}' \
    "$(mis AVD-AWS-0086 AVD-AWS-0086 'Block public acls' MEDIUM)" "$(mis DS026 AVD-DS-0026 'No healthcheck' LOW)" > "$WORK/ml.json"
  TRIVY_JSON="$WORK/ml.json" run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO] MEDIUM"*"AVD-AWS-0086"* ]]
  [[ "$output" == *"[INFO] LOW"*"DS026"* ]]
}

@test "scan: --severity CRITICAL convierte HIGH en informativo (umbral más permisivo)" {
  only "$(mis DS002 AVD-DS-0002 'Root user' HIGH)"
  run bash "$SCAN" --path "$INFRA" --severity CRITICAL
  [ "$status" -eq 0 ]
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
}

@test "scan: --severity en minúsculas se normaliza (critical,high ⇒ bloquea)" {
  run bash "$SCAN" --path "$INFRA" --severity critical,high
  [ "$status" -eq 1 ]
  [ "$(jget "$(report)" '",".join(d["blocking_severities"])')" = "CRITICAL,HIGH" ]
}

@test "scan: trivy se invoca una sola vez, con --exit-code 0 y un ignorefile explícito" {
  run bash "$SCAN" --path "$INFRA"
  [ "$(wc -l < "$TRIVY_LOG")" -eq 1 ]
  grep -q -- $'--exit-code\t0' "$TRIVY_LOG"
  grep -q -- $'--ignorefile\t' "$TRIVY_LOG"
  grep -q -- $'--severity\tUNKNOWN,LOW,MEDIUM,HIGH,CRITICAL' "$TRIVY_LOG"
}

@test "scan: --skip-update en modo config pasa --skip-check-update a trivy" {
  run bash "$SCAN" --path "$INFRA" --skip-update
  grep -q -- '--skip-check-update' "$TRIVY_LOG"
  run grep -q -- '--skip-db-update' "$TRIVY_LOG"
  [ "$status" -ne 0 ]
}

@test "scan: --format json deja en stdout un JSON válido con los hallazgos" {
  run --separate-stderr bash "$SCAN" --path "$INFRA" --format json
  [ "$status" -eq 1 ]
  printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["findings"])==5, d'
}

@test "scan: escribe el summary Markdown con el veredicto FAIL" {
  run bash "$SCAN" --path "$INFRA"
  grep -q "FAIL" "$OUT"/iac-scan-*.md
  grep -q "Bloqueantes: 3" "$OUT"/iac-scan-*.md
}

@test "scan: detecta k8s en .yml, compose en .yaml y rutas con espacios" {
  printf 'apiVersion: v1\nkind: Pod\n' > "$INFRA/pod manifest.yml"
  printf 'services:\n  web:\n    image: x\n' > "$INFRA/docker-compose.prod.yaml"
  run bash "$SCAN" --path "$INFRA"
  [[ "$output" == *"kubernetes"* ]]
  [[ "$output" == *"docker-compose"* ]]
  [[ "$output" == *"terraform"* ]]
}

@test "scan: imagen con CVE CRITICAL ⇒ exit 1 e informe de imagen" {
  printf '{"Results":[{"Target":"img","Vulnerabilities":[{"VulnerabilityID":"CVE-2024-1","PkgName":"openssl","InstalledVersion":"1.0","Severity":"CRITICAL"}]}]}' > "$WORK/img.json"
  TRIVY_JSON="$WORK/img.json" run bash "$SCAN" --image myapp:latest
  [ "$status" -eq 1 ]
  [ "$(jget "$OUT"/iac-image-scan-*.json 'd["findings"][0]["id"]')" = "CVE-2024-1" ]
  grep -q $'^image\t' "$TRIVY_LOG"
}

# ── Fail-closed: herramienta ausente, rota o salida inválida ─────────────────

@test "scan: trivy falla (fatal) ⇒ exit 2 ERROR, sin afirmar hallazgos ni PASS" {
  TRIVY_FAIL=1 run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Hallazgos CRITICAL/HIGH detectados"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "scan: un fallo posterior sobrescribe el report PASS del mismo día con status ERROR" {
  printf '{"Results":[]}' > "$WORK/clean.json"
  TRIVY_JSON="$WORK/clean.json" run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  TRIVY_FAIL=1 run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
  [ "$(jget "$(report)" 'd["status"]')" = "ERROR" ]
  grep -q "ERROR" "$OUT"/iac-scan-*.md
}

@test "baseline: hacer source del scan solo carga funciones, no escanea" {
  run bash -c 'source "$1"; declare -F iac_run_trivy iac_evaluate >/dev/null && echo cargado' _ "$SCAN"
  [ "$status" -eq 0 ]
  [ "$output" = "cargado" ]
  [ ! -s "$TRIVY_LOG" ]
}

@test "scan: trivy devuelve JSON inválido ⇒ exit 2 (error, nunca PASS)" {
  TRIVY_RAW='not json' run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
  [[ "$output" == *"JSON"* ]]
}

@test "scan: trivy sale 0 con salida vacía ⇒ exit 2 (empty no es limpio)" {
  TRIVY_RAW='' run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
}

@test "scan: sin trivy ni docker ⇒ exit 2 con instrucción de instalación" {
  mv "$WORK/stub/trivy" "$WORK/trivy.off"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Ni Trivy ni Docker"* ]]
}

@test "scan: fallback docker monta la ruta (con espacios) en /workspace y evalúa su JSON" {
  mv "$WORK/stub/trivy" "$WORK/trivy.off"
  cat > "$WORK/stub/docker" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DOCKER_ARGS"
cat "$TRIVY_JSON"
STUB
  chmod +x "$WORK/stub/docker"
  DOCKER_ARGS="$WORK/docker.args" run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
  grep -qxF "$INFRA:/workspace:ro" "$WORK/docker.args"
  run grep -q -- '^--severity:' "$WORK/docker.args"
  [ "$status" -ne 0 ]
  [ "$(tail -1 "$WORK/docker.args")" = "/workspace" ]
}

@test "scan: fallback docker que falla ⇒ exit 2" {
  mv "$WORK/stub/trivy" "$WORK/trivy.off"
  printf '#!/usr/bin/env bash\necho "Cannot connect to the Docker daemon" >&2\nexit 125\n' > "$WORK/stub/docker"
  chmod +x "$WORK/stub/docker"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 2 ]
}

# ── Supresiones (.trivyignore) ───────────────────────────────────────────────

@test "scan: .trivyignore del path (con espacios) suprime y lo informa; CRITICAL suprimido avisa" {
  printf '# justificado\nAVD-AWS-0089\nAVD-AWS-0057\nDS002\n' > "$INFRA/.trivyignore"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [ "$(jget "$(report)" 'd["summary"]["suppressed"]')" = "3" ]
  [[ "$output" == *"CRITICAL suprimidos"* ]]
  [[ "$output" == *"[SUPRIMIDO]"* ]]
}

@test "scan: un .trivyignore del directorio actual NO suprime a escondidas (reject implícito)" {
  printf 'AVD-AWS-0089\nAVD-AWS-0057\nDS002\n' > "$WORK/cwd/.trivyignore"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
}

@test "scan: --ignorefile explícito se aplica; si no existe ⇒ exit 2" {
  printf 'AVD-AWS-0089\nAVD-AWS-0057\nDS002\n' > "$WORK/ignore list"
  run bash "$SCAN" --path "$INFRA" --ignorefile "$WORK/ignore list"
  [ "$status" -eq 0 ]
  run bash "$SCAN" --path "$INFRA" --ignorefile "$WORK/no-existe"
  [ "$status" -eq 2 ]
}

@test "scan: supresión caducada (exp: pasado) no se aplica y se avisa" {
  printf 'AVD-AWS-0089 exp:2020-01-01\nAVD-AWS-0057\nDS002\n' > "$INFRA/.trivyignore"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"caducadas"*"AVD-AWS-0089"* ]]
}

@test "scan: supresión por AVDID (AVD-DS-0002) cubre DS002; las no usadas se listan" {
  only "$(mis DS002 AVD-DS-0002 'Root user' HIGH)"
  printf 'AVD-DS-0002\nAVD-AWS-9999\n' > "$INFRA/.trivyignore"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin hallazgo asociado"*"AVD-AWS-9999"* ]]
}

@test "scan: entradas con Status PASS no cuentan como hallazgo" {
  only "$(mis AVD-AWS-0057 AVD-AWS-0057 'IAM wildcard' CRITICAL PASS)"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
}

# ── Argumentos inválidos ─────────────────────────────────────────────────────

@test "scan: severidad inválida o vacía ⇒ exit 2 (invalid, sin llamar a trivy)" {
  run bash "$SCAN" --path "$INFRA" --severity BOGUS
  [ "$status" -eq 2 ]
  run bash "$SCAN" --path "$INFRA" --severity ""
  [ "$status" -eq 2 ]
  [ ! -s "$TRIVY_LOG" ]
}

@test "scan: --format inválido ⇒ exit 2" {
  run bash "$SCAN" --path "$INFRA" --format xml
  [ "$status" -eq 2 ]
}

@test "scan: --path sin valor, path inexistente, argumento desconocido o sin args ⇒ exit 2" {
  run bash "$SCAN" --path
  [ "$status" -eq 2 ]
  [[ "$output" != *"unbound"* && "$output" != *"sin asignar"* ]]
  run bash "$SCAN" --path "$WORK/nope"
  [ "$status" -eq 2 ]
  run bash "$SCAN" --bogus
  [ "$status" -eq 2 ]
  run bash "$SCAN"
  [ "$status" -eq 2 ]
}

# ── Límites ──────────────────────────────────────────────────────────────────

@test "scan: directorio sin IaC (empty) ⇒ exit 0 pero dice NO_IAC, no PASS" {
  mkdir -p "$WORK/vacio"
  printf '{"Results":null}' > "$WORK/null.json"
  TRIVY_JSON="$WORK/null.json" run bash "$SCAN" --path "$WORK/vacio"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO_IAC"* ]]
  [ "$(jget "$(report)" 'd["status"]')" = "NO_IAC" ]
}

@test "scan: volumen grande (500 hallazgos HIGH) se cuenta exacto" {
  python3 -c 'import json; print(json.dumps({"Results":[{"Target":"f%d.tf"%i,"Misconfigurations":[{"ID":"AVD-X-%04d"%i,"Severity":"HIGH","Status":"FAIL"}]} for i in range(500)]}))' > "$WORK/big.json"
  TRIVY_JSON="$WORK/big.json" run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
  [ "$(jget "$(report)" 'd["summary"]["blocking"]')" = "500" ]
}

# ── Baseline ─────────────────────────────────────────────────────────────────

@test "baseline: genera IDs con severidad y ficheros afectados; exit 0" {
  run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 0 ]
  grep -qx "AVD-AWS-0057" "$WORK/base.ignore"
  grep -qx "DS002" "$WORK/base.ignore"
  grep -q "CRITICAL.*main.tf" "$WORK/base.ignore"
  [ "$(grep -cvE '^(#|$)' "$WORK/base.ignore")" -eq 5 ]
}

@test "baseline: trivy falla ⇒ exit 2 y NO escribe un fichero que diga limpio (fail-open)" {
  TRIVY_FAIL=1 run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 2 ]
  [ ! -e "$WORK/base.ignore" ]
  [[ "$output" != *"limpio"* ]]
}

@test "baseline: JSON inválido ⇒ exit 2 sin fichero" {
  TRIVY_RAW='{"Results": [' run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 2 ]
  [ ! -e "$WORK/base.ignore" ]
}

@test "baseline: no sobrescribe un .trivyignore existente sin --force (block)" {
  printf 'AVD-MANUAL-1  # justificado a mano\n' > "$WORK/base.ignore"
  run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 2 ]
  grep -q "AVD-MANUAL-1" "$WORK/base.ignore"
  run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore" --force
  [ "$status" -eq 0 ]
  grep -qx "DS002" "$WORK/base.ignore"
}

@test "baseline: ignora entradas Status PASS y con IaC limpio escribe cero IDs" {
  only "$(mis AVD-AWS-0057 AVD-AWS-0057 'IAM wildcard' CRITICAL PASS)"
  run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 0 ]
  [ "$(grep -cvE '^(#|$)' "$WORK/base.ignore")" -eq 0 ]
}

@test "baseline: sin trivy ni docker ⇒ exit 2; --path sin valor ⇒ exit 2" {
  mv "$WORK/stub/trivy" "$WORK/trivy.off"
  run bash "$BASE" --path "$INFRA" --output "$WORK/base.ignore"
  [ "$status" -eq 2 ]
  run bash "$BASE" --path
  [ "$status" -eq 2 ]
}

@test "baseline → scan: el baseline generado deja el gate en exit 0 y todo SUPRIMIDO" {
  run bash "$BASE" --path "$INFRA" --output "$INFRA/.trivyignore"
  [ "$status" -eq 0 ]
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [ "$(jget "$(report)" 'd["summary"]["suppressed"]')" = "5" ]
}

@test "baseline → scan: sin --output escribe <path>/.trivyignore y el scan lo aplica (flujo documentado)" {
  run bash "$BASE" --path "$INFRA"
  [ "$status" -eq 0 ]
  [ -f "$INFRA/.trivyignore" ]
  [ ! -e "$WORK/cwd/.trivyignore" ]
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 0 ]
  [ "$(jget "$(report)" 'd["summary"]["suppressed"]')" = "5" ]
}

@test "scan: exp: con formato inválido (2099/12/01) no se aplica y se avisa (reject)" {
  only "$(mis DS002 AVD-DS-0002 'Root user' HIGH)"
  printf 'DS002 exp:2099/12/01\n' > "$INFRA/.trivyignore"
  run bash "$SCAN" --path "$INFRA"
  [ "$status" -eq 1 ]
  [[ "$output" == *"exp: inválido"*"DS002"* ]]
}
