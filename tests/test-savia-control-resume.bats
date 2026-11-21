#!/usr/bin/env bats
# SE-498 F0 — solo la operadora reanuda (AC-6): aprobación por PR con gh y remoto simulados,
# gobernanza tier 4, identidad, aceptación de inciertos, cobertura, reutilización, dos clones,
# nombre del fichero, vía débil por terminal y pseudo-terminal bajo un ejecutor.

load fixtures/savia-control/setup

setup() { setup_control; operator_setup; }

marker() { echo "$(git -C "$R" rev-parse --absolute-git-dir)/savia-control/installed"; }
seq_of() { jget "$SAVIA_CONTROL_DIR/state.json" "d['stops']['$1']['stop_seq']"; }
consumed() { grep -q "$1" "$(marker)"; }
ledger() { printf '%s\n' "$@" > "$SAVIA_EFFECT_LEDGER"; }

paused_a() { sc pause --scope executor:a --reason x; sc reconcile --scope executor:a || [ $? -eq 5 ]; }

@test "AC-6: resume sin terminal ni PR sale 4 y state.json no cambia" {
  paused_a
  before=$(state_sha)
  run sc resume --scope executor:a < /dev/null; [ "$status" -eq 4 ]; [[ "$output" == *NO_APPROVAL* ]]
  [ "$(state_sha)" = "$before" ]
}

@test "AC-6: con la aprobación de la época vigente, la regla activa y la fusión de la operadora, procede" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]
  consumed "$APPROVAL_BLOB"
  grep -q "\"approval_blob\":\"$APPROVAL_BLOB\"" "$SAVIA_CONTROL_DIR/control.jsonl"
}

@test "AC-6: ausente, de una época anterior o de otro ámbito → 4 APPROVAL_MISSING; contenido con época o stop_seq viejos → 4 APPROVAL_INVALID" {
  sc revoke --reason r; sc reconcile
  S=$(seq_of global)
  run sc resume --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_MISSING* ]]   # ausente
  approve global 0 "$S"                     # época anterior (la vigente es 1): el nombre no casa
  run sc resume --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_MISSING* ]]
  approve executor:a 1 "$S"                 # otro ámbito: tampoco casa el nombre
  run sc resume --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_MISSING* ]]
  # nombre vigente con época o stop_seq anteriores en el contenido → APPROVAL_INVALID
  P="config/control/resume/1-$S-$(printf global | sha256sum | cut -c1-16).json"
  origin_put "$P" "{\"epoch\":0,\"stop_seq\":$S,\"scope\":\"global\",\"reason\":\"ok\",\"accept\":[]}"
  run sc resume --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_INVALID* ]]
  origin_put "$P" "{\"epoch\":1,\"stop_seq\":$((S - 1)),\"scope\":\"global\",\"reason\":\"ok\",\"accept\":[]}"
  run sc resume --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_INVALID* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "AC-6 negativos: gh api fallando, git fetch fallando, regla inactiva o fusión de otro → 4 (no 2)" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  before=$(state_sha)
  touch "$GH_STUB_DIR/api/repos_owner_repo_rules_branches_main.fail"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
  rm "$GH_STUB_DIR/api/repos_owner_repo_rules_branches_main.fail"
  git -C "$R" remote set-url origin "$T/no-existe.git"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *FETCH_FAILED* ]]
  git -C "$R" remote set-url origin "$ORIGIN"
  gh_api repos_owner_repo_rules_branches_main '[{"type":"deletion"}]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *RULE_INACTIVE* ]]
  gh_api repos_owner_repo_rules_branches_main '[{"type":"pull_request"}]'
  gh_api "repos_owner_repo_pulls_$APPROVAL_PR" "{\"number\":$APPROVAL_PR,\"merged_by\":{\"login\":\"otra\"}}"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *MERGED_BY_OTHER* ]]
  [ "$(state_sha)" = "$before" ]
  run consumed "$APPROVAL_BLOB"; [ "$status" -ne 0 ]
}

@test "AC-6 gobernanza: risk-tier clasifica tier 4 una PR que solo toca config/control/" {
  for f in config/control/resume/1-2-0123456789abcdef.json config/control/operator.json \
           config/control/executors-remote.json config/control/REVOCATION_EPOCH config/control/gate.json; do
    [ "$(python3 "$SRC_ROOT/scripts/risk-tier.py" --diff "$f" --json | jget /dev/stdin 'd["tier"]')" = 4 ]
  done
}

@test "AC-6 gobernanza: la PR de la aprobación tier 3 según el risk-tier.py de origin/main → 4 sin consumir" {
  paused_a
  sed 's|, "config/control/")|)|' "$R/scripts/risk-tier.py" > "$T/rt.py"
  origin_put scripts/risk-tier.py "$(cat "$T/rt.py")"
  approve executor:a 0 "$(seq_of executor:a)"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *TIER_NOT_4* ]]
  run consumed "$APPROVAL_BLOB"; [ "$status" -ne 0 ]
}

@test "AC-6 gobernanza: la PR figura MERGED en el ledger del merge-sprint → 4 sin consumir" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  mkdir -p "$MERGE_SPRINT_HOME"; echo "{\"event\":\"MERGED\",\"pr\":\"$APPROVAL_PR\"}" > "$MERGE_SPRINT_HOME/ledger.jsonl"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *MERGED_BY_SPRINT* ]]
  run consumed "$APPROVAL_BLOB"; [ "$status" -ne 0 ]
}

@test "AC-6 identidad: fusión de «otra» con AUTONOMOUS_REVIEWER y SAVIA_ACTOR = otra → 4; sin operator.json → 4" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)" '[]' otra
  AUTONOMOUS_REVIEWER=otra SAVIA_ACTOR=otra run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
  gh_api "repos_owner_repo_pulls_$APPROVAL_PR" "{\"number\":$APPROVAL_PR,\"merged_by\":{\"login\":\"operadora\"}}"
  git -C "$R" rm -q config/control/operator.json; git -C "$R" commit -qm rm; git -C "$R" push -q origin main
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *OPERATOR_UNKNOWN* ]]
}

@test "AC-6 aceptación: el conjunto aceptado tiene que ser exactamente el de INDETERMINATE" {
  ledger '{"effect_id":"e1","state":"NEEDS_REVIEW","executor":"a"}' '{"effect_id":"e2","state":"DISPATCHED","executor":"a"}' \
         '{"effect_id":"e9","state":"NEEDS_REVIEW","executor":"b"}'
  sc pause --scope executor:a --reason x
  run sc reconcile --scope executor:a; [ "$status" -eq 5 ]
  [[ "$output" == *"INDETERMINATE e1"* && "$output" == *"INDETERMINATE e2"* && "$output" != *e9* ]]
  S=$(seq_of executor:a)
  approve executor:a 0 "$S" '["e1"]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *"ACCEPT_MISMATCH: faltan e2"* ]]
  run consumed "$APPROVAL_BLOB"; [ "$status" -ne 0 ]
  approve executor:a 0 "$S" '["e1","e2","e3"]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *"sobran e3"* ]]
  approve executor:a 0 "$S" '["e1","e2"]'
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  grep '"op":"resume"' "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"effect_id":"e1"'
  grep '"op":"resume"' "$SAVIA_CONTROL_DIR/control.jsonl" | grep -q '"effect_id":"e2"'
}

@test "AC-6 aceptación: no hay otra vía para aceptar (resume --accept y reconcile --accept salen 2)" {
  paused_a
  run sc resume --scope executor:a --accept e1; [ "$status" -eq 2 ]
  run sc reconcile --accept e1; [ "$status" -eq 2 ]
}

@test "AC-6: sin reconcile del ámbito tras su parada, resume aprobado sale 5 RECONCILE_REQUIRED" {
  sc pause --scope executor:a --reason x
  approve executor:a 0 "$(seq_of executor:a)"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *RECONCILE_REQUIRED* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "AC-6 cobertura: con global vigente sale 9 y no consume la aprobación de executor:a, que sirve después" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"; BLOB_A=$APPROVAL_BLOB
  sc pause --reason g; sc reconcile --scope global
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 9 ]
  run consumed "$BLOB_A"; [ "$status" -ne 0 ]
  approve global 0 "$(seq_of global)"
  run sc resume --via-pr; [ "$status" -eq 0 ]
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  consumed "$BLOB_A"
}

@test "AC-6 reutilización: pause → resume aprobado → pause en la misma época → el mismo fichero da 4" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 0 ]
  paused_a
  before=$(state_sha)
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
  [ "$(state_sha)" = "$before" ]
}

force_seq() {  # fuerza la entrada <ámbito> a un stop_seq anterior (fixture de AC-6)
  python3 - "$SAVIA_CONTROL_DIR/state.json" "$1" "$2" <<'EOF'
import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["stops"][sys.argv[2]]["stop_seq"]=int(sys.argv[3]); json.dump(d,open(p,"w"))
EOF
}

@test "AC-6 reutilización: un blob ya consumido sale 4 aunque el stop_seq vuelva a coincidir" {
  paused_a
  S=$(seq_of executor:a)
  approve executor:a 0 "$S"
  sc resume --scope executor:a --via-pr
  sc pause --scope executor:a --reason otra; force_seq executor:a "$S"; sc reconcile --scope executor:a
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_CONSUMED* ]]
}

@test "AC-6 dos clones: el clon B no reutiliza el blob consumido por A aunque su marca no lo tenga" {
  paused_a
  S=$(seq_of executor:a)
  approve executor:a 0 "$S"
  sc resume --scope executor:a --via-pr
  git clone -q "$ORIGIN" "$T/B"
  sc pause --scope executor:a --reason otra; force_seq executor:a "$S"; sc reconcile --scope executor:a
  run python3 -I "$T/B/scripts/savia-control.py" resume --scope executor:a --via-pr
  echo "$output"; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_CONSUMED* ]]
  [ ! -e "$T/B/.git/savia-control/installed" ]   # B no tenía marca: lo frena el diario compartido
}

@test "AC-6: otro ámbito no invalida la aprobación (pause b tras aprobar a; resume a procede y b sigue PAUSED)" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  sc pause --scope executor:b --reason y
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc check --executor b; [ "$status" -eq 6 ]; [[ "$output" == *PAUSED* ]]
}

@test "AC-6 nombre: hash que no corresponde al scope del contenido, o scope con : sobrantes → 4" {
  paused_a
  S=$(seq_of executor:a)
  approve executor:a 0 "$S" '[]' operadora executor:b
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_INVALID* ]]
  approve executor:a 0 "$S" '[]' operadora 'executor:a:x'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
  approve executor:a 0 "$S" '[]' operadora 'executor:../a'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
}

@test "AC-6 precedencia: sin aprobación y con efectos INDETERMINATE a la vez, sale 4" {
  ledger '{"effect_id":"e1","state":"NEEDS_REVIEW","executor":"a"}'
  paused_a
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]
}

@test "AC-6: pause, revoke y quarantine funcionan sin terminal" {
  run sc pause --scope executor:a --reason x < /dev/null; [ "$status" -eq 0 ]
  run sc quarantine b --reason y < /dev/null; [ "$status" -eq 0 ]
  run sc revoke --reason z < /dev/null; [ "$status" -eq 0 ]
}

pty_run() {  # pty_run <entradas separadas por |> <orden...>: en una pseudo-terminal desacoplada del árbol
  local inputs="$1"; shift
  python3 "$SRC_ROOT/tests/fixtures/savia-control/pty-detached.py" "$T/res" "$inputs" "$@"
  for _ in $(seq 75); do [ -f "$T/res" ] && break; sleep 0.2; done
  cat "$T/res.out"; RES=$(cat "$T/res"); OUT=$(cat "$T/res.out"); rm -f "$T/res"
}

terminal_resume() {  # terminal_resume <ámbito> <entradas separadas por |>
  pty_run "$2" python3 -I "$R/scripts/savia-control.py" resume --scope "$1"
}

# wrapped_resume <nombre> [args tras -c]: resume executor:a por terminal dentro de una copia de bash con ese
# nombre, ya fuera del árbol del ejecutor que lanza los tests. Sin `script` en la cadena, para que cada test
# aísle una sola rama de forbidden(). `; exit $?` impide que bash haga exec y desaparezca del árbol.
wrapped_resume() {
  local w="$T/w/$1"; shift
  mkdir -p "$T/w"; cp "$(command -v bash)" "$w"
  pty_run "executor:a|1" "$w" -c "python3 -I $R/scripts/savia-control.py resume --scope executor:a; exit \$?" "$@"
}

denied_by() {  # denied_by <comm>: salió 4 por ese ancestro concreto y el ámbito sigue parado
  [ "$RES" = 4 ]; [[ "$OUT" == *"ancestro es un ejecutor conocido ($1, pid"* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "AC-6 ancestros (control): el mismo envoltorio con un nombre neutro deja reanudar" {
  paused_a; wrapped_resume operadora-sh
  [ "$RES" = 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]
}

@test "AC-6 ancestros: un padre con comm claude bloquea la vía terminal (sin script en la cadena)" {
  paused_a; wrapped_resume claude; denied_by claude
}

@test "AC-6 ancestros: un padre con comm opencode bloquea la vía terminal" {
  paused_a; wrapped_resume opencode; denied_by opencode
}

# En CI la falta de util-linux `script` es un fallo, no un skip: el caso del pseudo-terminal quedaría sin ejercer.
# $1 opcional: ruta de búsqueda. Solo afecta a `command -v`; `run` de bats conserva el PATH real.
require_script() {
  if PATH="${1:-$PATH}" command -v script >/dev/null; then return 0; fi
  if [ -n "${CI:-}" ]; then echo "falta util-linux script en CI" >&2; return 1; fi
  skip "sin util-linux script"
}

@test "d82d4d5 security P2-2: en CI, sin util-linux script, la prueba del pseudo-terminal falla en vez de omitirse" {
  CI=1 run require_script "$T/sin-nada"
  [ "$status" -eq 1 ]; [[ "$output" == *"falta util-linux script en CI"* ]]
}

@test "d82d4d5 security P2-2 (negativo): con script disponible, require_script pasa también en CI" {
  mkdir -p "$T/bin"; printf '#!/bin/sh\n' > "$T/bin/script"; chmod +x "$T/bin/script"
  CI=1 run require_script "$T/bin"
  [ "$status" -eq 0 ]
}

@test "AC-6 ancestros: script -qec como padre bloquea la vía terminal" {
  require_script
  paused_a
  pty_run "executor:a|1" script -qec "python3 -I $R/scripts/savia-control.py resume --scope executor:a" /dev/null
  denied_by script
}

@test "AC-6 ancestros: node con claude u opencode en la cmdline bloquea; node sin ellos no" {
  paused_a
  wrapped_resume node claude-code; denied_by node
  wrapped_resume node opencode-cli; denied_by node
  wrapped_resume node otra-herramienta; [ "$RES" = 0 ]
}

@test "AC-6 ancestros: comm overnight-sprin… (truncado) bloquea aunque la cmdline no diga overnight-sprint-loop" {
  paused_a; wrapped_resume overnight-sprint-x; denied_by overnight-sprin
}

@test "AC-6 ancestros: overnight-sprint-loop en la cmdline bloquea con un comm neutro" {
  paused_a; wrapped_resume worker overnight-sprint-loop.sh; denied_by worker
}

@test "AC-6 vía débil: resume por terminal deja ancestros y via terminal; WEAK_RESUME hasta la siguiente parada" {
  paused_a
  terminal_resume executor:a "executor:a|1"
  [ "$RES" = 0 ]
  grep '"op":"resume"' "$SAVIA_CONTROL_DIR/control.jsonl" | grep '"via":"terminal"' | grep -q '"cmdline"'
  run sc status; [[ "$output" == *"WEAK_RESUME executor:a"* ]]
  sc pause --scope executor:a --reason otra
  run sc status; [[ "$output" != *WEAK_RESUME* ]]
}

@test "AC-6 vía débil: stop_seq tecleado distinto → 4 sin mostrar efectos" {
  ledger '{"effect_id":"e1","state":"NEEDS_REVIEW","executor":"a"}'
  paused_a
  terminal_resume executor:a "executor:a|99"
  [ "$RES" = 4 ]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "AC-6 vía débil: por terminal se aceptan los inciertos uno a uno; faltar uno da 5 ACCEPT_MISMATCH" {
  ledger '{"effect_id":"e1","state":"NEEDS_REVIEW","executor":"a"}' '{"effect_id":"e2","state":"NEEDS_REVIEW","executor":"a"}'
  paused_a
  terminal_resume executor:a "executor:a|1|acepto e1|no"
  [ "$RES" = 5 ]
  terminal_resume executor:a "executor:a|1|acepto e1|acepto e2"
  [ "$RES" = 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]
}

# ── revisión #1593: paginación y trazabilidad de la PR de aprobación ────────

@test "AC-6 gh: el fichero tier 4 en la página 2 de pulls/N/files cuenta (se pagina)" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  gh_api "repos_owner_repo_pulls_${APPROVAL_PR}_files" '[{"filename":"docs/x.md"}]'
  printf '[{"filename":"%s","sha":"%s"}]' "$APPROVAL_PATH" "$APPROVAL_BLOB" > "$GH_STUB_DIR/api/repos_owner_repo_pulls_${APPROVAL_PR}_files.page2.json"
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  grep -q "pulls/$APPROVAL_PR/files --paginate" "$GH_STUB_DIR/calls.log"
}

@test "AC-6 gh negativo: sin la página 2, la misma PR solo con docs/x.md sale TIER_NOT_4" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  gh_api "repos_owner_repo_pulls_${APPROVAL_PR}_files" '[{"filename":"docs/x.md"}]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *TIER_NOT_4* ]]
}

@test "AC-6 gh: un nombre de fichero con espacios en la PR → 4 TIER_UNVERIFIABLE sin consumir" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  gh_api "repos_owner_repo_pulls_${APPROVAL_PR}_files" "[{\"filename\":\"$APPROVAL_PATH\"},{\"filename\":\"docs/a b.md\"}]"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *TIER_UNVERIFIABLE* ]]
  run consumed "$APPROVAL_BLOB"; [ "$status" -ne 0 ]
}

@test "AC-6 gh: el commit de la aprobación en dos PR fusionadas → 4 APPROVAL_UNTRACEABLE; en una sola y otra abierta, procede" {
  paused_a
  approve executor:a 0 "$(seq_of executor:a)"
  sha=$(git -C "$R" log -1 --format=%H -- "$APPROVAL_PATH")
  gh_api "repos_owner_repo_commits_${sha}_pulls" "[{\"number\":$APPROVAL_PR,\"merged_at\":\"2026-11-16T00:00:00Z\"},{\"number\":9,\"merged_at\":\"2026-11-16T00:00:00Z\"}]"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_UNTRACEABLE* ]]
  gh_api "repos_owner_repo_commits_${sha}_pulls" "[{\"number\":9,\"merged_at\":null},{\"number\":$APPROVAL_PR,\"merged_at\":\"2026-11-16T00:00:00Z\"}]"
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
}
