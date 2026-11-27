#!/usr/bin/env bats
# tests/test-vaults-cli-containment.bats — barrido Python (pendientes, 2026-11-27)
# projects/savia-vaults/scripts/vaults: el nombre de cúpula es un nombre, nunca
# una ruta (contención con realpath bajo VAULT_ROOT), y los datos del usuario
# (id, url, token, username, permission...) van a Python por argv, nunca dentro
# del código de python3 -c.
# Ref: docs/evidence/barridos/20261127-barrido-python.md (fila 21)

VAULTS="projects/savia-vaults/scripts/vaults"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  T="$(mktemp -d)"
  export SAVIA_VAULT_ROOT="$T/root/vaults"
  export HOME="$T/home"
  mkdir -p "$SAVIA_VAULT_ROOT" "$HOME" "$T/root/victim"
  echo keep > "$T/root/victim/keep.txt"
  export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
  : > "$GIT_CONFIG_GLOBAL"
  bash "$VAULTS" dome create d1 >/dev/null 2>&1
}

teardown() {
  [[ -n "${T:-}" && -d "$T" ]] && rm -rf "$T"
}

@test "dome delete con ../ no borra fuera de VAULT_ROOT" {
  run bash "$VAULTS" dome delete ../victim --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid dome name"* ]]
  [ -f "$T/root/victim/keep.txt" ]
}

@test "dome delete rechaza una cúpula enlazada fuera de VAULT_ROOT" {
  ln -s "$T/root/victim" "$SAVIA_VAULT_ROOT/evil"
  run bash "$VAULTS" dome delete evil --force
  [ "$status" -ne 0 ]
  [[ "$output" == *"outside"* ]]
  [ -f "$T/root/victim/keep.txt" ]
}

@test "--dome con ../ se rechaza en user, confidentiality y search" {
  run bash "$VAULTS" user list --dome ../victim
  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid dome name"* ]]
  run bash "$VAULTS" confidentiality set N1 --dome ../victim
  [ "$status" -ne 0 ]
  [ ! -e "$T/root/victim/.savia-vault" ]
  run bash "$VAULTS" dome search hola --dome ../victim
  [ "$status" -ne 0 ]
}

@test "dome rename no mueve a ni desde fuera de VAULT_ROOT" {
  run bash "$VAULTS" dome rename d1 ../fuera
  [ "$status" -ne 0 ]
  [ -d "$SAVIA_VAULT_ROOT/d1" ]
  [ ! -e "$T/root/fuera" ]
}

@test "federate add: id con comillas no ejecuta código y queda literal en el JSON" {
  local id="x'+str(__import__('pathlib').Path('$T/pwn-fed').touch())+'"
  run bash "$VAULTS" dome federate add "$id" "http://u.example" --token "t'k" --weight 2
  [ ! -e "$T/pwn-fed" ]
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1]))["federation"]["domes"]; assert d[0]["id"]==sys.argv[2] and d[0]["authToken"]=="t'"'"'k" and d[0]["weight"]==2.0, d' \
    "$SAVIA_VAULT_ROOT/d1/savia-vaults.config.json" "$id"
  [ "$status" -eq 0 ]
}

@test "federate add: weight no numérico se rechaza sin ejecutar código" {
  run bash "$VAULTS" dome federate add ok "http://u.example" --weight "__import__('pathlib').Path('$T/pwn-w').touch()"
  [ "$status" -ne 0 ]
  [ ! -e "$T/pwn-w" ]
}

@test "federate remove: id con comillas no ejecuta código" {
  run bash "$VAULTS" dome federate remove "x'+str(__import__('pathlib').Path('$T/pwn-rm').touch())+'"
  [ ! -e "$T/pwn-rm" ]
}

@test "user add/perm/remove: username y permiso con comillas no ejecutan código" {
  local u="u'+str(__import__('pathlib').Path('$T/pwn-user').touch())+'"
  run bash -c "printf 'password123\n' | bash '$VAULTS' user add \"\$1\" --dome d1" _ "$u"
  [ ! -e "$T/pwn-user" ]
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; assert sys.argv[2] in json.load(open(sys.argv[1]))' \
    "$SAVIA_VAULT_ROOT/d1/.savia-vault/users.json" "$u"
  [ "$status" -eq 0 ]
  run bash "$VAULTS" user perm "$u" "p'+str(__import__('pathlib').Path('$T/pwn-perm').touch())+'" true --dome d1
  [ ! -e "$T/pwn-perm" ]
  [ "$status" -eq 0 ]
  run bash "$VAULTS" user remove "$u" --dome d1
  [ ! -e "$T/pwn-user" ]
  run python3 -c 'import json,sys; assert sys.argv[2] not in json.load(open(sys.argv[1]))' \
    "$SAVIA_VAULT_ROOT/d1/.savia-vault/users.json" "$u"
  [ "$status" -eq 0 ]
}

@test "camino feliz: cúpula válida, usuario y federación normales" {
  run bash "$VAULTS" dome federate add peer "http://peer.example"
  [ "$status" -eq 0 ]
  run bash "$VAULTS" dome federate list
  [[ "$output" == *"peer"* ]]
  run bash -c "printf 'password123\n' | bash '$VAULTS' user add ana --dome d1"
  [ "$status" -eq 0 ]
  run bash "$VAULTS" user list --dome d1
  [[ "$output" == *"ana"* ]]
  run bash "$VAULTS" confidentiality set N2 --dome d1
  [ "$status" -eq 0 ]
  run bash "$VAULTS" confidentiality list
  [[ "$output" == *"N2"* ]]
  run bash "$VAULTS" dome delete d1 --force
  [ "$status" -eq 0 ]
  [ ! -e "$SAVIA_VAULT_ROOT/d1" ]
}
