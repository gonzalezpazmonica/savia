---
name: comprehension-report
description: Generate mental model report for an implemented task. Documents architectural decisions, failure heuristics, and 3AM debugging guide.
argument-hint: "[task-id]"
allowed-tools:
  - Read
  - Glob
  - Grep
model_tier: heavy
context_cost: medium
tier: core
---

# /comprehension-report

Generate a comprehensive mental model document explaining the architecture decisions, failure points, and debugging heuristics for an implemented feature or fix.

## Usage

```
/comprehension-report {task-id}
```

### Arguments

- `{task-id}` (required): Task identifier from your PM tool
  - Azure DevOps format: `AB#1234` (project + work item ID)
  - Savia Flow format: `sprint-12/feature-auth`
  - Commit hash: auto-detects associated task from commit message

## What Gets Generated

1. **Architecture Decisions** — Why each design choice was made
2. **Data Flow Diagram** — Mermaid diagram showing inputs/processing/outputs
3. **Failure Heuristics** — "If X fails, look at Y, check metric Z" for each module
4. **Implicit Dependencies** — Runtime, config, data format, external service assumptions
5. **3AM Debugging Guide** — Step-by-step procedures for on-call diagnosis
6. **Appendix** — Agent notes, spec excerpt, test results summary

## Output

```
📊 Mental Model Report Generated
├─ Main report: output/comprehension/YYYYMMDD-{task-id}-mental-model.md
├─ Flow diagram: output/comprehension/YYYYMMDD-{task-id}-flow.mermaid
└─ PNG export: output/comprehension/YYYYMMDD-{task-id}-flow.png

Coherence: 92%
Completeness: 5 modules, 8 failure scenarios, 6 implicit dependencies
Páginas: 7 (1-page TL;DR + detailed sections)

⏱️ Duración: ~3 min
```

## Example

```
/comprehension-report AB#2847
```

Generates report for User Authentication feature (Azure DevOps AB#2847):
- Explains why JWT validation uses RS256 instead of HS256
- Documents failure mode: "If token validation fails with 'InvalidSignature', 
  it's probably cert rotation. Check /var/log/auth and certctl list."
- Lists implicit dependencies: clock skew tolerance, secret versioning, 
  role mapping table updates
- Provides 3AM steps: verify cert is loaded, check token format, validate claims

## When to Use

- ✅ After implementing a feature (creates on-call knowledge)
- ✅ After fixing a complex bug (documents what was wrong and how to prevent)
- ✅ Onboarding new team members (explains "why" without reading code)
- ✅ Before a production deployment (pre-flight checks documented)
- ✅ Post-incident review (explains how monitors should have caught it)

## Workflow

**Phase 1: Data Collection**
- Locate task in PM tool
- Load associated spec
- Find implemented code files
- Extract test results

**Phase 2-6: Analysis** (architect agent)
- Architecture decisions from spec vs. code
- Flow diagram from code structure
- Failure heuristics by module
- Implicit dependencies from config/tests
- 3AM guide from test scenarios

**Phase 7: Report Generation**
- Compile markdown document
- Render Mermaid diagrams
- Coherence validation
- Save to output/comprehension/

## Prerequisitos

- Task completed and tests passing
- Code committed with traceable commit message
- Spec available (from task or `/spec-generate`)
- Implemented code files readable in project directory

## Integration

Recommended workflow:
```
/spec-generate AB#2847           # create spec
/dev-session start AB#2847       # implement
/dev-session review              # validate implementation
/comprehension-report AB#2847    # generate mental model ← You are here
/board-flow --refresh            # mark complete
```

## Output Locale

Reports generated in **Spanish** for user-facing sections, **English** for
code excerpts and technical references (follows pm-workspace locale standard).

**Siguiente paso:** Revisar el reporte, compararlo contra el spec, y usarlo
para actualizar la documentación de tu proyecto.
