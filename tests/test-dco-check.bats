#!/usr/bin/env bats
# SE-451 AC1-AC4: el script embebido en dco-check.yml se extrae y se prueba.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WF="$REPO_ROOT/.github/workflows/dco-check.yml"
  T="$(mktemp -d "${BATS_TMPDIR:-$REPO_ROOT/.tmp-bats}/dco.XXXXXX")"
  sed -n '/DCO-SCRIPT-BEGIN/,/DCO-SCRIPT-END/p' "$WF" | sed 's/^          //' > "$T/dco.sh"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  unset GIT_DIR GIT_WORK_TREE
  git init -q "$T/r"
  export GITHUB_STEP_SUMMARY="$T/summary"
  export PR_AUTHOR=ana HEAD_REF=feature/x MAINTAINERS=owner BOT_LOGINS="dependabot[bot]"
}

teardown() { rm -rf "$T"; }

# mk "<flags>" "<mensaje>" [correo]
mk() {
  local email="${3:-ana@example.com}"
  git -C "$T/r" -c user.name=Ana -c user.email="$email" commit -q --allow-empty $1 -m "$2"
}

# json <login> <type>: volcado del log al formato de la API de pulls/commits
json() {
  git -C "$T/r" log --reverse --format='%H%x09%P%x09%ae%x09%B%x1e' | python3 -c '
import sys, json
out = []
for rec in sys.stdin.read().split("\x1e"):
    rec = rec.strip("\n")
    if not rec:
        continue
    sha, par, ae, msg = rec.split("\t", 3)
    out.append({"sha": sha, "parents": [{}] * len(par.split()),
                "author": None if sys.argv[1] == "null" else {"login": sys.argv[1], "type": sys.argv[2]},
                "commit": {"author": {"email": ae}, "message": msg}})
print(json.dumps(out))' "$1" "$2" > "$T/c.json"
}

run_dco() { run bash "$T/dco.sh" "$T/c.json"; }

@test "commit con -s pasa" {
  mk -s "feat: a"; json ana User; run_dco
  [ "$status" -eq 0 ]
}

@test "commit sin -s falla y nombra el SHA" {
  mk "" "feat: a"; json ana User; run_dco
  [ "$status" -eq 1 ]
  sha="$(git -C "$T/r" rev-parse HEAD)"
  [[ "$output" == *"${sha:0:12}"* ]]
  [[ "$output" == *"--amend -s"* ]]
}

@test "sign-off de otra persona no vale" {
  mk "" "x

Signed-off-by: Beto <beto@example.com>"; json ana User; run_dco
  [ "$status" -eq 1 ]
}

@test "commit de bot sin sign-off pasa" {
  mk "" "chore: bump" "49699333+dependabot[bot]@users.noreply.github.com"; json "dependabot[bot]" Bot; run_dco
  [ "$status" -eq 0 ]
}

@test "login de la lista de bots sin type Bot pasa" {
  mk "" "chore: bump"; json "dependabot[bot]" User; run_dco
  [ "$status" -eq 0 ]
}

@test "PR agent/* del mantenedor sin sign-off pasa" {
  mk "" "feat: agente"; json owner User
  PR_AUTHOR=owner HEAD_REF=agent/se451-x run_dco
  [ "$status" -eq 0 ]
  [[ "$output" == *"exento"* ]]
}

@test "PR agent/* de persona ajena no esta exento" {
  mk "" "feat: agente"; json ana User
  HEAD_REF=agent/se451-x run_dco
  [ "$status" -eq 1 ]
}

@test "PR del mantenedor en rama no agent/* no esta exento" {
  mk "" "feat: humano"; json owner User
  PR_AUTHOR=owner HEAD_REF=feature/x run_dco
  [ "$status" -eq 1 ]
}

@test "correo con metacaracteres se compara literal" {
  mk -s "feat: plus" "ana+x@example.com"; json ana User; run_dco
  [ "$status" -eq 0 ]
}

@test "AC3: pull_request, contents read, sin checkout ni pull_request_target" {
  grep -q '^  pull_request:' "$WF"
  grep -q 'contents: read' "$WF"
  run grep -E 'actions/checkout|pull_request_target' "$WF"
  [ "$status" -ne 0 ]
}

@test "AC4: todo uses: fijado a SHA de 40 hex" {
  run bash -c "grep -E '^[[:space:]-]*uses:' '$WF' | grep -vE '@[0-9a-f]{40}'"
  [ "$status" -ne 0 ]
}

@test "AC1: CONTRIBUTING documenta el DCO" {
  [ "$(grep -c 'Signed-off-by' "$REPO_ROOT/CONTRIBUTING.md")" -ge 1 ]
  grep -q 'Developer Certificate of Origin' "$REPO_ROOT/CONTRIBUTING.md"
}

@test "autor sin cuenta de GitHub vinculada y con -s pasa (author null no desplaza campos)" {
  mk -s "feat: a"; json null ""; run_dco
  [ "$status" -eq 0 ]
}

@test "autor sin cuenta de GitHub vinculada y sin -s falla" {
  mk "" "feat: a"; json null ""; run_dco
  [ "$status" -ne 0 ]
}
