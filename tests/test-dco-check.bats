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

# ── Comportamiento: ramas del script con JSON a medida ────────────────────

# jc <sha> <parents> <login> <type> <email> <mensaje> → un commit en $T/c.json
jc() {
  python3 - "$@" > "$T/c.json" <<'PY'
import json, sys
sha, par, login, typ, email, msg = sys.argv[1:7]
print(json.dumps([{"sha": sha, "parents": [{}] * int(par),
  "author": None if login == "null" else {"login": login, "type": typ},
  "commit": {"author": {"email": email}, "message": msg}}]))
PY
}

@test "lista de commits vacía pasa con el mensaje de éxito" {
  echo '[]' > "$T/c.json"; run_dco
  [ "$status" -eq 0 ]
  [[ "$output" == *"DCO: todos los commits llevan Signed-off-by"* ]]
}

@test "el éxito también se escribe en el resumen de la acción" {
  mk -s "feat: a"; json ana User; run_dco
  grep -q "todos los commits llevan Signed-off-by" "$T/summary"
}

@test "commit de merge (dos padres) sin sign-off se salta" {
  jc aaaaaaaaaaaaaaaa 2 ana User ana@example.com "Merge branch x"; run_dco
  [ "$status" -eq 0 ]
}

@test "commit con un padre sin sign-off falla; con cero padres (raíz) también se evalúa" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com "feat: a"; run_dco
  [ "$status" -eq 1 ]
  jc bbbbbbbbbbbbbbbb 0 ana User ana@example.com "feat: raiz"; run_dco
  [ "$status" -eq 1 ]
}

@test "Signed-off-by en minúsculas y con otro caso de correo vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User Ana@Example.COM "feat: a

signed-off-by: Ana <ana@example.com>"; run_dco
  [ "$status" -eq 0 ]
}

@test "espacios y retorno de carro al final de la línea Signed-off-by se toleran" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\r\n\r\nSigned-off-by: Ana <ana@example.com>  \r\n'; run_dco
  [ "$status" -eq 0 ]
}

@test "la línea Signed-off-by puede estar en medio del cuerpo" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nSigned-off-by: Ana <ana@example.com>\n\nCo-authored-by: X <x@y.z>'; run_dco
  [ "$status" -eq 0 ]
}

@test "un correo que solo termina igual (prefijo extra) no vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nSigned-off-by: Otra <otraana@example.com>'; run_dco
  [ "$status" -eq 1 ]
}

@test "una línea que menciona Signed-off-by sin empezar por ella no vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nNo Signed-off-by: Ana <ana@example.com>'; run_dco
  [ "$status" -eq 1 ]
}

@test "correo del sign-off sin ángulos no vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nSigned-off-by: Ana ana@example.com'; run_dco
  [ "$status" -eq 1 ]
}

@test "varios commits: uno malo hace fallar y solo se nombra el malo" {
  mk -s "feat: bueno"; mk "" "feat: malo"; mk -s "feat: bueno2"; json ana User; run_dco
  [ "$status" -eq 1 ]
  malo=$(git -C "$T/r" log --format='%H %s' | grep 'malo' | cut -c1-12)
  [[ "$output" == *"$malo"* ]]
  [ "$(echo "$output" | grep -c 'Sin Signed-off-by coincidente')" -eq 1 ]
}

@test "varios commits malos se nombran todos" {
  mk "" "feat: m1"; mk "" "feat: m2"; json ana User; run_dco
  [ "$status" -eq 1 ]
  [ "$(echo "$output" | grep -c 'Sin Signed-off-by coincidente')" -eq 2 ]
}

@test "el fallo explica cómo arreglarlo y lo vuelca al resumen" {
  mk "" "feat: a"; json ana User; run_dco
  [[ "$output" == *"git commit --amend -s --no-edit"* ]]
  [[ "$output" == *"git rebase --signoff origin/main"* ]]
  [[ "$output" == *"--force-with-lease"* ]]
  grep -q "Sin Signed-off-by coincidente" "$T/summary"
  [[ "$output" == *"(ana@example.com)"* ]]
}

@test "tipo Bot pasa aunque el login no termine en [bot]" {
  jc aaaaaaaaaaaaaaaa 1 mi-bot Bot x@y.z "feat: auto"; run_dco
  [ "$status" -eq 0 ]
}

@test "login que termina en [bot] pasa aunque el tipo sea User" {
  jc aaaaaaaaaaaaaaaa 1 "renovate[bot]" User x@y.z "feat: auto"; run_dco
  [ "$status" -eq 0 ]
}

@test "BOT_LOGINS admite varios y solo exime a los listados" {
  jc aaaaaaaaaaaaaaaa 1 robot2 User x@y.z "feat: auto"
  BOT_LOGINS="robot1 robot2" run_dco
  [ "$status" -eq 0 ]
  BOT_LOGINS="robot1 robot3" run_dco
  [ "$status" -eq 1 ]
  BOT_LOGINS="" run_dco
  [ "$status" -eq 1 ]
}

@test "BOT_LOGINS compara el login completo, no un prefijo" {
  jc aaaaaaaaaaaaaaaa 1 robot2x User x@y.z "feat: auto"
  BOT_LOGINS="robot2" run_dco
  [ "$status" -eq 1 ]
}

@test "mantenedor: comparación sin distinguir mayúsculas y varios mantenedores" {
  mk "" "feat: agente"; json owner2 User
  PR_AUTHOR=OWNER2 MAINTAINERS="owner owner2" HEAD_REF=agent/x run_dco
  [ "$status" -eq 0 ]
  [[ "$output" == *"exento, PR de rama agent/* abierto por OWNER2 (mantenedor)"* ]]
}

@test "la exención se escribe también en el resumen" {
  mk "" "feat: agente"; json owner User
  PR_AUTHOR=owner HEAD_REF=agent/x run_dco
  grep -q "exento" "$T/summary"
}

@test "sin MAINTAINERS nadie queda exento" {
  mk "" "feat: agente"; json owner User
  PR_AUTHOR=owner MAINTAINERS="" HEAD_REF=agent/x run_dco
  [ "$status" -eq 1 ]
}

@test "exención solo con prefijo agent/ exacto (no 'xagent/')" {
  mk "" "feat: agente"; json owner User
  PR_AUTHOR=owner HEAD_REF=xagent/x run_dco
  [ "$status" -eq 1 ]
}

@test "mantenedor parcial: 'own' no exime a 'owner'" {
  mk "" "feat: agente"; json owner User
  PR_AUTHOR=owner MAINTAINERS="own" HEAD_REF=agent/x run_dco
  [ "$status" -eq 1 ]
}

@test "Signed-off-by sin espacio tras los dos puntos no vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nSigned-off-by:Ana <ana@example.com>'; run_dco
  [ "$status" -eq 1 ]
}

@test "texto después del correo en la línea Signed-off-by no vale" {
  jc aaaaaaaaaaaaaaaa 1 ana User ana@example.com $'feat: a\n\nSigned-off-by: Ana <ana@example.com> y otros'; run_dco
  [ "$status" -eq 1 ]
}
