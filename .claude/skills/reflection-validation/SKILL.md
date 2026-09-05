---
layer: peripheral
name: reflection-validation
description: Usar cuando una respuesta o decisión importante necesita validación metacognitiva (System 2).
allowed-tools: [Read, Glob, Grep]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: governance
  savia.maturity: stable
  savia.context_cost: medium
  savia.disable-model-invocation: false
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Validacion meta-cognitiva (System 2): detecta proxy optimization, supuestos no declarados y cadenas causales rotas. Usa reflection-validator agent. Output: VALIDATED/CORRECTED/RETHINK."
  savia.tags: "reflection, meta-cognitive, system2, assumptions"
  savia.user-invocable: False
---
# Reflection Validation — System 2 Protocol

> Thinking fast catches the obvious. Thinking slow catches the real.

## Purpose

Structured meta-cognition cycle — "wait, does that actually work?" — that
humans do naturally but LLMs typically skip. Based on Kahneman's dual-process
theory: System 1 (fast, heuristic) vs. System 2 (slow, deliberate).

---

## The 5-Step Protocol

### Step 1 — Extract the Real Objective

Re-read the question. Distinguish between:

| Layer | Question | Example |
|---|---|---|
| **Literal** | What was asked | "Walk or drive to the car wash 50m away?" |
| **Real** | What needs to happen | "The car must end up washed" |
| **Implicit** | Unstated constraints | "The car must be AT the wash" |

**Key question**: Does the literal objective match the real one?

### Step 2 — Assumption Audit

List ALL implicit assumptions in the response:
1. What was taken for granted?
2. What context was ignored?
3. Was the right variable optimized?
4. What domain knowledge was assumed vs. verified?

**Minimum 3 assumptions** per response. Mark each valid/invalid.

### Step 3 — Mental Simulation

Walk through the recommendation step by step:
1. If the user follows this advice, what happens at each step?
2. Does the causal chain lead to the real objective?
3. Is there a broken link?

**Template**: "User does X → Y happens → Z → ... → objective achieved?"
If ANY step produces "???" → the chain is broken.

### Step 4 — Gap Detection

Identify where the chain fails:

| Gap Type | Description |
|---|---|
| **Missing prerequisite** | Something must exist/happen first |
| **Wrong optimization** | Correct metric, wrong variable |
| **Ignored constraint** | Real-world limitation missed |
| **Anchoring bias** | Fixated on one detail |
| **Satisficing** | First plausible answer, unchecked |
| **Narrow framing** | Only one dimension considered |

### Step 5 — Transparent Correction

**If gap detected:**
```
Thinking: [initial reasoning and why it seemed correct]
But: [what was missed and why it matters]
Because: [the real objective requires X, not Y]
Corrected: [the right answer with full reasoning]
```

**If NO gap detected:**
```
Validation: Response passes System 2 check.
Objective alignment: [confirmed] | Assumptions: [all valid] | Chain: [complete]
```

---

## Cognitive Bias Taxonomy

| Bias / Error | Detection Step | Signal |
|---|---|---|
| Proxy optimization | Step 1 | Literal ≠ real objective |
| Undeclared assumption | Step 2 | "Obviously..." or implicit context |
| Broken causal chain | Step 3 | Step produces "???" |
| Anchoring | Step 1 | One detail dominates reasoning |
| Satisficing | Step 4 | No active search for flaws |
| Narrow framing | Step 2 | Only one dimension considered |
| Confirmation bias | Step 4 | Evidence only supports, never challenges |
| Sunk cost reasoning | Step 1 | Past effort justifies current path |

---

## Embeddable Pattern

Agents can include this block to activate internal reflection without
invoking the external `reflection-validator` agent:

```markdown
## Post-Response Reflection (System 2)
Before delivering your final response, run internally:
1. What is the REAL objective, not the literal one?
2. What did I assume implicitly? List 3 assumptions.
3. If the user follows my advice step by step, do they reach the goal?
4. Is there a broken link in the chain?
If you find a gap → correct and show the reasoning change.
```

---

## Output Format

The `reflection-validator` agent produces a structured report:

```
═══════════════════════════════════════════════
  REFLECTION VALIDATOR — System 2 Analysis
═══════════════════════════════════════════════
  Question .............. [original question]
  Response evaluated .... [summary]
  ── Step 1: Real Objective ─────────────────
  Literal / Real / Match? YES|NO
  ── Step 2: Assumptions ────────────────────
  1-3 assumptions — valid / invalid
  ── Step 3: Simulation ─────────────────────
  Causal chain — reaches objective? YES|NO
  ── Step 4: Gaps ───────────────────────────
  Gaps or "No gaps detected"
  ── Step 5: Verdict ────────────────────────
  VALIDATED / CORRECTED / REQUIRES_RETHINKING
═══════════════════════════════════════════════
```
## Integration
- **`reflection-validator` agent**: applies this protocol to any input; other agents reference the Embeddable Pattern via `@`
