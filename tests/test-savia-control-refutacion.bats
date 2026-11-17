#!/usr/bin/env bats
# SE-498 F0 — correcciones tras la refutación independiente de #1593 (P1-2, P1-3, P1-4, P2-5, P2-6)
# y los P2 de las revisoras de corrección y seguridad. Cada test falla sin su arreglo.

load fixtures/savia-control/setup

setup() { setup_control; }

ledger() { printf '%s\n' "$@" > "$SAVIA_EFFECT_LEDGER"; }

# ── P1-2: GIT_DIR y compañía no redirigen la marca ──────────────────────────

@test "P1-2: GIT_DIR/GIT_WORK_TREE ajenos no esquivan la marca de revocación" {
  sc revoke --reason x
  run sc check --executor a; [ "$status" -eq 6 ]
  git init -q "$T/ajeno"
  GIT_DIR="$T/ajeno/.git" GIT_WORK_TREE="$T/ajeno" SAVIA_CONTROL_DIR="$T/vacio" run sc check --executor a
  echo "$output"
  [ "$status" -ne 0 ]
  GIT_DIR="$T/ajeno/.git" GIT_WORK_TREE="$T/ajeno" run sc check --executor a
  [ "$status" -eq 6 ]; [[ "$output" == *REVOKED* ]]
}

@test "P1-2: GIT_CONFIG_COUNT con core.worktree tampoco redirige" {
  sc revoke --reason x
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.worktree GIT_CONFIG_VALUE_0="$T" run sc check --executor a
  [ "$status" -eq 6 ]
}

@test "P1-2 (negativo): sin variables de Git, el repositorio se resuelve igual que antes" {
  run sc check --executor a; [ "$status" -eq 0 ]; [[ "$output" == *RUNNING* ]]
}

# ── P1-3: un ledger desaparecido no borra los inciertos ─────────────────────

@test "P1-3: un ledger que desaparece no borra los inciertos ya reconocidos" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
  : > "$SAVIA_EFFECT_LEDGER"
  run sc reconcile; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]; [[ "$output" == *e1* ]]
  operator_setup; approve executor:a 0 1 '[]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *ACCEPT_MISMATCH* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "P1-3: con el fichero del ledger ausente (no vacío) pasa lo mismo" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  run sc reconcile; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

@test "P1-3 (negativo): sin inciertos previos, un ledger ausente sigue siendo vacío" {
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 0 ]
}

@test "P1-3 (negativo): un efecto que el ledger ya trae resuelto no bloquea el reconcile" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}' '{"effect_id":"e1","state":"SUCCEEDED","receipt":"r","executor":"a"}'
  run sc reconcile; [ "$status" -eq 0 ]; [[ "$output" == *"CONFIRMED e1"* ]]
}

# ── P1-4: un registro incompleto no hace desaparecer el efecto ──────────────

@test "P1-4: un registro posterior incompleto no hace desaparecer el efecto" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}' '{"effect_id":"e1","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1 [executor:a]"* ]]
}

@test "P1-4: un efecto sin atribución cuenta en todos los ámbitos parados (fail-closed)" {
  ledger '{"effect_id":"huerfano","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE huerfano"* ]]
}

@test "P1-4 (negativo): un efecto de otro ejecutor no entra en el ámbito parado" {
  ledger '{"effect_id":"e2","state":"DISPATCHED","executor":"b"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 0 ]; [[ "$output" != *e2* ]]
}

# ── P2-5: reconcile en instalación nueva ────────────────────────────────────

@test "P2-5: reconcile en una instalación nueva no provoca LOST_STATE" {
  run sc check --executor a; [ "$status" -eq 0 ]
  run sc reconcile; [ "$status" -eq 0 ]
  run sc check --executor a; [ "$status" -eq 0 ]; [[ "$output" == *RUNNING* ]]
}

# ── P2-6: registro de adaptadores ilegible ──────────────────────────────────

@test "P2-6: con executors.json ilegible, revoke persiste la parada y avisa con exit 2" {
  mkdir -p "$SAVIA_CONTROL_DIR"; printf '{' > "$SAVIA_CONTROL_DIR/executors.json"
  run sc revoke --reason x; echo "$output"
  [ "$status" -eq 2 ]; [[ "$output" == *REGISTRY_UNREADABLE* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
  run sc epoch; [ "${lines[0]}" = 1 ]
}

@test "P2-6 (negativo): con executors.json legible, revoke sale 0" {
  register a
  run sc revoke --reason x; [ "$status" -eq 0 ]
}

# ── P2 de las revisoras ─────────────────────────────────────────────────────

@test "seguridad P2-3: check no emite secuencias de control del motivo" {
  sc pause --scope executor:a --reason $'x\e[31mrojo\rfalso'
  run sc check --executor a; [ "$status" -eq 6 ]
  [[ "$output" != *$'\e'* ]]; [[ "$output" != *$'\r'* ]]
}

@test "correctness P2-1: la época de origin con dos saltos de línea finales es ilegible, con uno es válida" {
  origin_put config/control/REVOCATION_EPOCH $'5\n\n'
  run sc check --executor a; [ "$status" -eq 2 ]; [[ "$output" == *ORIGIN_EPOCH_UNREADABLE* ]]
  origin_put config/control/REVOCATION_EPOCH $'5\n'
  run sc epoch; [ "$status" -eq 0 ]; [ "${lines[0]}" = 5 ]
}

@test "correctness P2-2: una salida no UTF-8 de un adaptador no da traceback" {
  mkdir -p "$T/adapters"
  printf '#!/usr/bin/env bash\nprintf "\\xff\\xfe{"\n' > "$T/adapters/bad"; chmod +x "$T/adapters/bad"
  mkdir -p "$SAVIA_CONTROL_DIR"; printf '{"bad":{"adapter":"%s"}}' "$T/adapters/bad" > "$SAVIA_CONTROL_DIR/executors.json"
  run sc revoke --reason x; echo "$output"
  [[ "$output" != *Traceback* ]]; [ "$status" -eq 0 ]; [[ "$output" == *SIN_ACUSE* ]]
}

@test "correctness P2-3: un renombrado desde config/control/ cuenta con su nombre antiguo para el tier" {
  operator_setup; sc pause --scope executor:a --reason x; sc reconcile
  approve executor:a 0 1
  gh_api "repos_owner_repo_pulls_${APPROVAL_PR}_files" "[{\"filename\":\"docs/x.md\",\"previous_filename\":\"config/control/operator.json\"}]"
  run sc resume --scope executor:a --via-pr; echo "$output"
  [ "$status" -eq 0 ]
}

@test "correctness P2-3 (negativo): el mismo renombrado a un nombre inocuo no sale tier 4" {
  operator_setup; sc pause --scope executor:a --reason x; sc reconcile
  approve executor:a 0 1
  gh_api "repos_owner_repo_pulls_${APPROVAL_PR}_files" "[{\"filename\":\"docs/x.md\",\"previous_filename\":\"docs/y.md\"}]"
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 4 ]; [[ "$output" == *TIER_NOT_4* ]]
}
