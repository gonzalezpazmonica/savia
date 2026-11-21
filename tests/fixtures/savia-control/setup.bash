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

# Aprobación de resume por PR (R6.1) con su rastro en el gh simulado.
# operator_setup: operator.json en origin/main y regla de PR activa en main.
operator_setup() {
  origin_put config/control/operator.json '{"login":"operadora"}'
  gh_api repos_owner_repo_rules_branches_main '[{"type":"pull_request"}]'
}

# approve <ámbito> <época> <stop_seq> [accept-json] [login-de-quien-fusiona] [ámbito-en-el-contenido]
APPROVAL_N=500
approve() {
  local scope="$1" h path sha n
  h=$(printf '%s' "$scope" | sha256sum | cut -c1-16)
  path="config/control/resume/$2-$3-$h.json"
  origin_put "$path" "{\"epoch\":$2,\"stop_seq\":$3,\"scope\":\"${6:-$scope}\",\"reason\":\"ok\",\"accept\":${4:-[]}}"
  sha=$(git -C "$R" rev-parse HEAD); APPROVAL_N=$((APPROVAL_N + 1)); n=$APPROVAL_N
  gh_api "repos_owner_repo_commits_${sha}_pulls" "[{\"number\":$n,\"merged_at\":\"2026-11-16T00:00:00Z\"}]"
  gh_api "repos_owner_repo_pulls_$n" "{\"number\":$n,\"merged_by\":{\"login\":\"${5:-operadora}\"}}"
  APPROVAL_PATH="$path"; APPROVAL_PR="$n"; APPROVAL_BLOB=$(git -C "$R" rev-parse "HEAD:$path")
  gh_api "repos_owner_repo_pulls_${n}_files" "[{\"filename\":\"$path\",\"sha\":\"$APPROVAL_BLOB\"}]"
}

# jget <fichero json> <expresión python sobre d>
jget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2]))' "$1" "$2"; }
