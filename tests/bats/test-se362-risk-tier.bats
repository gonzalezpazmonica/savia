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

teardown() { rm -rf "$TMP_DIR"; }

# SE-501: la lista de derivados se lee del commit base, nunca del disco de la PR.
base_fixture() {
  FIXTURE="$TMP_DIR/base"
  mkdir -p "$FIXTURE/scripts"
  cp "$TIER" "$FIXTURE/scripts/risk-tier.py"
  git -C "$FIXTURE" init -q -b main
  fixture_base
}

fixture_git() {
  git -C "$FIXTURE" -c core.hooksPath=/dev/null -c commit.gpgsign=false \
    -c user.name=test -c user.email=test@example.invalid "$@"
}

fixture_base() {
  fixture_git add scripts/risk-tier.py
  if [[ -f "$FIXTURE/scripts/derived-paths.txt" ]]; then
    fixture_git add scripts/derived-paths.txt
  fi
  fixture_git commit -qm base
  fixture_git update-ref refs/remotes/origin/main HEAD
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

# ── S03n: comportamiento discriminante ──────────────────────────────────────

# tier_of <script> "<ficheros>" → imprime "tier requires_human"
tier_of() {
  python3 "$1" --diff "$2" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["tier"], d["requires_human"])'
}

@test "S03n gobernanza: .opencode/, workflows y settings de raíz son tier 4" {
  run tier_of "$TIER" ".opencode/hooks/x.sh"
  [ "$output" = "4 True" ]
  run tier_of "$TIER" ".claude/settings.local.json"
  [ "$output" = "4 True" ]
  run tier_of "$TIER" "config/merge-sprint-policy.yaml"
  [ "$output" = "4 True" ]
}

@test "S03n gobernanza: settings en subcarpeta de .claude no es gobernanza" {
  run python3 "$TIER" --diff ".claude/settings/extra.json" --json
  [ "$status" -eq 0 ]
  [[ "$output" != *"path de gobernanza"* ]]
  # Aserción positiva: sin ella, una salida vacía también pasaría.
  run tier_of "$TIER" ".claude/settings/extra.json"
  [ "$output" = "2 False" ]
}

@test "S03n gobernanza: autonomous-safety*.md en docs/rules/domain gana a la exención de docs" {
  run tier_of "$TIER" "docs/rules/domain/autonomous-safety-merge-grant.md"
  [ "$output" = "4 True" ]
  run tier_of "$TIER" "docs/rules/domain/radical-honesty.md"
  [ "$output" = "4 True" ]
  # La misma familia de nombre en una subcarpeta o en otra raíz es doc normal.
  run tier_of "$TIER" "docs/rules/domain/sub/autonomous-safety.md"
  [ "$output" = "1 False" ]
  run tier_of "$TIER" "docs/rules/domain/otra-regla.md"
  [ "$output" = "1 False" ]
}

@test "S03n gobernanza: la comparación no distingue mayúsculas" {
  run tier_of "$TIER" "Scripts/Merge-Sprint.sh"
  [ "$output" = "4 True" ]
}

@test "S03n precedencia: tier 4 gana a tier 3 y el orden no importa" {
  run tier_of "$TIER" "scripts/auth-helper.py infra/main.tf"
  [ "$output" = "4 True" ]
  run tier_of "$TIER" "infra/main.tf scripts/auth-helper.py"
  [ "$output" = "4 True" ]
}

@test "S03n frontera: requires_human empieza exactamente en tier 3" {
  run tier_of "$TIER" "src/app.py"
  [ "$output" = "2 False" ]
  run tier_of "$TIER" "src/token_store.py"
  [ "$output" = "3 True" ]
}

@test "S03n: .yml de raíz sin categoría es fail-closed 3; solo docs es 1; docs con código es 2" {
  run tier_of "$TIER" "mkdocs.yml"
  [ "$output" = "3 True" ]
  run tier_of "$TIER" "CHANGELOG.md README.md"
  [ "$output" = "1 False" ]
  run tier_of "$TIER" "CHANGELOG.md src/app.py"
  [ "$output" = "2 False" ]
}

@test "S03n: el doc en docs/ con extensión de código no se exime" {
  run tier_of "$TIER" "docs/deploy-script.sh"
  [ "$output" = "3 True" ]
}

@test "S03n: salida de texto con la etiqueta de humano o auto-merge" {
  run python3 "$TIER" --diff "src/app.py"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Risk tier: 2 (auto-merge posible)" ]]
  run python3 "$TIER" --diff "infra/x.tf"
  [[ "${lines[0]}" == "Risk tier: 4 (humano requerido)" ]]
  [[ "${lines[1]}" == "  rationale: path crítico: infra/x.tf" ]]
}

@test "S03n fail-closed: sin derived-paths.txt nada de .scm se exime" {
  base_fixture
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/views/authority.json scripts/tool.sh"
  [ "$output" = "3 True" ]
  cp "$REPO_ROOT/scripts/derived-paths.txt" "$FIXTURE/scripts/"
  # Una lista presente solo en el árbol de la propuesta no autoriza la exención.
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/views/authority.json scripts/tool.sh"
  [ "$output" = "3 True" ]
  fixture_base
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/views/authority.json scripts/tool.sh"
  [ "$output" = "2 False" ]
}

@test "S03n fail-closed: una entrada .scm/ global o de fichero a mano en la lista se ignora" {
  base_fixture
  printf '.scm/\n.scm/runtime-surface/\n.scm/sam-authority-declarations.json\n' > "$FIXTURE/scripts/derived-paths.txt"
  fixture_base
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/views/authority.json"
  [ "$output" = "3 True" ]
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/sam-authority-declarations.json"
  [ "$output" = "3 True" ]
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/runtime-surface/auth.json"
  [ "$output" = "3 True" ]
}

@test "S03n: prefijo de directorio de la lista exime lo que cuelga de él y nada más" {
  base_fixture
  printf '# comentario\n.scm/views/\n' > "$FIXTURE/scripts/derived-paths.txt"
  fixture_base
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/views/authority.json scripts/tool.sh"
  [ "$output" = "2 False" ]
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/viewsx/authority.json scripts/tool.sh"
  [ "$output" = "3 True" ]
}

@test "S03n: un .json de raíz sensible no baja a tier 1 por ser «artefacto de proceso»" {
  run tier_of "$TIER" "token.json"
  [ "$output" = "3 True" ]
  run tier_of "$TIER" "README.md credentials.yaml"
  [ "$output" = "3 True" ]
}

@test "S03n fail-closed: runtime-surface y *.schema.json nunca son derivados aunque la lista los nombre" {
  base_fixture
  printf '.scm/runtime-surface/sub/\n.scm/auth.schema.json\n' > "$FIXTURE/scripts/derived-paths.txt"
  fixture_base
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/runtime-surface/sub/auth.json"
  [ "$output" = "3 True" ]
  run tier_of "$FIXTURE/scripts/risk-tier.py" ".scm/auth.schema.json"
  [ "$output" = "3 True" ]
}
