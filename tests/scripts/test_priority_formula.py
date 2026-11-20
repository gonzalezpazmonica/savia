"""
SPEC-154 — Tests para la fórmula canónica V×U/E.
pytest ≥ 15 tests cubriendo AC-01..AC-07 y adapters.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

# Add scripts to path
SCRIPTS = Path(__file__).parent.parent.parent / "scripts"
sys.path.insert(0, str(SCRIPTS))
sys.path.insert(0, str(SCRIPTS / "priority"))
sys.path.insert(0, str(SCRIPTS / "priority" / "adapters"))

from priority.score import (
    PriorityEffort,
    PriorityInput,
    PriorityOutput,
    normalize_effort,
    score,
)
from priority.adapters.rice_to_vue import rice_to_vue
from priority.adapters.wsjf_to_vue import wsjf_to_vue
from priority.adapters.adhoc_to_vue import adhoc_to_vue, ADHOC_CONFIDENCE


# ---------------------------------------------------------------------------
# AC-01 — Idempotencia: función pura
# ---------------------------------------------------------------------------

def make_sample_input() -> PriorityInput:
    return PriorityInput(
        value=80,
        urgency=70,
        effort=PriorityEffort(tokens=5000, human_review_hours=4.0, regression_risk=2, cognitive_complexity=3),
        item_id="TEST-001",
        context="sample context",
    )


def test_idempotency_100_calls():
    """AC-01: 100 invocaciones con mismo input → mismo output."""
    item = make_sample_input()
    results = [score(item) for _ in range(100)]
    scores = [r.priority_score for r in results]
    assert len(set(scores)) == 1, f"Non-idempotent scores: {set(scores)}"


def test_idempotency_decision_trail():
    """AC-01: decision_trail idéntico en 10 invocaciones."""
    item = make_sample_input()
    trails = [score(item).decision_trail for _ in range(10)]
    assert len(set(trails)) == 1


# ---------------------------------------------------------------------------
# effort_normalized en [1, 100]
# ---------------------------------------------------------------------------

def test_effort_normalized_min():
    """effort_normalized nunca < 1."""
    e = PriorityEffort(tokens=0, human_review_hours=0.0, regression_risk=1, cognitive_complexity=1)
    assert normalize_effort(e) >= 1


def test_effort_normalized_max():
    """effort_normalized nunca > 100."""
    e = PriorityEffort(tokens=1_000_000, human_review_hours=100.0, regression_risk=5, cognitive_complexity=5)
    assert normalize_effort(e) <= 100


def test_effort_normalized_range_exhaustive():
    """effort_normalized siempre en [1, 100] para boundary values."""
    cases = [
        PriorityEffort(0, 0.0, 1, 1),
        PriorityEffort(50_000, 8.0, 5, 5),
        PriorityEffort(1, 0.08, 1, 1),
    ]
    for e in cases:
        en = normalize_effort(e)
        assert 1 <= en <= 100, f"Out of range: {en} for {e}"


# ---------------------------------------------------------------------------
# score > 0 siempre
# ---------------------------------------------------------------------------

def test_score_always_positive():
    """score > 0 para cualquier input válido."""
    cases = [
        PriorityInput(1, 1, PriorityEffort(0, 0.0, 1, 1)),
        PriorityInput(100, 100, PriorityEffort(1_000_000, 100.0, 5, 5)),
        PriorityInput(50, 50, PriorityEffort(0, 1.0, 3, 3)),
    ]
    for item in cases:
        out = score(item)
        assert out.priority_score > 0, f"Non-positive score for {item}"


# ---------------------------------------------------------------------------
# Valor más alto → score mayor (ceteris paribus)
# ---------------------------------------------------------------------------

def test_higher_value_higher_score():
    """Ceteris paribus: value 90 > value 40 → score mayor."""
    effort = PriorityEffort(tokens=1000, human_review_hours=2.0, regression_risk=2, cognitive_complexity=2)
    low = score(PriorityInput(value=40, urgency=50, effort=effort))
    high = score(PriorityInput(value=90, urgency=50, effort=effort))
    assert high.priority_score > low.priority_score


def test_higher_urgency_higher_score():
    """Ceteris paribus: urgency 90 > urgency 20 → score mayor."""
    effort = PriorityEffort(tokens=1000, human_review_hours=2.0, regression_risk=2, cognitive_complexity=2)
    low = score(PriorityInput(value=50, urgency=20, effort=effort))
    high = score(PriorityInput(value=50, urgency=90, effort=effort))
    assert high.priority_score > low.priority_score


# ---------------------------------------------------------------------------
# Counterfactual: esfuerzo mayor → score menor
# ---------------------------------------------------------------------------

def test_counterfactual_higher_effort_lower_score():
    """AC-06: Si effort sube 20%, score baja."""
    item = make_sample_input()
    out = score(item)
    # Extract counterfactual score
    cf_score = float(out.counterfactual.split("score=")[1])
    assert cf_score < out.priority_score, (
        f"Counterfactual score {cf_score} should be < original {out.priority_score}"
    )


def test_counterfactual_non_empty():
    """AC-06: counterfactual siempre no vacío."""
    out = score(make_sample_input())
    assert out.counterfactual
    assert "score=" in out.counterfactual


# ---------------------------------------------------------------------------
# Adapters
# ---------------------------------------------------------------------------

def test_rice_to_vue_valid_output():
    """Adapter RICE produce PriorityInput válido con campos en rango."""
    inp = rice_to_vue(reach=5000, impact=2.0, confidence=0.8, effort_weeks=2.0, item_id="RICE-01")
    assert hasattr(inp, "value") and hasattr(inp, "urgency") and hasattr(inp, "effort")
    assert 1 <= inp.value <= 100
    assert 1 <= inp.urgency <= 100
    assert inp.effort.human_review_hours > 0


def test_rice_to_vue_produces_positive_score():
    """rice_to_vue → score() → priority_score > 0."""
    inp = rice_to_vue(reach=1000, impact=1.0, confidence=0.7, effort_weeks=1.0)
    out = score(inp)
    assert out.priority_score > 0


def test_wsjf_to_vue_valid_output():
    """Adapter WSJF produce PriorityInput válido."""
    inp = wsjf_to_vue(business_value=70, time_criticality=60, risk_reduction=50, job_size=40)
    assert hasattr(inp, "value") and hasattr(inp, "urgency") and hasattr(inp, "effort")
    assert 1 <= inp.value <= 100
    assert 1 <= inp.urgency <= 100


def test_wsjf_to_vue_produces_positive_score():
    """wsjf_to_vue → score() → priority_score > 0."""
    inp = wsjf_to_vue(business_value=80, time_criticality=70, risk_reduction=60, job_size=30)
    out = score(inp)
    assert out.priority_score > 0


def test_adhoc_to_vue_confidence_below_one():
    """AC: adhoc_to_vue confidence < 1.0 (heuristic approximation)."""
    # confidence is baked in as ADHOC_CONFIDENCE constant
    assert ADHOC_CONFIDENCE < 1.0


def test_adhoc_to_vue_dampened_values():
    """adhoc_to_vue values are dampened by confidence factor."""
    inp = adhoc_to_vue(priority="high", effort="m")
    # With confidence=0.65, value should be < 90 (high priority raw value)
    assert inp.value < 90
    assert inp.urgency < 95


def test_adhoc_to_vue_warning_in_context():
    """adhoc_to_vue includes warning about heuristic nature."""
    inp = adhoc_to_vue(priority="medium", effort="l")
    assert "WARNING" in inp.context or "heuristic" in inp.context.lower()


def test_adhoc_to_vue_invalid_priority_raises():
    """adhoc_to_vue raises ValueError for unknown priority."""
    with pytest.raises(ValueError, match="Unknown priority"):
        adhoc_to_vue(priority="ultra-critical", effort="m")


def test_adhoc_to_vue_invalid_effort_raises():
    """adhoc_to_vue raises ValueError for unknown effort."""
    with pytest.raises(ValueError, match="Unknown effort"):
        adhoc_to_vue(priority="high", effort="xxl")
