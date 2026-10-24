#!/usr/bin/env bats
# test-se244-dependency-scan.bats — Tests para SE-244 Dependency Vulnerability Scanning
# Ref: docs/propuestas/SE-244-dependency-vulnerability-scanning.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRIPTS="$REPO_ROOT/scripts"
  SKILLS="$REPO_ROOT/.opencode/skills"
  DOCS="$REPO_ROOT/docs/rules/domain"
}

# ── Test 1: dependency-scan.sh existe y pasa bash -n ────────────────────────
@test "SE-244-01: dependency-scan.sh existe y pasa bash -n" {
  [ -f "$SCRIPTS/dependency-scan.sh" ]
  run bash -n "$SCRIPTS/dependency-scan.sh"
  [ "$status" -eq 0 ]
}

# ── Test 2: dependency-scanner/SKILL.md existe y ≤150 líneas ─────────────────
@test "SE-244-02: dependency-scanner/SKILL.md existe y tiene 150 lineas o menos" {
  local skill_file="$SKILLS/dependency-scanner/SKILL.md"
  [ -f "$skill_file" ]
  local lines
  lines=$(wc -l < "$skill_file")
  [ "$lines" -le 150 ]
}

# ── Test 3: dependency-security-policy.md existe y ≤150 líneas ───────────────
@test "SE-244-03: dependency-security-policy.md existe y tiene 150 lineas o menos" {
  local policy_file="$DOCS/dependency-security-policy.md"
  [ -f "$policy_file" ]
  local lines
  lines=$(wc -l < "$policy_file")
  [ "$lines" -le 150 ]
}

# ── Test 4: Sin Trivy instalado → muestra alternativa Docker ─────────────────
@test "SE-244-04: sin Trivy muestra alternativa Docker en mensaje" {
  grep -q "aquasec/trivy\|docker run.*trivy" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 5: El script acepta --path ──────────────────────────────────────────
@test "SE-244-05: dependency-scan.sh acepta --path" {
  grep -q "\-\-path" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 6: El script acepta --generate-sbom ─────────────────────────────────
@test "SE-244-06: dependency-scan.sh acepta --generate-sbom" {
  grep -q "\-\-generate-sbom" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 7: El script auto-detecta package.json (Node) ───────────────────────
@test "SE-244-07: dependency-scan.sh auto-detecta package.json para Node" {
  grep -q "package.json" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 8: El script auto-detecta requirements.txt (Python) ─────────────────
@test "SE-244-08: dependency-scan.sh auto-detecta requirements.txt para Python" {
  grep -q "requirements.txt" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 9: El script auto-detecta *.csproj (C#) ─────────────────────────────
@test "SE-244-09: dependency-scan.sh auto-detecta *.csproj para C#/.NET" {
  grep -q "\.csproj" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 10: El script genera SBOM en output/security/ ───────────────────────
@test "SE-244-10: dependency-scan.sh genera SBOM en output/security/" {
  grep -q "output/security" "$SCRIPTS/dependency-scan.sh"
  grep -q "sbom" "$SCRIPTS/dependency-scan.sh"
}

# ── Test 11: dependency-security-policy.md menciona SBOM o CycloneDX ─────────
@test "SE-244-11: dependency-security-policy.md menciona SBOM o CycloneDX" {
  local policy_file="$DOCS/dependency-security-policy.md"
  grep -qiE "SBOM|CycloneDX" "$policy_file"
}

# ── Test 12: dependency-scan.sh tiene set -uo pipefail ───────────────────────
@test "SE-244-12: dependency-scan.sh tiene set -uo pipefail" {
  grep -qE "set -[ue]o pipefail|set -uo pipefail" "$SCRIPTS/dependency-scan.sh"
}


# ═══════════════════════════════════════════════════════════════════════════
# Comportamiento: árbol temporal con el script, Trivy simulado en el PATH.
# ═══════════════════════════════════════════════════════════════════════════

mk_dep() {
  D="$(mktemp -d)"
  mkdir -p "$D/tree/scripts" "$D/tree/.claude/hooks/lib" "$D/bin" "$D/proj" "$D/out"
  cp "$REPO_ROOT/scripts/dependency-scan.sh" "$D/tree/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$D/tree/.claude/hooks/lib/"
  echo '{}' > "$D/proj/package.json"
  # Trivy falso: registra argumentos; escribe FAKE_REPORT (o FAKE_SBOM con cyclonedx) en --output
  cat > "$D/bin/trivy" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$FAKE_ARGS"
printf -- '--call--\n' >> "$FAKE_ARGS"
fmt=""; out=""
while [[ $# -gt 0 ]]; do
  case "$1" in --format) fmt="$2" ;; --output) out="$2" ;; esac
  shift
done
if [[ "$fmt" == "cyclonedx" ]]; then
  [[ -n "${FAKE_SBOM:-}" ]] && printf '%s' "$FAKE_SBOM" > "$out"
  exit "${FAKE_SBOM_EXIT:-0}"
fi
[[ -n "${FAKE_REPORT:-}" ]] && printf '%s' "$FAKE_REPORT" > "$out"
exit "${FAKE_EXIT:-0}"
EOS
  chmod +x "$D/bin/trivy"
  export FAKE_ARGS="$D/args.txt"
  : > "$FAKE_ARGS"
  export DEP_SCAN_OUTPUT_DIR="$D/out"
}

dep() { run env PATH="$D/bin:$PATH" bash "$D/tree/scripts/dependency-scan.sh" "$@"; }
dlast() { printf '%s\n' "$output" | tail -1; }
rm_dep() { find "${D:-/nonexistent}" -delete 2>/dev/null; true; }

CLEAN_REPORT='{"SchemaVersion":2,"Results":[{"Target":"package-lock.json","Vulnerabilities":[{"Severity":"LOW","VulnerabilityID":"CVE-1","PkgName":"a","InstalledVersion":"1.0"}]}]}'
VULN_REPORT='{"SchemaVersion":2,"Results":[{"Target":"package-lock.json","Vulnerabilities":[{"Severity":"HIGH","VulnerabilityID":"CVE-2024-1","PkgName":"lodash","InstalledVersion":"4.0.0","FixedVersion":"4.17.21"},{"Severity":"LOW","VulnerabilityID":"CVE-2","PkgName":"b","InstalledVersion":"1"}]}]}'

@test "SE244-B01: usage errors exit 2 and name the problem" {
  mk_dep
  dep
  [ "$status" -eq 2 ]
  [[ "$output" == *"especifica --path"* ]]
  dep --path
  [ "$status" -eq 2 ]
  [[ "$output" == *"--path necesita un valor"* ]]
  dep --path "$D/nope"
  [ "$status" -eq 2 ]
  [[ "$output" == *"el path no existe"* ]]
  dep --path "$D/proj" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
  rm_dep
}

@test "SE244-B02: invalid severity lists are rejected before scanning" {
  mk_dep
  for s in "high" "HIGH;ls" "HIGH,,LOW" ""; do
    dep --path "$D/proj" --severity "$s"
    [ "$status" -eq 2 ]
  done
  [ ! -s "$FAKE_ARGS" ]
  rm_dep
}

@test "SE244-B03: no findings at the requested severities is clean (exit 0) with a report" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: Sin vulnerabilidades en severidades CRITICAL,HIGH."* ]]
  [[ "$output" != *"SBOM:   "* ]]
  [ "$(dlast)" = 'gate-result: {"result":"clean","gaps":[]}' ]
  [ -s "$D/out/dep-scan-$(date +%Y%m%d).json" ]
  rm_dep
}

@test "SE244-B04: a HIGH finding exits 1, lists id, package, fix and target" {
  mk_dep
  FAKE_REPORT="$VULN_REPORT" dep --path "$D/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hallazgos (1):"* ]]
  [[ "$output" == *"HIGH"*"CVE-2024-1"*"lodash 4.0.0 → 4.17.21"*"package-lock.json"* ]]
  [[ "$output" != *"CVE-2"$'\t'* ]]
  [[ "$output" == *"FAIL: Vulnerabilidades CRITICAL,HIGH detectadas"* ]]
  [ "$(dlast)" = 'gate-result: {"result":"findings","gaps":[]}' ]
  rm_dep
}

@test "SE244-B05: a finding without a fix says 'sin fix'" {
  mk_dep
  FAKE_REPORT='{"SchemaVersion":2,"Results":[{"Target":"t","Vulnerabilities":[{"Severity":"CRITICAL","VulnerabilityID":"CVE-9","PkgName":"x","InstalledVersion":"1"}]}]}' dep --path "$D/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"x 1 → sin fix"* ]]
  rm_dep
}

@test "SE244-B06: --severity widens the verdict to lower levels" {
  mk_dep
  FAKE_REPORT="$VULN_REPORT" dep --path "$D/proj" --severity LOW
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hallazgos (1):"* ]]
  [[ "$output" == *"CVE-2"* ]]
  [[ "$output" != *"CVE-2024-1"* ]]
  rm_dep
}

@test "SE244-B07: trivy is called with severity, vuln scanner, json format and the scan path" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj" --severity CRITICAL
  [ "$status" -eq 0 ]
  grep -qx -- 'fs' "$FAKE_ARGS"
  grep -qx -- '--severity' "$FAKE_ARGS"
  grep -qx -- 'CRITICAL' "$FAKE_ARGS"
  grep -qx -- '--scanners' "$FAKE_ARGS"
  grep -qx -- 'vuln' "$FAKE_ARGS"
  grep -qx -- 'json' "$FAKE_ARGS"
  grep -qx -- "$D/proj" "$FAKE_ARGS"
  ! grep -qx -- '--skip-db-update' "$FAKE_ARGS"
  rm_dep
}

@test "SE244-B08: --skip-update passes --skip-db-update to trivy" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj" --skip-update
  grep -qx -- '--skip-db-update' "$FAKE_ARGS"
  rm_dep
}

@test "SE244-B09: a .trivyignore in the scanned path is passed to trivy" {
  mk_dep
  : > "$D/proj/.trivyignore"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  grep -qx -- '--ignorefile' "$FAKE_ARGS"
  grep -qx -- "$D/proj/.trivyignore" "$FAKE_ARGS"
  rm_dep
}

@test "SE244-B10: project types are detected from manifests" {
  mk_dep
  : > "$D/proj/requirements.txt"
  : > "$D/proj/App.csproj"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [[ "$output" == *"Tipos de proyecto detectados: "*"node"* ]]
  [[ "$output" == *"python-requirements"* ]]
  [[ "$output" == *"dotnet"* ]]
  rm "$D/proj/package.json" "$D/proj/requirements.txt" "$D/proj/App.csproj"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [[ "$output" == *"Tipos de proyecto detectados: unknown"* ]]
  rm_dep
}

@test "SE244-B11: manifests under node_modules do not count as project types" {
  mk_dep
  rm "$D/proj/package.json"
  mkdir -p "$D/proj/node_modules/x"
  echo '{}' > "$D/proj/node_modules/x/package.json"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [[ "$output" == *"Tipos de proyecto detectados: unknown"* ]]
  rm_dep
}

@test "SE244-B12: trivy failing is unknown (exit 2), never clean, and keeps the output as .failed" {
  mk_dep
  FAKE_REPORT='partial' FAKE_EXIT=1 dep --path "$D/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"el escaneo no se completó (trivy rc=1)"* ]]
  [ "$(dlast)" = 'gate-result: {"result":"unknown","gaps":[{"check":"trivy","reason":"unreadable"}]}' ]
  [ -f "$D/out/dep-scan-$(date +%Y%m%d).json.failed" ]
  [ ! -f "$D/out/dep-scan-$(date +%Y%m%d).json" ]
  rm_dep
}

@test "SE244-B13: trivy timeout (rc 124) is reported as a timeout gap" {
  mk_dep
  FAKE_EXIT=124 dep --path "$D/proj"
  [ "$status" -eq 2 ]
  [[ "$(dlast)" == *'"reason":"timeout"'* ]]
  rm_dep
}

@test "SE244-B14: a report with an unknown schema version is an error, not clean" {
  mk_dep
  FAKE_REPORT='{"SchemaVersion":3,"Results":[]}' dep --path "$D/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"informe ilegible o esquema desconocido"* ]]
  FAKE_REPORT='not json' dep --path "$D/proj"
  [ "$status" -eq 2 ]
  rm_dep
}

@test "SE244-B15: a failed scan does not overwrite a good report from earlier the same day" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [ "$status" -eq 0 ]
  cp "$D/out/dep-scan-$(date +%Y%m%d).json" "$D/good.json"
  FAKE_REPORT='garbage' FAKE_EXIT=1 dep --path "$D/proj"
  [ "$status" -eq 2 ]
  cmp "$D/out/dep-scan-$(date +%Y%m%d).json" "$D/good.json"
  rm_dep
}

@test "SE244-B16: a null Results list is a valid clean report" {
  mk_dep
  FAKE_REPORT='{"SchemaVersion":2,"Results":null}' dep --path "$D/proj"
  [ "$status" -eq 0 ]
  rm_dep
}

@test "SE244-B17: --generate-sbom publishes a CycloneDX file" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" FAKE_SBOM='{"bomFormat":"CycloneDX","components":[]}' dep --path "$D/proj" --generate-sbom
  [ "$status" -eq 0 ]
  [[ "$output" == *"SBOM generado: $D/out/sbom-$(date +%Y%m%d).json"* ]]
  [[ "$output" == *"SBOM:   $D/out/sbom-$(date +%Y%m%d).json"* ]]
  [ "$(jq -r .bomFormat "$D/out/sbom-$(date +%Y%m%d).json")" = "CycloneDX" ]
  grep -qx -- 'cyclonedx' "$FAKE_ARGS"
  rm_dep
}

@test "SE244-B18: without --generate-sbom trivy is called once and no SBOM is written" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [ "$(grep -c -- '--call--' "$FAKE_ARGS")" -eq 1 ]
  [ ! -e "$D/out/sbom-$(date +%Y%m%d).json" ]
  rm_dep
}

@test "SE244-B19: an invalid SBOM exits 2, keeps .failed and writes no sbom file" {
  mk_dep
  FAKE_REPORT="$CLEAN_REPORT" FAKE_SBOM='{"bomFormat":"Other"}' dep --path "$D/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [[ "$output" == *"SBOM no generado"* ]]
  [[ "$output" != *"SBOM:   "* ]]
  [ "$(dlast)" = 'gate-result: {"result":"unknown","gaps":[{"check":"sbom","reason":"unreadable"}]}' ]
  [ ! -e "$D/out/sbom-$(date +%Y%m%d).json" ]
  [ -f "$D/out/sbom-$(date +%Y%m%d).json.failed" ]
  rm_dep
}

@test "SE244-B20: a failed SBOM turns an earlier SBOM of the same day into .stale" {
  mk_dep
  day="$(date +%Y%m%d)"
  FAKE_REPORT="$CLEAN_REPORT" FAKE_SBOM='{"bomFormat":"CycloneDX"}' dep --path "$D/proj" --generate-sbom
  [ "$status" -eq 0 ]
  FAKE_REPORT="$CLEAN_REPORT" FAKE_SBOM_EXIT=1 dep --path "$D/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [ ! -e "$D/out/sbom-$day.json" ]
  [ -f "$D/out/sbom-$day.json.stale" ]
  rm_dep
}

@test "SE244-B21: findings plus a failed SBOM exit 2 (error wins) but still list the findings" {
  mk_dep
  FAKE_REPORT="$VULN_REPORT" FAKE_SBOM_EXIT=1 dep --path "$D/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [[ "$output" == *"CVE-2024-1"* ]]
  [[ "$output" == *"SBOM no generado"* ]]
  rm_dep
}

@test "SE244-B22: without trivy or docker the scan is unknown with a missing_tool gap" {
  mk_dep
  rm "$D/bin/trivy"
  mkdir -p "$D/min"
  for b in bash jq mkdir mktemp date cat dirname find grep sed tr wc head rm mv; do
    p="$(command -v $b)" && ln -sf "$p" "$D/min/$b"
  done
  run env PATH="$D/min" bash "$D/tree/scripts/dependency-scan.sh" --path "$D/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Ni Trivy ni Docker disponibles"* ]]
  [ "$(dlast)" = 'gate-result: {"result":"unknown","gaps":[{"check":"trivy","reason":"missing_tool"}]}' ]
  rm_dep
}

@test "SE244-B23: DEP_SCAN_OUTPUT_DIR is created when it does not exist" {
  mk_dep
  export DEP_SCAN_OUTPUT_DIR="$D/new/dir"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [ "$status" -eq 0 ]
  [ -s "$D/new/dir/dep-scan-$(date +%Y%m%d).json" ]
  rm_dep
}

@test "SE244-B24: an output directory that cannot be created is unknown (exit 2)" {
  mk_dep
  : > "$D/afile"
  export DEP_SCAN_OUTPUT_DIR="$D/afile/sub"
  FAKE_REPORT="$CLEAN_REPORT" dep --path "$D/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no se puede crear el directorio de salida"* ]]
  [ "$(dlast)" = 'gate-result: {"result":"unknown","gaps":[{"check":"output-dir","reason":"unreadable"}]}' ]
  [ ! -s "$FAKE_ARGS" ]
  rm_dep
}
