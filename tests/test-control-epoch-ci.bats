#!/usr/bin/env bats
# SE-498 F0 (AC-8) — comportamiento del check de CI de época monótona y salvaguardas de su workflow.
# Ejecuta tests/test-control-epoch-monotonic.bats contra repos de prueba con diffs buenos y malos.

SRC_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CHECK="$SRC_ROOT/tests/test-control-epoch-monotonic.bats"
WF="$SRC_ROOT/.github/workflows/control-epoch.yml"
F=config/control/REVOCATION_EPOCH

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  G="$BATS_TEST_TMPDIR/g"
  git init -q -b main "$G"
  mkdir -p "$G/tests"; cp "$CHECK" "$G/tests/"
  echo x > "$G/README"; git -C "$G" add -A; git -C "$G" commit -qm base
}

main_epoch() { mkdir -p "$G/config/control"; printf '%s' "$1" > "$G/$F"; git -C "$G" add -A; git -C "$G" commit -qm "main $1"; }
branch() { git -C "$G" checkout -q -b pr; }
commit_pr() { git -C "$G" add -A; git -C "$G" commit -qm pr; git -C "$G" checkout -q main; }
set_pr() { branch; mkdir -p "$G/config/control"; printf '%s' "$1" > "$G/$F"; commit_pr; }

verdict() {  # verdict [fichero-de-test] → status del check sobre main..pr
  CONTROL_EPOCH_REPO="$G" CONTROL_EPOCH_BASE=main CONTROL_EPOCH_HEAD=pr run bats "${1:-$CHECK}"
  echo "$output"
}

@test "CI época: falla si la PR la baja, la deja no entera o la sube más de 1" {
  main_epoch $'3\n'
  # cada valor malo con la causa que debe dar: un fallo por otra razón (base ilegible…) no vale
  NI="no es un entero de 1-9 cifras"
  for case in $'2\n|no a 2' "x|$NI" $'3; rm\n|'"$NI" $'5\n|no a 5' $'999999999\n|no a 999999999' \
              $'1234567890\n|'"$NI" " 4|$NI"; do
    bad="${case%%|*}"; why="${case#*|}"
    if git -C "$G" rev-parse -q --verify pr >/dev/null; then git -C "$G" branch -q -D pr; fi
    set_pr "$bad"; verdict; [ "$status" -ne 0 ]; [[ "$output" == *"FALLO: "*"$why"* ]]
  done
}

@test "CI época: pasa con exactamente main + 1, y con una PR que no la toca" {
  main_epoch $'3\n'
  set_pr $'4\n'; verdict; [ "$status" -eq 0 ]
  git -C "$G" branch -q -D pr; branch; echo y >> "$G/README"; commit_pr
  verdict; [ "$status" -eq 0 ]
}

@test "CI época: fichero ausente en main vale 0; la PR solo puede crearlo con 1" {
  set_pr $'1\n'; verdict; [ "$status" -eq 0 ]
  git -C "$G" branch -q -D pr; set_pr $'2\n'; verdict; [ "$status" -ne 0 ]; [[ "$output" == *"main está en 0"*"no a 2"* ]]
}

@test "CI época: una PR que no la toca pero parte de un main anterior no falla" {
  main_epoch $'3\n'
  branch; echo y >> "$G/README"; commit_pr
  main_epoch $'4\n'
  verdict; [ "$status" -eq 0 ]
}

@test "CI época: con el fichero en main, falla si la PR lo borra, renombra, cambia a symlink o a ejecutable" {
  main_epoch $'3\n'
  branch; git -C "$G" rm -q "$F"; commit_pr; verdict; [ "$status" -ne 0 ]; [[ "$output" == *"FALLO: la PR borra o renombra"* ]]
  git -C "$G" branch -q -D pr; branch; git -C "$G" mv "$F" "$G/config/control/EPOCH"; commit_pr; verdict; [ "$status" -ne 0 ]
  [[ "$output" == *"FALLO: la PR borra o renombra"* ]]
  git -C "$G" branch -q -D pr; branch; rm "$G/$F"; ln -s /tmp/4 "$G/$F"; commit_pr; verdict; [ "$status" -ne 0 ]
  [[ "$output" == *"FALLO: $F debe ser un fichero regular 100644 (120000 blob)"* ]]
  git -C "$G" branch -q -D pr; branch; printf '4\n' > "$G/$F"; chmod +x "$G/$F"; commit_pr; verdict; [ "$status" -ne 0 ]
  [[ "$output" == *"FALLO: $F debe ser un fichero regular 100644 (100755 blob)"* ]]
}

@test "CI época: una PR que sube de 3 a 5 y reescribe el test sigue fallando con el test de la base" {
  main_epoch $'3\n'
  branch; printf '5\n' > "$G/$F"
  printf '@test "trampa" { true; }\n' > "$G/tests/test-control-epoch-monotonic.bats"; commit_pr
  git -C "$G" show main:tests/test-control-epoch-monotonic.bats > "$BATS_TEST_TMPDIR/base.bats"
  git -C "$G" show pr:tests/test-control-epoch-monotonic.bats > "$BATS_TEST_TMPDIR/head.bats"
  verdict "$BATS_TEST_TMPDIR/base.bats"; [ "$status" -ne 0 ]; [[ "$output" == *"FALLO: main está en 3"*"no a 5"* ]]
  # Mutación: ejecutar el test de la cabeza la deja pasar. Por eso el workflow usa el de la base.
  verdict "$BATS_TEST_TMPDIR/head.bats"; [ "$status" -eq 0 ]
}

# ── salvaguardas del workflow (R2) ──────────────────────────────────────────

wf_safe() {
  python3 -I - "$1" <<'EOF'
import re, sys
# los comentarios no cuentan: una salvaguarda escrita en un comentario no protege nada
text = "\n".join(l for l in open(sys.argv[1]).read().splitlines() if not l.lstrip().startswith("#")) + "\n"
lines = text.splitlines()
errs = []
if not re.search(r"^on:\s*\n\s+pull_request_target:", text, re.M) or re.search(r"^\s+pull_request:", text, re.M):
    errs.append("el disparador debe ser solo pull_request_target (workflow y test de la base)")
m = re.search(r"^permissions:\s*\n((?:[ \t]+.*\n?)*)", text, re.M)
if not m or m.group(1).strip() != "contents: read":
    errs.append("permissions debe ser exactamente contents: read")
if "secrets." in text:
    errs.append("referencia a secrets.")
if text.count("actions/checkout") != text.count("persist-credentials: false"):
    errs.append("un checkout sin persist-credentials: false")
if re.search(r"^\s*ref:.*head", text, re.M):
    errs.append("checkout de la cabeza")
for l in lines:
    s = l.strip()
    if re.search(r"(^|[\s;&|])(source|\.)\s+\S", s) and not s.startswith("#"):
        errs.append(f"source: {s}")
    if "pr/head" in s and not (s.startswith("run: git -C base fetch") or s.startswith("CONTROL_EPOCH_HEAD:")):
        errs.append(f"uso de la cabeza fuera de fetch/env: {s}")
    if re.search(r"\bbats\s", s) and not re.search(r"\bbats\s+base/", s) and "bats-core" not in s and "/tmp/bats" not in s:
        errs.append(f"bats fuera de la base: {s}")
for e in errs:
    print(e)
sys.exit(1 if errs else 0)
EOF
}

@test "workflow: el de F0 cumple las salvaguardas" {
  run wf_safe "$WF"; echo "$output"; [ "$status" -eq 0 ]
}

@test "workflow: cada mutación de una salvaguarda hace fallar el test estático" {
  m="$BATS_TEST_TMPDIR/m.yml"
  # la mutación se aplica sobre el workflow sin comentarios, para tocar la línea efectiva
  mut() { python3 -I -c 'import sys; t="\n".join(l for l in open(sys.argv[1]).read().splitlines() if not l.lstrip().startswith("#")); assert sys.argv[2] in t; open(sys.argv[4],"w").write(t.replace(sys.argv[2],sys.argv[3],1))' "$WF" "$1" "$2" "$m"; }
  cp "$WF" "$m"; run wf_safe "$m"; [ "$status" -eq 0 ]
  mut "pull_request_target:" "pull_request:";                         run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "contents: read" "contents: write";                             run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "timeout-minutes: 10" 'timeout-minutes: 10
    env:
      T: ${{ secrets.GITHUB_TOKEN }}';                                  run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "persist-credentials: false" "persist-credentials: true";       run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "ref: \${{ github.event.pull_request.base.sha }}" "ref: \${{ github.event.pull_request.head.sha }}"
  run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "run: bats base/tests" "run: bats tests";                       run wf_safe "$m"; [ "$status" -ne 0 ]
  mut "sudo /tmp/bats/install.sh /usr/local" 'sudo /tmp/bats/install.sh /usr/local
          git -C base show pr/head:scripts/x.sh > x.sh && source x.sh'
  run wf_safe "$m"; [ "$status" -ne 0 ]
}
