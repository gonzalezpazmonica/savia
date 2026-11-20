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
  [ "$status" -eq 2 ]; [[ "$output" == *CONTROL_DIR_MISMATCH* ]]
  GIT_DIR="$T/ajeno/.git" GIT_WORK_TREE="$T/ajeno" run sc check --executor a
  [ "$status" -eq 6 ]; [[ "$output" == *REVOKED* ]]
}

@test "P1-2: GIT_COMMON_DIR ajeno tampoco redirige la marca" {
  sc revoke --reason x
  git init -q "$T/ajeno"
  GIT_COMMON_DIR="$T/ajeno/.git" SAVIA_CONTROL_DIR="$T/vacio" run sc check --executor a
  echo "$output"
  [ "$status" -eq 2 ]; [[ "$output" == *CONTROL_DIR_MISMATCH* ]]
}

@test "P1-2: GIT_CONFIG_COUNT/KEY/VALUE no llegan a los git del script" {
  # remote.origin.url apuntando a un remoto ajeno: si la variable llegase a git, el push iría allí
  git init -q --bare -b main "$T/ajeno.git"
  sc revoke --reason x
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=remote.origin.url GIT_CONFIG_VALUE_0="$T/ajeno.git" run sc publish-epoch
  echo "$output"; [ "$status" -eq 0 ]
  git -C "$ORIGIN" rev-parse -q --verify refs/heads/agent/control-epoch-1
  run git -C "$T/ajeno.git" rev-parse -q --verify refs/heads/agent/control-epoch-1
  [ "$status" -ne 0 ]
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

# ── P2 de la revisión de seguridad y corrección sobre 9b59a736b ─────────────

@test "security P2-2: un ámbito con salto de línea final no es válido" {
  run sc pause --scope $'executor:foo\n' --reason x; echo "$output"
  [ "$status" -eq 2 ]; [[ "$output" == *SCOPE_INVALID* ]]
  run sc check --executor a; [ "$status" -eq 0 ]
}

@test "security P2-2 (negativo): el mismo ámbito sin salto de línea sí vale" {
  run sc pause --scope executor:foo --reason x; [ "$status" -eq 0 ]
  run sc check --executor foo; [ "$status" -eq 6 ]
}

@test "security P2-2: un login de operadora con salto de línea final es OPERATOR_UNKNOWN" {
  origin_put config/control/operator.json '{"login":"operadora\n"}'
  gh_api repos_owner_repo_rules_branches_main '[{"type":"pull_request"}]'
  sc pause --scope executor:a --reason x; sc reconcile
  approve executor:a 0 1
  run sc resume --scope executor:a --via-pr; echo "$output"
  [ "$status" -eq 4 ]; [[ "$output" == *OPERATOR_UNKNOWN* ]]
}

@test "security P2-3: publish-epoch no cierra ni da por suya una PR de época desde un fork" {
  sc revoke --reason a; sc revoke --reason b
  origin_put config/control/REVOCATION_EPOCH 1
  echo '[{"number":7,"headRefName":"agent/control-epoch-1","url":"u7","isCrossRepository":true},
         {"number":8,"headRefName":"agent/control-epoch-2","url":"u8","isCrossRepository":true}]' > "$GH_STUB_DIR/prs.json"
  run sc publish-epoch; echo "$output"; [ "$status" -eq 0 ]
  run grep -c '^pr close' "$GH_STUB_DIR/calls.log"; [ "$output" = 0 ]
  [ "$(cat "$GH_STUB_DIR/created")" = 1 ]
  [ "$(git -C "$ORIGIN" show agent/control-epoch-2:config/control/REVOCATION_EPOCH)" = 2 ]
}

@test "security P2-3 (negativo): la PR propia de la misma rama sí cuenta como ALREADY_OPEN" {
  sc revoke --reason a
  echo '[{"number":9,"headRefName":"agent/control-epoch-1","url":"u9","isCrossRepository":false}]' > "$GH_STUB_DIR/prs.json"
  run sc publish-epoch; [ "$status" -eq 0 ]; [[ "$output" == *ALREADY_OPEN* ]]
  [ ! -e "$GH_STUB_DIR/created" ]
}

@test "security P2-5: una aprobación con epoch true o stop_seq 1.0 es APPROVAL_INVALID" {
  operator_setup
  sc revoke --reason r; sc reconcile
  S=$(jget "$SAVIA_CONTROL_DIR/state.json" 'd["stops"]["global"]["stop_seq"]')
  P="config/control/resume/1-$S-$(printf global | sha256sum | cut -c1-16).json"
  origin_put "$P" "{\"epoch\":true,\"stop_seq\":$S,\"scope\":\"global\",\"reason\":\"ok\",\"accept\":[]}"
  run sc resume --via-pr; echo "$output"; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_INVALID* ]]
  origin_put "$P" "{\"epoch\":1,\"stop_seq\":$S.0,\"scope\":\"global\",\"reason\":\"ok\",\"accept\":[]}"
  run sc resume --via-pr; echo "$output"; [ "$status" -eq 4 ]; [[ "$output" == *APPROVAL_INVALID* ]]
}

@test "correctness P2-1: un incierto que un reconcile posterior resolvió no bloquea si el ledger desaparece" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  ledger '{"effect_id":"e1","state":"SUCCEEDED","receipt":"r1","executor":"a"}'
  run sc reconcile; [ "$status" -eq 0 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]
}

@test "correctness P2-1 (negativo): si el último reconcile lo dejó incierto, sigue bloqueando" {
  ledger '{"effect_id":"e1","state":"SUCCEEDED","receipt":"r1","executor":"a"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 0 ]
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  run sc reconcile; [ "$status" -eq 5 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  run sc reconcile; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

# ── revisiones sobre 382d87ab8 ──────────────────────────────────────────────

marker() { echo "$(git -C "$R" rev-parse --absolute-git-dir)/savia-control/installed"; }
seq_of() { jget "$SAVIA_CONTROL_DIR/state.json" "d['stops']['$1']['stop_seq']"; }

@test "security P2-3: GH_REPO y GH_HOST no llegan a los gh de resume --via-pr" {
  operator_setup
  sc pause --scope executor:a --reason x; sc reconcile --scope executor:a
  approve executor:a 0 "$(seq_of executor:a)"
  GH_REPO=atacante/repo GH_HOST=evil.invalid run sc resume --scope executor:a --via-pr
  echo "$output"; [ "$status" -eq 0 ]
  grep -q '^api ' "$GH_STUB_DIR/calls.log"            # gh se llamó de verdad
  run grep -c '^ENV GH_' "$GH_STUB_DIR/calls.log"; [ "$output" = 0 ]
}

@test "security P2-4: SAVIA_EFFECT_LEDGER queda fijado en la marca; otro valor sale 2 y sin variable se usa el fijado" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc pause --scope executor:a --reason x
  SAVIA_EFFECT_LEDGER="$T/otro.jsonl" run sc reconcile
  echo "$output"; [ "$status" -eq 2 ]; [[ "$output" == *PATH_MISMATCH* ]]
  unset SAVIA_EFFECT_LEDGER
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
}

@test "security P2-4: MERGE_SPRINT_HOME queda fijado; redirigirlo no salta MERGED_BY_SPRINT" {
  operator_setup
  sc pause --scope executor:a --reason x; sc reconcile --scope executor:a
  approve executor:a 0 "$(seq_of executor:a)"
  mkdir -p "$MERGE_SPRINT_HOME"; echo "{\"event\":\"MERGED\",\"pr\":\"$APPROVAL_PR\"}" > "$MERGE_SPRINT_HOME/ledger.jsonl"
  MERGE_SPRINT_HOME="$T/vacio" run sc resume --scope executor:a --via-pr
  echo "$output"; [ "$status" -eq 2 ]; [[ "$output" == *PATH_MISMATCH* ]]
  unset MERGE_SPRINT_HOME
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 4 ]; [[ "$output" == *MERGED_BY_SPRINT* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "security P2-4 (negativo): una marca sin rutas fijadas adopta las del entorno y las fija" {
  sc pause --scope executor:a --reason x
  python3 -c 'import json,sys; p=sys.argv[1]; m=json.load(open(p)); m.pop("effect_ledger"); m.pop("merge_sprint_home"); json.dump(m, open(p,"w"))' "$(marker)"
  export SAVIA_EFFECT_LEDGER="$T/nuevo.jsonl"
  ledger '{"effect_id":"e2","state":"DISPATCHED","executor":"a"}'
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e2"* ]]
  [ "$(jget "$(marker)" 'd["effect_ledger"]')" = "$(realpath "$T/nuevo.jsonl")" ]
}

@test "correctness P2: un reconcile por ámbito que resuelve un incierto del global lo descarga también del global" {
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  sc revoke --reason r; sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  ledger '{"effect_id":"e1","state":"SUCCEEDED","receipt":"r1","executor":"a"}'
  run sc reconcile --scope executor:a; [ "$status" -eq 0 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]
}

@test "correctness P2 (negativo): si un reconcile posterior al que lo resolvió lo vuelve a dejar incierto, bloquea" {
  ledger '{"effect_id":"e1","state":"SUCCEEDED","receipt":"r1","executor":"a"}'
  sc revoke --reason r; sc pause --scope executor:a --reason x
  run sc reconcile --scope executor:a; [ "$status" -eq 0 ]
  ledger '{"effect_id":"e1","state":"DISPATCHED","executor":"a"}'
  run sc reconcile; [ "$status" -eq 5 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  run sc reconcile; echo "$output"; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

# ── refutación sobre fbb5eb6c5 (Codex P1-2, P1-3, P1-4) ─────────────────────

@test "refutación P1-2: renovar la parada no descarga un incierto si luego desaparece el ledger" {
  ledger '{"effect_id":"e1","executor":"a","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason inicial
  run sc reconcile; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  sc pause --scope executor:a --reason renovacion
  run sc reconcile; echo "$output"; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]; [[ "$output" == *e1* ]]
  operator_setup; approve executor:a 0 "$(seq_of executor:a)" '[]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *RECONCILE_REQUIRED* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "refutación P1-2: la pérdida bloquea también el reconcile de otro ámbito (sin registro no se sabe de quién era)" {
  ledger '{"effect_id":"e1","executor":"a","principal":"p","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  sc pause --scope principal:p --reason y
  run sc reconcile --scope principal:p; echo "$output"; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

@test "refutación P1-2 (negativo): un incierto aceptado en un resume deja de contar aunque desaparezca del ledger" {
  ledger '{"effect_id":"e1","executor":"a","state":"DISPATCHED"}'
  operator_setup
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  approve executor:a 0 "$(seq_of executor:a)" '["e1"]'
  run sc resume --scope executor:a --via-pr; echo "$output"; [ "$status" -eq 0 ]
  mv "$SAVIA_EFFECT_LEDGER" "$T/ledger.guardado"
  sc pause --scope executor:a --reason otra
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]
}

@test "refutación P1-3: un ejecutor null posterior no saca el efecto del ámbito" {
  ledger '{"effect_id":"e1","executor":"a","principal":"p","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 5 ]
  ledger '{"effect_id":"e1","executor":"a","principal":"p","state":"DISPATCHED"}' '{"effect_id":"e1","executor":null}'
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1 [executor:a]"* ]]
}

@test "refutación P1-3: un ejecutor con tipo malformado cuenta en todos los ámbitos (fail-closed)" {
  ledger '{"effect_id":"e1","executor":"b","principal":"p","state":"DISPATCHED"}' '{"effect_id":"e1","executor":7}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
}

@test "refutación P1-3: un cambio de ejecutor no saca el efecto del ámbito del ejecutor anterior" {
  ledger '{"effect_id":"e1","executor":"a","state":"DISPATCHED"}' '{"effect_id":"e1","executor":"b"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1 [executor:a]"* ]]
}

@test "refutación P1-3 (negativo): un efecto bien atribuido a otro ejecutor sigue fuera del ámbito" {
  ledger '{"effect_id":"e1","executor":"b","principal":"p","state":"DISPATCHED"}' '{"effect_id":"e1","executor":null}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]; [[ "$output" != *e1* ]]
}

@test "refutación P1-4: la sonda del intento 0 no prueba la ausencia del intento 1" {
  ledger '{"effect_id":"e1","executor":"a","attempt":0,"state":"FAILED","probe":{"result":"ABSENT","definitive":true}}' \
         '{"effect_id":"e1","attempt":1,"state":"DISPATCHED"}' '{"effect_id":"e1","attempt":1,"state":"FAILED"}'
  sc pause --scope executor:a --reason revision
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
  operator_setup; approve executor:a 0 "$(seq_of executor:a)" '[]'
  run sc resume --scope executor:a --via-pr; [ "$status" -eq 5 ]; [[ "$output" == *ACCEPT_MISMATCH* ]]
  run sc check --executor a; [ "$status" -eq 6 ]
}

@test "refutación P1-4: un registro tardío del intento 0 no sustituye el estado del intento 1" {
  ledger '{"effect_id":"e1","executor":"a","attempt":1,"state":"DISPATCHED"}' \
         '{"effect_id":"e1","attempt":0,"state":"FAILED","probe":{"result":"ABSENT","definitive":true}}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 5 ]; [[ "$output" == *"INDETERMINATE e1"* ]]
}

@test "refutación P1-4 (negativo): con sonda definitiva del mismo intento 1 sí es REJECTED" {
  ledger '{"effect_id":"e1","executor":"a","attempt":0,"state":"FAILED","probe":{"result":"ABSENT","definitive":true}}' \
         '{"effect_id":"e1","attempt":1,"state":"DISPATCHED"}' \
         '{"effect_id":"e1","attempt":1,"state":"FAILED","probe":{"result":"ABSENT","definitive":true}}'
  sc pause --scope executor:a --reason x
  run sc reconcile; echo "$output"; [ "$status" -eq 0 ]; [[ "$output" == *"REJECTED e1"* ]]
}

@test "refutación P1-4: un attempt que no es entero natural hace el ledger ilegible" {
  ledger '{"effect_id":"e1","executor":"a","attempt":"1","state":"DISPATCHED"}'
  sc pause --scope executor:a --reason x
  run sc reconcile; [ "$status" -eq 2 ]; [[ "$output" == *LEDGER_UNREADABLE* ]]
}

@test "security P2-2: GIT_CONFIG_GLOBAL y GIT_CONFIG_SYSTEM se descartan al arrancar" {
  GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_SYSTEM="$T/gitconfig" run python3 -I -c '
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("sc", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(sorted(k for k in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM") if k in os.environ))' "$R/scripts/savia-control.py"
  echo "$output"; [ "$output" = "[]" ]
}
