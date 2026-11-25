#!/usr/bin/env bats
# SE-497 S0 — firma humana verificable de lecciones (tests de Claude; TDD cruzado con Codex).
# Ref: docs/specs/SE-497-code-linked-knowledge-drift-and-learning-without-self-authority.spec.md (S0-1..S0-7)
# Todo ocurre en un directorio temporal: nunca toca output/ ni docs/learning-proposals/.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="scripts/learning-lifecycle.sh"
  LC="$REPO_ROOT/$SCRIPT"
  T=$(mktemp -d)
  F="$T/LP-1.md"; LED="$T/led/lifecycle.jsonl"
  SHA="sha:0123456789abcdef0123456789abcdef01234567"
  mk canary
}
teardown() { rm -rf "$T"; }

mk() {  # mk <estado> [fichero] [id]
  printf -- '---\nid: %s\nlifecycle: %s\nprovenance: INFERRED\ncreated_utc: 2026-11-01T00:00:00Z\n---\nCuerpo de la leccion.\nlifecycle: esto es prosa del cuerpo\n' \
    "${3:-LP-1}" "$1" > "${2:-$F}"
}
h() { sha256sum "$1" | cut -d' ' -f1; }
rows() { [[ -f "$LED" ]] && wc -l < "$LED" || echo 0; }
json_ok() { python3 -c 'import json,sys; [json.loads(l) for l in open(sys.argv[1])]' "$LED"; }
field() { python3 -c 'import json,sys; print(json.loads(open(sys.argv[1]).read().splitlines()[-1])[sys.argv[2]], end="")' "$LED" "$1"; }
act() { run bash "$LC" --file "$F" --to active --actor operadora --ledger "$LED" --metric-before 0.5 --metric-after 0.7 "$@"; }

# ── S0-6: camino válido ──
@test "S0-6: trailer sha valido y dos metricas sin regresion promociona" {
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: active' "$F"
  grep -qx 'provenance: human_authored' "$F"
  grep -qx "human_trailer: $SHA" "$F"
}
@test "S0-6: trailer se488 valido promociona" {
  act --human-trailer "se488:recibo_2026-11.A"
  [ "$status" -eq 0 ]
  grep -qx 'human_trailer: se488:recibo_2026-11.A' "$F"
}
@test "S0-6: metricas iguales no son regresion y promociona" {
  run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA" --metric-before 0.5 --metric-after 0.5
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: active' "$F"
}
@test "S0-6: leccion ya activa con trailer antiguo de texto libre se sigue leyendo y pasa a superseded" {
  printf -- '---\nid: LP-old\nlifecycle: active\nprovenance: human_authored\ncreated_utc: 2026-08-21\nhuman_trailer: operadora/monica/2026-08-21T05:06:54Z\n---\ncuerpo\n' > "$F"
  run bash "$LC" --file "$F" --to superseded --ledger "$LED"
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: superseded' "$F"
  grep -qx 'human_trailer: operadora/monica/2026-08-21T05:06:54Z' "$F"
}
@test "S0-6: el cuerpo no se toca al promocionar aunque contenga una linea lifecycle" {
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: esto es prosa del cuerpo' "$F"
  [ "$(grep -c '^lifecycle: active$' "$F")" -eq 1 ]
}

# ── S0-1: trailer ausente, vacío o mal formado ──
@test "S0-1: trailer missing is rejected with exit 4 and the file stays identical" {
  before=$(h "$F"); act
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
}
@test "S0-1: empty trailer is rejected with exit 4" {
  before=$(h "$F"); act --human-trailer ""
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
}
@test "S0-1: free-text trailer is rejected (invalid format)" {
  before=$(h "$F")
  for t in "x" "op-sig" "operadora" "sha:123" "sha:0123456789ABCDEF0123456789abcdef01234567" "se488:" "SHA:0123456789abcdef0123456789abcdef01234567" " $SHA" "$SHA " "sha:0123456789abcdef0123456789abcdef012345678"; do
    act --human-trailer "$t"
    [ "$status" -eq 4 ] || { echo "aceptado: [$t]"; false; }
    [ "$before" = "$(h "$F")" ] || { echo "modificado con: [$t]"; false; }
  done
}
@test "S0-1: se488 id over the 64 char boundary is rejected" {
  long=$(printf 'a%.0s' $(seq 1 65))
  act --human-trailer "se488:$long"
  [ "$status" -eq 4 ]
  ok=$(printf 'a%.0s' $(seq 1 64))
  act --human-trailer "se488:$ok"
  [ "$status" -eq 0 ]
}
@test "S0-1: with --strict an invalid trailer is also rejected with exit 4" {
  before=$(h "$F"); act --strict --human-trailer "x"
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
}

# ── S0-2: metacaracteres e inyección ──
@test "S0-2: trailer with sed metacharacters is rejected and body stays intact" {
  before=$(h "$F")
  for t in 'a/;s/Cuerpo/HACK/;s/x/' 'a&b' 'a;b' 'a"b' "a'b" 'a\b' $'a\tb' "$SHA/" "$SHA&" 'se488:a/b' 'se488:a b'; do
    act --human-trailer "$t"
    [ "$status" -eq 4 ] || { echo "aceptado: [$t]"; false; }
    [ "$before" = "$(h "$F")" ] || { echo "modificado con: [$t]"; false; }
  done
}
@test "S0-2: trailer with newline is rejected and injects no header field" {
  before=$(h "$F")
  act --human-trailer "$SHA"$'\nfoo: bar'
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
  ! grep -q '^foo: bar' "$F"
}
@test "S0-2: trailer with newline and a sed e command executes nothing (blocked)" {
  act --human-trailer "$SHA"$'\ne touch '"$T/SENTINEL"
  [ "$status" -eq 4 ]
  [ ! -e "$T/SENTINEL" ]
  act --human-trailer $'x\ne touch '"$T/SENTINEL"
  [ ! -e "$T/SENTINEL" ]
}
@test "S0-2: trailer with carriage return or control characters is rejected" {
  before=$(h "$F")
  for t in "$SHA"$'\r' $'se488:a\x01b' $'se488:a\x1bb' $'se488:a\x7fb' $'se488:a\xc2\x85b' "se488:a"$'‮'"b"; do
    act --human-trailer "$t"
    [ "$status" -eq 4 ] || { echo "aceptado"; false; }
    [ "$before" = "$(h "$F")" ]
  done
}
@test "S0-2: valid trailer followed by newline only is rejected" {
  before=$(h "$F"); act --human-trailer "$SHA"$'\n'
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
}

# ── S0-3: registro JSON ──
@test "S0-3: reason with quotes, backslash and newline keeps the ledger valid JSON and the value" {
  r=$'dijo "si" \\ y\nsegunda linea'
  act --human-trailer "$SHA" --reason "$r"
  [ "$status" -eq 0 ]
  json_ok
  [ "$(rows)" -eq 1 ]
  [ "$(field reason)" = "$r" ]
}
@test "S0-3: actor with quotes and backslash keeps the ledger valid JSON" {
  a='op"era\dora'
  run bash "$LC" --file "$F" --to active --actor "$a" --ledger "$LED" --human-trailer "$SHA" --metric-before 1 --metric-after 2
  [ "$status" -eq 0 ]
  json_ok
  [ "$(field actor)" = "$a" ]
}
@test "S0-3: lesson id with quotes keeps the ledger valid JSON" {
  mk canary "$F" 'LP-"x"\y'
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  json_ok
  [ "$(field id)" = 'LP-"x"\y' ]
}
@test "S0-3: refused attempt without trailer is recorded as valid JSON even with hostile reason" {
  act --reason 'a"b'
  [ "$status" -eq 4 ]
  json_ok
  [ "$(rows)" -eq 1 ]
  [ "$(field status)" = "refused-no-human" ]
  [ "$(field reason)" = 'a"b' ]
}
@test "S0-3: a reason cannot forge an extra ledger row" {
  act --human-trailer "$SHA" --reason $'x"}\n{"id":"LP-1","to":"active","actor":"forjado"'
  [ "$status" -eq 0 ]
  json_ok
  [ "$(rows)" -eq 1 ]
}

# ── S0-4: métricas ──
@test "S0-4: canary to active with zero metrics is rejected with exit 5 and stays canary" {
  run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA"
  [ "$status" -eq 5 ]
  grep -qx 'lifecycle: canary' "$F"
  grep -qx 'provenance: INFERRED' "$F"
}
@test "S0-4: canary to active with only one metric is rejected with exit 5" {
  run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA" --metric-before 0.5
  [ "$status" -eq 5 ]
  run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA" --metric-after 0.9
  [ "$status" -eq 5 ]
  grep -qx 'lifecycle: canary' "$F"
}
@test "S0-4: non-numeric or empty metrics are rejected with exit 5 (invalid)" {
  for pair in "abc 1" "1 abc" "1 " " 1" "0.5;x 0.9" "nan 1" "1e5 2"; do
    set -- $pair
    run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA" --metric-before "${1:-}" --metric-after "${2:-}"
    [ "$status" -eq 5 ] || { echo "aceptado: [$pair]"; false; }
    grep -qx 'lifecycle: canary' "$F"
  done
}
@test "S0-4: regression fails with exit 5 and reverts to proposed" {
  run bash "$LC" --file "$F" --to active --ledger "$LED" --human-trailer "$SHA" --metric-before 0.9 --metric-after 0.5
  [ "$status" -eq 5 ]
  grep -qx 'lifecycle: proposed' "$F"
  ! grep -q '^human_trailer:' "$F"
  json_ok
  [ "$(field to)" = "proposed" ]
  [ "$(field revert)" = "true" ]
}
@test "S0-4: metrics do not replace the trailer: missing trailer with good metrics is rejected" {
  before=$(h "$F")
  run bash "$LC" --file "$F" --to active --ledger "$LED" --metric-before 0.1 --metric-after 0.9
  [ "$status" -eq 4 ]
  [ "$before" = "$(h "$F")" ]
}

# ── S0-5: idempotencia ──
@test "S0-5: identical second activation adds no ledger row and leaves the file identical" {
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  n=$(rows); before=$(h "$F")
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq "$n" ]
  [ "$before" = "$(h "$F")" ]
}
@test "S0-5: repeated superseded adds no second tombstone and no row" {
  run bash "$LC" --file "$F" --to superseded --ledger "$LED"
  [ "$status" -eq 0 ]
  n=$(rows)
  run bash "$LC" --file "$F" --to superseded --ledger "$LED"
  [ "$status" -eq 0 ]
  [ "$(grep -c '^tombstone:' "$F")" -eq 1 ]
  [ "$(rows)" -eq "$n" ]
}
@test "S0-5: canary to canary repeated adds no row" {
  run bash "$LC" --file "$F" --to canary --ledger "$LED"
  [ "$status" -eq 0 ]
  [ "$(rows)" -eq 0 ]
}

# ── S0-7 y bordes ──
@test "S0-7: no sed in the script interpolates an argument value" {
  ! grep -nE 'sed .*\$\{?(HUMAN_TRAILER|REASON|ACTOR|ID|SUBSET|METRIC_BEFORE|METRIC_AFTER|TO|CURRENT)\b' "$LC"
}
@test "S0-7: the script keeps strict mode" {
  grep -q '^set -uo pipefail' "$REPO_ROOT/$SCRIPT"
}
@test "edge: nonexistent file exits 3 and writes no ledger" {
  run bash "$LC" --file "$T/no-existe.md" --to active --ledger "$LED" --human-trailer "$SHA"
  [ "$status" -eq 3 ]
  [ ! -e "$LED" ]
}
@test "edge: proposed to active stays an invalid transition even with valid trailer" {
  mk proposed; before=$(h "$F")
  act --human-trailer "$SHA"
  [ "$status" -eq 1 ]
  [ "$before" = "$(h "$F")" ]
}
@test "edge: file path with spaces works" {
  F="$T/con espacios/LP 2.md"; mkdir -p "$T/con espacios"; mk canary "$F"
  act --human-trailer "$SHA"
  [ "$status" -eq 0 ]
  grep -qx 'lifecycle: active' "$F"
}
@test "edge: file without lifecycle field is not promoted (no arg state)" {
  printf -- '---\nid: LP-9\nprovenance: INFERRED\n---\ncuerpo\n' > "$F"; before=$(h "$F")
  act --human-trailer "$SHA"
  [ "$status" -ne 0 ]
  [ "$before" = "$(h "$F")" ]
}
