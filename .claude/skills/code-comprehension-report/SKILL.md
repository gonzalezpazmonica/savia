---
layer: peripheral
name: code-comprehension-report
description: Usar cuando se ha completado una implementación SDD y se necesita documentar el modelo mental.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: sdd-framework
  savia.context: fork
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Genera modelo mental post-implementacion: decisiones, heuristicas de fallo y guia de debugging 3AM. Pipeline 7 fases. Output: comprehension report en output/."
  savia.tags: "comprehension, mental-model, debugging, documentation"
---

# Code Comprehension Report — Mental Model Generation

Addresses AI-generated code opacity. After each SDD dev-session, auto-generate a mental model document explaining implementation decisions, failure points, debugging heuristics, and implicit dependencies.

## When to Use

- After implementing a feature (post-SDD completion)
- After fixing a complex bug
- When onboarding new team members to undocumented code
- When code lacks sufficient inline documentation
- User asks to `/comprehension-report {task-id}`

## 7-Phase Pipeline

### Phase 1: Collect Implementation Data (5 min)

- **Input**: spec path, git commit hash, or task ID
- **Collect**: SDD spec, implemented code files, test results, agent notes
- **Verify**: code compiles, tests pass, spec is complete
- **Store**: in `output/dev-sessions/{task-id}/phase-1-data.md`

### Phase 2: Architecture Decisions (10 min)

- **List each decision**: made during implementation
- **For each decision**:
  - Why it was chosen (trade-offs considered)
  - Alternatives discarded (with reason)
  - Key assumptions underlying the decision
  - Risks or caveats if violated

Output: table format with Decision | Rationale | Alternatives | Risks

### Phase 3: Flow Diagram (5 min)

- **Generate Mermaid diagram** of the change:
  - Data flow (inputs → processing → outputs)
  - Call chain (entry points → internal calls → external deps)
  - State transitions if applicable
  - External integrations highlighted

Output: `.mermaid` file embedded in report + PNG export

### Phase 4: Failure Heuristics (15 min)

**For each module touched**: "If this fails, it's probably X. Look at Y. Key metric: Z"

Template: see `references/schemas.md`

### Phase 5: Implicit Dependencies (8 min)

**List dependencies introduced that aren't obvious from imports:**

- **Runtime deps**: required services, databases, caches (not just NuGet)
- **Config deps**: environment variables, feature flags, settings
- **Data format assumptions**: field ordering, encoding, version compatibility
- **External service deps**: third-party APIs, webhooks, message queues
- **Timing deps**: race conditions, retry policies, timeouts

Format: table with Dependency Type | What's Required | Impact if Missing

### Phase 6: 3AM Debugging Guide (12 min)

**Concrete steps an on-call engineer would follow** to diagnose issues at 3 AM without context:

**Step-by-step procedures:**
1. Verify prerequisites (service running, DB accessible, env vars set)
2. Check logs at key points (entry, error handling, exit)
3. Inspect state (cache state, queue depth, last transaction)
4. Common fixes (restart service, clear cache, check disk space)
5. Escalation path (who to call, what to provide)

**For each common failure scenario:**
- Symptom (what the user reports)
- Immediate check (5 min diagnosis)
- Root cause areas (3-5 places to look)
- Fix (if it's a quick win) or escalation

### Phase 7: Generate Report (5 min)

- **Compile all phases** into single markdown document
- **Save to**: `output/comprehension/YYYYMMDD-{task-id}-mental-model.md`
- **Format**: 
  - Summary (1 page TL;DR)
  - Architecture decisions (1 page)
  - Flow diagram (visual)
  - Failure heuristics (2 pages, by module)
  - Implicit dependencies (1 page)
  - 3AM guide (2 pages)
  - Appendix: agent notes, spec excerpt
- **Quality check**: coherence validator confirms completeness

## Schemas

Input/output schemas and templates: `references/schemas.md`

## Quality Gates

- **Phase 1**: All input files exist and are readable
- **Phase 2**: ≥3 decisions documented, each with alternatives
- **Phase 3**: Mermaid diagram renders without error
- **Phase 4**: ≥2 failure heuristics per module touched
- **Phase 5**: ≥5 implicit dependencies documented
- **Phase 6**: ≥3 steps per common scenario, escalation clear
- **Phase 7**: Report ≤ 15 pages, coherence ≥ 85%

## Limitations

- Does NOT re-implement the feature (read-only operation)
- Does NOT modify code or specs
- Assumes code compiles and tests pass
- Spanish user-facing, technical content may be English (code comments, schema names)

## Integration

Triggered by:
- `/comprehension-report {task-id}` — generate on demand
- `/dev-session` auto-completion (optional post-session)
- `/spec-completion` → "Generate mental model? [y/n]"

Used by:
- Team onboarding: new developers understand decisions + caveats
- Postmortem analysis: why a bug occurred, prevented mechanisms
- Code review: reviewers understand intent before reading code

## Related Skills

- `.opencode/skills/spec-driven-development/SKILL.md` — generates specs that feed this skill
- `.opencode/skills/code-review/SKILL.md` — uses comprehension as context for better reviews
