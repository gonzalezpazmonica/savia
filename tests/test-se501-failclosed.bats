#!/usr/bin/env bats
# Ref: docs/specs/SE-501-derivados-fuera-de-las-pr.spec.md — seguimientos declarados en la PR #1472.
# 1. El gate de derivados de la CI no usa nunca el de la propia PR (sin respaldo de arranque).
# 2. EXCLUDE_PATHS del escáner de confidencialidad: rutas exactas, no subcadenas.
# 3. risk-tier.py lee scripts/derived-paths.txt de la base, no del checkout de la PR.
# (4. push-pr.sh --merge con --pr-base: tests/test-push-pr.bats.)

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  T="$BATS_TEST_TMPDIR"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
}

G() { git -C "$R" -c commit.gpgsign=false "$@"; }

# ── 1. Respaldo de arranque retirado (ci.yml, «Derived paths absent») ────────────────────────────

# step_run <yaml> <nombre del paso> → el script `run` del paso, leído del YAML parseado.
step_run() {
  python3 - "$1" "$2" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for job in (doc.get("jobs") or {}).values():
    for st in job.get("steps") or []:
        if st.get("name") == sys.argv[2]:
            print(st["run"]); sys.exit(0)
sys.exit(3)
PY
}

# with_fallback <script> — variante que reintroduce el respaldo de arranque retirado (el `else` de #1472).
with_fallback() {
  python3 - "$1" <<'PY'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
old = ('else\n  echo "::warning::la base aún no tiene derived.sh gate (PR de arranque): se usa el de la PR"\n'
       '  bash scripts/derived.sh gate --range "$BASE_SHA..HEAD"\nfi')
out, n = re.subn(r"(?s)else\n.*?\nfi", lambda _: old, s, count=1)
assert n == 1, "sin rama else"
print(out)
PY
}

# gate_repo <base-con-gate:0|1> — repo con un commit base y uno de PR. La PR trae su propio derived.sh
# (espía que anota «pr-gate» y sale 0). Si la base trae el gate, es otro espía que anota «base-gate».
gate_repo() {
  R="$T/g"; rm -rf "$R"; mkdir -p "$R/scripts"; git init -q -b main "$R"
  echo base > "$R/a.txt"
  if [[ "$1" == 1 ]]; then
    printf '#!/usr/bin/env bash\ncase "$1" in\n  gate) echo base-gate >> "$SPY" ;;\nesac\n' > "$R/scripts/derived.sh"
    echo '.scm/sam.json' > "$R/scripts/derived-paths.txt"
  fi
  G add -A; G commit -qm base; BASE=$(G rev-parse HEAD)
  printf '#!/usr/bin/env bash\necho pr-gate >> "$SPY"\nexit 0\n' > "$R/scripts/derived.sh"
  echo '' > "$R/scripts/derived-paths.txt"
  G add -A; G commit -qm pr
  export SPY="$T/spy"; : > "$SPY"
}

# run_step <script> — como lo ejecuta GitHub Actions (bash -eo pipefail) desde el checkout.
run_step() { run bash -c 'cd "$1" && BASE_SHA="$2" bash --noprofile --norc -eo pipefail "$3"' _ "$R" "$BASE" "$1"; }

@test "fail-closed ci.yml: base sin derived.sh gate → el paso falla con mensaje claro y nunca ejecuta el gate de la PR" {
  step_run "$REPO/.github/workflows/ci.yml" "Derived paths absent" > "$T/step.sh"
  gate_repo 0
  run_step "$T/step.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"*"no hay gate de confianza"* ]]
  [ ! -s "$SPY" ]                              # el derived.sh de la PR no se ejecutó
}

@test "fail-closed ci.yml: con el gate en la base se ejecuta el de la base, no el de la PR" {
  step_run "$REPO/.github/workflows/ci.yml" "Derived paths absent" > "$T/step.sh"
  gate_repo 1
  run_step "$T/step.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$SPY")" = base-gate ]
}

@test "fail-closed ci.yml negativo: una variante que reintroduce el respaldo de arranque no pasa la comprobación" {
  step_run "$REPO/.github/workflows/ci.yml" "Derived paths absent" > "$T/step.sh"
  with_fallback "$T/step.sh" > "$T/variante.sh"
  grep -q 'se usa el de la PR' "$T/variante.sh"
  gate_repo 0
  run_step "$T/variante.sh"
  # La variante da verde y ejecuta el gate de la PR: exactamente lo que el primer test prohíbe.
  [ "$status" -eq 0 ]
  [ "$(cat "$SPY")" = pr-gate ]
}

# gate_from_checkout <yaml> — exit 1 si algún paso invoca «gate» con un derived.sh que no sea la copia de la
# base ("$X/scripts/derived.sh"): cualquier forma de ruta (bash/sh/./, $PWD) o una variable intermedia.
# ensure/verify no son el gate. Revisión de #1488 (P2-2): antes solo detectaba «bash scripts/derived.sh gate».
gate_from_checkout() {
  python3 - "$1" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
for job in doc["jobs"].values():
    for st in job.get("steps") or []:
        for line in str(st.get("run", "")).splitlines():
            toks = line.replace(";", " ; ").split()
            for i, tok in enumerate(toks[1:], 1):
                prev = toks[i - 1]
                if tok == "gate" and ("derived" in prev or "$" in prev) and prev != '"$X/scripts/derived.sh"':
                    print("gate fuera de la base:", st.get("name"), "→", line.strip()); sys.exit(1)
print("ok")
PY
}

@test "fail-closed ci.yml: ningún paso del YAML parseado ejecuta scripts/derived.sh del checkout" {
  run gate_from_checkout "$REPO/.github/workflows/ci.yml"
  [ "$status" -eq 0 ]
  [ "$output" = ok ]
}

@test "fail-closed ci.yml negativo: otras formas de ejecutar el gate del checkout se detectan" {
  local v
  for v in 'bash scripts/derived.sh gate --range "$BASE_SHA..HEAD"' \
           './scripts/derived.sh gate' 'sh scripts/derived.sh gate' \
           'bash "$PWD/scripts/derived.sh" gate' 'D=scripts/derived.sh; bash "$D" gate'; do
    V="$v" python3 - "$REPO/.github/workflows/ci.yml" > "$T/ci-variante.yml" <<'PY'
import os, sys, yaml
doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
job = next(iter(doc["jobs"].values()))
job["steps"].append({"name": "variante", "run": os.environ["V"] + "\n"})
print(yaml.safe_dump(doc, allow_unicode=True))
PY
    run gate_from_checkout "$T/ci-variante.yml"
    [ "$status" -eq 1 ] || { echo "no detectada: $v"; return 1; }
    [[ "$output" == *"gate fuera de la base: variante"* ]]
  done
}

# ── 2. EXCLUDE_PATHS: rutas exactas ─────────────────────────────────────────────────────────────

scan_repo() {
  R="$T/s"; rm -rf "$R"; mkdir -p "$R/scripts" "$R/.claude/hooks/lib"
  cp "$REPO/scripts/confidentiality-scan.sh" "$R/scripts/"
  cp "$REPO/.claude/hooks/lib/gate-result.sh" "$R/.claude/hooks/lib/"
  printf '#!/usr/bin/env bash\necho termino-vetado-xyz\n' > "$R/scripts/generate-blocklist.sh"
  git init -q -b main "$R"; G add -A; G commit -qm base
}

# staged_scan <ruta> — escanea (--staged) un único fichero nuevo con el término vetado.
staged_scan() {
  G reset -q; mkdir -p "$R/$(dirname "$1")"
  printf 'linea con termino-vetado-xyz\n' > "$R/$1"; G add -f -- "$1"
  run bash "$R/scripts/confidentiality-scan.sh" --staged
  rm -f "$R/$1"
}

@test "EXCLUDE_PATHS: un fichero cuyo nombre contiene una ruta excluida se escanea (findings)" {
  scan_repo
  local p
  for p in docs/x-tests/n.md sub/tests/n.md docs/notas-confidentiality-scan.sh.md \
           scripts/test-algo.sh docs/pentesting/n.md mi-pii-sanitization.md \
           docs/rules/domain/pii-sanitization.md.bak; do
    staged_scan "$p"
    [ "$status" -eq 1 ] || { echo "no escaneado: $p"; false; }
    [[ "$output" == *'"result":"findings"'* ]]
  done
}

@test "EXCLUDE_PATHS negativo: las rutas exactas y los directorios anclados en la raíz siguen excluidos" {
  scan_repo
  local p
  for p in tests/n.md tests/sub/n.md docs/rules/domain/pii-sanitization.md .claude/skills/pentesting/x.md; do
    staged_scan "$p"
    [ "$status" -eq 0 ] || { echo "no excluido: $p"; false; }
    [[ "$output" == *'"result":"clean"'* ]]
  done
}

@test "EXCLUDE_PATHS: una línea «+++ b/tests/…» dentro de un hunk no salta el resto del fichero" {
  scan_repo
  printf '++ b/tests/x\nlinea con termino-vetado-xyz\n' > "$R/docs-a.md"; G add docs-a.md
  run bash "$R/scripts/confidentiality-scan.sh" --staged
  [ "$status" -eq 1 ]
  [[ "$output" == *'"result":"findings"'* ]]
}

@test "EXCLUDE_PATHS --full-repo: ruta con subcadena excluida se escanea; la exacta no" {
  scan_repo
  mkdir -p "$R/tests"; printf 'termino-vetado-xyz\n' > "$R/tests/n.md"; G add -A; G commit -qm t
  run bash "$R/scripts/confidentiality-scan.sh" --full-repo
  [ "$status" -eq 0 ]
  mkdir -p "$R/docs/x-tests"; printf 'termino-vetado-xyz\n' > "$R/docs/x-tests/n.md"; G add -A; G commit -qm x
  run bash "$R/scripts/confidentiality-scan.sh" --full-repo
  [ "$status" -eq 1 ]
}

@test "EXCLUDE_PATHS: una entrada con comodines es un error de configuración (exit 2), no un escaneo parcial" {
  scan_repo
  sed -i 's|^  tests/$|  tests/*|' "$R/scripts/confidentiality-scan.sh"
  grep -q '^  tests/\*$' "$R/scripts/confidentiality-scan.sh"
  run bash "$R/scripts/confidentiality-scan.sh" --staged
  [ "$status" -eq 2 ]
  [[ "$output" == *"EXCLUDE_PATHS no válida"* ]]
}

# ── 3. risk-tier.py lee derived-paths.txt de la base ────────────────────────────────────────────

rt_repo() {
  R="$T/rt"; rm -rf "$R"; mkdir -p "$R/scripts"; git init -q -b main "$R"
  cp "$REPO/scripts/risk-tier.py" "$R/scripts/"
  printf '.scm/sam.json\n.scm/views/\n' > "$R/scripts/derived-paths.txt"
  G add -A; G commit -qm base; G update-ref refs/remotes/origin/main HEAD
  # La PR se añade a sí misma a la lista (en su commit y en el checkout).
  G checkout -q -b agent/pr
  printf '.scm/sam.json\n.scm/views/\n.scm/llave-auth.json\n' > "$R/scripts/derived-paths.txt"
  G add -A; G commit -qm "pr: se añade a D"
}
tier() { python3 "$R/scripts/risk-tier.py" --diff "$1" --json "${@:2}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tier"])'; }

@test "risk-tier: una PR que añade su propia ruta a derived-paths.txt sigue clasificada por la lista de la base" {
  rt_repo
  # La ruta añadida por la PR no está en la lista de la base: «auth» la sube a tier 3.
  [ "$(tier .scm/llave-auth.json)" = 3 ]
  # Control: lo que la base sí declara D sigue exento (views/authority.json no sube por «auth»).
  [ "$(tier .scm/views/authority.json)" = 2 ]
}

@test "risk-tier: --base elige la base; una base ilegible o con «-» no exime nada (fail-closed)" {
  rt_repo
  [ "$(tier .scm/llave-auth.json --base agent/pr)" = 2 ]     # control: con la lista de la PR sí la eximiría
  [ "$(tier .scm/views/authority.json --base no-existe)" = 3 ]
  [ "$(tier .scm/views/authority.json --base=--output=/tmp/x)" = 3 ]
  G update-ref -d refs/remotes/origin/main
  [ "$(tier .scm/views/authority.json)" = 3 ]
}
