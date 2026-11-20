#!/usr/bin/env bats
# SE-376 S03 — mobile-security-scanner: el auditor de AndroidManifest detecta cada clase de
# riesgo con su severidad y su exit code (= nº de hallazgos); un manifest limpio da PASS y uno
# ilegible NUNCA da PASS. Se ejecuta el script real sobre manifests de prueba.
# Ref: SE-240 · .claude/skills/mobile-security-scanner/SKILL.md · scripts/android-manifest-audit.sh
set -uo pipefail

SCRIPT="scripts/android-manifest-audit.sh"
NS='xmlns:android="http://schemas.android.com/apk/res/android"'

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  AUDIT="$ROOT/$SCRIPT"
  W="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
}

teardown() { rm -f "$W"/*.xml; }

# manifest <fichero> <atributos de <application>> <cuerpo de <application>> [permisos <uses-permission>]
manifest() {
  printf '<?xml version="1.0"?>\n<manifest %s package="org.example.app">\n%s\n<application %s>\n%s\n</application>\n</manifest>\n' \
    "$NS" "${4:-}" "$2" "$3" > "$1"
}

@test "manifest limpio (backup off, nada exportado, sin permisos peligrosos) → PASS, exit 0, 0 hallazgos" {
  manifest "$W/ok.xml" 'android:allowBackup="false" android:debuggable="false"' '<activity android:name=".Main" android:exported="false"/>'
  run bash "$AUDIT" "$W/ok.xml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total findings: 0"* ]]
  [[ "$output" == *"PASS:"* ]]
  [[ "$output" != *"CRITICAL"* && "$output" != *"HIGH"* && "$output" != *"MEDIUM"* ]]
}

@test "debuggable=true → CRITICAL, exit 1 (único hallazgo)" {
  manifest "$W/dbg.xml" 'android:allowBackup="false" android:debuggable="true"' ''
  run bash "$AUDIT" "$W/dbg.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *'CRITICAL: android:debuggable="true"'* ]]
  [[ "$output" != *"PASS:"* ]]
}

@test "allowBackup=true explícito → HIGH, exit 1" {
  manifest "$W/bk.xml" 'android:allowBackup="true"' ''
  run bash "$AUDIT" "$W/bk.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *'HIGH: android:allowBackup="true"'* ]]
}

@test "allowBackup ausente se trata como true (default de Android) → HIGH" {
  manifest "$W/bk-default.xml" 'android:debuggable="false"' ''
  run bash "$AUDIT" "$W/bk-default.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *'HIGH: android:allowBackup="true" (default)'* ]]
}

@test "componentes exportados sin permission se cuentan; con permission o exported=false no" {
  manifest "$W/exp.xml" 'android:allowBackup="false"' '
<activity android:name=".A" android:exported="true"/>
<service android:name=".S" android:exported="true"/>
<receiver android:name=".R" android:exported="true" android:permission="org.example.PERM"/>
<provider android:name=".P" android:exported="false"/>'
  run bash "$AUDIT" "$W/exp.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HIGH: 2 componentes exportados"* ]]
}

@test "un provider exportado sin permission cuenta igual que una activity" {
  manifest "$W/exp-prov.xml" 'android:allowBackup="false"' '<provider android:name=".P" android:exported="true"/>'
  run bash "$AUDIT" "$W/exp-prov.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"HIGH: 1 componentes exportados"* ]]
}

@test "permisos peligrosos → MEDIUM y se listan solo los peligrosos" {
  manifest "$W/perm.xml" 'android:allowBackup="false"' '' '<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_SMS"/>'
  run bash "$AUDIT" "$W/perm.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MEDIUM: Permisos peligrosos declarados: CAMERA,READ_SMS"* ]]
  [[ "$output" != *"INTERNET"* ]]
}

@test "solo permisos no peligrosos (INTERNET) → PASS" {
  manifest "$W/perm-ok.xml" 'android:allowBackup="false"' '' '<uses-permission android:name="android.permission.INTERNET"/>'
  run bash "$AUDIT" "$W/perm-ok.xml"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS:"* ]]
}

@test "los cuatro riesgos a la vez → exit 4 y las cuatro severidades en la salida" {
  manifest "$W/all.xml" 'android:debuggable="true" android:allowBackup="true"' '<activity android:name=".A" android:exported="true"/>' '<uses-permission android:name="android.permission.RECORD_AUDIO"/>'
  run bash "$AUDIT" "$W/all.xml"
  [ "$status" -eq 4 ]
  [[ "$output" == *"CRITICAL"* && "$output" == *"HIGH: android:allowBackup"* && "$output" == *"componentes exportados"* && "$output" == *"MEDIUM"* ]]
  [[ "$output" == *"Total findings: 4"* ]]
}

@test "error de parseo: manifest inválido (no es XML) nunca da PASS (fail-closed)" {
  printf 'esto no es xml <<<\n' > "$W/roto.xml"
  run bash "$AUDIT" "$W/roto.xml"
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS:"* ]]
}

@test "negativo de entrada: sin argumento → exit 1 con uso; fichero inexistente → exit 1" {
  run bash "$AUDIT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Uso:"* ]]
  run bash "$AUDIT" "$W/no-existe.xml"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Fichero no encontrado"* ]]
}

@test "caso límite: manifest empty (fichero vacío) nunca da PASS" {
  : > "$W/vacio.xml"
  run bash "$AUDIT" "$W/vacio.xml"
  [ "$status" -ne 0 ]
  [[ "$output" != *"PASS:"* ]]
}

@test "caso límite: manifest sin <application> (nonexistent element) no inventa debuggable ni exportados" {
  printf '<?xml version="1.0"?>\n<manifest %s package="org.example.app"/>\n' "$NS" > "$W/sin-app.xml"
  run bash "$AUDIT" "$W/sin-app.xml"
  [[ "$output" != *"CRITICAL"* ]]
  [[ "$output" != *"componentes exportados"* ]]
  [[ "$output" != *"MEDIUM"* ]]
}

@test "caso límite: zero permisos peligrosos no emite línea MEDIUM aunque haya otros uses-permission" {
  manifest "$W/zero.xml" 'android:allowBackup="false"' '' '<uses-permission android:name="com.example.CUSTOM"/>'
  run bash "$AUDIT" "$W/zero.xml"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MEDIUM"* ]]
}
