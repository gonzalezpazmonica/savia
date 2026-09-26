---
name: check-coherence
description: Validate that a spec, report, or code output actually matches its stated objective
argument-hint: "[spec|report|code] [--strict] [--file path]"
allowed-tools:
  - Read
  - Glob
  - Grep
model_tier: mid
context_cost: low
tier: core
---

# /check-coherence

Invokes the coherence-validator agent to verify that generated outputs align with
their objectives. Detects coverage gaps, internal contradictions, and missing assumptions.

## Usage

```
/check-coherence {type} [--strict] [--file path]
```

### Arguments

- `{type}`: **spec** | **report** | **code** (required)
  - **spec**: Validate a SDD specification or design document
  - **report**: Validate an executive report, sprint report, or analysis
  - **code**: Validate implementation against interface/contract
- `--strict` (optional): Treat warnings as errors; block on warning or critical
- `--file {path}` (optional): Check specific file; if omitted, checks last generated output

## Examples

### Spanish
```
/check-coherence spec --file projects/sala-reservas/specs/FEATURE-001.spec.md
/check-coherence report --strict
/check-coherence code --file src/AuthService.cs
```

### English
```
/check-coherence spec --file projects/project/specs/FEATURE-001.spec.md
/check-coherence report --strict
/check-coherence code --file src/OrderService.cs
```

## What Gets Checked

| Type | Checks |
|---|---|
| **spec** | Requirements coverage, acceptance criteria testability, example consistency, architecture coherence |
| **report** | KPI accuracy, trend alignment with charts, actionability, scope match |
| **code** | Interface implementation, test coverage of claims, domain naming |

## Output

A structured coherence report with:
- **Coverage %**: how many requirements are addressed
- **Severity**: ✅ ok | ⚠️ warning | 🔴 critical
- **Checks passed**: each of the 3 coherence checks (coverage, consistency, completeness)
- **Gaps found**: specific unaddressed requirements
- **Recommendations**: improvements with locations

## Non-Blocking

By default, findings are informational. User can override with:
- `--force`: ignore warnings/critical and proceed
- `--strict`: block on any finding ≥ warning level

## Integration

Works automatically after:
- `/spec-generate` (if `--verify-coherence` flag)
- `/executive-report`, `/sprint-report` (if auto-validation enabled in workflow)
- Manual invocation on any file

Always check coherence before finalizing high-impact outputs (specs, reports, decisions).
