#!/usr/bin/env bash
set -euo pipefail
# ci-bats-deps.sh — Generate dependency map for dynamic BATS test selection
#
# Parses tests/bats/*.bats to extract source file references from:
# 1. Variable assignments (e.g. SKILLS_DIR="$REPO_ROOT/.opencode/skills")
# 2. Path literals used in assertions and commands
# 3. Merges manual directory rules from tests/bats/.deps-rules.yaml.

MODE="${1:---generate}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
BATS_DIR="$ROOT/tests/bats"
DEPS_FILE="$BATS_DIR/.deps.json"
RULES_FILE="$BATS_DIR/.deps-rules.yaml"

CORE_TESTS=(
  "test-opencode-config-validate.bats"
  "test-evals-ci-gate.bats"
  "test-se-079-scope-gate.bats"
  "test-se-210-skill-antipatterns.bats"
  "test-se253-agent-sync.bats"
  "test-se253-hooks-coverage.bats"
  "test-se-097-rules-index-regen.bats"
  "test-se-220-speculative.bats"
  "test-priority-formula.bats"
  "test-router-mode-dispatch.bats"
  "test-cognitive-debt.bats"
  "test-context-greedy-budget.bats"
  "test-memory-feedback.bats"
)

generate() {
  echo "Generating BATS dependency map..."
  local total=0
  declare -A mappings

  for bats_file in "$BATS_DIR"/*.bats; do
    [[ -f "$bats_file" ]] || continue
    total=$((total + 1))
    local testname
    testname=$(basename "$bats_file")

    while IFS= read -r ref; do
      [[ -z "$ref" ]] && continue
      ref=$(echo "$ref" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      if [[ -z "${mappings[$ref]:-}" ]]; then
        mappings[$ref]="$testname"
      else
        if [[ ! " ${mappings[$ref]} " =~ " $testname " ]]; then
          mappings[$ref]="${mappings[$ref]} $testname"
        fi
      fi
    done < <(
      grep -oP '(?<=")\$?REPO_ROOT/(scripts|docs|\.opencode|\.claude|projects|\.github|tests)/[^"]+' "$bats_file" 2>/dev/null | sed 's/^\$REPO_ROOT\///' | sort -u || true
      grep -oP '(?<=")\$?\w+_DIR/(scripts|docs|\.opencode|\.claude|projects|\.github|tests)/[^"]+' "$bats_file" 2>/dev/null | sed 's/^\$[A-Z_]*\///' | sort -u || true
    )
  done

  python3 -c "
import json, os
from datetime import datetime, timezone

total = int('$total')
core_raw = '${CORE_TESTS[*]}'
core = core_raw.split()

mapping_dict = {}
for key, val in [
$(for key in "${!mappings[@]}"; do echo "('$key', '${mappings[$key]}'),"; done)
]:
    if key and val:
        tests = sorted(set(val.split()))
        mapping_dict[key] = tests if tests else [val.strip()]

output = {
    'version': '1',
    'generated_at': datetime.now(timezone.utc).isoformat(),
    'total_tests': total,
    'core_tests': core,
    'mappings': mapping_dict,
    'dir_rules': {}
}

rules_file = '$RULES_FILE'
if os.path.exists(rules_file):
    try:
        import yaml
        with open(rules_file) as f:
            rules = yaml.safe_load(f) or {}
        dir_rules = {}
        for rule in rules.get('rules', []):
            d = rule.get('dir', '')
            t = rule.get('tests', [])
            f = rule.get('file', '')
            if f and t:
                dir_rules[f] = t
            elif d and t:
                dir_rules[d] = t
        output['dir_rules'] = dir_rules
    except ImportError:
        pass

os.makedirs(os.path.dirname('$DEPS_FILE'), exist_ok=True)
with open('$DEPS_FILE', 'w') as f:
    json.dump(output, f, indent=2, ensure_ascii=False)

print(f'wrote $DEPS_FILE ({total} tests, {len(mapping_dict)} mappings, {len(output[\"dir_rules\"])} dir rules)')
"
}

check() {
  if [[ ! -f "$DEPS_FILE" ]]; then
    echo "STALE: .deps.json not found"
    exit 1
  fi
  local bats_latest deps_latest
  bats_latest=$(find "$BATS_DIR" -name "*.bats" -printf '%T@\n' 2>/dev/null | sort -rn | head -1 || echo 0)
  deps_latest=$(stat -c '%Y' "$DEPS_FILE" 2>/dev/null || echo 0)
  if [[ "${bats_latest%.*}" -gt "${deps_latest%.*}" ]]; then
    echo "STALE: .bats files newer than .deps.json"
    exit 1
  fi
  echo "OK: .deps.json is fresh"
}

case "$MODE" in
  --generate|generate) generate ;;
  --check|check) check ;;
  *) echo "Usage: ci-bats-deps.sh [--generate|--check]" >&2; exit 1 ;;
esac
