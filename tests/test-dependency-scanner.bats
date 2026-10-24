#!/usr/bin/env bats
# Ref: docs/rules/domain/dependency-security-policy.md — SE-244 / SE-376
#
# Comportamiento de scripts/dependency-scan.sh con un trivy (y un docker) falsos en el PATH:
# qué banderas recibe Trivy, cómo se traduce su resultado a códigos de salida y que un fallo
# del escáner nunca se presente como «limpio» ni como «vulnerabilidades», ni fabrique un SBOM.

SCRIPT="scripts/dependency-scan.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR="$(mktemp -d)"
  mkdir -p "$TMPDIR/bin" "$TMPDIR/proj" "$TMPDIR/out"
  printf '{"name":"demo","dependencies":{"lodash":"4.17.0"}}\n' > "$TMPDIR/proj/package.json"
  export DEP_SCAN_OUTPUT_DIR="$TMPDIR/out"
  export FAKE_LOG="$TMPDIR/calls.log"
  export FAKE_JSON='{"SchemaVersion":2,"Results":[]}'
  export FAKE_RC=0
  export FAKE_SBOM_RC=0
  # trivy falso: registra la llamada; con --format json escribe FAKE_JSON; con cyclonedx, un SBOM.
  cat > "$TMPDIR/bin/trivy" <<'EOF'
#!/usr/bin/env bash
echo "trivy $*" >> "$FAKE_LOG"
out="" fmt=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) out="$2"; shift 2 ;;
    --format) fmt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "$fmt" == "cyclonedx" ]]; then
  [[ "$FAKE_SBOM_RC" -ne 0 ]] && exit "$FAKE_SBOM_RC"
  sbom='{"bomFormat":"CycloneDX","components":[{"name":"lodash"}]}'
  printf '%s\n' "${FAKE_SBOM:-$sbom}" > "$out"
  exit "${FAKE_SBOM_RC_AFTER_WRITE:-0}"
fi
[[ "$FAKE_RC" -ne 0 ]] && { echo "FATAL fake trivy failure" >&2; exit "$FAKE_RC"; }
[[ -n "$out" ]] && printf '%s\n' "$FAKE_JSON" > "$out"
[[ -n "${FAKE_DELAY:-}" ]] && sleep "$FAKE_DELAY"
exit "${FAKE_RC_AFTER_WRITE:-0}"
EOF
  chmod +x "$TMPDIR/bin/trivy"
  PATH="$TMPDIR/bin:$PATH"
}

teardown() {
  rm -rf "$TMPDIR"
}

vuln_json() {
  printf '{"SchemaVersion":2,"Results":[{"Target":"package-lock.json","Vulnerabilities":[{"VulnerabilityID":"%s","PkgName":"lodash","InstalledVersion":"4.17.0","FixedVersion":"4.17.21","Severity":"%s"}]}]}' "$1" "$2"
}

@test "target has safety flags" {
  grep -q "set -uo pipefail" "$REPO_ROOT/$SCRIPT"
}

@test "clean scan exits 0 with PASS and writes the JSON report" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
  ls "$TMPDIR/out"/dep-scan-*.json
}

@test "HIGH vulnerability blocks with exit 1 and names the CVE and package" {
  FAKE_JSON="$(vuln_json CVE-2021-23337 HIGH)"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CVE-2021-23337"* ]]
  [[ "$output" == *"lodash"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "MEDIUM vulnerability does not block with the default severities" {
  FAKE_JSON="$(vuln_json CVE-2020-0001 MEDIUM)"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
}

@test "scanner failure is an error (exit 2), never PASS and never a vulnerability verdict" {
  FAKE_RC=1
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"PASS"* ]]
  [[ "$output" != *"Vulnerabilidades CRITICAL/HIGH detectadas"* ]]
  run ls "$TMPDIR/out"
  [ -z "$output" ]
}

@test "invalid JSON from the scanner is an error, not a clean result" {
  FAKE_JSON='no es json'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" != *"PASS"* ]]
}

@test "trivy receives --scanners vuln, the severities and --skip-db-update" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --severity CRITICAL --skip-update
  [ "$status" -eq 0 ]
  grep -q -- "--scanners vuln" "$FAKE_LOG"
  grep -q -- "--severity CRITICAL" "$FAKE_LOG"
  grep -q -- "--skip-db-update" "$FAKE_LOG"
  ! grep -q -- "--security-checks" "$FAKE_LOG"
}

@test "scanner runs once per scan (no triple invocation)" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^trivy fs' "$FAKE_LOG")" -eq 1 ]
}

@test ".trivyignore in the scanned path is passed as --ignorefile" {
  printf 'CVE-2020-0001\n' > "$TMPDIR/proj/.trivyignore"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  grep -q -- "--ignorefile $TMPDIR/proj/.trivyignore" "$FAKE_LOG"
}

@test "SBOM is generated with trivy fs --format cyclonedx" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 0 ]
  grep -q "^trivy fs .*--format cyclonedx" "$FAKE_LOG"
  python3 -c "import json,sys,glob; d=json.load(open(glob.glob(sys.argv[1]+'/sbom-*.json')[0])); assert d['components']" "$TMPDIR/out"
}

@test "SBOM failure is an error and no empty SBOM is fabricated" {
  FAKE_SBOM_RC=1
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [[ "$output" == *"SBOM"* ]]
  ! ls "$TMPDIR/out"/sbom-*.json 2>/dev/null
}

@test "docker fallback mounts the scanned path and passes the flags to trivy fs" {
  PATH="/usr/bin:/bin" command -v trivy >/dev/null && skip "trivy real en /usr/bin"
  mv "$TMPDIR/bin/trivy" "$TMPDIR/trivy.real"
  cat > "$TMPDIR/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$FAKE_LOG"
printf '%s\n' "$FAKE_JSON"
EOF
  chmod +x "$TMPDIR/bin/docker"
  run env PATH="$TMPDIR/bin:/usr/bin:/bin" bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  grep -q -- "-v $TMPDIR/proj:/workspace" "$FAKE_LOG"
  grep -q -- "aquasec/trivy:latest fs .*--scanners vuln.*/workspace$" "$FAKE_LOG"
}

@test "missing --path or a nonexistent path is a usage error (exit 2)" {
  run bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/nonexistent"
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --bad-flag
  [ "$status" -eq 2 ]
}

@test "edge: null Results and empty Vulnerabilities count as clean" {
  FAKE_JSON='{"SchemaVersion":2,"Results":null}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  FAKE_JSON='{"SchemaVersion":2,"Results":[{"Target":"x","Vulnerabilities":[]}]}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
}

@test "edge: neither trivy nor docker available is an error with install guidance" {
  PATH="/usr/bin:/bin" command -v trivy >/dev/null && skip "trivy real en /usr/bin"
  PATH="/usr/bin:/bin" command -v docker >/dev/null && skip "docker real en /usr/bin"
  rm -f "$TMPDIR/bin/trivy"
  run env PATH="$TMPDIR/bin:/usr/bin:/bin" bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Instala Trivy"* ]]
}

@test "unknown report schema is an error, not PASS (fail-closed on Trivy format changes)" {
  FAKE_JSON='{"SchemaVersion":99,"Matches":[{"Severity":"CRITICAL","VulnerabilityID":"CVE-2099-0001"}]}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "malformed Results (not an array of objects) is rejected with exit 2, never PASS" {
  FAKE_JSON='{"SchemaVersion":2,"Results":{"x":1}}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" != *"PASS"* ]]
  FAKE_JSON='{"SchemaVersion":2,"Results":[1]}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" != *"PASS"* ]]
}

@test "docker fallback passes the mounted .trivyignore (/workspace path, not the host path)" {
  PATH="/usr/bin:/bin" command -v trivy >/dev/null && skip "trivy real en /usr/bin"
  mv "$TMPDIR/bin/trivy" "$TMPDIR/trivy.real"
  printf 'CVE-2020-0001\n' > "$TMPDIR/proj/.trivyignore"
  printf '#!/usr/bin/env bash\necho "docker $*" >> "$FAKE_LOG"\nprintf "%%s\\n" "$FAKE_JSON"\n' > "$TMPDIR/bin/docker"
  chmod +x "$TMPDIR/bin/docker"
  run env PATH="$TMPDIR/bin:/usr/bin:/bin" bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  grep -q -- "--ignorefile /workspace/.trivyignore" "$FAKE_LOG"
  ! grep -q -- "--ignorefile $TMPDIR/proj" "$FAKE_LOG"
}

@test "workspace-root .trivyignore is used when the scanned path has none" {
  mkdir -p "$TMPDIR/ws/scripts"
  cp "$REPO_ROOT/$SCRIPT" "$TMPDIR/ws/scripts/"; mkdir -p "$TMPDIR/ws/.claude/hooks/lib"; cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$TMPDIR/ws/.claude/hooks/lib/"
  printf 'CVE-2020-0002\n' > "$TMPDIR/ws/.trivyignore"
  run bash "$TMPDIR/ws/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  grep -q -- "--ignorefile $TMPDIR/ws/.trivyignore" "$FAKE_LOG"
}

@test "findings plus failed SBOM exit 2: the missing release artifact is not hidden" {
  FAKE_JSON="$(vuln_json CVE-2021-23337 HIGH)"
  FAKE_SBOM_RC=1
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [[ "$output" == *"CVE-2021-23337"* ]]
  [[ "$output" == *"SBOM no generado"* ]]
}

@test "failed scan does not overwrite a valid report from an earlier run of the same day" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  report="$(ls "$TMPDIR/out"/dep-scan-*.json)"
  FAKE_JSON='no es json'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  jq -e '.SchemaVersion == 2' "$report"
  ls "$TMPDIR/out"/dep-scan-*.json.failed
  ! ls "$TMPDIR/out"/*.tmp* 2>/dev/null
}

@test "failed SBOM retires an earlier same-day SBOM so it cannot pass as current" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 0 ]
  FAKE_SBOM_RC=1
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 2 ]
  run ls "$TMPDIR/out"/sbom-*.json
  [ "$status" -ne 0 ]
  ls "$TMPDIR/out"/sbom-*.json.stale
  ! ls "$TMPDIR/out"/*.tmp* 2>/dev/null
}

# ── Calibración SE-376 (2026-10-03): casos que la batería anterior no discriminaba ──

@test "trivy failing after writing a valid report is an error (exit 2), not PASS" {
  export FAKE_RC_AFTER_WRITE=3
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"trivy rc=3"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "SBOM written but trivy exits non-zero is rejected (exit 2), no SBOM published" {
  export FAKE_SBOM_RC_AFTER_WRITE=1
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 2 ]
  run ls "$TMPDIR/out"/sbom-*.json
  [ "$status" -ne 0 ]
  ls "$TMPDIR/out"/sbom-*.json.failed
}

@test "SBOM that is not CycloneDX (empty object) is rejected with exit 2" {
  export FAKE_SBOM="{}"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --generate-sbom
  [ "$status" -eq 2 ]
  [[ "$output" == *"SBOM no generado"* ]]
  run ls "$TMPDIR/out"/sbom-*.json
  [ "$status" -ne 0 ]
}

@test "finding lists fixed version, manifest target, and 'sin fix' when there is none" {
  FAKE_JSON='{"SchemaVersion":2,"Results":[{"Target":"package-lock.json","Vulnerabilities":[
    {"VulnerabilityID":"CVE-2021-23337","PkgName":"lodash","InstalledVersion":"4.17.0","FixedVersion":"4.17.21","Severity":"HIGH"},
    {"VulnerabilityID":"CVE-2022-0002","PkgName":"minimist","InstalledVersion":"1.2.0","Severity":"CRITICAL"}]}]}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hallazgos (2)"* ]]
  [[ "$output" == *"lodash 4.17.0 → 4.17.21"*"package-lock.json"* ]]
  [[ "$output" == *"minimist 1.2.0 → sin fix"* ]]
}

@test "malformed Vulnerabilities (not objects) is an error (exit 2), never a silent PASS" {
  FAKE_JSON='{"SchemaVersion":2,"Results":[{"Target":"x","Vulnerabilities":{"a":1}}]}'
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" != *"PASS"* ]]
}

@test "invalid severity list is rejected as usage error (exit 2) before running trivy" {
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --severity "high;rm"
  [ "$status" -eq 2 ]
  [[ "$output" == *"severidades inválidas"* ]]
  [ ! -s "$FAKE_LOG" ]
}

@test "flag without value (--path last) fails fast with exit 2, no infinite loop" {
  run timeout 10 bash "$REPO_ROOT/$SCRIPT" --path
  [ "$status" -eq 2 ]
  run timeout 10 bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" --severity
  [ "$status" -eq 2 ]
}

@test "missing jq is an error (exit 2) instead of an unverifiable verdict" {
  mkdir -p "$TMPDIR/nojq"
  for f in /usr/bin/*; do
    if [[ "$(basename "$f")" != jq ]]; then ln -s "$f" "$TMPDIR/nojq/" 2>/dev/null || true; fi
  done
  run env PATH="$TMPDIR/bin:$TMPDIR/nojq" bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 2 ]
  [[ "$output" == *"jq no disponible"* ]]
}

@test "project type detection names every manifest and ignores node_modules" {
  printf 'requests==2.0\n' > "$TMPDIR/proj/requirements.txt"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  [[ "$output" == *"detectados: node python-requirements"* ]]
  mkdir -p "$TMPDIR/vendored/node_modules/x"
  printf '{}\n' > "$TMPDIR/vendored/node_modules/x/package.json"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/vendored"
  [[ "$output" == *"detectados: unknown"* ]]
}

@test "path with spaces is passed to trivy as a single absolute argument" {
  mkdir -p "$TMPDIR/my proj"
  cp "$TMPDIR/proj/package.json" "$TMPDIR/my proj/"
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/my proj"
  [ "$status" -eq 0 ]
  grep -q -- "$TMPDIR/my proj$" "$FAKE_LOG"
}

@test "docker fallback with a relative --path mounts an absolute path plus the DB cache" {
  PATH="/usr/bin:/bin" command -v trivy >/dev/null && skip "trivy real en /usr/bin"
  mv "$TMPDIR/bin/trivy" "$TMPDIR/trivy.real"
  printf '#!/usr/bin/env bash\necho "docker $*" >> "$FAKE_LOG"\nprintf "%%s\\n" "$FAKE_JSON"\n' > "$TMPDIR/bin/docker"
  chmod +x "$TMPDIR/bin/docker"
  cd "$TMPDIR"
  run env PATH="$TMPDIR/bin:/usr/bin:/bin" bash "$REPO_ROOT/$SCRIPT" --path proj
  [ "$status" -eq 0 ]
  grep -q -- "-v $TMPDIR/proj:/workspace" "$FAKE_LOG"
  grep -q -- "-v $HOME/.cache/trivy:/root/.cache/trivy" "$FAKE_LOG"
}

@test "docker fallback does not pass the host-only workspace-root .trivyignore" {
  PATH="/usr/bin:/bin" command -v trivy >/dev/null && skip "trivy real en /usr/bin"
  mkdir -p "$TMPDIR/ws/scripts"
  cp "$REPO_ROOT/$SCRIPT" "$TMPDIR/ws/scripts/"; mkdir -p "$TMPDIR/ws/.claude/hooks/lib"; cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$TMPDIR/ws/.claude/hooks/lib/"
  printf 'CVE-2020-0002\n' > "$TMPDIR/ws/.trivyignore"
  mv "$TMPDIR/bin/trivy" "$TMPDIR/trivy.real"
  printf '#!/usr/bin/env bash\necho "docker $*" >> "$FAKE_LOG"\nprintf "%%s\\n" "$FAKE_JSON"\n' > "$TMPDIR/bin/docker"
  chmod +x "$TMPDIR/bin/docker"
  run env PATH="$TMPDIR/bin:/usr/bin:/bin" bash "$TMPDIR/ws/$SCRIPT" --path "$TMPDIR/proj"
  [ "$status" -eq 0 ]
  run grep -q -- "--ignorefile" "$FAKE_LOG"
  [ "$status" -ne 0 ]
}

@test "concurrent scans of two projects into one output dir keep each verdict (no shared .tmp)" {
  mkdir -p "$TMPDIR/clean"
  cp "$TMPDIR/proj/package.json" "$TMPDIR/clean/"
  # A (vulnerable) escribe su informe y tarda; B (limpio) escribe el suyo mientras A sigue en Trivy.
  FAKE_JSON="$(vuln_json CVE-2021-23337 HIGH)" FAKE_DELAY=2 \
    bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/proj" > "$TMPDIR/a.out" 2>&1 &
  pid_a=$!
  sleep 0.5
  run bash "$REPO_ROOT/$SCRIPT" --path "$TMPDIR/clean"
  [ "$status" -eq 0 ]
  rc_a=0; wait "$pid_a" || rc_a=$?
  [ "$rc_a" -eq 1 ]
  grep -q "CVE-2021-23337" "$TMPDIR/a.out"
}
