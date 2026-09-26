---
name: pipeline-local-run
description: "Run a local pipeline defined as YAML — no Jenkins/Azure Pipelines needed"
model_tier: mid
context_cost: medium
allowed-tools: [Read, Bash, Glob]
argument-hint: "<pipeline.yaml> [--dry-run]"
tier: core
---

# /pipeline-local-run

Execute a pipeline defined in `projects/{project}/pipelines/*.yaml`.

## Steps

1. Locate pipeline file (by name or path)
2. Parse stages from YAML definition
3. Execute stages respecting dependencies and parallelism
4. Log results to `output/pipeline-runs/{timestamp}/`
5. Show summary with pass/fail per stage

## Usage

```
/pipeline-local-run projects/my-project/pipelines/ci-main.yaml
/pipeline-local-run projects/my-project/pipelines/ci-main.yaml --dry-run
```

## Pipeline YAML format

See `.claude/templates/pipeline/ci-template.yaml` for full example.

## Stage types

- **command**: Direct bash command execution
- **agent**: Delegate to a Claude agent (test-runner, security-guardian, etc.)

## Safety

- Stages with `agent` type require Claude orchestration
- `--dry-run` shows what would execute without running
- Results always logged to `output/pipeline-runs/`
- NEVER deploys to production without explicit confirmation
