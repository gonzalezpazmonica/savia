#!/usr/bin/env bats
# SE-376 — onboarding-dev: calibración de su parte ejecutable. La skill es prosa (la ejecuta
# el agente); lo único ejecutable de su cadena es scripts/setup-memory.sh, que /project-new
# (prerrequisito de /onboarding-dev) usa para crear la memoria del proyecto en
# ~/.savia/projects/<proyecto>/memory/. Nunca toca el HOME real: HOME apunta a un temporal.
# Ref: .claude/skills/onboarding-dev/SKILL.md, .claude/commands/project-new.md,
#      docs/propuestas/SPEC-INSTALLER-OPENCODE-MIGRATION.md (AC-4)
set -uo pipefail

bats_require_minimum_version 1.5.0
SCRIPT="scripts/setup-memory.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TARGET="$REPO_ROOT/$SCRIPT"
  TMP="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
  export HOME="$TMP/home"
  mkdir -p "$HOME"
  unset SAVIA_MEMORY_DIR
  BASE="$HOME/.savia/projects"
  TODAY="$(date +%Y-%m-%d)"
}

teardown() { rm -rf "$TMP"; }

# Lista los ficheros que existen bajo $TMP (para detectar escrituras fuera de sitio).
all_files() { (cd "$TMP" && find . -type f | sort); }

@test "script: existe, es bash válido y usa modo estricto set -euo pipefail" {
  [ -f "$TARGET" ]
  run bash -n "$TARGET"
  [ "$status" -eq 0 ]
  run grep -cE '^set -[a-z]*u[a-z]*o pipefail' "$TARGET"
  [ "$output" -ge 1 ]
}

@test "positivo: crea MEMORY.md y los 5 topic files con el nombre y la fecha de hoy" {
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  d="$BASE/mi-api/memory"
  [ "$(head -1 "$d/MEMORY.md")" = "# Memory — mi-api" ]
  grep -qF "> Última sync: $TODAY" "$d/MEMORY.md"
  for t in sprint-history architecture debugging team-patterns devops-notes; do
    [ -f "$d/$t.md" ]
    grep -qF "— mi-api" "$d/$t.md"
    grep -qF "> Actualizado: $TODAY" "$d/$t.md"
  done
  [ "$(head -1 "$d/team-patterns.md")" = "# Team Patterns — mi-api" ]
  [ "$(find "$d" -type f | wc -l)" -eq 6 ]
}

@test "idempotente: la segunda ejecución no sobrescribe notas ya existentes" {
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  echo "nota de la operadora" >> "$BASE/mi-api/memory/debugging.md"
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
  grep -qF "nota de la operadora" "$BASE/mi-api/memory/debugging.md"
}

@test "nombre con & : el nombre se escribe literal, sin metacaracteres de sed" {
  run bash "$TARGET" 'R&D'
  [ "$status" -eq 0 ]
  [ "$(head -1 "$BASE/R&D/memory/MEMORY.md")" = "# Memory — R&D" ]
  grep -qF "— R&D" "$BASE/R&D/memory/architecture.md"
}

@test "nombre que contiene FECHA o PROJECT_NAME no se corrompe al rellenar la plantilla" {
  run bash "$TARGET" FECHA-app
  [ "$status" -eq 0 ]
  [ "$(head -1 "$BASE/FECHA-app/memory/MEMORY.md")" = "# Memory — FECHA-app" ]
  run bash "$TARGET" PROJECT_NAME_x
  [ "$status" -eq 0 ]
  [ "$(head -1 "$BASE/PROJECT_NAME_x/memory/MEMORY.md")" = "# Memory — PROJECT_NAME_x" ]
}

@test "ruta con espacios: nombre con espacios funciona y cuenta como un proyecto" {
  run bash "$TARGET" "Mi Proyecto Grande"
  [ "$status" -eq 0 ]
  [ "$(head -1 "$BASE/Mi Proyecto Grande/memory/MEMORY.md")" = "# Memory — Mi Proyecto Grande" ]
  [ "$(ls "$BASE" | wc -l)" -eq 1 ]
}

@test "invalid: nombre con / se rechaza con exit 2 y sin crear nada" {
  run bash "$TARGET" 'a/b'
  [ "$status" -eq 2 ]
  [[ "$output" == *"nombre de proyecto inválido"* ]]
  [ -z "$(all_files)" ]
}

@test "reject: path traversal ../ no escribe fuera de ~/.savia/projects" {
  run bash "$TARGET" '../../escape'
  [ "$status" -eq 2 ]
  [ -z "$(all_files)" ]
  [ ! -e "$HOME/escape" ]
  run bash "$TARGET" '..'
  [ "$status" -eq 2 ]
  run bash "$TARGET" '.'
  [ "$status" -eq 2 ]
  [ -z "$(all_files)" ]
}

@test "reject: nombre con salto de línea o que empieza por guion se rechaza" {
  run bash "$TARGET" $'linea1\nlinea2'
  [ "$status" -eq 2 ]
  run bash "$TARGET" '-rf'
  [ "$status" -eq 2 ]
  [ -z "$(all_files)" ]
}

@test "empty: argumento vacío usa el basename de la raíz git" {
  repo="$TMP/repo con espacio"
  mkdir -p "$repo"
  git -C "$repo" init -q
  run bash -c 'cd "$1" && bash "$2" ""' _ "$repo" "$TARGET"
  [ "$status" -eq 0 ]
  [ -f "$BASE/repo con espacio/memory/MEMORY.md" ]
}

@test "SAVIA_MEMORY_DIR redirige el destino y no toca ~/.savia" {
  export SAVIA_MEMORY_DIR="$TMP/otra ruta/mem"
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [ -f "$TMP/otra ruta/mem/MEMORY.md" ]
  [ ! -e "$HOME/.savia" ]
}

@test "error: sin HOME ni SAVIA_MEMORY_DIR falla con exit 2 y mensaje claro" {
  run env -u HOME -u SAVIA_MEMORY_DIR bash "$TARGET" mi-api
  [ "$status" -eq 2 ]
  [[ "$output" == *"HOME"* ]]
  [[ "$output" != *"unbound"* && "$output" != *"sin asignar"* ]]
}

@test "error: destino no escribible falla con exit distinto de 0 y no deja MEMORY.md a medias" {
  mkdir -p "$BASE"
  chmod 0555 "$BASE"
  run bash "$TARGET" mi-api
  chmod 0755 "$BASE"
  [ "$status" -ne 0 ]
  [ ! -e "$BASE/mi-api/memory/MEMORY.md" ]
}

@test "concurrencia: 20 rondas de 8 ejecuciones simultáneas dejan 6 ficheros completos y ningún temporal" {
  # La versión con cat > + sed -i fallaba ~1 de cada 20 rondas (medido: 2/40).
  for round in $(seq 1 20); do
    d="$BASE/p$round/memory"
    pids=()
    for i in 1 2 3 4 5 6 7 8; do
      bash "$TARGET" "p$round" >"$TMP/out.$round.$i" 2>&1 &
      pids+=("$!")
    done
    rc=0
    for p in "${pids[@]}"; do wait "$p" || rc=1; done
    [ "$rc" -eq 0 ]
    [ "$(find "$d" -type f | wc -l)" -eq 6 ]
    [ "$(head -1 "$d/MEMORY.md")" = "# Memory — p$round" ]
    grep -qF "(pendiente de primera sync)" "$d/MEMORY.md"
    [ "$(grep -c '^# Memory' "$d/MEMORY.md")" -eq 1 ]
    [ "$(grep -c '^# ' "$d/debugging.md")" -eq 1 ]
  done
}

@test "locale es_ES: la fecha sigue en formato ISO y nada depende de la coma decimal" {
  run env LC_ALL=es_ES.UTF-8 LANG=es_ES.UTF-8 bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  grep -qE '^> Última sync: [0-9]{4}-[0-9]{2}-[0-9]{2}$' "$BASE/mi-api/memory/MEMORY.md"
}

@test "boundary: nombre largo (200 chars) funciona; 300 chars se rechaza sin crear nada" {
  long="$(printf 'a%.0s' $(seq 1 200))"
  run bash "$TARGET" "$long"
  [ "$status" -eq 0 ]
  [ -f "$BASE/$long/memory/MEMORY.md" ]
  huge="$(printf 'b%.0s' $(seq 1 300))"
  run bash "$TARGET" "$huge"
  [ "$status" -eq 2 ]
  [ ! -e "$BASE/$huge" ]
}

# fake_bin <nombre> <cuerpo> — crea un ejecutable en $TMP/bin que sustituye a <nombre> vía PATH.
fake_bin() {
  mkdir -p "$TMP/bin"
  printf '#!/bin/bash\n%s\n' "$2" > "$TMP/bin/$1"
  chmod +x "$TMP/bin/$1"
}

@test "atomicidad: MEMORY.md no existe mientras se escribe su contenido (solo se publica completo)" {
  [ -d /proc/self/fd ] || skip "sin /proc"
  real_cat="$(command -v cat)"
  # cat espía: anota a qué fichero escribe y si MEMORY.md ya es visible en ese momento.
  fake_bin cat "out=\$(readlink /proc/\$\$/fd/1); vis=no; [ -e \"$BASE/mi-api/memory/MEMORY.md\" ] && vis=yes
echo \"\$out \$vis\" >> \"$TMP/spy.log\"; exec $real_cat \"\$@\""
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [ "$(head -1 "$BASE/mi-api/memory/MEMORY.md")" = "# Memory — mi-api" ]
  # Se escribió en un temporal y, en ese instante, el destino aún no existía.
  grep -qE 'memory/MEMORY\.md\.tmp\.[^ ]+ no$' "$TMP/spy.log"
  run grep -E 'memory/MEMORY\.md (yes|no)$' "$TMP/spy.log"
  [ "$status" -ne 0 ]
}

@test "error: memory/ existente sin permiso de escritura aborta con exit 1 (fail-closed) y sin MEMORY.md" {
  mkdir -p "$BASE/mi-api/memory"
  chmod 0555 "$BASE/mi-api/memory"
  run bash "$TARGET" mi-api
  chmod 0755 "$BASE/mi-api/memory"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Abortado"* ]]
  [ ! -e "$BASE/mi-api/memory/MEMORY.md" ]
  [[ "$output" != *"Auto Memory inicializada"* ]]
}

@test "permisos: los ficheros respetan la umask (644 con umask 022), no quedan en 600" {
  run bash -c 'umask 022 && bash "$1" mi-api' _ "$TARGET"
  [ "$status" -eq 0 ]
  for f in "$BASE/mi-api/memory/"*.md; do
    [ "$(stat -c %a "$f")" = "644" ]
  done
  run bash -c 'umask 077 && bash "$1" otro' _ "$TARGET"
  [ "$(stat -c %a "$BASE/otro/memory/MEMORY.md")" = "600" ]
}

@test "interrupción: SIGTERM durante la escritura no deja temporales huérfanos" {
  real_cat="$(command -v cat)"
  # El primer cat que escribe en un temporal envía SIGTERM a su padre y sigue.
  fake_bin cat "case \$(readlink /proc/\$\$/fd/1) in *.tmp.*) [ -e \"$TMP/killed\" ] || { touch \"$TMP/killed\"; kill -TERM \$PPID; } ;; esac
exec $real_cat \"\$@\""
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ -e "$TMP/killed" ]
  [ "$status" -ne 0 ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
  [ ! -e "$BASE/mi-api/memory/MEMORY.md" ]
}

@test "sin hard links: si ln falla (exFAT, SMB) cae a mv -n y crea los 6 ficheros" {
  fake_bin ln "exit 1"
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [ "$(find "$BASE/mi-api/memory" -type f | wc -l)" -eq 6 ]
  [ "$(head -1 "$BASE/mi-api/memory/MEMORY.md")" = "# Memory — mi-api" ]
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
}

@test "reject: proyecto o memory/ que es symlink hacia fuera se rechaza sin escribir en el destino" {
  mkdir -p "$BASE" "$TMP/fuera"
  ln -s "$TMP/fuera" "$BASE/evil"
  run bash "$TARGET" evil
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$TMP/fuera")" ]
  mkdir -p "$BASE/evil2"
  ln -s "$TMP/fuera" "$BASE/evil2/memory"
  run bash "$TARGET" evil2
  [ "$status" -eq 2 ]
  [ -z "$(ls -A "$TMP/fuera")" ]
}

@test "reject: caracteres Unicode de control bidi (U+202E) se rechazan con exit 2" {
  run bash "$TARGET" $'abc‮exe.md'
  [ "$status" -eq 2 ]
  run bash "$TARGET" $'x⁦y'
  [ "$status" -eq 2 ]
  [ ! -e "$BASE" ] || [ -z "$(ls -A "$BASE")" ]
}

@test "contrato skill: los /comandos que anuncian la skill y su comando existen (sin /onboarding-ask fantasma)" {
  missing=""
  for f in "$REPO_ROOT/.claude/skills/onboarding-dev/SKILL.md" "$REPO_ROOT/.claude/commands/onboarding-dev.md"; do
    while read -r cmd; do
      [ -z "$cmd" ] && continue
      case "$cmd" in compact) continue ;; esac   # built-in del frontend
      [ -f "$REPO_ROOT/.claude/commands/$cmd.md" ] || missing+=" $cmd"
    done < <(grep -oE '(^|[[:space:]`(])/[a-z][a-z0-9-]+([[:space:]`)]|$)' "$f" | tr -d ' `()/' | sort -u)
  done
  [ -z "$missing" ] || { echo "comandos inexistentes:$missing"; false; }
}

@test "contrato skill: projects/*/onboarding/ está git-ignorado (RN-ONB-01)" {
  run git -C "$REPO_ROOT" check-ignore -q "projects/mi-api/onboarding/01-arquitectura-alto-nivel.md"
  [ "$status" -eq 0 ]
  run git -C "$REPO_ROOT" check-ignore -q "projects/mi-api/onboarding/ana-plan-30-60-90.md"
  [ "$status" -eq 0 ]
}

# ── SE-376 S03 grupo 6: huecos que la mutación dejó vivos ────────────────────
# Mutación (grupo 6): 55 mutantes de scripts/setup-memory.sh, uno por condición, umbral,
# código de salida o mensaje. La suite previa mataba 35. Los 20 vivos se resuelven así:
# 18 los matan los tests de abajo (mutante entre paréntesis en cada test) y 2 son
# equivalentes, documentados al final del bloque.

# Ejecuta el script con locale UTF-8 para que `wc -m` y `wc -c` difieran con multibyte.
run_utf8() { run env LC_ALL=C.utf8 bash "$TARGET" "$@"; }

@test "bidi: U+200E (LRM) se rechaza (mutante: rango \\x8e\\x8f sin 200E)" {
  run_utf8 "a"$'\xe2\x80\x8e'"b"
  [ "$status" -eq 2 ]
  [[ "$output" == *"controles bidi"* ]]
  [ -z "$(all_files)" ]
}

@test "bidi: U+202A (LRE) se rechaza (mutante: inicio de rango 202A desplazado)" {
  run_utf8 "a"$'\xe2\x80\xaa'"b"
  [ "$status" -eq 2 ]
  [ -z "$(all_files)" ]
}

@test "bidi: U+2066 y U+2069 (extremos del bloque de aislamiento) se rechazan" {
  run_utf8 "a"$'\xe2\x81\xa6'"b"
  [ "$status" -eq 2 ]
  run_utf8 "a"$'\xe2\x81\xa9'"b"
  [ "$status" -eq 2 ]
  [ -z "$(all_files)" ]
}

@test "bidi frontera: los caracteres vecinos (U+200D, U+202F, U+2065, U+206A) NO se rechazan" {
  for ch in $'\xe2\x80\x8d' $'\xe2\x80\xaf' $'\xe2\x81\xa5' $'\xe2\x81\xaa'; do
    run_utf8 "a${ch}b"
    [ "$status" -eq 0 ]
    [ -f "$BASE/a${ch}b/memory/MEMORY.md" ]
  done
}

@test "longitud: 255 bytes se acepta y 256 se rechaza (mutantes: -gt 256 y -ge 255)" {
  n255="$(printf 'a%.0s' $(seq 1 255))"
  run bash "$TARGET" "$n255"
  [ "$status" -eq 0 ]
  [ -f "$BASE/$n255/memory/MEMORY.md" ]
  n256="$(printf 'b%.0s' $(seq 1 256))"
  run bash "$TARGET" "$n256"
  [ "$status" -eq 2 ]
  [[ "$output" == *"demasiado largo"* ]]
  [ ! -e "$BASE/$n256" ]
}

@test "longitud: el límite cuenta bytes, no caracteres (mutante: wc -m)" {
  # 127 × 'é' (2 bytes) + 'a' = 255 bytes y 128 caracteres: cabe.
  ok="$(printf 'é%.0s' $(seq 1 127))a"
  run_utf8 "$ok"
  [ "$status" -eq 0 ]
  [ -f "$BASE/$ok/memory/MEMORY.md" ]
  # 128 × 'é' = 256 bytes pero solo 128 caracteres: debe rechazarse.
  big="$(printf 'é%.0s' $(seq 1 128))"
  run_utf8 "$big"
  [ "$status" -eq 2 ]
  [[ "$output" == *"demasiado largo"* ]]
  [ ! -e "$BASE/$big" ]
}

@test "mensajes: primera ejecución dice 'creado' para los 6 ficheros y la segunda 'ya existe' (mutantes: mensajes y rc de topics)" {
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cE '^✅ [A-Za-z-]+\.md creado$')" -eq 6 ]
  [ "$(echo "$output" | grep -c 'ya existe')" -eq 0 ]
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -cE '^⏭️  [A-Za-z-]+\.md ya existe$')" -eq 6 ]
  [ "$(echo "$output" | grep -cE '^✅ .*\.md creado$')" -eq 0 ]
}

@test "mensajes: si falta un solo topic file, solo ese se crea y los otros 5 se respetan" {
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  unlink "$BASE/mi-api/memory/debugging.md"
  echo "nota" >> "$BASE/mi-api/memory/architecture.md"
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"✅ debugging.md creado"* ]]
  [ "$(echo "$output" | grep -c 'ya existe')" -eq 5 ]
  grep -qx "nota" "$BASE/mi-api/memory/architecture.md"
}

@test "plantilla: títulos exactos de los 5 topic files, cabecera de fecha exacta e índice completo en MEMORY.md (mutantes: sección, índice, cabecera)" {
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  d="$BASE/mi-api/memory"
  [ "$(head -1 "$d/sprint-history.md")" = "# Sprint History — mi-api" ]
  [ "$(head -1 "$d/architecture.md")" = "# Architecture — mi-api" ]
  [ "$(head -1 "$d/debugging.md")" = "# Debugging — mi-api" ]
  [ "$(head -1 "$d/team-patterns.md")" = "# Team Patterns — mi-api" ]
  [ "$(head -1 "$d/devops-notes.md")" = "# Devops Notes — mi-api" ]
  for t in sprint-history architecture debugging team-patterns devops-notes; do
    grep -qx "> Actualizado: $TODAY" "$d/$t.md"
    grep -qE "^- \`$t\.md\` — " "$d/MEMORY.md"
  done
  grep -qx '## Resumen' "$d/MEMORY.md"
  grep -qx '## Topic Files' "$d/MEMORY.md"
  grep -qx '## Insights Recientes' "$d/MEMORY.md"
}

@test "destino que es un fichero: aborta y no lo trata como carpeta existente (mutante: -e en vez de -d)" {
  echo "contenido previo" > "$TMP/soy-un-fichero"
  export SAVIA_MEMORY_DIR="$TMP/soy-un-fichero"
  run bash "$TARGET" mi-api
  [ "$status" -ne 0 ]
  [[ "$output" != *"Ya existe"* ]]
  [[ "$output" != *"Auto Memory inicializada"* ]]
  [ "$(cat "$TMP/soy-un-fichero")" = "contenido previo" ]
}

@test "interrupción: SIGINT durante la escritura aborta con exit != 0 y sin temporales (mutante: trap INT con exit 0)" {
  real_cat="$(command -v cat)"
  fake_bin cat "case \$(readlink /proc/\$\$/fd/1) in *.tmp.*) [ -e \"$TMP/killed\" ] || { touch \"$TMP/killed\"; kill -INT \$PPID; } ;; esac
exec $real_cat \"\$@\""
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ -e "$TMP/killed" ]
  [ "$status" -ne 0 ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
  [ ! -e "$BASE/mi-api/memory/MEMORY.md" ]
  [[ "$output" != *"Auto Memory inicializada"* ]]
}

@test "carrera con ln: otra ejecución publica el fichero entre medias; se respeta y se informa 'ya existe' (mutante: rc=0)" {
  # El ln falso simula al ganador de la carrera: crea el destino con otro contenido y falla.
  fake_bin ln 'for last; do :; done; echo concurrente > "$last"; exit 1'
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
  [[ "$output" != *"MEMORY.md creado"* ]]
  [ "$(cat "$BASE/mi-api/memory/MEMORY.md")" = "concurrente" ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
}

@test "carrera con mv -n (sin hard links): el ganador no se pisa y se informa 'ya existe' (mutantes: mv -f y rc=0)" {
  fake_bin ln "exit 1"
  real_mv="$(command -v mv)"
  # El mv falso publica el destino «concurrente» justo antes de que mv -n intente moverlo.
  fake_bin mv "for last; do :; done; echo concurrente > \"\$last\"; exec $real_mv \"\$@\""
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
  [[ "$output" != *"MEMORY.md creado"* ]]
  [ "$(cat "$BASE/mi-api/memory/MEMORY.md")" = "concurrente" ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
}

@test "carrera con ln: el ganador deja un symlink roto; cuenta como existente y no se pisa (mutante: sin -L en la línea 83)" {
  fake_bin ln 'for last; do :; done; /bin/ln -s /nonexistent-race-target "$last"; exit 1'
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
  [[ "$output" != *"MEMORY.md creado"* ]]
  [ -L "$BASE/mi-api/memory/MEMORY.md" ]
  [ ! -e /nonexistent-race-target ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
}

@test "ni ln ni mv pueden publicar: aborta con exit 1 y 'Abortado', no declara 'creado' (mutantes: rc=0 y return 0)" {
  fake_bin ln "exit 1"
  fake_bin mv "exit 1"
  run env PATH="$TMP/bin:$PATH" bash "$TARGET" mi-api
  [ "$status" -eq 1 ]
  [[ "$output" == *"No se pudo crear"* ]]
  [[ "$output" == *"Abortado"* ]]
  [[ "$output" != *"MEMORY.md creado"* ]]
  [[ "$output" != *"Auto Memory inicializada"* ]]
  [ ! -e "$BASE/mi-api/memory/MEMORY.md" ]
  [ -z "$(find "$BASE" -name '*.tmp.*')" ]
}

@test "destino colgante: un symlink roto en MEMORY.md no se sigue ni se pisa" {
  mkdir -p "$BASE/mi-api/memory"
  ln -s "$TMP/no-existe" "$BASE/mi-api/memory/MEMORY.md"
  run bash "$TARGET" mi-api
  [ "$status" -eq 0 ]
  [[ "$output" == *"MEMORY.md ya existe"* ]]
  [ ! -e "$TMP/no-existe" ]
  [ -L "$BASE/mi-api/memory/MEMORY.md" ]
  [ -f "$BASE/mi-api/memory/architecture.md" ]
}

# Mutantes equivalentes (sin conducta observable distinta; documentados, no ocultos):
#  - quitar `|| [ -L "$dst" ]` solo de la línea 70: la comprobación de la línea 83 devuelve
#    el mismo rc=3 tras el ln fallido; el resultado es idéntico.
#  - quitar `|| return 1` tras mktemp: tmp queda vacío, `cat >"$tmp"` falla y devuelve 1 por
#    la rama «No se pudo escribir»; mismo exit 1 y mismo aborto, distinto texto de error.
