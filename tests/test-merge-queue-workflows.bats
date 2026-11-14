#!/usr/bin/env bats
# Ref: docs/specs/SE-433-merge-sprint.spec.md · docs/rules/domain/autonomous-safety-merge-sprint.md
# Cola de fusión de GitHub (merge queue): los workflows que producen los checks obligatorios de main tienen que
# dispararse con merge_group, sus jobs obligatorios no pueden saltarse en la cola y ningún paso que corra en la
# cola puede leer datos que solo existen en una PR (github.event.pull_request, github.base_ref, el payload de la PR).
# Los workflows que solo tienen sentido sobre una PR o sobre main no se disparan en la cola.

CI=".github/workflows/ci.yml"
GUARD=".github/workflows/pr-guardian.yml"

# check <yaml> <nombres-de-jobs-obligatorios, separados por |> → audita el workflow; imprime los fallos
check() {
  python3 - "$1" "$2" <<'PY'
import re, sys, yaml
path, required = sys.argv[1], sys.argv[2].split("|")
d = yaml.safe_load(open(path))
on = d.get(True, d.get("on"))
errs = []
mg = on.get("merge_group") if isinstance(on, dict) else None
if not isinstance(mg, dict) or mg.get("types") != ["checks_requested"]:
    errs.append("sin disparador merge_group: types [checks_requested]")
# Datos que en merge_group no existen. Un paso que los lea solo vale si su `if` exige pull_request
# o si ofrece la alternativa de la cola (merge_group.base_sha).
# github.actor, github.sha y github.ref sí existen en merge_group; github.event.number y github.event.action no.
pr_only = re.compile(r"github\.event\.pull_request|github\.event\.number|github\.event\.action|github\.base_ref|"
                     r"github\.head_ref|context\.payload\.pull_request|context\.issue")
pr_gate = re.compile(r"github\.event_name\s*==\s*'pull_request'")
expr = re.compile(r"\$\{\{.*?\}\}", re.S)

def top_level(cond):
    """La condición sin los grupos entre paréntesis: un || dentro de (…) no abre otra vía al nivel superior."""
    prev = None
    while prev != cond:
        prev, cond = cond, re.sub(r"\([^()]*\)", "", cond)
    return cond

def pr_only_if(cond):
    """True si la condición exige pull_request sin alternativa: el == 'pull_request' en el nivel superior,
    unido solo con && (un || en el nivel superior la abriría a otros eventos) y sin mencionar merge_group."""
    t = top_level(cond)
    return bool(pr_gate.search(t)) and "||" not in t and "merge_group" not in cond

def reads_pr(body):
    """Lecturas de datos de la PR que quedan tras quitar las expresiones que ofrecen la base de la cola."""
    rest = expr.sub(lambda m: "" if "merge_group.base_sha" in m.group(0) else m.group(0), body)
    return bool(pr_only.search(rest))

names = set()
for jid, job in d["jobs"].items():
    name = job.get("name", jid); names.add(name)
    jif = str(job.get("if", ""))
    skipped_in_queue = "!= 'merge_group'" in jif or pr_only_if(jif)
    if name in required:
        if skipped_in_queue:
            errs.append(f"job obligatorio «{name}» se salta en merge_group")
    if skipped_in_queue:
        continue
    for st in job.get("steps", []):
        body = yaml.safe_dump({k: v for k, v in st.items() if k not in ("if", "name")}, width=10**6)
        if not reads_pr(body):
            continue
        if pr_only_if(str(st.get("if", ""))):
            continue          # solo corre en pull_request
        errs.append(f"«{name}» / «{st.get('name', '?')}» lee datos de la PR y corre en merge_group")
for r in required:
    if r not in names:
        errs.append(f"falta el job obligatorio «{r}»")
print("\n".join(errs))
sys.exit(1 if errs else 0)
PY
}

@test "ci.yml: merge_group dispara Validate workspace, Lint Markdown y BATS Hook Tests sin leer datos de la PR" {
  run check "$CI" "Validate workspace|Lint Markdown|BATS Hook Tests"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "pr-guardian.yml: merge_group dispara PR Guardian y las puertas de título, cuerpo y ficheros de la PR se saltan" {
  run check "$GUARD" "PR Guardian"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "pr-guardian.yml: las puertas que leen el diff (3, 4, 6, 7) siguen corriendo en la cola" {
  run python3 -c "
import yaml
steps=yaml.safe_load(open('$GUARD'))['jobs']['pr-guardian']['steps']
by={s['name']:s for s in steps}
for g in ['Gate 3: CLAUDE.md Context Guard','Gate 4: ShellCheck on changed scripts','Gate 6: Hook Safety Validator','Gate 7: Context Impact Summary']:
    assert 'pull_request' not in str(by[g].get('if','')), g
"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "negativo: un paso que lee la PR sin if de pull_request y corre en la cola se detecta" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  python3 - "$GUARD" "$f" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for s in d["jobs"]["pr-guardian"]["steps"]:
    if s.get("name") == "Gate 2: Conventional Commits":
        s.pop("if")
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
  run check "$f" "PR Guardian"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Gate 2: Conventional Commits"* ]]
}

@test "negativo: un job obligatorio excluido de merge_group se detecta" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  python3 - "$CI" "$f" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["jobs"]["lint-markdown"]["if"] = "github.event_name != 'merge_group'"
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
  run check "$f" "Validate workspace|Lint Markdown|BATS Hook Tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Lint Markdown"* ]]
}

@test "negativo: sin disparador merge_group el workflow no pasa" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  python3 - "$CI" "$f" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d[True].pop("merge_group")
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
  run check "$f" "Validate workspace|Lint Markdown|BATS Hook Tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sin disparador merge_group"* ]]
}

mutate_step() {  # mutate_step <yaml-origen> <destino> <nombre-de-paso> <python que modifica s> → copia mutada
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for job in d["jobs"].values():
    for s in job.get("steps", []):
        if s.get("name") == sys.argv[3]:
            exec(sys.argv[4])
yaml.safe_dump(d, open(sys.argv[2], "w"))
PY
}

@test "negativo: un if de pull_request unido con || en el nivel superior no cuenta como solo-PR" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  mutate_step "$GUARD" "$f" "Gate 2: Conventional Commits" 's["if"] = "github.event_name == \x27pull_request\x27 || always()"'
  run check "$f" "PR Guardian"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Gate 2: Conventional Commits"* ]]
}

@test "negativo: mencionar merge_group.base_sha no tapa otra lectura de la PR en el mismo paso" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  mutate_step "$CI" "$f" "Derived paths absent" 's["env"]["HEAD_REF"] = "${{ github.head_ref }}"'
  run check "$f" "Validate workspace|Lint Markdown|BATS Hook Tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Derived paths absent"* ]]
}

@test "negativo: github.event.number en un paso que corre en la cola se detecta" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  mutate_step "$CI" "$f" "Derived paths absent" 's["env"]["PR_N"] = "${{ github.event.number }}"'
  run check "$f" "Validate workspace|Lint Markdown|BATS Hook Tests"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Derived paths absent"* ]]
}

@test "positivo: un || dentro de paréntesis tras && pull_request sigue siendo solo-PR" {
  f="$BATS_TEST_TMPDIR/wf.yml"
  mutate_step "$GUARD" "$f" "Gate 2: Conventional Commits" 's["if"] = "github.event_name == \x27pull_request\x27 && (github.actor == \x27a\x27 || github.actor == \x27b\x27)"'
  run check "$f" "PR Guardian"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

@test "los workflows de PR o de main (auto-rebase, confidencialidad, DCO, etiquetas) no se disparan en la cola" {
  for w in auto-rebase-open-prs confidentiality-gate dco-check auto-label-pr; do
    run python3 -c "
import yaml,sys
d=yaml.safe_load(open('.github/workflows/$w.yml')); on=d.get(True, d.get('on'))
sys.exit(1 if isinstance(on, dict) and 'merge_group' in on else 0)"
    [ "$status" -eq 0 ] || { echo "$w se dispara con merge_group"; return 1; }
  done
}
