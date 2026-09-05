---
layer: peripheral
name: test-architect
description: Usar cuando se diseñan o generan tests de alta calidad en cualquier lenguaje.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: test-architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.context_cost: high
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Generates tests that score 80+ on the auditor from the first attempt. Knows 14 test types, 16 language frameworks, and 8 excellence patterns. Input: spec, source code, or bug report. Output: complete test files."
  savia.tags: "testing, quality, bats, multi-language, test-strategy"
---

# Skill: Test Architect

Designs and generates production-quality tests that pass quality gates from the first attempt.

**Prerequisites:** `scripts/test-auditor-engine.py` (SPEC-055), target spec or source file

---

## Decision Checklist

1. Is the input a spec, source file, or bug report? -> Determines test types needed
2. What language is the target? -> Selects framework from matrix below
3. Does the project have existing tests? -> Follow patterns for consistency
4. Is this a BATS validation test? -> Apply auditor-optimized template
5. Does the target touch auth, payments, or PII? -> Add security test cases

### Abort Conditions
- No clear target (no spec, no source, no bug) -> Ask for clarification
- Language not in the 16 supported packs -> Warn and use closest match

---

## Test Type Selection Matrix

| Input Type | Primary Test Types | Secondary |
|------------|-------------------|-----------|
| Spec (feature) | Unit + Integration + E2E | Contract, Property-based |
| Spec (API) | Unit + Contract + Integration | Security, Load |
| Source (script) | Validation (BATS) | Regression |
| Source (service) | Unit + Integration | Mutation |
| Bug report | Regression + Unit | E2E |
| Rule/config | Validation (BATS) | Snapshot |
| UI component | Unit + Visual regression | Accessibility, E2E |
| Pipeline | Pipeline + Integration | - |

## BATS Generation Protocol (Auditor-Optimized)

For BATS tests, follow `references/bats-template.md` exactly:

1. **Header**: shebang + SPEC reference + strategy comment
2. **Variables**: SCRIPT/HOOK path to target
3. **setup()**: mktemp -d for isolation
4. **teardown()**: rm -rf cleanup
5. **C1**: Target exists and is executable
6. **C2**: Safety flags verified (set -uo pipefail)
7. **C3**: 5+ positive scenario tests
8. **C4**: 4+ negative scenario tests (error/fail/missing/invalid keywords)
9. **C5**: 3+ edge case tests (empty/boundary/zero/nonexistent keywords)
10. **C8**: Spec doc existence test
11. **C9**: Mix assertion types throughout

Post-generation: run `python3 scripts/test-auditor-engine.py <file> .`
If score < 80: identify failing criteria, add missing patterns, re-verify.

## Non-BATS Generation Protocol

For all other languages, apply the 8 excellence patterns:

1. **Isolation**: Use framework's setup/teardown (BeforeEach, setUp, etc.)
2. **Positive paths**: 3+ happy-path tests with distinct scenarios
3. **Negative paths**: 2+ error-handling tests (invalid input, missing deps)
4. **Edge cases**: Empty collections, null/nil, boundary values, max limits
5. **Assertions**: Use framework-native assertion libraries (FluentAssertions, assertj)
6. **Coverage**: Test 60%+ of public API surface
7. **Documentation**: Test names explain WHAT and WHY, not HOW
8. **Determinism**: No sleep, no random, no external service dependencies

## Test Naming Convention

| Language | Pattern | Example |
|----------|---------|---------|
| BATS | Descriptive sentence | `"validates JSON output format"` |
| C#/xUnit | Method_Scenario_Expected | `CreateUser_WithInvalidEmail_ThrowsValidationError` |
| Java/JUnit | @DisplayName | `"should reject duplicate orders"` |
| Python/pytest | test_scenario_expected | `test_calculate_tax_with_zero_amount_returns_zero` |
| Go | TestFunction_Scenario | `TestParseConfig_EmptyInput` |
| JS/TS | describe+it | `it('should return 404 for missing user')` |

## Quality Verification

### BATS (automated)
```bash
python3 scripts/test-auditor-engine.py <generated-test.bats> .
# Must output: "certified": true, "total": >= 80
```

### Non-BATS (checklist)
- [ ] setup/teardown present
- [ ] 3+ positive cases
- [ ] 2+ negative cases
- [ ] Edge cases covered
- [ ] No external dependencies without mock/container
- [ ] Deterministic (no timing, no random)
- [ ] Test names are self-documenting
- [ ] Strategy comment in file header

## References

- `references/bats-template.md` — Golden BATS template (score 90+)
- `scripts/test-auditor-engine.py` — SPEC-055 auditor engine
- `docs/rules/domain/language-packs.md` — 16 language frameworks
- `docs/rules/domain/coverage-scripts.md` — Coverage patterns
- `.opencode/agents/test-engineer.md` — Complementary agent (execution)
