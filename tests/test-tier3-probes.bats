#!/usr/bin/env bats
# SE-376 S03 — tier3-probes: pruebas de comportamiento de scrapling-probe.sh y oumi-probe.sh
# Ref: SE-061, SE-028, docs/propuestas/SE-376-debt-budget.yaml
#
# Los probes deciden VIABLE / NEEDS_INSTALL / BLOCKED a partir de lo que encuentran en
# la máquina. Aquí se ejecutan con un PATH hermético y python3, df, pip3 y navegadores
# simulados, de modo que cada rama del veredicto se ejerce de verdad y no depende del
# equipo donde corre el test. Cada prueba cae si se rompe la regla que dice cubrir.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SCRAPLING="$REPO_ROOT/scripts/scrapling-probe.sh"
  OUMI="$REPO_ROOT/scripts/oumi-probe.sh"
  TMP="$(mktemp -d)"
  BIN="$TMP/bin"
  mkdir -p "$BIN" "$TMP/home"
  for t in cut awk head sed cat tr; do
    ln -s "$(command -v "$t")" "$BIN/$t"
  done
  # python3 simulado: versión y módulos importables salen de variables FAKE_*
  cat > "$BIN/python3" <<'PY'
#!/bin/bash
[[ "$1" == "-c" ]] || exit 0
case "$2" in
  *sys.version_info*) echo "${FAKE_PY_VERSION:-3.12.1}" ;;
  "import scrapling") [[ "${FAKE_SCRAPLING:-1}" == 1 ]] ;;
  "import lxml") [[ "${FAKE_LXML:-1}" == 1 ]] ;;
  "import playwright") [[ "${FAKE_PLAYWRIGHT:-1}" == 1 ]] ;;
  "import oumi") [[ "${FAKE_OUMI:-1}" == 1 ]] ;;
  "import torch") [[ "${FAKE_TORCH:-1}" == 1 ]] ;;
  *) [[ "${FAKE_OTHER:-1}" == 1 ]] ;;
esac
PY
  cat > "$BIN/df" <<'DF'
#!/bin/bash
printf 'Filesystem 1G-blocks Used Available Use%% Mounted\n/dev/x 500G 10G %sG 2%% /\n' "${FAKE_DISK:-50}"
DF
  printf "#!/bin/bash\nexit 0\n" > "$BIN/pip3"
  chmod +x "$BIN/python3" "$BIN/df" "$BIN/pip3"
  export HOME="$TMP/home"
  export FAKE_PY_VERSION=3.12.1 FAKE_SCRAPLING=1 FAKE_LXML=1 FAKE_PLAYWRIGHT=1 FAKE_DISK=50
}

teardown() {
  rm -rf "$TMP"
}

# probe <script> [args…]: ejecuta con el PATH hermético; deja status y output
probe() {
  local s="$1"; shift
  run env PATH="$BIN" "$(command -v bash)" "$s" "$@"
}

jf() { printf '%s' "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

# ── scrapling-probe: veredicto ────────────────────────────────────────────────

@test "scrapling: everything present is VIABLE with exit 0 and no reasons" {
  probe "$SCRAPLING" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "VIABLE" ]
  [ "$(jf "d['reasons']")" = "[]" ]
  [ "$(jf "d['scrapling_installed']")" = "1" ]
}

@test "scrapling: scrapling missing is NEEDS_INSTALL, still exit 0, with the pip hint" {
  FAKE_SCRAPLING=0 probe "$SCRAPLING"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERDICT: NEEDS_INSTALL"* ]]
  [[ "$output" == *"scrapling not installed"* ]]
  [[ "$output" == *"pip install scrapling"* ]]
}

@test "scrapling: lxml missing alone downgrades VIABLE to NEEDS_INSTALL" {
  FAKE_LXML=0 probe "$SCRAPLING" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "NEEDS_INSTALL" ]
  [ "$(jf "d['lxml']")" = "0" ]
  [[ "$(jf "d['reasons'][0]")" == *"lxml not installed"* ]]
}

@test "scrapling: Python 3.9 is BLOCKED with exit 1 and names the version" {
  FAKE_PY_VERSION=3.9.18 probe "$SCRAPLING" --json
  [ "$status" -eq 1 ]
  [ "$(jf "d['verdict']")" = "BLOCKED" ]
  [[ "$(jf "d['reasons'][0]")" == *"3.9.18"* ]]
}

@test "scrapling: Python 3.10.0 is the boundary and is accepted" {
  FAKE_PY_VERSION=3.10.0 probe "$SCRAPLING" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "VIABLE" ]
}

@test "scrapling: Python 2.7 is BLOCKED as not Python 3" {
  FAKE_PY_VERSION=2.7.18 probe "$SCRAPLING" --json
  [ "$status" -eq 1 ]
  [ "$(jf "d['verdict']")" = "BLOCKED" ]
  [[ "$(jf "d['reasons'][0]")" == *"Python 3 not found"* ]]
}

@test "scrapling: no python3 at all is BLOCKED, exit 1, empty version" {
  rm "$BIN/python3"
  probe "$SCRAPLING" --json
  [ "$status" -eq 1 ]
  [ "$(jf "d['verdict']")" = "BLOCKED" ]
  [ "$(jf "d['python_version']")" = "" ]
}

@test "scrapling: a blocked probe does not pile install reasons on top of the blocker" {
  FAKE_PY_VERSION=3.8.0 FAKE_SCRAPLING=0 FAKE_LXML=0 probe "$SCRAPLING" --json
  [ "$status" -eq 1 ]
  [ "$(jf "len(d['reasons'])")" = "1" ]
}

# ── scrapling-probe: disco y navegador ────────────────────────────────────────

@test "scrapling: 1 GB free adds a disk reason but does not change the verdict" {
  FAKE_DISK=1 probe "$SCRAPLING" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "VIABLE" ]
  [ "$(jf "d['disk_free_gb']")" = "1" ]
  [[ "$(jf "d['reasons'][0]")" == *"disk free < 2GB"* ]]
}

@test "scrapling: exactly 2 GB free is enough" {
  FAKE_DISK=2 probe "$SCRAPLING" --json
  [ "$(jf "d['reasons']")" = "[]" ]
}

@test "scrapling: without --check-browser a missing playwright and chromium are not reported" {
  FAKE_PLAYWRIGHT=0 probe "$SCRAPLING" --json
  [ "$(jf "d['reasons']")" = "[]" ]
  [ "$(jf "d['playwright']")" = "0" ]
}

@test "scrapling: --check-browser reports both playwright and chromium as optional gaps" {
  FAKE_PLAYWRIGHT=0 probe "$SCRAPLING" --json --check-browser
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "VIABLE" ]
  [[ "$(jf "'|'.join(d['reasons'])")" == *"playwright not installed"* ]]
  [[ "$(jf "'|'.join(d['reasons'])")" == *"no chromium browser found"* ]]
}

@test "scrapling: any of chromium, chromium-browser or google-chrome satisfies the browser check" {
  for b in chromium chromium-browser google-chrome; do
    printf "#!/bin/bash\nexit 0\n" > "$BIN/$b"; chmod +x "$BIN/$b"
    probe "$SCRAPLING" --json --check-browser
    [ "$(jf "d['chromium']")" = "1" ]
    [ "$(jf "d['reasons']")" = "[]" ]
    rm "$BIN/$b"
  done
}

@test "scrapling: the fetchers install hint only appears with --check-browser and playwright missing" {
  FAKE_SCRAPLING=0 FAKE_PLAYWRIGHT=0 probe "$SCRAPLING"
  [[ "$output" != *"scrapling[fetchers]"* ]]
  FAKE_SCRAPLING=0 FAKE_PLAYWRIGHT=0 probe "$SCRAPLING" --check-browser
  [[ "$output" == *"scrapling[fetchers]"* ]]
}

@test "scrapling: a VIABLE verdict prints no install instructions" {
  probe "$SCRAPLING"
  [[ "$output" == *"VERDICT: VIABLE"* ]]
  [[ "$output" != *"pip install"* ]]
}

# ── scrapling-probe: argumentos ───────────────────────────────────────────────

@test "scrapling: an unknown argument exits 2 with the argument named on stderr" {
  probe "$SCRAPLING" --nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--nope'"* ]]
}

@test "scrapling: --help exits 0 and runs no probe" {
  probe "$SCRAPLING" --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"VERDICT"* ]]
}

# ── oumi-probe: el mismo contrato con umbrales propios ───────────────────────

@test "oumi: Python 3.8 is BLOCKED but 3.9.0 is accepted (its floor is lower)" {
  FAKE_PY_VERSION=3.8.19 probe "$OUMI" --json
  [ "$status" -eq 1 ]
  [ "$(jf "d['verdict']")" = "BLOCKED" ]
  FAKE_PY_VERSION=3.9.0 FAKE_OUMI=1 FAKE_TORCH=1 probe "$OUMI" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" != "BLOCKED" ]
}

@test "oumi: oumi missing is NEEDS_INSTALL and exit 0" {
  FAKE_OUMI=0 probe "$OUMI" --json
  [ "$status" -eq 0 ]
  [ "$(jf "d['verdict']")" = "NEEDS_INSTALL" ]
}

@test "oumi: its disk floor is 10 GB, 9 reports it and 10 does not" {
  FAKE_DISK=9 probe "$OUMI" --json
  [[ "$(jf "'|'.join(d['reasons'])")" == *"disk"* ]]
  FAKE_DISK=10 probe "$OUMI" --json
  [[ "$(jf "'|'.join(d['reasons'])")" != *"disk"* ]]
}

@test "oumi: an unknown argument exits 2" {
  probe "$OUMI" --nope
  [ "$status" -eq 2 ]
}

# ── contrato de seguridad: solo lectura, modo estricto ───────────────────────

@test "probes stay read-only: running them writes nothing and both keep set -uo pipefail" {
  grep -q '^set -uo pipefail' "$SCRAPLING"
  grep -q '^set -uo pipefail' "$OUMI"
  mkdir "$TMP/work"
  cd "$TMP/work"
  probe "$SCRAPLING" --json --check-browser
  probe "$OUMI" --json
  [ -z "$(ls -A "$TMP/work")" ]
  [ -z "$(ls -A "$TMP/home")" ]
}
