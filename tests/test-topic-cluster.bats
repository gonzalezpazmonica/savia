#!/usr/bin/env bats
# test-topic-cluster.bats — SE-033 Slice 2 tests for topic-cluster.py + skill.
# Spec: docs/propuestas/SE-033-topic-cluster-skill.md

set -uo pipefail
ROOT="$BATS_TEST_DIRNAME/.."
SCRIPT="$ROOT/scripts/topic-cluster.py"
SKILL_DIR="$ROOT/.opencode/skills/topic-cluster"

setup() {
  TMPDIR="$(mktemp -d)"
  export TMPDIR
}

teardown() {
  [[ -n "${TMPDIR:-}" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR" || true
}

# --- Script existence ---

@test "script: topic-cluster.py exists" {
  [ -f "$SCRIPT" ]
}

@test "script: has shebang" {
  run head -1 "$SCRIPT"
  [[ "$output" == "#!/usr/bin/env python3" ]]
}

@test "script: is executable" {
  [ -x "$SCRIPT" ]
}

@test "script: --help works" {
  run python3 "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"BERTopic"* || "$output" == *"cluster"* ]]
}

# --- Input validation ---

@test "input: empty stdin returns parse error" {
  run bash -c "echo '' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: invalid JSON returns error" {
  run bash -c "echo 'not json' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: missing documents field returns error" {
  run bash -c "echo '{}' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: documents not a list returns error" {
  run bash -c "echo '{\"documents\":\"nope\"}' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: insufficient documents (<3) returns error" {
  local input='{"documents":[{"id":"a","text":"hi"},{"id":"b","text":"ho"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: document missing id returns error" {
  local input='{"documents":[{"text":"a"},{"text":"b"},{"text":"c"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "input: document missing text returns error" {
  local input='{"documents":[{"id":"1"},{"id":"2"},{"id":"3"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

# --- Happy path ---

@test "happy: 6 docs with clusters produces output" {
  local input='{"documents":[{"id":"1","text":"sprint planning agile methodology"},{"id":"2","text":"code review feedback pull request"},{"id":"3","text":"sprint velocity tracking metrics"},{"id":"4","text":"pull request review comments"},{"id":"5","text":"agile sprint retrospective"},{"id":"6","text":"pr review code quality"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' --min-cluster-size 3 2>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"topics"'* ]]
  [[ "$output" == *'"backend"'* ]]
}

@test "happy: output has latency_ms field" {
  local input='{"documents":[{"id":"1","text":"a b c"},{"id":"2","text":"d e f"},{"id":"3","text":"g h i"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' 2>/dev/null"
  [[ "$output" == *'"latency_ms"'* ]]
}

@test "happy: --json produces pretty output" {
  local input='{"documents":[{"id":"1","text":"a"},{"id":"2","text":"b"},{"id":"3","text":"c"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' --json 2>/dev/null"
  local lines=$(echo "$output" | wc -l)
  [ "$lines" -gt 3 ]
}

@test "happy: outliers field always present" {
  local input='{"documents":[{"id":"1","text":"a"},{"id":"2","text":"b"},{"id":"3","text":"c"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' 2>/dev/null"
  [[ "$output" == *'"outliers"'* ]]
}

# --- Fallback ---

@test "fallback: works without bertopic (keyword fallback)" {
  local input='{"documents":[{"id":"1","text":"sprint planning"},{"id":"2","text":"sprint velocity"},{"id":"3","text":"sprint review"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' --min-cluster-size 3 2>/dev/null"
  [ "$status" -eq 0 ]
  # Either backend is fine
  [[ "$output" == *"bertopic"* || "$output" == *"fallback-keyword"* ]]
}

@test "fallback: keyword groups by shared word" {
  local input='{"documents":[{"id":"1","text":"sprint planning"},{"id":"2","text":"sprint velocity"},{"id":"3","text":"sprint review"},{"id":"4","text":"backlog grooming"},{"id":"5","text":"backlog refinement"},{"id":"6","text":"backlog priority"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' --min-cluster-size 3 2>/dev/null"
  [ "$status" -eq 0 ]
  # With 6 docs, 2 themed clusters expected
  run python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d['topics']))" <<<"$output"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

# --- Usage errors ---

@test "usage: invalid min-cluster-size rejected" {
  run python3 "$SCRIPT" --min-cluster-size 1
  [ "$status" -eq 2 ]
}

@test "usage: unknown flag rejected" {
  run python3 "$SCRIPT" --bogus-flag
  [ "$status" -ne 0 ]
}

# --- Skill structure ---

@test "skill: topic-cluster directory exists" {
  [ -d "$SKILL_DIR" ]
}

@test "skill: SKILL.md under 150 lines" {
  [ -f "$SKILL_DIR/SKILL.md" ]
  local lines=$(wc -l < "$SKILL_DIR/SKILL.md")
  [ "$lines" -le 150 ]
}

@test "skill: DOMAIN.md under 150 lines" {
  [ -f "$SKILL_DIR/DOMAIN.md" ]
  local lines=$(wc -l < "$SKILL_DIR/DOMAIN.md")
  [ "$lines" -le 150 ]
}

@test "skill: SKILL.md references SE-033" {
  run grep "SE-033" "$SKILL_DIR/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "skill: DOMAIN.md references SE-033" {
  run grep "SE-033" "$SKILL_DIR/DOMAIN.md"
  [ "$status" -eq 0 ]
}

@test "skill: SKILL.md frontmatter name is topic-cluster" {
  run grep -E "^name:\s*topic-cluster" "$SKILL_DIR/SKILL.md"
  [ "$status" -eq 0 ]
}

@test "skill: SKILL.md mentions UMAP HDBSCAN or BERTopic" {
  run grep -iE "UMAP|HDBSCAN|BERTopic" "$SKILL_DIR/SKILL.md"
  [ "$status" -eq 0 ]
}

# --- Coverage ---

@test "coverage: script has fallback_keyword_cluster function" {
  run grep "def fallback_keyword_cluster" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "coverage: script has try_bertopic function" {
  run grep "def try_bertopic" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "coverage: script handles ImportError gracefully" {
  run grep "ImportError" "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "coverage: script references SE-033" {
  run grep "SE-033" "$SCRIPT"
  [ "$status" -eq 0 ]
}

# --- Edge cases ---

@test "edge: zero documents rejected" {
  run bash -c "echo '{\"documents\":[]}' | python3 '$SCRIPT'"
  [ "$status" -eq 1 ]
}

@test "edge: no arg to --help works" {
  run python3 "$SCRIPT" --help
  [ "$status" -eq 0 ]
}

@test "edge: boundary at min-cluster-size=2 accepted" {
  local input='{"documents":[{"id":"1","text":"a"},{"id":"2","text":"b"},{"id":"3","text":"c"}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' --min-cluster-size 2 2>/dev/null"
  [ "$status" -eq 0 ]
}

@test "edge: empty text in document accepted" {
  local input='{"documents":[{"id":"1","text":""},{"id":"2","text":""},{"id":"3","text":""}]}'
  run bash -c "echo '$input' | python3 '$SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
}

@test "edge: nr-topics null accepted" {
  local input='{"documents":[{"id":"1","text":"a"},{"id":"2","text":"b"},{"id":"3","text":"c"}],"nr_topics":null}'
  run bash -c "echo '$input' | python3 '$SCRIPT' 2>/dev/null"
  [ "$status" -eq 0 ]
}

# --- Isolation ---

@test "isolation: script does not write to cwd" {
  cd "$TMPDIR"
  local before=$(find . -type f 2>/dev/null | wc -l)
  echo '{"documents":[{"id":"1","text":"a"},{"id":"2","text":"b"},{"id":"3","text":"c"}]}' | python3 "$SCRIPT" >/dev/null 2>&1 || true
  local after=$(find . -type f 2>/dev/null | wc -l)
  cd "$ROOT"
  [ "$before" -eq "$after" ]
}

@test "isolation: --help does not require network" {
  run timeout 3 python3 "$SCRIPT" --help
  [ "$status" -eq 0 ]
}
