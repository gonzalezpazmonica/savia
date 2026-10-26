#!/usr/bin/env python3
"""
memory-feedback-extractor.py — Extract outcome signals from PostToolUse Task payloads.
Spec: SPEC-164 Slice 1

Input:  JSON (stdin) — PostToolUse hook payload
Output: JSON (stdout) — {outcome, agent_name, lesson, entropy_score, should_write}
"""
import sys
import json
import re


def extract(payload: dict) -> dict:
    """Extract outcome signals from a PostToolUse Task payload."""

    # ── 1. Extract tool output ─────────────────────────────────────────────
    output = ""
    # PostToolUse payload structures vary; try multiple paths
    tool_result = payload.get("tool_result", "")
    if isinstance(tool_result, str):
        output = tool_result
    elif isinstance(tool_result, dict):
        output = str(tool_result.get("content", "") or tool_result.get("output", "") or "")

    # Also try direct output field
    if not output:
        output = str(payload.get("output", "") or payload.get("result", "") or "")

    # ── 2. Determine outcome ──────────────────────────────────────────────
    failure_patterns = [
        r"\bERROR\b", r"\berror\b", r"\bFAIL(ED|URE)?\b", r"\bfail(ed)?\b",
        r"\bexception\b", r"\bException\b", r"\bTraceback\b", r"\btraceback\b",
        r"\bCritical\b", r"\bcritical\b", r"\bFATAL\b", r"\bfatal\b",
        r"\bAbort\b", r"\babort\b", r"\bCrash\b", r"\bcrash\b",
    ]
    outcome = "success"
    for pat in failure_patterns:
        if re.search(pat, output):
            outcome = "failure"
            break

    # ── 3. Extract agent name ─────────────────────────────────────────────
    agent_name = "unknown"
    tool_input = payload.get("tool_input", {})
    if isinstance(tool_input, dict):
        # OpenCode Task tool stores the subagent type here
        agent_name = (
            tool_input.get("subagent_type", "")
            or tool_input.get("agent", "")
            or tool_input.get("agent_name", "")
            or ""
        )
        if not agent_name:
            # Try to infer from description
            desc = str(tool_input.get("description", "") or tool_input.get("prompt", "") or "")
            if desc:
                # Take first word/identifier that looks like an agent name
                m = re.search(r"\b([a-z][a-z0-9-]+(?:-developer|-agent|-judge|-runner)?)\b", desc)
                if m:
                    agent_name = m.group(1)
    if not agent_name:
        agent_name = "unknown"

    # ── 4. Extract lesson ──────────────────────────────────────────────────
    lesson = _extract_lesson(output, outcome)

    # ── 5. Entropy score (heuristic: unique token density) ────────────────
    entropy_score = _compute_entropy(output)

    # ── 6. Should write? ──────────────────────────────────────────────────
    # Always write failures; write successes only if entropy > threshold
    should_write = (outcome == "failure") or (entropy_score > 0.3)

    return {
        "outcome": outcome,
        "agent_name": agent_name,
        "lesson": lesson[:150],
        "entropy_score": round(entropy_score, 4),
        "should_write": should_write,
    }


def _extract_lesson(output: str, outcome: str) -> str:
    """Extract a concise lesson (<=150 chars) from the output."""
    if not output:
        return f"Task completed with {outcome}"

    lines = [ln.strip() for ln in output.splitlines() if ln.strip()]
    if not lines:
        return f"Task completed with {outcome}"

    # For failures: look for the error line
    if outcome == "failure":
        for line in lines:
            if re.search(r"\b(ERROR|error|FAIL|fail|Exception|Traceback)\b", line):
                return line[:150]

    # For success: use the first meaningful non-trivial line
    for line in lines:
        # Skip very short or boilerplate lines
        if len(line) < 10:
            continue
        if re.match(r"^(ok|OK|done|Done|success|Success|completed|Completed)\s*$", line, re.I):
            continue
        return line[:150]

    return lines[0][:150]


def _compute_entropy(output: str) -> float:
    """
    Heuristic entropy score: ratio of unique tokens to output length.
    Simplified: len(output)/100, capped at 1.0.
    Trivial outputs (<50 tokens) always score 0.
    """
    if not output:
        return 0.0

    token_count = len(output.split())
    if token_count < 10:
        return 0.0

    # Unique token ratio (vocabulary richness)
    tokens = output.lower().split()
    unique_ratio = len(set(tokens)) / max(len(tokens), 1)

    # Scale by output size: small outputs score low
    size_factor = min(len(output) / 100.0, 1.0)

    score = unique_ratio * size_factor
    return min(score, 1.0)


def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            print(json.dumps({
                "outcome": "unknown",
                "agent_name": "unknown",
                "lesson": "",
                "entropy_score": 0.0,
                "should_write": False,
            }))
            return

        payload = json.loads(raw)
        result = extract(payload)
        print(json.dumps(result))
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError):
        # Fail gracefully — output a safe default
        print(json.dumps({
            "outcome": "unknown",
            "agent_name": "unknown",
            "lesson": "",
            "entropy_score": 0.0,
            "should_write": False,
        }))


if __name__ == "__main__":
    main()
