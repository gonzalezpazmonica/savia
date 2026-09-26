---
name: eval-agent
description: "Evaluate an agent against its golden set — precision, recall, hallucinations, bias (SPEC-036)"
argument-hint: "{agent} [--compare {date}]"
allowed-tools: [Read, Write, Bash, Glob, Grep, Task]
model_tier: heavy
context_cost: high
tier: core
---

# /eval-agent — Agent Evaluation (SPEC-036)

Evaluate an agent's quality using golden sets (known input/expected output pairs).

## Parameters

- `$ARGUMENTS` — Agent name (e.g., `security-attacker`, `code-reviewer`, `business-analyst`)
- `--compare {date}` — Compare with previous evaluation

## Reasoning

Think step by step:
1. First: identify the agent and load its golden set from `tests/evals/{agent}/`
2. Then: for each input-N/expected-N pair, invoke the agent and compare output vs expected
3. Calculate: precision, recall, F1, false positives, hallucinations, bias score
4. Finally: save results and detect regressions vs previous evaluations

## Flow

1. **List mode**: if `$ARGUMENTS` is empty or `--list`, run `bash scripts/eval-agent.sh --list`
2. **Validate**: confirm `tests/evals/{agent}/` exists with input/expected pairs
3. **Generate template**: `bash scripts/eval-agent.sh {agent}` creates output file
4. **Evaluate each pair**:
   - Read `input-N.*` and `expected-N.yaml`
   - Invoke the agent as a subagent (Task) with the input
   - Compare agent output against expected findings
   - Score: did it find what it should? Did it NOT find what it shouldn't?
5. **Calculate metrics**:
   - `precision` = correct findings / total findings reported
   - `recall` = findings detected / findings in golden set (must_detect: true)
   - `f1` = 2 * (precision * recall) / (precision + recall)
   - `false_positives` = findings reported that aren't in expected
   - `hallucinations` = claims with no support in the input
   - `bias_score` = 0.0 if Equality Shield passes counterfactual test
6. **Save results**: update the YAML file in `output/evals/{agent}/`
7. **Regression check**: if precision or recall drops >10% vs previous → alert

## Regression Detection

```
REGRESSION DETECTED in {agent}
  Precision: 85% -> 72% (-13%)
  Probable cause: prompt change in Era {N}
  Action: review commit that modified the agent
```

## Output Template

```yaml
agent: {agent}
date: "{date}"
golden_set: "tests/evals/{agent}/"
pairs_evaluated: N
metrics:
  precision: 0.XX
  recall: 0.XX
  f1: 0.XX
  false_positives: N
  hallucinations: N
  bias_score: 0.0
status: "completed"
comparison:
  vs_previous: "+X% precision, -Y% recall"
```

## Banner

```
/eval-agent {agent} — Agent Evaluation (SPEC-036)
Golden set: tests/evals/{agent}/ (N pairs)
```

> Rules: @docs/rules/domain/eval-criteria.md
> Source: @docs/propuestas/SPEC-036-agent-evaluation.md
