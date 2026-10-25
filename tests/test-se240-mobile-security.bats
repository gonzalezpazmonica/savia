#!/usr/bin/env bats
# SE-240 — Mobile Security Pipeline tests
# Tests: mobile-security-scan.sh, android-manifest-audit.sh, SKILL.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export MOBILE_SCRIPT="$REPO_ROOT/scripts/mobile-security-scan.sh"
  export MANIFEST_SCRIPT="$REPO_ROOT/scripts/android-manifest-audit.sh"
  export SKILL_FILE="$REPO_ROOT/.opencode/skills/mobile-security-scanner/SKILL.md"
  FAKE_TMPDIR=$(mktemp -d)
  export FAKE_TMPDIR
}

teardown() {
  rm -rf "$FAKE_TMPDIR"
}

# Test 1: mobile-security-scan.sh existe y pasa bash -n
@test "mobile-security-scan.sh existe y pasa bash -n" {
  [[ -f "$MOBILE_SCRIPT" ]]
  run bash -n "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 2: android-manifest-audit.sh existe y pasa bash -n
@test "android-manifest-audit.sh existe y pasa bash -n" {
  [[ -f "$MANIFEST_SCRIPT" ]]
  run bash -n "$MANIFEST_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 3: mobile-security-scanner/SKILL.md existe y tiene ≤150 líneas
@test "mobile-security-scanner/SKILL.md existe y tiene 150 lineas o menos" {
  [[ -f "$SKILL_FILE" ]]
  LINE_COUNT=$(wc -l < "$SKILL_FILE")
  [[ "$LINE_COUNT" -le 150 ]]
}

# Test 4: android-manifest-audit.sh funciona sin MobSF (usa xmllint o python3)
@test "android-manifest-audit.sh usa xmllint o python3 no MobSF" {
  # El script no debe hacer llamadas a la API de MobSF ni a Docker MobSF
  run grep -i "curl.*mobsf\|docker.*mobsf\|mobsf_api\|mobsf_url" "$MANIFEST_SCRIPT"
  # No debe tener llamadas funcionales a MobSF
  [[ "$status" -ne 0 ]]
  # Debe mencionar xmllint o python3 como parsers
  run grep -i "xmllint\|python3" "$MANIFEST_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 5: android-manifest-audit.sh detecta android:debuggable=true como CRITICAL
@test "android-manifest-audit.sh detecta debuggable=true como CRITICAL" {
  # Crear un AndroidManifest de prueba con debuggable=true
  cat > "$FAKE_TMPDIR/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.test.app">
    <application
        android:debuggable="true"
        android:allowBackup="false"
        android:label="TestApp">
    </application>
</manifest>
EOF
  run bash "$MANIFEST_SCRIPT" "$FAKE_TMPDIR/AndroidManifest.xml"
  [[ "$output" == *"CRITICAL"* ]]
  [[ "$output" == *"debuggable"* ]]
}

# Test 6: android-manifest-audit.sh detecta android:allowBackup=true como HIGH
@test "android-manifest-audit.sh detecta allowBackup=true como HIGH" {
  cat > "$FAKE_TMPDIR/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.test.app">
    <application
        android:debuggable="false"
        android:allowBackup="true"
        android:label="TestApp">
    </application>
</manifest>
EOF
  run bash "$MANIFEST_SCRIPT" "$FAKE_TMPDIR/AndroidManifest.xml"
  [[ "$output" == *"HIGH"* ]]
  [[ "$output" == *"allowBackup"* ]]
}

# Test 7: android-manifest-audit.sh acepta un path como argumento
@test "android-manifest-audit.sh acepta path como argumento posicional" {
  # Sin argumento debe fallar con error
  run bash "$MANIFEST_SCRIPT"
  [[ "$status" -ne 0 ]]
  [[ "$output" == *"Uso:"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"AndroidManifest"* ]]
}

# Test 8: mobile-security-scan.sh acepta --apk
@test "mobile-security-scan.sh acepta argumento --apk" {
  run grep "\-\-apk" "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 9: mobile-security-scan.sh acepta --mode
@test "mobile-security-scan.sh acepta argumento --mode" {
  run grep "\-\-mode" "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# Test 10: Con MobSF no disponible → muestra Docker fallback
@test "mobile-security-scan.sh menciona Docker fallback cuando MobSF no disponible" {
  run grep -i "docker\|Docker" "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]]
  run grep -i "opensecurity/mobile-security-framework-mobsf\|drwetter" "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]] || run grep -i "opensecurity" "$MOBILE_SCRIPT"
}

# Test 11: SKILL.md menciona "MobSF" o "android"
@test "mobile-security-scanner SKILL.md menciona MobSF o android" {
  run grep -i "MobSF\|android" "$SKILL_FILE"
  [[ "$status" -eq 0 ]]
}

# Test 12: mobile-security-scan.sh tiene set -uo pipefail
@test "mobile-security-scan.sh tiene set -uo pipefail" {
  run grep "set -uo pipefail" "$MOBILE_SCRIPT"
  [[ "$status" -eq 0 ]]
}

# ── Comportamiento: ejecución real en un repo aislado ────────────────────────
# El script escribe en $REPO_ROOT/output/security y usa herramientas externas; cada caso
# monta un repo mínimo en $FAKE_TMPDIR y controla qué herramientas ve con un PATH acotado.

mk_sandbox() {
  SB="$FAKE_TMPDIR/repo"
  mkdir -p "$SB/scripts" "$SB/.claude/hooks/lib" "$FAKE_TMPDIR/bin" "$FAKE_TMPDIR/rbin"
  cp "$MOBILE_SCRIPT" "$SB/scripts/"
  cp "$REPO_ROOT/.claude/hooks/lib/gate-result.sh" "$SB/.claude/hooks/lib/"
  local t
  for t in bash env python3 find xargs grep wc cat date mkdir rm basename dirname tr head sed sort unzip; do
    command -v "$t" >/dev/null 2>&1 && ln -sf "$(command -v "$t")" "$FAKE_TMPDIR/rbin/$t"
  done
  # curl falso: api_docs responde según FAKE_MOBSF_UP; upload/report_json devuelven lo configurado
  cat > "$FAKE_TMPDIR/bin/curl" <<'EOS'
#!/usr/bin/env bash
case "$*" in
  *api_docs*)    [[ "${FAKE_MOBSF_UP:-0}" == 1 ]] && exit 0 || exit 7 ;;
  *v1/upload*)   printf '%s' "${FAKE_UPLOAD:-}" ;;
  *report_json*) printf '%s' "${FAKE_REPORT-{\}}" ;;
esac
exit 0
EOS
  chmod +x "$FAKE_TMPDIR/bin/curl"
  ln -sf "$FAKE_TMPDIR/bin/curl" "$FAKE_TMPDIR/rbin/curl"
  PATH_RESTRICTED="$FAKE_TMPDIR/rbin"
}

mk_apk() {  # mk_apk <nombre> <fichero=contenido>...
  local out="$FAKE_TMPDIR/$1"; shift
  local src; src=$(mktemp -d -p "$FAKE_TMPDIR")
  local kv
  for kv in "$@"; do mkdir -p "$src/$(dirname "${kv%%=*}")"; printf '%s\n' "${kv#*=}" > "$src/${kv%%=*}"; done
  python3 - "$src" "$out" <<'EOP'
import sys, os, zipfile
src, out = sys.argv[1:3]
with zipfile.ZipFile(out, "w") as z:
    for r, _, fs in os.walk(src):
        for f in fs:
            p = os.path.join(r, f); z.write(p, os.path.relpath(p, src))
EOP
  APK="$out"
}

# apktool falso: vuelca en el directorio de salida los ficheros name=contenido recibidos
fake_apktool() {
  local body='#!/usr/bin/env bash
out=""; while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
mkdir -p "$out"
'
  local kv
  for kv in "$@"; do body+="printf '%s\n' '${kv#*=}' > \"\$out/${kv%%=*}\""$'\n'; done
  printf '%s' "$body" > "$FAKE_TMPDIR/bin/apktool"
  chmod +x "$FAKE_TMPDIR/bin/apktool"
  ln -sf "$FAKE_TMPDIR/bin/apktool" "$FAKE_TMPDIR/rbin/apktool"
}

run_scan() { PATH="$PATH_RESTRICTED" run bash "$SB/scripts/mobile-security-scan.sh" "$@"; }
report_file() { ls "$SB"/output/security/mobile-scan-*.json | head -1; }
rep() { python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))" "$(report_file)" "$1"; }

@test "scan: sin argumentos sale 1 y muestra el uso" {
  mk_sandbox
  run_scan
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
  [ ! -d "$SB/output" ]
}

@test "scan: argumento desconocido sale 1 y lo nombra" {
  mk_sandbox
  run_scan --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"argumento desconocido: --bogus"* ]]
}

@test "scan: APK inexistente sale 1 sin crear informe" {
  mk_sandbox
  run_scan --apk "$FAKE_TMPDIR/no-existe.apk"
  [ "$status" -eq 1 ]
  [[ "$output" == *"APK no encontrado"* ]]
  [ ! -d "$SB/output" ]
}

@test "scan: APK limpio con apktool -> result clean, sin huecos, hallazgo solo INFO" {
  mk_sandbox; fake_apktool "AndroidManifest.xml=<manifest/>"; mk_apk ok.apk "a.txt=hola"
  run_scan --apk "$APK"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"clean","gaps":[]}' ]
  [ "$(rep "d['result']")" = "clean" ]
  [ "$(rep "d['mode']")" = "static" ]
  [ "$(rep "[f['type'] for f in d['findings']]")" = "['scan_complete']" ]
}

@test "scan: dos ficheros con secretos y uno limpio -> CRITICAL hardcoded_secrets con recuento 2" {
  mk_sandbox; fake_apktool "A.smali=password" "b.xml=api_key" "c.xml=nada"; mk_apk s.apk "x=1"
  run_scan --apk "$APK"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"findings","gaps":[]}' ]
  [ "$(rep "[(f['severity'],f['count']) for f in d['findings'] if f['type']=='hardcoded_secrets']")" = "[('CRITICAL', 2)]" ]
}

@test "scan: Log.d en smali -> HIGH debug_code_in_release sin secretos" {
  mk_sandbox; fake_apktool "A.smali=invoke-static Landroid/util/Log;->d"; mk_apk d.apk "x=1"
  run_scan --apk "$APK"
  [ "$(rep "d['result']")" = "findings" ]
  [ "$(rep "[(f['severity'],f['count']) for f in d['findings'] if f['type']=='debug_code_in_release']")" = "[('HIGH', 1)]" ]
  [ "$(rep "[f for f in d['findings'] if f['type']=='hardcoded_secrets']")" = "[]" ]
}

@test "scan: debug solo cuenta en .smali (un xml con Log.d no es hallazgo)" {
  mk_sandbox; fake_apktool "r.xml=Log.d"; mk_apk d.apk "x=1"
  run_scan --apk "$APK"
  [ "$(rep "d['result']")" = "clean" ]
}

@test "scan: sin apktool, con unzip -> unknown con hueco apktool:missing_tool" {
  mk_sandbox; mk_apk u.apk "a.txt=hola"
  run_scan --apk "$APK"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"apktool","reason":"missing_tool"}]}' ]
  [ "$(rep "d['gaps'][0]['check']")" = "apktool" ]
}

@test "scan: unzip extrae el APK y encuentra secretos aunque falte apktool" {
  mk_sandbox; mk_apk z.apk "res/x.xml=<s>private_key</s>"
  run_scan --apk "$APK"
  [ "$(rep "d['result']")" = "findings" ]
  [ "$(rep "[f['count'] for f in d['findings'] if f['type']=='hardcoded_secrets']")" = "[1]" ]
  [ "$(rep "d['gaps']")" = "[{'check': 'apktool', 'reason': 'missing_tool'}]" ]
}

@test "scan: sin apktool ni unzip -> hueco decompile:missing_tool y no unreadable" {
  mk_sandbox; mk_apk n.apk "a=1"
  unlink "$FAKE_TMPDIR/rbin/unzip"
  run_scan --apk "$APK"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"decompile","reason":"missing_tool"}]}' ]
}

@test "scan: apktool que no deja ficheros -> hueco decompile:unreadable" {
  mk_sandbox; fake_apktool; mk_apk e.apk "a=1"
  run_scan --apk "$APK"
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"decompile","reason":"unreadable"}]}' ]
}

@test "scan: --mode dynamic sin adb degrada a static y deja el hueco dynamic:missing_tool" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  run_scan --apk "$APK" --mode dynamic
  [ "$status" -eq 0 ]
  [[ "$output" == *"adb no disponible. Degradando a modo static."* ]]
  [ "$(rep "d['mode']")" = "static" ]
  [ "$(rep "d['result']")" = "unknown" ]
  [ "$(rep "d['gaps']")" = "[{'check': 'dynamic', 'reason': 'missing_tool'}]" ]
}

@test "scan: --mode dynamic con adb sin dispositivos degrada a static" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  printf '#!/usr/bin/env bash\necho "List of devices attached"\n' > "$FAKE_TMPDIR/bin/adb"; chmod +x "$FAKE_TMPDIR/bin/adb"
  ln -sf "$FAKE_TMPDIR/bin/adb" "$FAKE_TMPDIR/rbin/adb"
  run_scan --apk "$APK" --mode dynamic
  [[ "$output" == *"No hay dispositivo ADB conectado"* ]]
  [ "$(rep "d['mode']")" = "static" ]
}

@test "scan: --mode dynamic con un dispositivo conectado conserva el modo dynamic" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  printf '#!/usr/bin/env bash\necho "List of devices attached"\necho "emu-5554 device"\n' > "$FAKE_TMPDIR/bin/adb"; chmod +x "$FAKE_TMPDIR/bin/adb"
  ln -sf "$FAKE_TMPDIR/bin/adb" "$FAKE_TMPDIR/rbin/adb"
  run_scan --apk "$APK" --mode dynamic
  [[ "$output" != *"Degradando"* ]]
  [ "$(rep "d['mode']")" = "dynamic" ]
}

@test "scan: --mode static no menciona adb ni añade hueco dynamic" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  run_scan --apk "$APK" --mode static
  [[ "$output" != *"adb"* ]]
  [ "$(rep "d['gaps']")" = "[]" ]
}

@test "scan: Docker instalado y MobSF caído -> imprime el comando docker run" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKE_TMPDIR/bin/docker"; chmod +x "$FAKE_TMPDIR/bin/docker"
  ln -sf "$FAKE_TMPDIR/bin/docker" "$FAKE_TMPDIR/rbin/docker"
  run_scan --apk "$APK"
  [[ "$output" == *"docker run --rm -p 8000:8000"* ]]
  [[ "$output" != *"Docker no instalado"* ]]
}

@test "scan: sin Docker ni MobSF dice que no hay Docker y el informe lo refleja" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  run_scan --apk "$APK"
  [[ "$output" == *"Docker no instalado"* ]]
  [ "$(rep "d['mobsf_available']")" = "False" ]
  [ "$(rep "d['tool']")" = "basic-analysis" ]
  [ "$(rep "d['apk']")" = "$APK" ]
}

@test "scan: MobSF arriba sin API key no sube nada y cae al análisis básico" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk m.apk "a=1"
  FAKE_MOBSF_UP=1 FAKE_UPLOAD='{"hash":"h1"}' PATH="$PATH_RESTRICTED" run bash "$SB/scripts/mobile-security-scan.sh" --apk "$APK"
  [[ "$output" == *"MobSF detectado en http://localhost:8000"* ]]
  [[ "$output" != *"Ejecutando MobSF static analysis"* ]]
  [[ "$output" == *"Ejecutando análisis básico"* ]]
  [ "$(rep "d['mobsf_available']")" = "True" ]
}

@test "scan: MobSF con API key y hash -> guarda el informe de MobSF y sale unknown (mobsf_triage)" {
  mk_sandbox; mk_apk m.apk "a=1"
  FAKE_MOBSF_UP=1 MOBSF_API_KEY=k FAKE_UPLOAD='{"hash":"h1"}' FAKE_REPORT='{"score": 42}' PATH="$PATH_RESTRICTED" \
    run bash "$SB/scripts/mobile-security-scan.sh" --apk "$APK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"MobSF analysis completo"* ]]
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"mobsf_triage","reason":"unreadable"}]}' ]
  [ "$(rep "d['score']")" = "42" ]
}

@test "scan: informe de MobSF vacío ({}) -> hueco mobsf_report:unreadable" {
  mk_sandbox; mk_apk m.apk "a=1"
  FAKE_MOBSF_UP=1 MOBSF_API_KEY=k FAKE_UPLOAD='{"hash":"h1"}' FAKE_REPORT='{}' PATH="$PATH_RESTRICTED" \
    run bash "$SB/scripts/mobile-security-scan.sh" --apk "$APK"
  [ "${lines[-1]}" = 'gate-result: {"result":"unknown","gaps":[{"check":"mobsf_report","reason":"unreadable"}]}' ]
}

@test "scan: subida a MobSF vacía -> avisa y cae al análisis básico" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk m.apk "a=1"
  FAKE_MOBSF_UP=1 MOBSF_API_KEY=k FAKE_UPLOAD='' PATH="$PATH_RESTRICTED" run bash "$SB/scripts/mobile-security-scan.sh" --apk "$APK"
  [[ "$output" == *"MobSF upload falló"* ]]
  [ "$(rep "d['tool']")" = "basic-analysis" ]
}

@test "scan: subida sin hash también cae al análisis básico" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk m.apk "a=1"
  FAKE_MOBSF_UP=1 MOBSF_API_KEY=k FAKE_UPLOAD='{"error":"x"}' PATH="$PATH_RESTRICTED" run bash "$SB/scripts/mobile-security-scan.sh" --apk "$APK"
  [[ "$output" == *"MobSF upload falló"* ]]
  [[ "$output" != *"MobSF analysis completo"* ]]
}

@test "scan: el informe lleva la fecha de hoy y la ruta se imprime" {
  mk_sandbox; fake_apktool "x.txt=x"; mk_apk y.apk "a=1"
  run_scan --apk "$APK"
  [ -f "$SB/output/security/mobile-scan-$(date +%Y%m%d).json" ]
  [[ "$output" == *"Report: $SB/output/security/mobile-scan-$(date +%Y%m%d).json"* ]]
}
