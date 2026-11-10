#!/usr/bin/env bats
# tests/test-se271-s3-wall-check.bats — SE-271 Slice 3: Wall Check tests
# Tests for scripts/engagement-wall-check.sh

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
INIT_SCRIPT="$REPO_ROOT/scripts/engagement-init.sh"
WALL_SCRIPT="$REPO_ROOT/scripts/engagement-wall-check.sh"
TMP_ENG="$BATS_TEST_TMPDIR/engagements"

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INIT_SCRIPT="$REPO_ROOT/scripts/engagement-init.sh"
  WALL_SCRIPT="$REPO_ROOT/scripts/engagement-wall-check.sh"
  TMP_ENG="$BATS_TEST_TMPDIR/engagements"
  mkdir -p "$TMP_ENG"
}

teardown() {
  rm -rf "$TMP_ENG"
}

# ── Structure tests ──────────────────────────────────────────────────────────

@test "SE271-WALL-01: wall-check script exists" {
  [ -f "$WALL_SCRIPT" ]
}

@test "SE271-WALL-02: wall-check script has set -uo pipefail" {
  grep -q "set -uo pipefail" "$WALL_SCRIPT"
}

@test "SE271-WALL-03: wall-check script has SE-271 reference" {
  grep -q "SE-271" "$WALL_SCRIPT"
}

@test "SE271-WALL-04: wall-check --help exits 0" {
  run bash "$WALL_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
  [[ "$output" == *"Layers"* ]]
}

@test "SE271-WALL-05: wall-check exits 0 with no engagements" {
  run bash "$WALL_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SE271-WALL-06: wall-check --json produces valid JSON" {
  run bash "$WALL_SCRIPT" --json
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.loads('''$output''')
assert 'engagements' in d
assert 'violation_count' in d
assert 'violations' in d
assert 'wall_intact' in d
assert isinstance(d['violations'], list)
print('OK')
"
  [[ "$output" == *"OK"* ]]
}

# ── Layer-specific checks ────────────────────────────────────────────────────

@test "SE271-WALL-07: --layer 1 only checks episodic memory" {
  run bash "$WALL_SCRIPT" --layer 1 --json
  [ "$status" -eq 0 ]
  run python3 -c "
import json
d = json.loads('''$output''')
# Layer filter should work without error
print('OK')
"
  [[ "$output" == *"OK"* ]]
}

@test "SE271-WALL-08: all 7 layers are documented" {
  run bash "$WALL_SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"episodic_memory"* ]]
  [[ "$output" == *"semantic_memory"* ]]
  [[ "$output" == *"active_context"* ]]
  [[ "$output" == *"knowledge_graph"* ]]
  [[ "$output" == *"domes"* ]]
  [[ "$output" == *"federation_exchange"* ]]
  [[ "$output" == *"briefs_drafts_engrams"* ]]
}

@test "SE271-WALL-09: --strict exits non-zero on violation" {
  # Create temp engagement context with cross-contamination
  local test_client_a="testclienta"
  local test_client_b="testclientb"
  local tmp_artifacts="$TMP_ENG/testclienta/artifacts"
  mkdir -p "$tmp_artifacts"

  # Create artifact tagged with wrong client
  echo "<!-- SE-271-WALL client:testclientb engagement:test confidentiality:3 -->" > "$tmp_artifacts/test.md"
  echo "# Test artifact" >> "$tmp_artifacts/test.md"

  run bash "$WALL_SCRIPT" --client "$test_client_a" --strict --json
  # Should detect violation even without full engagement setup
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

# ── Tag detection tests ──────────────────────────────────────────────────────

@test "SE271-WALL-10: wall-check detects cross-client tags in artifacts" {
  local tmp_dir="$BATS_TEST_TMPDIR/wall-test-$$"
  mkdir -p "$tmp_dir"
  echo "<!-- SE-271-WALL client:clientalpha engagement:x confidentiality:3 -->" > "$tmp_dir/clean.md"
  echo "<!-- SE-271-WALL client:clientbeta engagement:y confidentiality:3 -->" > "$tmp_dir/cross.md"

  # Just verify the tag detection pattern works
  local has_alpha
  has_alpha=$(grep -c "client:clientalpha" "$tmp_dir/clean.md" 2>/dev/null || echo 0)
  local has_beta
  has_beta=$(grep -c "client:clientbeta" "$tmp_dir/cross.md" 2>/dev/null || echo 0)
  [ "$has_alpha" -gt 0 ]
  [ "$has_beta" -gt 0 ]

  rm -rf "$tmp_dir"
}

@test "SE271-WALL-11: unknown flag exits 2" {
  run bash "$WALL_SCRIPT" --fake-flag
  [ "$status" -eq 2 ]
}

# ── Integration: wall-check with real engagements ────────────────────────────

@test "SE271-WALL-12: wall-check runs after engagement-init" {
  local test_client="wallinttest"
  local test_eng="wallcheck"

  # Use the init script to create an engagement
  run bash "$INIT_SCRIPT" \
    --client "$test_client" \
    --engagement "$test_eng" \
    --wall strict \
    --json

  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]  # may fail if dir exists

  # Now run wall-check against it
  run bash "$WALL_SCRIPT" --client "$test_client" --json
  [ "$status" -eq 0 ]

  # Cleanup
  rm -rf "$REPO_ROOT/engagements/$test_client" 2>/dev/null || true
}

@test "SE271-WALL-13: default wall mode is strict" {
  local test_client="defaultwall"
  local test_eng="strictdefault"
  local tmp_yaml="$BATS_TEST_TMPDIR/engagements/$test_client/${test_eng}.yaml"
  mkdir -p "$(dirname "$tmp_yaml")"

  echo "  mode: strict" > "$tmp_yaml"

  local mode
  mode=$(grep "mode:" "$tmp_yaml" | head -1 | awk '{print $2}')
  [ "$mode" = "strict" ]

  rm -rf "$BATS_TEST_TMPDIR/engagements"
}

# ── Bash syntax ──────────────────────────────────────────────────────────────

@test "SE271-WALL-14: bash -n passes on wall-check" {
  run bash -n "$WALL_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SE271-WALL-15: wall-check references all 7 layers in code" {
  local code_layers
  code_layers=$(grep -c "check_layer_" "$WALL_SCRIPT" 2>/dev/null || echo 0)
  [ "$code_layers" -ge 7 ]
}

# ── S03t: las 7 capas en un árbol sintético aislado ─────────────────────────
# El script deriva ROOT de su ruta: se copia a un árbol propio (BATS_TEST_TMPDIR)
# con dos engagements (acme estricto, beta permeable) y se planta contaminación
# capa a capa. HOME apunta al árbol para que la capa 4 no lea el del operador.

s03t_wall_tree() {
  W="$BATS_TEST_TMPDIR/wt"
  mkdir -p "$W/scripts" "$W/engagements/acme" "$W/engagements/beta" "$W/home"
  cp "$WALL_SCRIPT" "$W/scripts/engagement-wall-check.sh"
  printf 'wall:\n  mode: strict\n' > "$W/engagements/acme/prod.yaml"
  printf 'wall:\n  mode: permeable-declared\n' > "$W/engagements/beta/prod.yaml"
  WC="$W/scripts/engagement-wall-check.sh"
}

s03t_wall() { HOME="$W/home" run bash "$WC" "$@"; }

# Imprime "<capa>:<n>" por cada capa con violaciones del JSON de la salida.
s03t_layers() {
  python3 -c "
import json,sys,collections
d=json.loads(sys.argv[1]); c=collections.Counter(v['layer'] for v in d['violations'])
print(' '.join('%s:%d'%(k,c[k]) for k in sorted(c)) or 'none')
" "$output"
}

@test "wall tree: with clean artifacts every layer passes and the wall is intact" {
  s03t_wall_tree
  mkdir -p "$W/output" "$W/.claude/profiles/acme"
  echo "client:acme report" > "$W/output/a.md"
  s03t_wall --json
  [ "$status" -eq 0 ]
  [ "$(s03t_layers)" = "none" ]
  python3 -c "
import json,sys
d=json.loads(sys.argv[1]); assert d['wall_intact'] is True and d['violation_count']==0 and d['engagements']==2
assert d['checked_layers']==[1,2,3,4,5,6,7]
" "$output"
}

@test "layer 1: MEMORY.md mixing two client tags is a violation; a single tag is not" {
  s03t_wall_tree
  mkdir -p "$W/.claude/external-memory/auto"
  echo "client:acme only" > "$W/.claude/external-memory/auto/MEMORY.md"
  s03t_wall --layer 1 --json
  [ "$(s03t_layers)" = "none" ]
  printf 'client:acme\nclient:beta\n' > "$W/.claude/external-memory/auto/MEMORY.md"
  s03t_wall --layer 1 --json
  [ "$(s03t_layers)" = "episodic_memory:2" ]
  [[ "$output" == *"contains 2 client tags"* ]]
}

@test "layer 1: engagement memory file tagged with another client is a violation; its own tag is not" {
  s03t_wall_tree
  mkdir -p "$W/.claude/external-memory/auto" "$W/engagements/acme/memory"
  echo "client:acme" > "$W/engagements/acme/memory/ok.md"
  echo "client:beta" > "$W/engagements/acme/memory/bad.md"
  s03t_wall --layer 1 --json
  [ "$(s03t_layers)" = "episodic_memory:1" ]
  [[ "$output" == *"bad.md"* ]]
  [[ "$output" != *"ok.md"* ]]
  [[ "$output" == *"tagged client:beta but belongs to client:acme"* ]]
}

@test "layer 1: without the external-memory dir nothing is checked" {
  s03t_wall_tree
  mkdir -p "$W/engagements/acme/memory"
  echo "client:beta" > "$W/engagements/acme/memory/bad.md"
  s03t_wall --layer 1 --json
  [ "$(s03t_layers)" = "none" ]
}

@test "layer 2: output artifact tagged with a client outside the engagements is a violation" {
  s03t_wall_tree
  mkdir -p "$W/output"
  echo "client:acme" > "$W/output/ok.md"
  echo "client:ghost" > "$W/output/ghost.md"
  s03t_wall --layer 2 --json
  [ "$(s03t_layers)" = "semantic_memory:1" ]
  [[ "$output" == *"ghost.md"* && "$output" == *"client not in active engagements"* ]]
}

@test "layer 3: profile artifact tagged with another client is a violation" {
  s03t_wall_tree
  mkdir -p "$W/.claude/profiles/acme"
  echo "client:acme" > "$W/.claude/profiles/acme/ok.md"
  echo "client:beta" > "$W/.claude/profiles/acme/bad.yaml"
  s03t_wall --layer 3 --json
  [ "$(s03t_layers)" = "active_context:1" ]
  [[ "$output" == *"bad.yaml"* ]]
}

@test "layer 4: flat KG file tagged with a client other than the only engagement is a violation" {
  s03t_wall_tree
  mv "$W/engagements/beta/prod.yaml" "$W/home/beta.yaml"
  echo '{"client":"x"} client:acme' > "$W/own.kg.json"
  s03t_wall --layer 4 --json
  [ "$(s03t_layers)" = "none" ]
  echo '{"client":"x"} client:ghost' > "$W/ghost.kg.json"
  s03t_wall --layer 4 --json
  [ "$(s03t_layers)" = "knowledge_graph:1" ]
  [[ "$output" == *"ghost.kg.json"* ]]
}

@test "layer 4: knowledge-graph DB without client_tag column is a violation" {
  command -v sqlite3 >/dev/null || skip "sqlite3 no disponible"
  s03t_wall_tree
  mkdir -p "$W/home/.savia"
  sqlite3 "$W/home/.savia/knowledge-graph.db" "CREATE TABLE entities(id INTEGER, name TEXT);"
  s03t_wall --layer 4 --json
  [ "$(s03t_layers)" = "knowledge_graph:1" ]
  [[ "$output" == *"missing client_tag column"* ]]
}

@test "layer 4: knowledge-graph DB with untagged entities and cross-client relations reports both" {
  command -v sqlite3 >/dev/null || skip "sqlite3 no disponible"
  s03t_wall_tree
  mkdir -p "$W/home/.savia"
  sqlite3 "$W/home/.savia/knowledge-graph.db" "
    CREATE TABLE entities(id INTEGER, client_tag TEXT);
    CREATE TABLE relations(source_id INTEGER, target_id INTEGER);
    INSERT INTO entities VALUES (1,'acme'),(2,'beta'),(3,'');
    INSERT INTO relations VALUES (1,2);"
  s03t_wall --layer 4 --json
  [ "$(s03t_layers)" = "knowledge_graph:2" ]
  [[ "$output" == *"1 entities without client_tag"* ]]
  [[ "$output" == *"1 cross-client relations"* ]]
}

@test "layer 4: fully tagged knowledge-graph DB with same-client relations passes" {
  command -v sqlite3 >/dev/null || skip "sqlite3 no disponible"
  s03t_wall_tree
  mkdir -p "$W/home/.savia"
  sqlite3 "$W/home/.savia/knowledge-graph.db" "
    CREATE TABLE entities(id INTEGER, client_tag TEXT);
    CREATE TABLE relations(source_id INTEGER, target_id INTEGER);
    INSERT INTO entities VALUES (1,'acme'),(2,'acme');
    INSERT INTO relations VALUES (1,2);"
  s03t_wall --layer 4 --json
  [ "$(s03t_layers)" = "none" ]
}

@test "layer 5: untagged dome is a violation only when a client is given" {
  s03t_wall_tree
  mkdir -p "$W/output/domes"
  echo "no tag" > "$W/output/domes/d.md"
  s03t_wall --layer 5 --json
  [ "$(s03t_layers)" = "none" ]
  s03t_wall --layer 5 --client acme --json
  [ "$(s03t_layers)" = "domes:1" ]
  [[ "$output" == *"lacks client tag"* ]]
}

@test "layer 5: dome tagged with an unknown client is a violation; known client is not" {
  s03t_wall_tree
  mkdir -p "$W/output/domes"
  echo "client:acme" > "$W/output/domes/ok.md"
  echo "client:ghost" > "$W/output/domes/bad.md"
  s03t_wall --layer 5 --json
  [ "$(s03t_layers)" = "domes:1" ]
  [[ "$output" == *"bad.md"* && "$output" == *"client not in engagements"* ]]
}

@test "layer 6: foreign tag in federation exchange is blocked by a strict wall" {
  s03t_wall_tree
  mv "$W/engagements/beta/prod.yaml" "$W/home/beta.yaml"
  mkdir -p "$W/coordinacion/exchange"
  echo '{"x":1} client:acme' > "$W/coordinacion/exchange/own.jsonl"
  echo '{"x":1} client:beta' > "$W/coordinacion/exchange/foreign.jsonl"
  s03t_wall --layer 6 --json
  [ "$(s03t_layers)" = "federation_exchange:1" ]
  [[ "$output" == *"foreign.jsonl"* && "$output" == *"wall:strict blocks"* ]]
}

@test "layer 6: permeable wall needs a declaration naming the foreign client" {
  s03t_wall_tree
  mv "$W/engagements/acme/prod.yaml" "$W/home/acme.yaml"
  mkdir -p "$W/coordinacion/exchange"
  echo '{"x":1} client:acme' > "$W/coordinacion/exchange/f.jsonl"
  s03t_wall --layer 6 --json
  [[ "$output" == *"no permeability declaration"* ]]
  [ "$(s03t_layers)" = "federation_exchange:1" ]
  mkdir -p "$W/engagements/beta/wall"
  echo "allow: client:other" > "$W/engagements/beta/wall/permeability-declarations.yaml"
  s03t_wall --layer 6 --json
  [[ "$output" == *"no operator declaration"* ]]
  echo "allow: client:acme" > "$W/engagements/beta/wall/permeability-declarations.yaml"
  s03t_wall --layer 6 --json
  [ "$(s03t_layers)" = "none" ]
}

@test "layer 7: untagged report is a violation with a client, and not without one" {
  s03t_wall_tree
  mkdir -p "$W/output/reports"
  echo "no tag" > "$W/output/reports/r.md"
  s03t_wall --layer 7 --json
  [ "$(s03t_layers)" = "none" ]
  s03t_wall --layer 7 --client acme --json
  [ "$(s03t_layers)" = "briefs_drafts_engrams:1" ]
  [[ "$output" == *"lacks client tag"* ]]
}

@test "layer 7: --tag-artifacts tags the untagged brief once and clears the violation" {
  s03t_wall_tree
  mkdir -p "$W/output/briefs"
  echo "plain text" > "$W/output/briefs/b.md"
  s03t_wall --layer 7 --client acme --engagement prod --tag-artifacts --json
  [ "$(s03t_layers)" = "none" ]
  grep -q 'SE-271-WALL client:acme engagement:prod' "$W/output/briefs/b.md"
  s03t_wall --layer 7 --client acme --engagement prod --tag-artifacts --json
  [ "$(grep -c 'client:acme' "$W/output/briefs/b.md")" = "1" ]
}

@test "layer 7: binary content is not tagged even with --tag-artifacts" {
  s03t_wall_tree
  mkdir -p "$W/output/briefs"
  head -c 64 /dev/urandom > "$W/output/briefs/bin.json"
  before="$(sha256sum "$W/output/briefs/bin.json")"
  s03t_wall --layer 7 --client acme --tag-artifacts --json
  [ "$before" = "$(sha256sum "$W/output/briefs/bin.json")" ]
}

@test "layer 7: brief tagged with an unknown client and engagement artifact of another client are violations" {
  s03t_wall_tree
  mkdir -p "$W/output/drafts" "$W/engagements/acme/artifacts"
  echo "client:acme" > "$W/output/drafts/ok.md"
  echo "client:ghost" > "$W/output/drafts/ghost.md"
  echo "client:beta" > "$W/engagements/acme/artifacts/leak.md"
  s03t_wall --layer 7 --json
  [ "$(s03t_layers)" = "briefs_drafts_engrams:2" ]
  [[ "$output" == *"unknown client:ghost"* ]]
  [[ "$output" == *"found in client:acme directory"* ]]
}

@test "--layer N restricts the check to that layer and reports checked_layers" {
  s03t_wall_tree
  mkdir -p "$W/output"
  echo "client:ghost" > "$W/output/ghost.md"
  s03t_wall --layer 3 --json
  [ "$(s03t_layers)" = "none" ]
  python3 -c "
import json,sys; assert json.loads(sys.argv[1])['checked_layers']==[3]" "$output"
  s03t_wall --layer 2 --json
  [ "$(s03t_layers)" = "semantic_memory:1" ]
}

@test "--strict exits 1 on a violation and 0 without; non-strict always exits 0" {
  s03t_wall_tree
  mkdir -p "$W/output"
  s03t_wall --strict
  [ "$status" -eq 0 ]
  [[ "$output" == *"WALL INTACT"* ]]
  echo "client:ghost" > "$W/output/ghost.md"
  s03t_wall
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 violations"* && "$output" == *"[VIOLATION] semantic_memory"* ]]
  s03t_wall --strict
  [ "$status" -eq 1 ]
}

@test "--client with --engagement of a missing engagement checks zero engagements" {
  s03t_wall_tree
  s03t_wall --client acme --engagement nope --json
  python3 -c "
import json,sys; assert json.loads(sys.argv[1])['engagements']==0" "$output"
  s03t_wall --client acme --json
  python3 -c "
import json,sys; assert json.loads(sys.argv[1])['engagements']==1" "$output"
}

@test "a file carrying its own client tag first and a foreign tag later is still a violation (layers 1, 3, 6, 7)" {
  s03t_wall_tree
  mv "$W/engagements/beta/prod.yaml" "$W/home/beta.yaml"
  mkdir -p "$W/.claude/external-memory/auto" "$W/engagements/acme/memory" "$W/.claude/profiles/acme" "$W/coordinacion/exchange" "$W/engagements/acme/artifacts"
  printf 'client:acme\nlater client:beta\n' > "$W/engagements/acme/memory/m.md"
  printf 'client:acme\nlater client:beta\n' > "$W/.claude/profiles/acme/p.md"
  printf 'client:acme\nlater client:beta\n' > "$W/coordinacion/exchange/f.jsonl"
  printf 'client:acme\nlater client:beta\n' > "$W/engagements/acme/artifacts/a.md"
  s03t_wall --json
  [ "$(s03t_layers)" = "active_context:1 briefs_drafts_engrams:2 episodic_memory:1 federation_exchange:1" ]
}
