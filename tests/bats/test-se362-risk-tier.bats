#!/usr/bin/env bats
# test-se362-risk-tier.bats — BATS tests for SE-362 risk-tiering
# Ref: SE-362 — gradación de riesgo para auto-merge

SCRIPT="scripts/risk-tier.py"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TIER="$REPO_ROOT/$SCRIPT"
  export REPO_ROOT TIER
  TMP_DIR="$(mktemp -d -p "$BATS_TEST_TMPDIR")"
}

@test "docs-only → tier 1, no requiere humano" {
  run python3 "$TIER" --diff "README.md docs/guide.md" --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 1, f'tier={d[\"tier\"]}'
assert d['requires_human'] is False
"
}

@test "scripts con push/merge → tier 3, requiere humano" {
  # push-pr.sh ya no sirve de ejemplo: es gobernanza (tier 4, SE-343).
  run python3 "$TIER" --diff "scripts/git-push-helper.sh" --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 3, f'tier={d[\"tier\"]}'
assert d['requires_human'] is True
"
}

@test "SE-343: push-pr.sh y operator-grant.sh (mergean y verifican el grant) → tier 4" {
  for f in scripts/push-pr.sh scripts/operator-grant.sh; do
    run python3 "$TIER" --diff "$f" --json
    [[ "$status" -eq 0 ]]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 4, f'tier={d[\"tier\"]}'
"
  done
}

@test "infra → tier 4" {
  run python3 "$TIER" --diff "infra/main.tf" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 4, f'tier={d[\"tier\"]}'
"
}

@test "código normal → tier 2" {
  run python3 "$TIER" --diff "src/service.py tests/test_service.py" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 2, f'tier={d[\"tier\"]}'
"
}

@test "path desconocido → fail-closed tier 3" {
  run python3 "$TIER" --diff "weird/file.bin" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 3, f'fail-closed: tier={d[\"tier\"]}'
"
}

@test "edge: código + doc al final sigue siendo tier 2 (sin depender del orden)" {
  for diff in "scripts/tool.sh CLAUDE.md" "CLAUDE.md scripts/tool.sh"; do
    run python3 "$TIER" --diff "$diff" --json
    [[ "$status" -eq 0 ]]
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 2, f'tier={d[\"tier\"]}'
assert d['requires_human'] is False
"
  done
}

@test "edge: empty diff → fail-closed tier 3 (no se puede evaluar)" {
  run python3 "$TIER" --diff "" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 3, f'tier={d[\"tier\"]}'
assert d['requires_human'] is True
"
}

@test "error: no --diff arg → exit 2 con uso" {
  run python3 "$TIER" --json
  [ "$status" -ne 0 ]
  [[ "$output" == *"--diff"* ]]
}

@test "edge: large diff de 500 ficheros de código con un doc al final → tier 2" {
  for i in $(seq 1 500); do printf 'src/mod%s.py ' "$i"; done > "$TMP_DIR/diff.txt"
  printf 'docs/zz-final.md' >> "$TMP_DIR/diff.txt"
  run python3 "$TIER" --diff "$(cat "$TMP_DIR/diff.txt")" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 2, f'tier={d[\"tier\"]}'
assert len(d['files']) == 501
"
}

@test "reject downgrade: un path de infra entre muchos docs → tier 4" {
  run python3 "$TIER" --diff "docs/a.md README.md .github/workflows/ci.yml docs/b.md" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 4, f'tier={d[\"tier\"]}'
assert 'ci.yml' in d['rationale']
"
}

@test "API: classify() es independiente del orden y main() devuelve 0 con --json" {
  run python3 - "$TIER" <<'PY'
import importlib.util, itertools, sys
spec = importlib.util.spec_from_file_location("risk_tier", sys.argv[1])
rt = importlib.util.module_from_spec(spec); spec.loader.exec_module(rt)
files = ["docs/a.md", "scripts/tool.sh", "README.md"]
tiers = {rt.classify(list(p))["tier"] for p in itertools.permutations(files)}
assert tiers == {2}, tiers
sys.argv = ["risk-tier.py", "--diff", "docs/a.md", "--json"]
assert rt.main() == 0
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *'"tier": 1'* ]]
}

@test "SAM regenerado (.scm generado) no eleva el tier: views/authority.json con código normal → tier 2" {
  run python3 "$TIER" --diff ".scm/sam.json .scm/views/authority.json .scm/reports/drift.json .scm/registry.json .scm/INDEX.scm .scm/categories/planning.scm scripts/tool.sh" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] == 2, f'tier={d[\"tier\"]} {d[\"rationale\"]}'
"
}

@test "reject: las declaraciones del SAM (fuentes a mano, autoridad) siguen elevando el tier" {
  run python3 "$TIER" --diff ".scm/sam-runtime-declarations.json .scm/views/authority.json" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] >= 2, f'tier={d[\"tier\"]}'
assert '.scm/views/authority.json' not in d['rationale'], d['rationale']
"
  run python3 "$TIER" --diff ".scm/sam-authority-declarations.json" --json
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d['tier'] >= 3, f'tier={d[\"tier\"]}'
"
}
