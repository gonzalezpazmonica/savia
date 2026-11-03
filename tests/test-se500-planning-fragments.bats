#!/usr/bin/env bats
# SE-500 S1 — fragmentos de planificación (planning.d/, LOG.d/) y vista consolidada.
# Spec: docs/specs/SE-500-merge-sprint-sin-realineacion.spec.md (AC-1 a AC-8).

ROOT_REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RM="$ROOT_REAL/scripts/roadmap.sh"
PV="$ROOT_REAL/scripts/planning-view.py"

setup() {
  FX="$BATS_TEST_TMPDIR/repo"
  P="$FX/docs/propuestas"
  mkdir -p "$P" "$FX/docs/specs"
  cat > "$P/planning-state.json" <<'JSON'
{"version":2,"tracked_spec_floor":375,"completion_contract_floor":396,
 "route":{"current_phase":"A","phases":["A","B"],"wip_limit":{"savia_implementing":3}},
 "initiatives":[
  {"id":"SE-375","status":"APPROVED","approval":"human approval","phase":"A","title":"uno","evidence":""},
  {"id":"SE-376","status":"PROPOSED","phase":"A","title":"dos","evidence":""}
]}
JSON
  printf '# Specs Lifecycle Log\n\n> cabecera\n\n## 2026-09-06 SE-376 PROPOSED\n\nfixture\n\n## 2026-09-05 SE-375 APPROVED\n\nfixture\n' > "$P/LOG.md"
  spec 375 APPROVED
  spec 376 PROPOSED
  git -C "$FX" init -q -b main
  git -C "$FX" config user.email test@example.invalid
  git -C "$FX" config user.name "SE-500 Test"
  git -C "$FX" add -A
  git -C "$FX" commit -qm baseline
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
}

spec() { printf 'status: %s\n' "$2" > "$FX/docs/specs/SE-$1-example.spec.md"; }
frag() { mkdir -p "$P/planning.d"; printf '%s\n' "$2" > "$P/planning.d/$1"; }
logfrag() { mkdir -p "$P/LOG.d"; printf '%s\n' "$2" > "$P/LOG.d/$1"; }
validate() { run env REPO_ROOT="$FX" bash "$RM" validate "$@"; }
set_session() { # <initiative> <prerequisites>
  jq --arg i "$1" --arg p "$2" '.route.session_plan=[{"id":"S01","phase":"A","priority":"P0","initiatives":[$i],
    "title":"t","action":"a","prerequisites":$p,"done":"d","necessity":"n","urgency":"u","value":"v",
    "dependency_value":"dv","effort":"e"}]' "$P/planning-state.json" > "$FX/s.tmp"
  mv "$FX/s.tmp" "$P/planning-state.json"
}

@test "baseline: the fixture validates" {
  validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

# ── AC-1: determinista ─────────────────────────────────────────────────────

make_set() { # <root> <order: a|b>
  local d="$1/docs/propuestas"
  mkdir -p "$d/planning.d" "$d/LOG.d"
  local files=(
    'planning.d/SE-380.json|{"id":"SE-380","status":"APPROVED","approval":"ok","phase":"A","title":"c","evidence":""}'
    'planning.d/SE-376.json|{"id":"SE-376","status":"APPROVED","approval":"ok","phase":"A","title":"dos","evidence":""}'
    'planning.d/SE-381.json|{"id":"SE-381","status":"PROPOSED","phase":"A","title":"d","evidence":""}'
    'LOG.d/SE-380-PROPOSED.md|## 2026-11-01 SE-380 PROPOSED'
    'LOG.d/SE-380-APPROVED.md|## 2026-11-01 SE-380 APPROVED'
    'LOG.d/SE-381-PROPOSED.md|## 2026-11-01 SE-381 PROPOSED'
    'LOG.d/SE-376-APPROVED.md|## 2026-11-02 SE-376 APPROVED'
  )
  local idx=(0 1 2 3 4 5 6)
  [[ "$2" == b ]] && idx=(6 5 4 3 2 1 0)
  for i in "${idx[@]}"; do printf '%s\n' "${files[$i]#*|}" > "$d/${files[$i]%%|*}"; done
}

@test "AC-1: state and log are byte-identical regardless of creation order and LC_ALL" {
  cp -r "$FX" "$BATS_TEST_TMPDIR/b"
  make_set "$FX" a
  make_set "$BATS_TEST_TMPDIR/b" b
  LC_ALL=C python3 "$PV" --root "$FX" state > "$BATS_TEST_TMPDIR/s1"
  LC_ALL=C.UTF-8 python3 "$PV" --root "$BATS_TEST_TMPDIR/b" state > "$BATS_TEST_TMPDIR/s2"
  LC_ALL=C python3 "$PV" --root "$FX" log > "$BATS_TEST_TMPDIR/l1"
  LC_ALL=C.UTF-8 python3 "$PV" --root "$BATS_TEST_TMPDIR/b" log > "$BATS_TEST_TMPDIR/l2"
  cmp "$BATS_TEST_TMPDIR/s1" "$BATS_TEST_TMPDIR/s2"
  cmp "$BATS_TEST_TMPDIR/l1" "$BATS_TEST_TMPDIR/l2"
  # Orden exigido: fecha desc, id numérico desc, rango de estado desc; luego la base.
  run grep '^## ' "$BATS_TEST_TMPDIR/l1"
  [ "${lines[0]}" = "## 2026-11-02 SE-376 APPROVED" ]
  [ "${lines[1]}" = "## 2026-11-01 SE-381 PROPOSED" ]
  [ "${lines[2]}" = "## 2026-11-01 SE-380 APPROVED" ]
  [ "${lines[3]}" = "## 2026-11-01 SE-380 PROPOSED" ]
  [ "${lines[4]}" = "## 2026-09-06 SE-376 PROPOSED" ]
  # state: SE-376 sustituido en su sitio; altas en orden numérico.
  run jq -r '.initiatives[] | "\(.id) \(.status)"' "$BATS_TEST_TMPDIR/s1"
  [ "$output" = "$(printf 'SE-375 APPROVED\nSE-376 APPROVED\nSE-380 APPROVED\nSE-381 PROPOSED')" ]
}

@test "AC-1: without fragments the view is the base byte for byte" {
  python3 "$PV" --root "$FX" log | cmp - "$P/LOG.md"
  python3 "$PV" --root "$FX" state | jq -S . > "$BATS_TEST_TMPDIR/v"
  jq -S . "$P/planning-state.json" | cmp - "$BATS_TEST_TMPDIR/v"
}

# ── AC-2: consolidate idempotente y conservador ────────────────────────────

@test "AC-2: consolidate keeps the view identical, removes fragments and is idempotent" {
  make_set "$FX" a
  python3 "$PV" --root "$FX" state > "$BATS_TEST_TMPDIR/s0"
  python3 "$PV" --root "$FX" log > "$BATS_TEST_TMPDIR/l0"
  run env REPO_ROOT="$FX" bash "$RM" consolidate
  [ "$status" -eq 0 ]
  [ -z "$(ls "$P/planning.d")" ]
  [ -z "$(ls "$P/LOG.d")" ]
  cmp "$BATS_TEST_TMPDIR/s0" "$P/planning-state.json"
  cmp "$BATS_TEST_TMPDIR/l0" "$P/LOG.md"
  python3 "$PV" --root "$FX" state | cmp - "$BATS_TEST_TMPDIR/s0"
  python3 "$PV" --root "$FX" log | cmp - "$BATS_TEST_TMPDIR/l0"
  sum1=$(cat "$P/planning-state.json" "$P/LOG.md" | sha256sum)
  run env REPO_ROOT="$FX" bash "$RM" consolidate
  [ "$status" -eq 0 ]
  [ "$(cat "$P/planning-state.json" "$P/LOG.md" | sha256sum)" = "$sum1" ]
}

@test "AC-2: consolidate refuses (fail-closed) while a fragment is invalid" {
  frag SE-377.json '{"id":"SE-378","status":"PROPOSED","title":"x","evidence":""}'
  before=$(sha256sum "$P/planning-state.json")
  run env REPO_ROOT="$FX" bash "$RM" consolidate
  [ "$status" -ne 0 ]
  [ -f "$P/planning.d/SE-377.json" ]
  [ "$(sha256sum "$P/planning-state.json")" = "$before" ]
}

# ── AC-3: las 10 comprobaciones sobre la vista, con el fallo en un fragmento ─

@test "AC-3 check 1: fragment duplicating a base id (SE-0375) → IDs duplicados" {
  frag SE-0375.json '{"id":"SE-0375","status":"APPROVED","approval":"ok","phase":"A","title":"x","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IDs duplicados: SE-375"* ]]
}

@test "AC-3 check 2: fragment with an invalid status → estados inválidos" {
  frag SE-376.json '{"id":"SE-376","status":"BOGUS","phase":"A","title":"dos","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estados inválidos: BOGUS"* ]]
}

@test "AC-3 check 3: fragment IMPLEMENTED without evidence → FAIL" {
  frag SE-376.json '{"id":"SE-376","status":"IMPLEMENTED","phase":"A","title":"dos","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IMPLEMENTED sin evidencia: SE-376"* ]]
}

@test "AC-3 check 4: fragment raising its spec to APPROVED without approval → FAIL" {
  frag SE-376.json '{"id":"SE-376","status":"APPROVED","phase":"A","title":"dos","evidence":""}'
  logfrag SE-376-APPROVED.md '## 2026-11-03 SE-376 APPROVED'
  spec 376 APPROVED
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: APPROVED sin aprobación registrada: SE-376"* ]]
  # control: con aprobación registrada pasa
  frag SE-376.json '{"id":"SE-376","status":"APPROVED","approval":"operadora","phase":"A","title":"dos","evidence":""}'
  validate
  [ "$status" -eq 0 ]
}

@test "AC-3 check 5: spec registered only by a misnamed fragment → specs omitidas" {
  spec 377 PROPOSED
  frag SE-377.json '{"id":"SE-737","status":"PROPOSED","phase":"A","title":"x","evidence":""}'
  logfrag SE-377-PROPOSED.md '## 2026-11-03 SE-377 PROPOSED'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: specs omitidas de planning-state: SE-377"* ]]
  # control: bien nombrado, pasa
  frag SE-377.json '{"id":"SE-377","status":"PROPOSED","phase":"A","title":"x","evidence":""}'
  validate
  [ "$status" -eq 0 ]
}

@test "AC-3 check 6: fragment status contradicting the spec → FAIL" {
  frag SE-375.json '{"id":"SE-375","status":"REJECTED","phase":"A","title":"uno","evidence":""}'
  logfrag SE-375-REJECTED.md '## 2026-11-03 SE-375 REJECTED'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: SE-375 spec=APPROVED vs state=REJECTED"* ]]
}

@test "AC-3 check 7: fragment status without its LOG.d entry → FAIL; with it → PASS" {
  frag SE-375.json '{"id":"SE-375","status":"DEFERRED","phase":"A","title":"uno","evidence":""}'
  spec 375 DEFERRED
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estado vigente sin registro en LOG.md: SE-375"* ]]
  logfrag SE-375-DEFERRED.md '## 2026-11-03 SE-375 DEFERRED'
  validate
  [ "$status" -eq 0 ]
}

@test "AC-3 check 8: fragment with a phase outside the route → FAIL" {
  frag SE-375.json '{"id":"SE-375","status":"APPROVED","approval":"ok","phase":"Z","title":"uno","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: iniciativas sin fase válida de la ruta: SE-375"* ]]
}

@test "AC-3 check 8: fragments exceeding the WIP limit → FAIL" {
  jq '.route.wip_limit.savia_implementing=0' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  frag SE-375.json '{"id":"SE-375","status":"IMPLEMENTING","approval":"ok","phase":"A","title":"uno","evidence":""}'
  logfrag SE-375-IMPLEMENTING.md '## 2026-11-03 SE-375 IMPLEMENTING'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: WIP excedido: 1 IMPLEMENTING > límite 0"* ]]
}

@test "AC-3 check 9: session referencing an initiative whose fragment is misnamed → FAIL" {
  set_session SE-378 "nada"
  frag SE-378.json '{"id":"SE-387","status":"PROPOSED","phase":"A","title":"x","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: cola de sesiones inválida"* ]]
  frag SE-378.json '{"id":"SE-378","status":"PROPOSED","phase":"A","title":"x","evidence":""}'
  logfrag SE-378-PROPOSED.md '## 2026-11-03 SE-378 PROPOSED'
  validate
  [ "$status" -eq 0 ]
}

@test "AC-3 check 10: fragment approving a spec that a session still asks to approve → FAIL" {
  set_session SE-376 "Aprobación de SE-376"
  validate
  [ "$status" -eq 0 ]
  frag SE-376.json '{"id":"SE-376","status":"APPROVED","approval":"operadora","phase":"A","title":"dos","evidence":""}'
  logfrag SE-376-APPROVED.md '## 2026-11-03 SE-376 APPROVED'
  spec 376 APPROVED
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"pide aprobar una spec ya resuelta: S01:SE-376=APPROVED"* ]]
}

@test "AC-3: LOG.d names outside the regex fail (unknown state, spaces, ..)" {
  for name in 'SE-376-BOGUS.md' 'SE-376 -PROPOSED.md' 'SE-376-PROPOSED..md' '..SE-376-PROPOSED.md' 'SE-376-proposed.md'; do
    rm -rf "$P/LOG.d"
    logfrag "$name" '## 2026-11-03 SE-376 PROPOSED'
    validate
    [ "$status" -ne 0 ]
    [[ "$output" == *"LOG.d: nombre de fragmento inválido"* ]]
  done
}

@test "AC-3: LOG.d entry with a header that does not match its name, or two headers → FAIL" {
  logfrag SE-376-PROPOSED.md '## 2026-11-03 SE-377 PROPOSED'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"la cabecera no coincide con el nombre"* ]]
  logfrag SE-376-PROPOSED.md "$(printf '## 2026-11-03 SE-376 PROPOSED\n\ntexto\n## 2026-11-04 SE-376 PROPOSED')"
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"más de una cabecera"* ]]
}

@test "AC-3: LOG.d entry dated before the newest base entry → WARN only" {
  logfrag SE-376-PROPOSED.md '## 2026-01-01 SE-376 PROPOSED'
  validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARN: LOG.d/SE-376-PROPOSED.md tiene fecha 2026-01-01 anterior"* ]]
}

# ── AC-4: nombre/id, JSON, duplicados ──────────────────────────────────────

@test "AC-4: fragment name and id differ → FAIL" {
  frag SE-376.json '{"id":"SE-377","status":"PROPOSED","phase":"A","title":"x","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"planning.d/SE-376.json: nombre e id no coinciden"* ]]
}

@test "AC-4: invalid JSON fragment → FAIL; readers refuse the view (fail-closed)" {
  frag SE-376.json '{"id": "SE-376", '
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"planning.d/SE-376.json: JSON inválido"* ]]
  run env REPO_ROOT="$FX" bash "$RM" current
  [ "$status" -ne 0 ]
  [[ "$output" == *"vista de planificación no construible"* ]]
}

@test "AC-4: the same id in two fragments → FAIL" {
  frag SE-376.json '{"id":"SE-376","status":"PROPOSED","phase":"A","title":"dos","evidence":""}'
  frag SE-0376.json '{"id":"SE-0376","status":"PROPOSED","phase":"A","title":"dos","evidence":""}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"id duplicado en varios fragmentos: SE-0376.json, SE-376.json"* ]]
}

@test "AC-4: fragment missing mandatory fields → FAIL" {
  frag SE-376.json '{"id":"SE-376","status":"PROPOSED","phase":"A"}'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"faltan campos obligatorios: title, evidence"* ]]
}

# ── AC-5: validate --diff ──────────────────────────────────────────────────

on_branch() { git -C "$FX" checkout -qb feature; }
commit_all() { git -C "$FX" add -A && git -C "$FX" commit -qm "${1:-change}"; }

@test "AC-5: editing a base initiative outside a consolidation → FAIL" {
  on_branch
  jq '.initiatives[0].title="cambiado"' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  commit_all
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"initiatives de la base cambiadas sin ser consolidación pura"*"SE-375"* ]]
}

@test "AC-5: adding an initiative directly to the base → FAIL" {
  on_branch
  jq '.initiatives += [{"id":"SE-377","status":"PROPOSED","phase":"A","title":"x","evidence":""}]' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  spec 377 PROPOSED
  sed -i 's/^## 2026-09-06/## 2026-11-03 SE-377 PROPOSED\n\n## 2026-09-06/' "$P/LOG.md"
  commit_all
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-377"* ]]
  [[ "$output" == *"LOG.md editado sin ser consolidación pura"* ]]
}

@test "AC-5: adding an entry directly to LOG.md → FAIL" {
  on_branch
  sed -i 's/^## 2026-09-06 SE-376 PROPOSED/## 2026-11-03 SE-375 APPROVED\n\nnueva\n\n&/' "$P/LOG.md"
  commit_all
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"LOG.md editado sin ser consolidación pura"* ]]
}

@test "AC-5: modifying or deleting an existing LOG.md entry → FAIL" {
  on_branch
  sed -i 's/^fixture$/reescrito/' "$P/LOG.md"
  commit_all
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"LOG.md editado"* ]]
  git -C "$FX" checkout -q main -- docs/propuestas/LOG.md
  sed -i '/^## 2026-09-05 SE-375 APPROVED$/,$d' "$P/LOG.md"
  commit_all
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"LOG.md editado"* ]]
}

@test "AC-5: the consolidation PR passes; consolidation plus an extra edit fails" {
  spec 377 PROPOSED
  run env REPO_ROOT="$FX" bash "$RM" register SE-377 --status PROPOSED --phase A --title "nueva" --date 2026-11-03
  [ "$status" -eq 0 ]
  run env REPO_ROOT="$FX" bash "$RM" register SE-376 --status APPROVED --approval "operadora" --date 2026-11-03
  [ "$status" -eq 0 ]
  spec 376 APPROVED
  commit_all "register on main"
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  on_branch
  run env REPO_ROOT="$FX" bash "$RM" consolidate
  [ "$status" -eq 0 ]
  commit_all consolidate
  validate --diff origin/main
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: base de planificación sin cambios fuera de consolidación (2+2"* ]]
  jq '.initiatives[0].title="colado"' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  commit_all extra
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-375"* ]]
}

@test "AC-5: deleting a fragment without consolidating it → FAIL" {
  run env REPO_ROOT="$FX" bash "$RM" register SE-376 --status APPROVED --approval ok --date 2026-11-03
  spec 376 APPROVED
  commit_all "register on main"
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  on_branch
  git -C "$FX" rm -q docs/propuestas/planning.d/SE-376.json docs/propuestas/LOG.d/SE-376-APPROVED.md
  commit_all drop
  validate --diff origin/main
  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-376"* ]]
}

@test "AC-5: --diff without a resolvable merge-base fails closed" {
  validate --diff refs/remotes/origin/nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"validate --diff no evaluable"* ]]
}

# ── AC-5b: nombres con \n final ────────────────────────────────────────────

@test "AC-5b: planning.d and LOG.d names with a trailing newline → FAIL" {
  mkdir -p "$P/planning.d" "$P/LOG.d"
  printf '%s\n' '{"id":"SE-1","status":"PROPOSED","title":"x","evidence":""}' > "$P/planning.d/SE-1.json"$'\n'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"planning.d: nombre de fragmento inválido: 'SE-1.json\\n'"* ]]
  rm -rf "$P/planning.d"
  printf '## 2026-11-03 SE-376 PROPOSED\n' > "$P/LOG.d/SE-376-PROPOSED.md"$'\n'
  validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"LOG.d: nombre de fragmento inválido: 'SE-376-PROPOSED.md\\n'"* ]]
}

# ── AC-6: escritores solo fragmentos; dos PR sin conflicto ─────────────────

@test "AC-6: roadmap.sh register writes only the two fragments" {
  before=$(cat "$P/planning-state.json" "$P/LOG.md" | sha256sum)
  run env REPO_ROOT="$FX" bash "$RM" register SE-377 --status PROPOSED --priority P2 --phase A \
    --title "Nueva" --note "por qué" --evidence "" --date 2026-11-03
  [ "$status" -eq 0 ]
  [ "$(cat "$P/planning-state.json" "$P/LOG.md" | sha256sum)" = "$before" ]
  run git -C "$FX" status --porcelain --untracked-files=all
  [ "$output" = "$(printf '?? docs/propuestas/LOG.d/SE-377-PROPOSED.md\n?? docs/propuestas/planning.d/SE-377.json')" ]
  run jq -c . "$P/planning.d/SE-377.json"
  [ "$output" = '{"id":"SE-377","status":"PROPOSED","priority":"P2","phase":"A","title":"Nueva","evidence":"","note":"por qué"}' ]
  [ "$(cat "$P/LOG.d/SE-377-PROPOSED.md")" = "$(printf '## 2026-11-03 SE-377 PROPOSED\n\npor qué')" ]
}

@test "AC-6: register rejects an invalid id or status without writing" {
  run env REPO_ROOT="$FX" bash "$RM" register 'SE-1/../x' --status PROPOSED --title t
  [ "$status" -ne 0 ]
  run env REPO_ROOT="$FX" bash "$RM" register SE-377 --status DONE --title t
  [ "$status" -ne 0 ]
  [ ! -e "$P/planning.d" ]
  [ ! -e "$P/LOG.d" ]
}

@test "AC-6: spec-lifecycle.sh writes only a LOG.d fragment" {
  printf -- '---\nspec_id: SE-376\ntitle: "dos"\nstatus: PROPOSED\n---\n' > "$FX/docs/specs/SE-376-example.spec.md"
  git -C "$FX" add -A && git -C "$FX" commit -qm spec
  run env PROPUESTAS_DIR_OVERRIDE="$P" bash "$ROOT_REAL/scripts/spec-lifecycle.sh" \
    --spec "$FX/docs/specs/SE-376-example.spec.md" --status APPROVED --note "aprobada" --no-timeline
  [ "$status" -eq 0 ]
  run git -C "$FX" status --porcelain --untracked-files=all
  [ "$output" = "$(printf ' M docs/specs/SE-376-example.spec.md\n?? docs/propuestas/LOG.d/SE-376-APPROVED.md')" ]
}

@test "AC-6: two branches registering different specs merge in any order without conflict" {
  for order in "a b" "b a"; do
    git -C "$FX" checkout -q main
    git -C "$FX" reset -q --hard refs/remotes/origin/main
    git -C "$FX" branch -D a b >/dev/null 2>&1 || true
    git -C "$FX" checkout -qb a main
    spec 377 PROPOSED
    env REPO_ROOT="$FX" bash "$RM" register SE-377 --status PROPOSED --phase A --title "a" --date 2026-11-03 >/dev/null
    commit_all a
    git -C "$FX" checkout -qb b main
    spec 378 PROPOSED
    env REPO_ROOT="$FX" bash "$RM" register SE-378 --status PROPOSED --phase A --title "b" --date 2026-11-04 >/dev/null
    commit_all b
    git -C "$FX" checkout -q main
    for br in $order; do
      run git -C "$FX" merge -q --no-edit "$br"
      [ "$status" -eq 0 ]
    done
    validate
    [ "$status" -eq 0 ]
    run env REPO_ROOT="$FX" bash "$RM" next
    [[ "$output" == *"SE-377"* && "$output" == *"SE-378"* ]]
  done
}

@test "AC-6 control: the same two registrations edited in the base do conflict" {
  git -C "$FX" checkout -qb a main
  jq '.initiatives += [{"id":"SE-377","status":"PROPOSED","title":"a","evidence":""}]' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  commit_all a
  git -C "$FX" checkout -qb b main
  jq '.initiatives += [{"id":"SE-378","status":"PROPOSED","title":"b","evidence":""}]' "$P/planning-state.json" > "$FX/s.tmp" && mv "$FX/s.tmp" "$P/planning-state.json"
  commit_all b
  git -C "$FX" checkout -q main
  git -C "$FX" merge -q --no-edit a
  run git -C "$FX" merge -q --no-edit b
  [ "$status" -ne 0 ]
}

# ── AC-8: lectores sobre la vista ──────────────────────────────────────────

@test "AC-8: an initiative present only in a fragment reaches planning-transition, ROADMAP-CURRENT and validate-ci-local" {
  frag SE-377.json '{"id":"SE-377","status":"IMPLEMENTING","phase":"A","title":"solo fragmento","evidence":"",
    "completion":{"merge_pr":1,"acceptance_evidence":[{"criterion":"A1","file":"x","authority":"simulada","authority_required":"real"}]}}'
  logfrag SE-377-IMPLEMENTING.md '## 2026-11-03 SE-377 IMPLEMENTING'
  # planning-transition.sh: la ve (sin la vista diría «no existe»)
  run env REPO_ROOT="$FX" bash "$ROOT_REAL/scripts/planning-transition.sh" check SE-377
  [[ "$output" != *"no existe"* ]]
  [[ "$output" == *"NOT_READY"* ]]
  # ROADMAP-CURRENT.md generado desde la vista
  run env REPO_ROOT="$FX" bash "$RM" render
  [ "$status" -eq 0 ]
  grep -q 'SE-377 \[IMPLEMENTING\] solo fragmento' "$P/ROADMAP-CURRENT.md"
  # validate-ci-local.sh: informe de cobertura leído de la vista
  mkdir -p "$FX/scripts/lib" "$FX/.claude/hooks/lib"
  cp "$ROOT_REAL/scripts/validate-ci-local.sh" "$ROOT_REAL/scripts/planning-view.py" "$FX/scripts/"
  cp "$ROOT_REAL/scripts/lib/mock-env.sh" "$ROOT_REAL/scripts/lib/planning-completion.sh" "$FX/scripts/lib/"
  printf '#!/usr/bin/env bash\necho ok\n' > "$FX/scripts/coherence-gates.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/.claude/hooks/lib/gate-result.sh"
  run env -u SAVIA_PLANNING_STATE_FOR_TESTS SAVIA_FRESH_CHECKS_FOR_TESTS=' ' SAVIA_LOCK_DIRS_FOR_TESTS=' ' \
    bash -c 'cd "$1" && bash scripts/validate-ci-local.sh --quick' _ "$FX"
  [[ "$output" == *"SE-377 · A1: autoridad simulada < requerida real"* ]]
}

@test "AC-8: history shows a fragment-only initiative and its LOG.d entry" {
  frag SE-377.json '{"id":"SE-377","status":"PROPOSED","phase":"A","title":"solo fragmento","evidence":""}'
  logfrag SE-377-PROPOSED.md '## 2026-11-03 SE-377 PROPOSED'
  run env REPO_ROOT="$FX" bash "$RM" history SE-377
  [ "$status" -eq 0 ]
  [[ "$output" == *"estado: PROPOSED"* ]]
  [[ "$output" == *"## 2026-11-03 SE-377 PROPOSED"* ]]
}
