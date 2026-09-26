---
name: best-practices-check
description: "Evaluate workspace against Claude Code best practices"
model_tier: mid
context_cost: medium
allowed-tools: [Read, Bash, Glob, Grep]
argument-hint: "[--format brief|full]"
tier: core
---

# /best-practices-check

Evaluate the current pm-workspace installation against best practices.

## Checks

### Structure (30%)
1. CLAUDE.md exists and ≤150 lines
2. .claude/settings.json is valid JSON with hooks
3. docs/rules/ directory has domain rules
4. .opencode/agents/ have frontmatter with name + description
5. .opencode/commands/ have frontmatter with name

### Hooks (20%)
1. All hooks have `set -uo pipefail`
2. All hooks read stdin (`cat /dev/stdin`)
3. No `eval` in hooks (security)
4. Async hooks marked correctly in settings.json

### Context Health (20%)
1. CLAUDE.md ≤120 lines (warning at 100)
2. No hardcoded paths in scripts
3. config/model-capabilities.yaml exists (Era 100)
4. context-cache in .gitignore

### Testing (15%)
1. tests/ directory exists with BATS files
2. ≥5 test suites
3. All tests pass (`bats tests/structure/*.bats`)

### Documentation (15%)
1. README.md exists
2. CHANGELOG.md follows Keep a Changelog
3. CONTRIBUTING.md exists
4. SECURITY.md exists

## Output

Save to `output/best-practices-YYYYMMDD.md` with score per category.

```
Best Practices Score: 85/100
  Structure:  28/30 ✅
  Hooks:      18/20 ✅
  Context:    17/20 ⚠️ (CLAUDE.md at 151 lines)
  Testing:    12/15 ✅
  Docs:       10/15 ⚠️ (CHANGELOG needs Era refs)
```
