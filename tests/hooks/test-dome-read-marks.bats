#!/usr/bin/env bats
# SE-462 S1 — marca de sesión de lecturas de cúpula N2+ (hook dome-guard.sh y su gemelo TS de savia-gates).
# Ref: docs/specs/SE-462-read-is-not-relay.spec.md (S1; AC1, AC6, AC8, y negativos: N1 y escritura no marcan)
# Cada caso corre contra las dos implementaciones con el mismo payload: núcleo Python vía hook, y
# lib/dome-guard.ts vía su CLI de paridad. Las marcas van a un directorio temporal (SAVIA_DOME_READ_DIR);
# ningún test toca el HOME real.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  HOOK="$REPO_ROOT/.claude/hooks/dome-guard.sh"
  CLI="$REPO_ROOT/scripts/opencode-plugin/savia-gates/__tests__/dome-guard-cli.ts"
  TS_RUNTIME=""
  if command -v bun >/dev/null 2>&1; then TS_RUNTIME="bun"
  elif [[ -x "$HOME/.bun/bin/bun" ]]; then TS_RUNTIME="$HOME/.bun/bin/bun"
  elif node --experimental-strip-types --no-warnings -e '' >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
  unset SAVIA_DOME_GUARD SAVIA_GATES_PIN SAVIA_SPACE_DOMES_FILE SAVIA_HOOK_PROFILE SAVIA_AUTONOMOUS_RUN
  TMP="$(cd "$(mktemp -d)" && pwd -P)"
  WS="$TMP/ws"
  MARKS="$TMP/area/dome-read"       # dos niveles bajo TMP: un `../../x` caería dentro de TMP
  mkdir -p "$WS/projects/savia-vaults" "$WS/vaults/gallinero" "$WS/vaults/secreta" "$WS/vaults/abierta" "$WS/src"
  printf '{"version":1,"domes":{"gallinero":{"path":"%s/vaults/gallinero","confidentiality":"N2"},"secreta":{"path":"%s/vaults/secreta","confidentiality":"N3"},"abierta":{"path":"%s/vaults/abierta","confidentiality":"N1"}}}' \
    "$WS" "$WS" "$WS" > "$WS/projects/savia-vaults/savia-vaults.domes.json"
  export SAVIA_DOME_READ_DIR="$MARKS"
}

teardown() {
  [[ -n "${TMP:-}" && -d "$TMP" ]] && find "$TMP" -mindepth 1 -delete 2>/dev/null; rmdir "$TMP" 2>/dev/null || true
}

# Deja el área de marcas como si nunca hubiera existido (sin borrado recursivo: find -delete bajo $TMP/area).
reset_marks() {
  [[ -d "$TMP/area" ]] && find "$TMP/area" -mindepth 1 -delete
  mkdir -p "$TMP/area"
  return 0
}

# payload TOOL INPUT_JSON SESSION_JSON [EXTRA]  (SESSION_JSON con comillas, p. ej. '"s1"')
payload() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"session_id":%s,"cwd":"%s"%s}' "$1" "$2" "$3" "$WS" "${4:-}"
}

# run_impl bash|ts PAYLOAD → $output = decisión (pass|ask|deny)
run_impl() {
  local impl="$1" data="$2" out
  if [[ "$impl" == bash ]]; then
    out=$(printf '%s' "$data" | CLAUDE_PROJECT_DIR="$WS" bash "$HOOK")
    if [[ -z "$out" ]]; then output="pass"; else output=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'); fi
  else
    out=$(printf '%s' "$data" | $TS_RUNTIME "$CLI" --root "$WS")
    output=$(printf '%s' "$out" | jq -r '.decision')
  fi
}

impls() {
  if [[ -n "$TS_RUNTIME" ]]; then printf 'bash ts'; else printf 'bash'; fi
}

tree() { find "$TMP" -mindepth 1 -printf '%p %y %m %s\n' | sort; }

NOTA='"file_path":"%s/vaults/gallinero/nota.md"'
nota() { printf "{$NOTA}" "$WS"; }
NUBE_FUERA=',"dome_context":{"cloud":false}'

@test "paridad: el entorno de pruebas tiene un ejecutor TypeScript" {
  [ -n "$TS_RUNTIME" ]
}

@test "AC1: a permitted Read of an N2 dome note leaves a mark with dome and level" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "pass" ]
    [ -f "$MARKS/s1" ]
    [ "$(cat "$MARKS/s1")" = '{"cupula":"gallinero","nivel":"N2"}' ]
  done
}

@test "an asked (cloud, not attached) N2 read also marks: the hook cannot know if the person approved" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"')"
    [ "$output" = "ask" ]
    [ "$(cat "$MARKS/s1")" = '{"cupula":"gallinero","nivel":"N2"}' ]
  done
}

@test "an N3 read outside the cloud marks with level N3; the same read denied in the cloud does not" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/vaults/secreta/a.md\"}" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "pass" ]
    [ "$(cat "$MARKS/s1")" = '{"cupula":"secreta","nivel":"N3"}' ]
    reset_marks
    run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/vaults/secreta/a.md\"}" '"s1"')"
    [ "$output" = "deny" ]
    [ ! -e "$MARKS" ]
  done
}

@test "bash cat of an N2 note marks (same core path as the file tools)" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Bash "{\"command\":\"cat $WS/vaults/gallinero/nota.md\"}" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "pass" ]
    [ "$(cat "$MARKS/s1")" = '{"cupula":"gallinero","nivel":"N2"}' ]
  done
}

@test "negative: reading an N1 dome or a file outside any dome leaves no mark" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/vaults/abierta/a.md\"}" '"s1"')"
    [ "$output" = "pass" ]
    run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/src/a.md\"}" '"s1"')"
    [ "$output" = "pass" ]
    [ ! -e "$MARKS" ]
  done
}

@test "negative: writing into an N2 dome asks (proposal notice) and leaves no mark" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Edit "{\"file_path\":\"$WS/vaults/gallinero/nota.md\",\"old_string\":\"a\",\"new_string\":\"b\"}" '"s1"')"
    [ "$output" = "ask" ]
    run_impl "$impl" "$(payload Write "{\"file_path\":\"$WS/vaults/gallinero/nueva.md\",\"content\":\"x\"}" '"s1"')"
    [ "$output" = "ask" ]
    run_impl "$impl" "$(payload Bash "{\"command\":\"cp $WS/src/a.md $WS/vaults/gallinero/nueva.md\"}" '"s1"')"
    [ "$output" = "ask" ]
    [ ! -e "$MARKS" ]
  done
}

@test "AC6: another session_id does not see the mark" {
  for impl in $(impls); do
    reset_marks
    run_impl "$impl" "$(payload Read "$(nota)" '"sesion-A"' "$NUBE_FUERA")"
    [ -f "$MARKS/sesion-A" ]
    [ ! -e "$MARKS/sesion-B" ]
    [ "$(ls "$MARKS")" = "sesion-A" ]
  done
}

@test "marks accumulate per dome without duplicates; directory is 0700 and file 0600" {
  for impl in $(impls); do
    reset_marks
    for f in gallinero/a.md secreta/b.md gallinero/c.md; do
      run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/vaults/$f\"}" '"s1"' "$NUBE_FUERA")"
    done
    [ "$(wc -l < "$MARKS/s1")" -eq 2 ]
    [ "$(stat -c %a "$MARKS")" = "700" ]
    [ "$(stat -c %a "$MARKS/s1")" = "600" ]
  done
}

@test "files older than 7 days are purged on the next mark; recent ones stay" {
  for impl in $(impls); do
    reset_marks; mkdir -p "$MARKS"; chmod 700 "$MARKS"
    : > "$MARKS/vieja"; : > "$MARKS/reciente"
    touch -d '8 days ago' "$MARKS/vieja"
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"' "$NUBE_FUERA")"
    [ ! -e "$MARKS/vieja" ]
    [ -e "$MARKS/reciente" ]
  done
}

@test "AC8: invalid session ids ask, create nothing and leave the file tree unchanged" {
  long="$(printf 'a%.0s' $(seq 1 129))"
  for impl in $(impls); do
    for sid in '"../../x"' '"a/b"' '""' "\"$long\"" '"con espacio"' 'null' '42'; do
      reset_marks
      before="$(tree)"
      run_impl "$impl" "$(payload Read "$(nota)" "$sid" "$NUBE_FUERA")"
      [ "$output" = "ask" ] || { echo "$impl sid=$sid dio $output"; return 1; }
      [ "$(tree)" = "$before" ] || { echo "$impl sid=$sid cambió el árbol"; return 1; }
    done
  done
}

@test "AC8: a payload without session_id asks too" {
  for impl in $(impls); do
    reset_marks
    data="{\"tool_name\":\"Read\",\"tool_input\":$(nota),\"cwd\":\"$WS\",\"dome_context\":{\"cloud\":false}}"
    run_impl "$impl" "$data"
    [ "$output" = "ask" ]
    [ ! -e "$MARKS" ]
  done
}

@test "invalid session id outside any dome decides nothing (the guard only acts on dome reads)" {
  for impl in $(impls); do
    run_impl "$impl" "$(payload Read "{\"file_path\":\"$WS/src/a.md\"}" '"../../x"')"
    [ "$output" = "pass" ]
  done
}

@test "autonomous run: invalid session id and unwritable mark directory deny instead of ask" {
  for impl in $(impls); do
    reset_marks
    export SAVIA_AUTONOMOUS_RUN=1
    run_impl "$impl" "$(payload Read "$(nota)" '"../x"' "$NUBE_FUERA")"
    [ "$output" = "deny" ]
    : > "$MARKS"   # el directorio de marcas es un fichero regular
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "deny" ]
    unset SAVIA_AUTONOMOUS_RUN
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "ask" ]
  done
}

@test "a symlink in place of the mark directory is refused (ask), nothing is written through it" {
  for impl in $(impls); do
    reset_marks; mkdir -p "$TMP/destino"
    ln -s "$TMP/destino" "$MARKS"
    run_impl "$impl" "$(payload Read "$(nota)" '"s1"' "$NUBE_FUERA")"
    [ "$output" = "ask" ]
    [ -z "$(ls -A "$TMP/destino")" ]
  done
}
