#!/usr/bin/env bats
# SE-453 S3 (por demanda) — resultado clean/findings/unknown en los escáneres que quedaban fuera del
# primer lote: mobile-security-scan, security-scan, vuln-scan y el no medido de data-sovereignty-gate.
# Spec: docs/specs/SE-453-gate-result-contract.spec.md · Contrato: docs/rules/domain/gate-result-contract.md

setup_file() {
  # PATH aislado: todo /usr/bin menos las herramientas que se quieren ausentes.
  mkpath() {
    local dir="$1"; shift
    local f name skip x
    mkdir -p "$dir"
    for f in /usr/bin/*; do
      name="${f##*/}"; skip=0
      for x in "$@"; do [[ "$name" == "$x" ]] && skip=1; done
      [[ $skip -eq 1 ]] && continue
      [[ -x "$f" ]] && ln -sf "$f" "$dir/$name"
    done
  }
  export NOAPK="$BATS_FILE_TMPDIR/noapk" NODECOMP="$BATS_FILE_TMPDIR/nodecomp" NOJQ="$BATS_FILE_TMPDIR/nojq"
  mkpath "$NOAPK" apktool docker adb
  mkpath "$NODECOMP" apktool unzip docker adb
  mkpath "$NOJQ" jq
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WORK="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  PROJ="$WORK/proj"
  mkdir -p "$PROJ/scripts" "$PROJ/.claude/hooks/lib" "$WORK/bin" "$WORK/apk"
  cp "$REPO_ROOT/scripts/mobile-security-scan.sh" "$REPO_ROOT/scripts/security-scan.sh" \
     "$REPO_ROOT/scripts/vuln-scan.sh" "$PROJ/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$PROJ/.claude/hooks/lib/"
  # APK de prueba: un zip con un manifiesto (no hace falta que sea un APK válido).
  printf '<manifest package="t"/>\n' > "$WORK/apk/AndroidManifest.xml"
  (cd "$WORK/apk" && zip -q "$WORK/app.apk" AndroidManifest.xml)
  # MobSF inalcanzable: puerto cerrado, respuesta inmediata.
  export MOBSF_URL="http://127.0.0.1:9"
}

last_result() { printf '%s\n' "$output" | grep '^gate-result: ' | tail -1 | sed 's/^gate-result: //'; }
is_last_line() { [ "$(printf '%s\n' "$output" | tail -1)" = "gate-result: $1" ]; }
has_gap() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["result"]==sys.argv[2] and {"check":sys.argv[3],"reason":sys.argv[4]} in d["gaps"], d' "$(last_result)" "$@"; }

# apktool falso: crea la salida que pida $APK_SMALI (vacío ⇒ no descompila nada).
fake_apktool() {
  cat > "$WORK/bin/apktool" <<'STUB'
#!/usr/bin/env bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == -o ]] && out="$2"; shift; done
[[ -z "${APK_SMALI:-}" ]] && exit 1
mkdir -p "$out/smali"; printf '%s\n' "$APK_SMALI" > "$out/smali/A.smali"
printf '<manifest package="t"/>\n' > "$out/AndroidManifest.xml"
STUB
  chmod +x "$WORK/bin/apktool"
}

# ── mobile-security-scan ─────────────────────────────────────────────────────

@test "mobile: sin apktool (solo unzip) ⇒ unknown/apktool:missing_tool, exit 0 y campo en el informe" {
  run env PATH="$NOAPK" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk"
  [ "$status" -eq 0 ]
  has_gap unknown apktool missing_tool
  is_last_line "$(last_result)"
  python3 -c 'import json,sys,glob; d=json.load(open(glob.glob(sys.argv[1]+"/output/security/mobile-scan-*.json")[0])); assert d["result"]=="unknown" and d["gaps"][0]["reason"]=="missing_tool", d' "$PROJ"
}

@test "mobile: sin apktool ni unzip ⇒ unknown/decompile:missing_tool" {
  run env PATH="$NODECOMP" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk"
  [ "$status" -eq 0 ]
  has_gap unknown decompile missing_tool
}

@test "mobile: apktool que no produce nada ⇒ unknown/decompile:unreadable, nunca clean" {
  fake_apktool
  run env PATH="$WORK/bin:$NOAPK" APK_SMALI="" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk"
  [ "$status" -eq 0 ]
  has_gap unknown decompile unreadable
}

@test "mobile: apktool con código inocuo ⇒ clean sin huecos" {
  fake_apktool
  run env PATH="$WORK/bin:$NOAPK" APK_SMALI=".class public LA;" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = '{"result":"clean","gaps":[]}' ]
}

@test "mobile: apktool con código de debug ⇒ findings" {
  fake_apktool
  run env PATH="$WORK/bin:$NOAPK" APK_SMALI="invoke-static {}, Landroid/util/Log;->d" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk"
  [ "$status" -eq 0 ]
  [ "$(last_result)" = '{"result":"findings","gaps":[]}' ]
}

@test "mobile: modo dynamic (no implementado) deja hueco dynamic aunque el estático salga limpio" {
  fake_apktool
  run env PATH="$WORK/bin:$NOAPK" APK_SMALI=".class public LA;" /usr/bin/bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/app.apk" --mode dynamic
  [ "$status" -eq 0 ]
  has_gap unknown dynamic missing_tool
}

@test "mobile: argumentos inválidos siguen saliendo 1 (códigos sin renumerar)" {
  run bash "$PROJ/scripts/mobile-security-scan.sh"
  [ "$status" -eq 1 ]
  run bash "$PROJ/scripts/mobile-security-scan.sh" --apk "$WORK/no-existe.apk"
  [ "$status" -eq 1 ]
}

# ── security-scan / vuln-scan ────────────────────────────────────────────────

# Proyecto mínimo que pasa security-scan sin hallazgos (solo avisos).
sec_fixture() {
  mkdir -p "$PROJ/.opencode/hooks"
  printf '# Security\n' > "$PROJ/SECURITY.md"
  printf '.env\n*.pem\n*.key\ncredentials\nsecrets\n' > "$PROJ/.gitignore"
  local h
  for h in block-credential-leak block-force-push block-infra-destructive; do
    printf '#!/usr/bin/env bash\nset -uo pipefail\n# lee el JSON con jq\nexit 0\n' > "$PROJ/.opencode/hooks/$h.sh"
    chmod +x "$PROJ/.opencode/hooks/$h.sh"
  done
}

@test "security-scan: proyecto completo ⇒ clean y exit 0 en --ci" {
  sec_fixture
  run bash "$PROJ/scripts/security-scan.sh" --ci
  [ "$status" -eq 0 ]
  is_last_line '{"result":"clean","gaps":[]}'
}

@test "security-scan: una clave AWS ⇒ findings y exit 1 en --ci (sin cambios)" {
  sec_fixture
  printf 'KEY=%s%s\n' "AKIA" "ABCDEFGHIJKLMNOP" > "$PROJ/scripts/conf.sh"
  run bash "$PROJ/scripts/security-scan.sh" --ci
  [ "$status" -eq 1 ]
  [ "$(last_result)" = '{"result":"findings","gaps":[]}' ]
}

@test "security-scan: fichero ilegible ⇒ unknown/unreadable, aviso, registro de no medido; con block sale 1" {
  [ "$(id -u)" -ne 0 ] || skip "root ignora los permisos 000: no se puede fabricar un fichero ilegible"
  sec_fixture
  printf 'x\n' > "$PROJ/scripts/locked.sh"; chmod 000 "$PROJ/scripts/locked.sh"
  run bash "$PROJ/scripts/security-scan.sh" --ci
  chmod 600 "$PROJ/scripts/locked.sh"
  [ "$status" -eq 0 ]
  has_gap unknown aws_keys unreadable
  [[ "$output" == *"WARN: scan incompleto"* ]]
  [[ "$output" != *"PASS:"* ]]
  grep -q '"hook":"security-scan","reason":"unreadable"' "$PROJ/output/unmeasured-gates.jsonl"
  chmod 000 "$PROJ/scripts/locked.sh"
  run env SAVIA_GATE_UNKNOWN=block bash "$PROJ/scripts/security-scan.sh" --ci
  chmod 600 "$PROJ/scripts/locked.sh"
  [ "$status" -eq 1 ]
}

@test "security-scan: sin hooks legibles ⇒ hueco hooks aunque haya hallazgos" {
  run bash "$PROJ/scripts/security-scan.sh"
  [ "$status" -eq 0 ]
  has_gap findings hooks unreadable
}

@test "vuln-scan: sin directorio de hooks ⇒ unknown/hooks:unreadable, nunca clean" {
  run bash "$PROJ/scripts/vuln-scan.sh" --ci
  [ "$status" -eq 0 ]
  has_gap unknown hooks unreadable
  [[ "$output" != *"PASS:"* ]]
  run env SAVIA_GATE_UNKNOWN=block bash "$PROJ/scripts/vuln-scan.sh" --ci
  [ "$status" -eq 1 ]
}

@test "vuln-scan: hooks presentes y sanos ⇒ clean; eval en un hook ⇒ findings y exit 1" {
  sec_fixture
  run bash "$PROJ/scripts/vuln-scan.sh" --ci
  [ "$status" -eq 0 ]
  is_last_line '{"result":"clean","gaps":[]}'
  printf '#!/usr/bin/env bash\nset -u\neval "$X" # jq\n' > "$PROJ/.opencode/hooks/bad.sh"; chmod +x "$PROJ/.opencode/hooks/bad.sh"
  run bash "$PROJ/scripts/vuln-scan.sh" --ci
  [ "$status" -eq 1 ]
  [ "$(last_result)" = '{"result":"findings","gaps":[]}' ]
}
