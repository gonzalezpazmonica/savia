#!/usr/bin/env bats
# SE-376 — savia-hub-sync: init y sync de SaviaHub contra repos git sintéticos
# (bare remotes locales en mktemp). Nunca toca ~/.savia, el hub real ni la red.
# Ref: .claude/skills/savia-hub-sync/SKILL.md · docs/rules/domain/savia-hub-config.md · docs/rules/domain/savia-hub-offline.md
# Funciones cubiertas: init: die, ensure_local_excludes, seed_structure, write_config
#                      sync: die, set_cfg, has_remote, in_flight, net_fetch, remote_branch, require_remote
set -uo pipefail

SCRIPT="scripts/savia-hub-init.sh"
SYNC="scripts/savia-hub-sync.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMP="$(mktemp -d)"
  export HOME="$TMP/home"; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$TMP/gitconfig"
  # defaultBranch=master a propósito: la skill documenta la rama main.
  printf '[user]\n\tname = t\n\temail = t@example.com\n[init]\n\tdefaultBranch = master\n' > "$GIT_CONFIG_GLOBAL"
  unset SAVIA_HUB_REMOTE
  export SAVIA_HUB_PATH="$TMP/my hub"   # ruta con espacios
  REMOTE="$TMP/remote.git"
  INIT="$REPO_ROOT/$SCRIPT"; SY="$REPO_ROOT/$SYNC"
}

teardown() { rm -rf "$TMP"; }

bare() { git init -q --bare -b main "$REMOTE"; }
# refute <cmd>: falla el test si la orden tiene éxito (un «!» intermedio no lo hace en bats).
refute() { if "$@"; then echo "refute: $*"; return 1; fi; }
seeded_remote() {  # remote con contenido y sin .gitignore
  git init -q -b main "$TMP/seed"; echo x > "$TMP/seed/a.md"; commit_in "$TMP/seed" s
  bare; git -C "$TMP/seed" push -q "$REMOTE" main
}
cached_has_config() { git -C "$SAVIA_HUB_PATH" diff --cached --name-only | grep -q savia-hub-config; }
remote_has_config() { remote_files | grep -q savia-hub-config; }
hub_with_remote() { bare; bash "$INIT" --remote "$REMOTE" >/dev/null 2>&1; }
other_clone() { SAVIA_HUB_PATH="$TMP/other hub" bash "$INIT" --remote "$REMOTE" >/dev/null 2>&1; }
remote_files() { git --git-dir="$REMOTE" ls-tree -r --name-only HEAD 2>/dev/null; }
commit_in() { (cd "$1" && git add -A && git commit -qm "$2"); }

@test "safety: init y sync declaran pipefail estricto" {
  grep -qE '^set -e?uo pipefail' "$REPO_ROOT/$SCRIPT"
  grep -qE '^set -uo pipefail' "$REPO_ROOT/$SYNC"
}

# Sustituye a scripts/test-savia-hub.sh (grep de presencia, retirado por el ratchet SE-380).
@test "docs boundary: comando, reglas y skill ≤150 líneas y cada subcomando del sync está documentado" {
  local f n sub
  for f in .claude/commands/savia-hub.md .claude/skills/savia-hub-sync/SKILL.md \
           docs/rules/domain/savia-hub-config.md docs/rules/domain/savia-hub-offline.md; do
    n=$(wc -l < "$REPO_ROOT/$f"); [ "$n" -le 150 ] || { echo "$f: $n líneas > 150"; return 1; }
  done
  # Sin -q: con pipefail, grep -q cierra la tubería al primer acierto y cat muere por SIGPIPE
  # según el reparto de tiempos (fallaba solo en CI con «Broken pipe»).
  for sub in status push pull "flight on" "flight off"; do
    cat "$REPO_ROOT/.claude/commands/savia-hub.md" "$REPO_ROOT/.claude/skills/savia-hub-sync/SKILL.md" \
        "$REPO_ROOT/docs/rules/domain/savia-hub-offline.md" | grep -F "savia-hub-sync.sh $sub" >/dev/null \
      || { echo "subcomando sin documentar: $sub"; return 1; }
    grep -qE "^${sub%% *}\)" "$REPO_ROOT/$SYNC" || { echo "documentado pero no implementado: $sub"; return 1; }
  done
  grep -qF '.savia-hub-config.md' "$REPO_ROOT/docs/rules/domain/savia-hub-config.md"
  grep -qF '.sync-queue.jsonl' "$REPO_ROOT/docs/rules/domain/savia-hub-offline.md"
}

@test "init local: estructura, commit inicial en main y árbol limpio en ruta con espacios" {
  run bash "$INIT"
  [ "$status" -eq 0 ]
  [ -f "$SAVIA_HUB_PATH/company/identity.md" ] && [ -f "$SAVIA_HUB_PATH/clients/.index.md" ] && [ -d "$SAVIA_HUB_PATH/users" ]
  [ "$(git -C "$SAVIA_HUB_PATH" branch --show-current)" = "main" ]
  [ -z "$(git -C "$SAVIA_HUB_PATH" status --porcelain)" ]
}

@test "init default: sin SAVIA_HUB_PATH crea el hub en HOME/.savia-hub (HOME temporal)" {
  unset SAVIA_HUB_PATH
  run bash "$INIT"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.savia-hub/.git" ]
}

@test "init idempotente: segunda ejecución no crea commits ni reescribe la config" {
  bash "$INIT" >/dev/null
  before="$(git -C "$SAVIA_HUB_PATH" rev-parse HEAD)"; cfg="$(cat "$SAVIA_HUB_PATH/.savia-hub-config.md")"
  run bash "$INIT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ya existe"* ]]
  [ "$(git -C "$SAVIA_HUB_PATH" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$SAVIA_HUB_PATH/.savia-hub-config.md")" = "$cfg" ]
}

@test "init incompleto (.git sin commits): lo completa en vez de decir que ya existe" {
  mkdir -p "$SAVIA_HUB_PATH" && git -C "$SAVIA_HUB_PATH" init -q
  run bash "$INIT"
  [ "$status" -eq 0 ]
  git -C "$SAVIA_HUB_PATH" rev-parse --verify -q HEAD
  [ -f "$SAVIA_HUB_PATH/company/identity.md" ]
}

@test "init respeta SAVIA_HUB_REMOTE del entorno, como dice --help" {
  bare
  SAVIA_HUB_REMOTE="$REMOTE" run bash "$INIT"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SAVIA_HUB_PATH" remote get-url origin)" = "$REMOTE" ]
}

@test "init --remote vacío: siembra la estructura y la commitea en local sin subir nada" {
  bare
  run bash "$INIT" --remote "$REMOTE"
  [ "$status" -eq 0 ]
  [ -f "$SAVIA_HUB_PATH/company/org-chart.md" ]
  git -C "$SAVIA_HUB_PATH" rev-parse --verify -q HEAD
  [ -z "$(remote_files)" ]
}

@test "init --remote poblado sin .gitignore: la config local nunca entra en git add -A (block fuga)" {
  seeded_remote
  run bash "$INIT" --remote "$REMOTE"
  [ "$status" -eq 0 ]
  [ ! -f "$SAVIA_HUB_PATH/.gitignore" ]   # el clon no trae .gitignore: protege info/exclude
  git -C "$SAVIA_HUB_PATH" add -A
  refute cached_has_config
}

@test "init --remote con HEAD del remote roto (boundary): usa la rama existente, sin historia paralela" {
  git init -q -b main "$TMP/seed"; echo x > "$TMP/seed/a.md"; commit_in "$TMP/seed" s
  git init -q --bare -b master "$REMOTE"; git -C "$TMP/seed" push -q "$REMOTE" main
  run bash "$INIT" --remote "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SAVIA_HUB_PATH" branch --show-current)" = "main" ]
  [ "$(git -C "$SAVIA_HUB_PATH" rev-list --count HEAD)" -eq 1 ]
  [ -f "$SAVIA_HUB_PATH/a.md" ]
}

@test "init interrumpido y relanzado con --remote: configura origin y adopta el contenido remoto" {
  seeded_remote
  mkdir -p "$SAVIA_HUB_PATH" && git -C "$SAVIA_HUB_PATH" init -q
  run bash "$INIT" --remote "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(git -C "$SAVIA_HUB_PATH" remote get-url origin)" = "$REMOTE" ]
  [ -f "$SAVIA_HUB_PATH/a.md" ]
}

@test "push en hub antiguo sin info/exclude ni .gitignore: block, la config nunca sube" {
  seeded_remote
  git clone -q "$REMOTE" "$SAVIA_HUB_PATH"   # clon hecho con el init anterior
  printf -- '---\nremote_url: "%s"\nflight_mode: false\nlast_sync: null\n---\n' "$REMOTE" > "$SAVIA_HUB_PATH/.savia-hub-config.md"
  echo nuevo > "$SAVIA_HUB_PATH/b.md"
  run bash "$SY" push
  [[ "$output" != *"savia-hub-config"* ]]
  run bash "$SY" push --yes
  [ "$status" -eq 0 ]
  remote_files | grep -q '^b.md$'
  refute remote_has_config
}

@test "pull con la config rastreada en el remote (fuga ajena): reject exit 6 sin pisar la config local" {
  seeded_remote
  bash "$INIT" --remote "$REMOTE" >/dev/null 2>&1
  echo LOCAL-CFG >> "$SAVIA_HUB_PATH/.savia-hub-config.md"
  echo ajena > "$TMP/seed/.savia-hub-config.md"; commit_in "$TMP/seed" fuga; git -C "$TMP/seed" push -q "$REMOTE" main
  run bash "$SY" pull
  [ "$status" -eq 6 ]
  grep -q LOCAL-CFG "$SAVIA_HUB_PATH/.savia-hub-config.md"
}

@test "push preview cuenta cada fichero de un directorio nuevo (boundary untracked)" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  mkdir -p "$SAVIA_HUB_PATH/clients/acme"
  for f in profile contacts rules a b; do echo x > "$SAVIA_HUB_PATH/clients/acme/$f.md"; done
  run bash "$SY" push
  [[ "$output" == *"Se van a subir 5 ficheros"* ]]
  [[ "$output" == *"clients/acme/rules.md"* ]]
}

@test "init --remote inalcanzable: error exit 3, mensaje claro y sin directorio a medias" {
  run bash "$INIT" --remote "$TMP/nonexistent.git"
  [ "$status" -eq 3 ]
  [[ "$output" == *"No se pudo clonar"* ]]
  [ ! -e "$SAVIA_HUB_PATH" ]
}

@test "init --remote sin valor (no arg): error de uso exit 1, no variable sin asignar" {
  run bash "$INIT" --remote
  [ "$status" -eq 1 ]
  [[ "$output" == *"requiere un valor"* ]]
}

@test "init con opción desconocida: reject exit 1" {
  run bash "$INIT" --bogus
  [ "$status" -eq 1 ]
}

@test "sync sobre hub inexistente (nonexistent): error exit 2 en status, push y pull" {
  for c in status push pull; do
    run bash "$SY" "$c"
    [ "$status" -eq 2 ]
  done
}

@test "sync con subcomando inválido: error de uso exit 1" {
  bash "$INIT" >/dev/null
  run bash "$SY" frobnicate
  [ "$status" -eq 1 ]
}

@test "status solo-local: lo dice y nunca afirma sincronizado" {
  bash "$INIT" >/dev/null
  run bash "$SY" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"solo local"* ]]
  [[ "$output" != *"sincronizado"* ]]
}

@test "push sin remote: fail exit 3 «Remote no configurado»" {
  bash "$INIT" >/dev/null
  run bash "$SY" push --yes
  [ "$status" -eq 3 ]
  [[ "$output" == *"Remote no configurado"* ]]
}

@test "push sin --yes: vista previa con la lista de ficheros y nada subido" {
  hub_with_remote
  run bash "$SY" push
  [ "$status" -eq 0 ]
  [[ "$output" == *"company/identity.md"* ]] && [[ "$output" == *"nada subido"* ]]
  [ -z "$(remote_files)" ]
}

@test "push --yes: sube, marca last_sync, deja status sincronizado y la config fuera del remote" {
  hub_with_remote
  run bash "$SY" push --yes
  [ "$status" -eq 0 ]
  remote_files | grep -q '^company/identity.md$'
  refute remote_has_config
  refute grep -q '^last_sync: null' "$SAVIA_HUB_PATH/.savia-hub-config.md"
  run bash "$SY" status
  [[ "$output" == *"Sync:"*"sincronizado"* ]]
}

@test "push sin cambios (empty): «Nada que sincronizar» exit 0" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  run bash "$SY" push --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nada que sincronizar"* ]]
}

@test "sin red (remote movido): push falla exit 5 y status dice inalcanzable, no sincronizado" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  mv "$REMOTE" "$TMP/moved.git"
  echo cambio >> "$SAVIA_HUB_PATH/company/identity.md"
  run bash "$SY" push --yes
  [ "$status" -eq 5 ]
  [[ "$output" == *"inalcanzable"* ]]
  run bash "$SY" status
  [[ "$output" == *"inalcanzable"* ]] && [[ "$output" != *"sincronizado"* ]]
}

@test "push con el remote por delante: reject exit 7 y pide pull antes" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  other_clone; echo b >> "$TMP/other hub/company/org-chart.md"
  SAVIA_HUB_PATH="$TMP/other hub" bash "$SY" push --yes >/dev/null
  echo a >> "$SAVIA_HUB_PATH/company/identity.md"
  run bash "$SY" push --yes
  [ "$status" -eq 7 ]
  [[ "$output" == *"pull"* ]]
}

@test "pull con conflicto: fail exit 8, lista el fichero, aborta el rebase y conserva lo local" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  other_clone; echo REMOTO > "$TMP/other hub/company/identity.md"
  SAVIA_HUB_PATH="$TMP/other hub" bash "$SY" push --yes >/dev/null
  echo LOCAL > "$SAVIA_HUB_PATH/company/identity.md"
  run bash "$SY" pull
  [ "$status" -eq 8 ]
  [[ "$output" == *"company/identity.md"* ]]
  [ ! -d "$SAVIA_HUB_PATH/.git/rebase-merge" ] && [ ! -d "$SAVIA_HUB_PATH/.git/rebase-apply" ]
  [ "$(cat "$SAVIA_HUB_PATH/company/identity.md")" = "LOCAL" ]
}

@test "pull sin conflicto con cambios locales sin commit: integra ambos y exit 0" {
  hub_with_remote; bash "$SY" push --yes >/dev/null
  other_clone; echo r > "$TMP/other hub/users/r.md"
  SAVIA_HUB_PATH="$TMP/other hub" bash "$SY" push --yes >/dev/null
  echo l > "$SAVIA_HUB_PATH/users/l.md"
  run bash "$SY" pull
  [ "$status" -eq 0 ]
  [ -f "$SAVIA_HUB_PATH/users/r.md" ] && [ -f "$SAVIA_HUB_PATH/users/l.md" ]
  run bash "$SY" pull
  [[ "$output" == *"Ya actualizado"* ]]
}

@test "flight mode on: push y pull bloqueados exit 4; off no afirma sincronizado" {
  hub_with_remote
  run bash "$SY" flight on
  [ "$status" -eq 0 ]
  grep -q '^flight_mode: true' "$SAVIA_HUB_PATH/.savia-hub-config.md"
  run bash "$SY" push --yes
  [ "$status" -eq 4 ]
  run bash "$SY" pull
  [ "$status" -eq 4 ]
  run bash "$SY" flight off
  [ "$status" -eq 0 ]
  [[ "$output" != *"sincronizado"* ]] || [[ "$output" == *"no se ha sincronizado"* ]]
  grep -q '^flight_mode: false' "$SAVIA_HUB_PATH/.savia-hub-config.md"
}

@test "push block: config local rastreada por git (fuga N4) aborta exit 6 sin subir" {
  hub_with_remote
  git -C "$SAVIA_HUB_PATH" add -f .savia-hub-config.md
  run bash "$SY" push --yes
  [ "$status" -eq 6 ]
  [ -z "$(remote_files)" ]
}

@test "push large: 300 ficheros de cliente suben en un único commit" {
  hub_with_remote
  for i in $(seq 1 300); do mkdir -p "$SAVIA_HUB_PATH/clients/c$i"; echo p > "$SAVIA_HUB_PATH/clients/c$i/profile.md"; done
  run bash "$SY" push --yes
  [ "$status" -eq 0 ]
  [ "$(remote_files | grep -c '^clients/c[0-9]*/profile.md$')" -eq 300 ]
}
