#!/usr/bin/env bats
# SE-378 planning-state coverage and status reconciliation tests.

SCRIPT="scripts/roadmap.sh"

set_session_plan() {
  set_route 3 A
  jq '.route.session_plan = [{"id":"S01","phase":"A","priority":"P0","initiatives":["SE-375"],
    "title":"review existing delivery","action":"verify receipts","prerequisites":"human review pending",
    "done":"acceptance evidence","necessity":"high","urgency":"high","value":"high",
    "dependency_value":"unblocks boundary","effort":"small"}]' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
}

@test "current renders session gates from the canonical plan" {
  set_session_plan
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" current
  [ "$status" -eq 0 ]
  [[ "$output" == *"S01 · P0 · fase A"* ]]
  [[ "$output" == *"Entrada: human review pending"* ]]
  [[ "$output" == *"Salida: acceptance evidence"* ]]
}

@test "validate rejects a session referencing an unknown initiative" {
  set_session_plan
  jq '.route.session_plan[0].initiatives=["SE-999"]' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"cola de sesiones inválida"* ]]
}

@test "validate accepts a well formed session plan without graduating an initiative" {
  set_session_plan
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "validate rejects a session that still asks to approve an APPROVED spec" {
  set_session_plan
  jq '.route.session_plan[0].prerequisites="Aprobación de SE-375 y decisión D1"' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"pide aprobar una spec ya resuelta: S01:SE-375=APPROVED"* ]]
}

@test "validate accepts a session asking to approve a PROPOSED spec" {
  set_session_plan
  jq '.initiatives[0].status="PROPOSED" | .route.session_plan[0].prerequisites="Aprobación de SE-375"' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  printf '%s\n' 'status: PROPOSED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '## 2026-09-05 SE-375 PROPOSED\n' >> "$FIXTURE/docs/propuestas/LOG.md"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [[ "$output" != *"pide aprobar"* ]]
  [ "$status" -eq 0 ]
}

@test "validate checks every spec in an approval enumeration, not only the first" {
  set_session_plan
  jq '.route.session_plan[0].prerequisites="Aprobación de SE-999 y SE-375"' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"pide aprobar una spec ya resuelta: S01:SE-375=APPROVED"* ]]
}

@test "validate accepts a session asking to reactivate a DEFERRED spec" {
  set_session_plan
  jq '.initiatives[0].status="DEFERRED" | .route.session_plan[0].prerequisites="Aprobación de SE-375 (reactivación)"' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  printf '%s\n' 'status: DEFERRED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '## 2026-09-05 SE-375 DEFERRED\n' >> "$FIXTURE/docs/propuestas/LOG.md"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [[ "$output" != *"pide aprobar"* ]]
  [ "$status" -eq 0 ]
}

@test "validate fails closed when the approval check cannot be evaluated" {
  set_session_plan
  jq '.route.session_plan[0].prerequisites=5' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"check de aprobaciones obsoletas no evaluable"* ]]
}

@test "validate reports stale approvals literally without shell globbing" {
  set_session_plan
  jq '.route.session_plan[0].id="S*" | .route.session_plan[0].prerequisites="Aprobación de SE-375"' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  touch "$FIXTURE/Sglob-hit:SE-375=APPROVED"
  run env REPO_ROOT="$FIXTURE" bash -c "cd '$FIXTURE' && bash '$PWD/$SCRIPT' validate"
  [ "$status" -ne 0 ]
  [[ "$output" == *"resuelta: S*:SE-375=APPROVED"* ]]
  [[ "$output" != *"glob-hit"* ]]
}

@test "next identifies merged delivery as review work while keeping APPROVED" {
  set_session_plan
  jq '.initiatives[0].delivery={"merge_pr":42}' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" next
  [ "$status" -eq 0 ]
  [[ "$output" == *"SE-375 [APPROVED]"*"integrada; revisar evidencia/graduación"* ]]
  [[ "$output" != *"SE-375 [IMPLEMENTED]"* ]]
}

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  FIXTURE="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$FIXTURE/docs/propuestas" "$FIXTURE/docs/specs"
  cat > "$FIXTURE/docs/propuestas/planning-state.json" <<'JSON'
{"version":2,"tracked_spec_floor":375,"completion_contract_floor":396,"initiatives":[
  {"id":"SE-375","status":"APPROVED","approval":"human approval"}
]}
JSON
  printf '## 2026-09-05 SE-375 APPROVED\n\nfixture\n' > "$FIXTURE/docs/propuestas/LOG.md"
  git -C "$FIXTURE" init -q
  git -C "$FIXTURE" config user.email test@example.invalid
  git -C "$FIXTURE" config user.name "Planning Test"
  git -C "$FIXTURE" add .
  git -C "$FIXTURE" commit -qm 'baseline'
  git -C "$FIXTURE" commit --allow-empty -qm 'feat: implementation (#42)'
  git -C "$FIXTURE" update-ref refs/remotes/origin/main HEAD
}

@test "roadmap validator exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "roadmap validator keeps strict pipefail safety" {
  grep -q 'set -uo pipefail' "$SCRIPT"
}

@test "validate accepts complete tracked coverage" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "validate rejects an omitted tracked spec" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-376-omitted.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: specs omitidas de planning-state: SE-376"* ]]
}

@test "validate ignores legacy specs below the declared floor" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-100-legacy.spec.md"
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
}

@test "validate detects YAML status drift" {
  printf '%s\n' 'status: PROPOSED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-375 spec=PROPOSED vs state=APPROVED"* ]]
}

@test "validate detects Markdown status drift" {
  printf '%s\n' '**Estado:** REJECTED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"SE-375 spec=REJECTED vs state=APPROVED"* ]]
}

@test "validate rejects duplicate initiative IDs" {
  jq '.initiatives += [.initiatives[0]]' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: IDs duplicados: SE-375"* ]]
}

@test "validate rejects an invalid lifecycle status" {
  jq '.initiatives[0].status="UNKNOWN"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estados inválidos: UNKNOWN"* ]]
}

@test "validate rejects approved state without human approval" {
  jq 'del(.initiatives[0].approval)' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: APPROVED sin aprobación registrada: SE-375"* ]]
}

@test "validate rejects missing completion contract floor" {
  jq 'del(.completion_contract_floor)' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: completion_contract_floor ausente o inválido"* ]]
}

set_route() { # <wip> <phase-of-SE-375>
  jq --argjson w "$1" --arg ph "$2" '.route={"current_phase":"A","phases":["A","B"],"wip_limit":{"savia_implementing":$w}} | .initiatives[0].phase=$ph' \
    "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
}

@test "validate rejects a tracked state missing from LOG.md" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '# empty log\n' > "$FIXTURE/docs/propuestas/LOG.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: estado vigente sin registro en LOG.md: SE-375"* ]]
}

@test "validate rejects a transition not recorded in LOG.md" {
  printf '%s\n' 'status: DEFERRED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  jq '.initiatives[0].status="DEFERRED"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"sin registro en LOG.md: SE-375"* ]]
}

@test "validate rejects a missing LOG.md file" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  mv "$FIXTURE/docs/propuestas/LOG.md" "$FIXTURE/LOG.moved"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"sin registro en LOG.md: SE-375"* ]]
}

@test "validate accepts IMPLEMENTING exactly at the WIP limit" {
  set_route 1 A
  jq '.initiatives[0].status="IMPLEMENTING"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  printf '## 2026-09-26 SE-375 IMPLEMENTING\n' >> "$FIXTURE/docs/propuestas/LOG.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

@test "validate rejects IMPLEMENTING above the WIP limit" {
  set_route 0 A
  jq '.initiatives[0].status="IMPLEMENTING"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
  printf '## 2026-09-26 SE-375 IMPLEMENTING\n' >> "$FIXTURE/docs/propuestas/LOG.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: WIP excedido: 1 IMPLEMENTING > límite 0"* ]]
}

@test "validate rejects a non-terminal initiative outside the route phases" {
  set_route 3 Z

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: iniciativas sin fase válida de la ruta: SE-375"* ]]
}

@test "validate rejects a route without a numeric WIP limit" {
  set_route 3 A
  jq '.route.wip_limit.savia_implementing="three"' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL: route.wip_limit.savia_implementing ausente o inválido"* ]]
}

@test "next selects the active phase and sorts by priority" {
  set_route 3 A
  jq '.initiatives = [
    {"id":"SE-375","status":"APPROVED","approval":"human approval","phase":"A","priority":"P2","title":"later"},
    {"id":"SE-376","status":"PROPOSED","phase":"A","priority":"P0","title":"needs approval"},
    {"id":"SE-377","status":"APPROVED","approval":"human approval","phase":"B","priority":"P0","title":"future phase"},
    {"id":"SE-378","status":"APPROVED","approval":"human approval","phase":"A","priority":"P1","title":"earlier"}
  ]' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" next

  [ "$status" -eq 0 ]
  [[ "$output" == *"Fase A"* ]]
  [[ "$output" != *"SE-377"* ]]
  [[ "$output" == *"SE-376 [PROPOSED]"*"requiere aprobación"* ]]
  [[ "$output" == *"SE-378 [APPROVED]"* ]]
  [[ "$output" == *"SE-375 [APPROVED]"* ]]
  [[ "$output" == *"SE-376"*"SE-378"*"SE-375"* ]]
}

@test "next does not offer new work when the route WIP limit is full" {
  set_route 1 A
  jq '.initiatives = [
    {"id":"SE-375","status":"IMPLEMENTING","phase":"A","title":"ongoing"},
    {"id":"SE-376","status":"APPROVED","approval":"human approval","phase":"A","priority":"P0","title":"queued"}
  ]' "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" next

  [ "$status" -eq 0 ]
  [[ "$output" == *"WIP completo (1/1)"* ]]
  [[ "$output" == *"SE-375 [IMPLEMENTING]"* ]]
  [[ "$output" != *"SE-376 [APPROVED]"* ]]
}

@test "next falls back to the legacy list when the route is absent" {
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" next

  [ "$status" -eq 0 ]
  [[ "$output" == *"SE-375 [APPROVED]"* ]]
}

@test "edge: validate ignores non-numeric spec IDs without arithmetic errors" {
  printf '%s\n' 'status: APPROVED' > "$FIXTURE/docs/specs/SE-375-example.spec.md"
  printf '%s\n' 'status: PROPOSED' > "$FIXTURE/docs/specs/SE-GRC-001-example.spec.md"

  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate

  [ "$status" -eq 0 ]
  [[ "$output" != *"constante entera"* && "$output" != *"invalid arithmetic"* ]]
  [[ "$output" == *"PASS: planning state consistente"* ]]
}

set_plan_filter() {
  jq "$1" "$FIXTURE/docs/propuestas/planning-state.json" > "$FIXTURE/state.tmp"
  mv "$FIXTURE/state.tmp" "$FIXTURE/docs/propuestas/planning-state.json"
}

@test "edge: validate rejects an empty session plan" {
  set_session_plan
  set_plan_filter '.route.session_plan = []'
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"cola de sesiones inválida"* ]]
}

@test "edge: render_sessions omits the queue when the plan has zero sessions" {
  set_session_plan
  set_plan_filter '.route.session_plan = []'
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" current
  [ "$status" -eq 0 ]
  [[ "$output" != *"Cola de sesiones"* ]]
  [[ "$output" == *"Iniciativas aprobadas o en curso"* ]]
}

@test "edge: validate rejects duplicate session IDs at the boundary of two entries" {
  set_session_plan
  set_plan_filter '.route.session_plan += [.route.session_plan[0]]'
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"cola de sesiones inválida"* ]]
}

@test "edge: validate rejects an empty criterion string and a null priority" {
  set_session_plan
  set_plan_filter '.route.session_plan[0].effort = ""'
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  set_plan_filter '.route.session_plan[0].effort = "small" | .route.session_plan[0].priority = null'
  run env REPO_ROOT="$FIXTURE" bash "$SCRIPT" validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"cola de sesiones inválida"* ]]
}

@test "edge: planning_pr_merged finds a merge at the tip of a large history under pipefail" {
  # Regresión S02 (2026-09-30): grep -q cortaba la tubería y git log moría por SIGPIPE (141).
  local parent tree i
  tree=$(git -C "$FIXTURE" rev-parse 'HEAD^{tree}')
  parent=$(git -C "$FIXTURE" rev-parse HEAD)
  for i in $(seq 1 250); do
    parent=$(git -C "$FIXTURE" commit-tree "$tree" -p "$parent" -m "chore: relleno $i con texto largo para llenar la tubería de git log")
  done
  parent=$(git -C "$FIXTURE" commit-tree "$tree" -p "$parent" -m 'feat: graduada (#1188)')
  git -C "$FIXTURE" update-ref refs/remotes/origin/main "$parent"
  run bash -c 'set -uo pipefail; . scripts/lib/planning-completion.sh; for n in 1 2 3 4 5; do planning_pr_merged "$1" origin/main 1188 || exit 1; done' _ "$FIXTURE"
  [ "$status" -eq 0 ]
  run bash -c 'set -uo pipefail; . scripts/lib/planning-completion.sh; planning_pr_merged "$1" origin/main 9999' _ "$FIXTURE"
  [ "$status" -eq 1 ]
}
