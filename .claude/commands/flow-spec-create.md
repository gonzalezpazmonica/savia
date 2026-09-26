---
name: flow-spec-create
description: Create a new SDD specification document
argument-hint: "<spec_id> <title>"
allowed-tools: [Bash, Write]
model_tier: mid
context_cost: medium
tier: core
---

# Create SDD Specification

**Arguments:** $ARGUMENTS

## Parámetros

- `<spec_id>` — Specification identifier (SPEC-YYYY-NNN)
- `<title>` — Specification title

## Estructura

Crea spec/.../SPEC-{id}.md con:
- Design Goals
- API Contracts
- Data Models
- Implementation Notes
