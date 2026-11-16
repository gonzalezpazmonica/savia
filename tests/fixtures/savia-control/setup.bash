# Banco común de los tests de SE-498 (savia-control.py). Cada test tiene su repo temporal
# con una copia del script, un remoto origin desnudo, SAVIA_CONTROL_DIR propio y un gh simulado.
SRC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

setup_control() {
  T="$BATS_TEST_TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  ORIGIN="$T/origin.git"; R="$T/repo"
  git init -q --bare -b main "$ORIGIN"
  git init -q -b main "$R"
  mkdir -p "$R/scripts"
  cp "$SRC_ROOT/scripts/savia-control.py" "$SRC_ROOT/scripts/risk-tier.py" "$R/scripts/"
  if [[ -f "$SRC_ROOT/scripts/derived-paths.txt" ]]; then cp "$SRC_ROOT/scripts/derived-paths.txt" "$R/scripts/"; fi
  git -C "$R" add -A && git -C "$R" commit -qm init
  git -C "$R" remote add origin "$ORIGIN"
  git -C "$R" push -q origin main
  git -C "$R" fetch -q origin
  export HOME="$T/home"; mkdir -p "$HOME"
  export SAVIA_CONTROL_DIR="$T/control"
  export SAVIA_EFFECT_LEDGER="$T/ledger.jsonl"
  export MERGE_SPRINT_HOME="$T/ms"
  export GH_STUB_DIR="$T/gh"; mkdir -p "$GH_STUB_DIR/api" "$T/bin"
  cp "$SRC_ROOT/tests/fixtures/savia-control/gh-stub.py" "$T/bin/gh"; chmod +x "$T/bin/gh"
  export PATH="$T/bin:$PATH"
  unset SAVIA_ACTOR AUTONOMOUS_REVIEWER
}

sc() { python3 -I "$R/scripts/savia-control.py" "$@"; }

# origin_put <ruta> <contenido>: commit en main del remoto y fetch (contenido tal cual, sin \n añadido).
origin_put() {
  mkdir -p "$(dirname "$R/$1")"; printf '%s' "$2" > "$R/$1"
  git -C "$R" add -f -- "$1" && git -C "$R" commit -qm "put $1" && git -C "$R" push -q origin main && git -C "$R" fetch -q origin
}

state_sha() { sha256sum "$SAVIA_CONTROL_DIR/state.json" 2>/dev/null | cut -d' ' -f1; }

# gh_api <ruta con / cambiadas por _ y sin llaves> <json>
gh_api() { printf '%s' "$2" > "$GH_STUB_DIR/api/$1.json"; }

# Adaptador de prueba: registra llamadas en $T/adapter-<n>.log y guarda su estado nativo en $T/native-<n>.
# Con $T/sticky-<n> presente no puede levantar su STOP nativo (como Soul) y deja pending_manual.
make_adapter() {
  local name="$1" a="$T/adapters/$1"
  mkdir -p "$T/adapters"
  cat > "$a" <<ADP
#!/usr/bin/env bash
echo "\$*" >> "$T/adapter-$name.log"
case "\$1" in
  halt) echo STOPPED > "$T/native-$name" ;;
  resume) [[ -f "$T/sticky-$name" ]] || echo RUNNING > "$T/native-$name" ;;
esac
st=\$(cat "$T/native-$name" 2>/dev/null || echo RUNNING)
pm=null; [[ -f "$T/sticky-$name" ]] && pm='"$name resume"'
printf '{"native_state":"%s","pending_manual":%s}\n' "\$st" "\$pm"
ADP
  chmod +x "$a"
}

register() {  # register a b c → executors.json con adaptadores de prueba
  local json="{" sep="" n
  for n in "$@"; do make_adapter "$n"; json+="$sep\"$n\":{\"adapter\":\"$T/adapters/$n\"}"; sep=","; done
  mkdir -p "$SAVIA_CONTROL_DIR"; printf '%s}' "$json" > "$SAVIA_CONTROL_DIR/executors.json"
}
