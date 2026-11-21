#!/usr/bin/env bats
# Ref: docs/specs/SE-260-blast-radius.spec.md — SE-376 S03, skill codegraph
#
# La skill codegraph es opt-in: Savia no la instala y el repo la trae desactivada. Lo que Savia
# ejecuta de ella es la elección de backend de scripts/blast-radius.sh (--list-backends) y la
# configuración de opencode.json. Aquí se prueba con un `codegraph` falso en el PATH (ausente,
# sin índice, con índice) para que la prueba no dependa de lo que haya instalado en la máquina.

SCRIPT="scripts/blast-radius.sh"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TMPDIR="$(mktemp -d)"
  # PATH mínimo: solo las herramientas que usa el script, sin ningún codegraph real
  MINBIN="$TMPDIR/minbin"
  mkdir -p "$MINBIN" "$TMPDIR/fake"
  local t p
  for t in bash dirname basename cat grep sed env python3 git mktemp find head tail sort tr rm date wc cut awk uniq xargs sh; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$MINBIN/$t"
  done
  export FAKE_LOG="$TMPDIR/calls.log"
  : > "$FAKE_LOG"
}

teardown() { find "$TMPDIR" -delete 2>/dev/null || true; }

# fake_codegraph <código de salida de «status»>
fake_codegraph() {
  cat > "$TMPDIR/fake/codegraph" <<EOF
#!/usr/bin/env bash
echo "codegraph \$*" >> "\$FAKE_LOG"
[[ "\$1" == "status" ]] && exit $1
exit 0
EOF
  chmod +x "$TMPDIR/fake/codegraph"
}

backends() { PATH="${1:-$MINBIN}" run bash "$REPO_ROOT/$SCRIPT" --list-backends; }

@test "CG-01: con codegraph indexado (status 0) el backend es codegraph" {
  fake_codegraph 0
  backends "$TMPDIR/fake:$MINBIN"
  [ "$status" -eq 0 ]
  [ "$output" = "backend=codegraph" ]
}

@test "CG-02: missing codegraph binary falls back to grep and says so" {
  backends "$MINBIN"
  [ "$status" -eq 0 ]
  [[ "$output" == "backend=grep"* ]]
  [[ "$output" == *"codegraph no disponible"* ]]
}

@test "CG-03: codegraph without index (status fails) falls back to grep, not codegraph" {
  fake_codegraph 1
  backends "$TMPDIR/fake:$MINBIN"
  [ "$status" -eq 0 ]
  [[ "$output" == "backend=grep"* ]]
  [[ "$output" != "backend=codegraph" ]]
}

@test "CG-04: --list-backends consulta el índice con «codegraph status» y nada más" {
  fake_codegraph 0
  backends "$TMPDIR/fake:$MINBIN"
  [ "$(cat "$FAKE_LOG")" = "codegraph status" ]
}

@test "CG-06: con codegraph indexado el análisis --symbol sigue siendo por grep y no lo invoca" {
  fake_codegraph 0
  local P="$TMPDIR/proj"
  mkdir -p "$P"
  git -C "$P" init -q
  printf 'helper() { :; }\n' > "$P/lib.sh"
  printf 'helper\n' > "$P/app.sh"
  git -C "$P" add -A
  cd "$P"
  PATH="$TMPDIR/fake:$MINBIN" run bash "$REPO_ROOT/$SCRIPT" --symbol helper
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['backend']=='grep', d; assert d['direct']==['app.sh'], d"
  [ ! -s "$FAKE_LOG" ]
}

@test "CG-07: no arg file needed: --list-backends has no error output" {
  backends "$MINBIN"
  [ "$status" -eq 0 ]
  [[ "$output" != *ERROR* ]]
}

@test "CG-08: el repo trae codegraph desactivado en opencode.json (opt-in, Rule 19)" {
  python3 - "$REPO_ROOT/opencode.json" <<'PY'
import json, sys
cg = json.load(open(sys.argv[1]))["mcp"]["codegraph"]
assert cg["enabled"] is False, cg
assert cg["type"] == "local", cg
assert cg["command"][-2:] == ["serve", "--mcp"], cg
PY
}

@test "CG-09: skill documents opt-in default (enabled false) and the init/serve flow" {
  grep -q 'serve' "$REPO_ROOT/.claude/skills/codegraph/SKILL.md" || grep -q 'codegraph init' "$REPO_ROOT/.claude/skills/codegraph/SKILL.md"
  grep -q 'enabled: false' "$REPO_ROOT/.claude/skills/codegraph/SKILL.md"
}

@test "CG-10: savia-setup enables codegraph only on request, keeps unmentioned state and creates unknown ones disabled (null-safe)" {
  python3 - "$REPO_ROOT" "$TMPDIR" <<'PY'
import json, os, re, subprocess, sys
root, tmp = sys.argv[1], sys.argv[2]
src = open(os.path.join(root, "scripts/savia-setup.sh")).read()
# extrae el cuerpo python de apply_mcp
m = re.search(r"apply_mcp\(\)\{\n  python3 - .*?<<'PY' \|\| return 1\n(.*?)\nPY\n", src, re.S)
assert m, "apply_mcp no encontrado"
body = m.group(1)
oc = os.path.join(tmp, "opencode.json"); st = os.path.join(tmp, "state.json")
def run(state, start):
    json.dump({"mcp": start}, open(oc, "w")); json.dump({"mcp": state}, open(st, "w"))
    subprocess.run([sys.executable, "-c", body, oc, st], check=True, capture_output=True)
    return json.load(open(oc))["mcp"]
start = {"codegraph": {"enabled": False}, "codebase-memory-mcp": {"enabled": True}}
r = run({"enabled": ["codegraph"], "disabled": []}, start)
assert r["codegraph"]["enabled"] is True and r["codebase-memory-mcp"]["enabled"] is True, r
r = run({"enabled": [], "disabled": ["codebase-memory-mcp"]}, start)
assert r["codegraph"]["enabled"] is False and r["codebase-memory-mcp"]["enabled"] is False, r
r = run({"enabled": [], "disabled": []}, {"codegraph": {"enabled": True}})
assert r["codegraph"]["enabled"] is True, r   # no mencionado: se conserva
assert r["savia-vaults"]["enabled"] is False, r  # desconocido: se crea desactivado
PY
}

@test "CG-11: invalid option and zero files are errors, never a silent backend report" {
  PATH="$MINBIN" run bash "$REPO_ROOT/$SCRIPT" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
  PATH="$MINBIN" run bash "$REPO_ROOT/$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"at least one file required"* ]]
}

@test "CG-12: boundary depth 5 accepted, depth 6 and 0 rejected" {
  local P="$TMPDIR/p2"; mkdir -p "$P"; printf 'x\n' > "$P/a.sh"
  PATH="$MINBIN" run bash "$REPO_ROOT/$SCRIPT" --project "$P" --depth 5 a.sh
  [ "$status" -eq 0 ]
  PATH="$MINBIN" run bash "$REPO_ROOT/$SCRIPT" --project "$P" --depth 6 a.sh
  [ "$status" -eq 1 ]
  PATH="$MINBIN" run bash "$REPO_ROOT/$SCRIPT" --project "$P" --depth 0 a.sh
  [ "$status" -eq 1 ]
}

@test "CG-13: strict mode is kept so a failing probe is never swallowed" {
  grep -q 'set -uo pipefail\|set -euo pipefail' "$REPO_ROOT/$SCRIPT"
}
