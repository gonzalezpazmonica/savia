#!/usr/bin/env python3
"""lexical-strip.py — SPEC-192 Layer 1: deterministic adulation pattern detector.

Loads regex patterns from a JSON file (default: regex-patterns.json next to
this script), matches them against an input draft, and reports the first
match with position and category. Used by the sycophancy-strip.sh hook and
by tests.

Stdlib only. No external deps.

Usage:
    python3 scripts/anti-adulation/lexical-strip.py \
        --draft "Buena pregunta. La respuesta es X" \
        [--patterns scripts/anti-adulation/regex-patterns.json] \
        --json

    --draft - reads the draft from stdin (no ARG_MAX limit; the hook uses it).

Output (--json):
    {
      "score": int (0-100),
      "category": "obvious" | "subtle" | "none",
      "pattern": str (the regex that matched, or empty),
      "position": int (char offset of match start, -1 if no match),
      "stripped": str (draft with the matched span removed)
    }

Score table:
    none           -> 0
    subtle match   -> 50
    obvious match  -> 90
    obvious match in first 50 chars -> 95

Exit codes:
    0  ok (always; result in JSON)
    2  bad arguments
    3  patterns file unreadable, not valid JSON or with an invalid regex

Ref: SPEC-192 docs/propuestas/SPEC-192-anti-adulation-illusory-truth.md
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from functools import lru_cache
from pathlib import Path

DEFAULT_PATTERNS = Path(__file__).parent / "regex-patterns.json"


@lru_cache(maxsize=4)
def _compile_patterns(patterns_path_str: str) -> tuple[tuple[str, re.Pattern], ...]:
    """Load and compile patterns, cached by path string.

    Returns a tuple of (category, compiled_regex) so callers can iterate in
    deterministic order: obvious patterns first, then subtle.
    """
    path = Path(patterns_path_str)
    if not path.exists():
        raise FileNotFoundError(f"Patterns file not found: {path}")
    raw = json.loads(path.read_text(encoding="utf-8"))
    out: list[tuple[str, re.Pattern]] = []
    for category in ("obvious", "subtle"):
        for raw_pat in raw.get(category, []):
            out.append((category, re.compile(raw_pat, re.IGNORECASE)))
    return tuple(out)


def detect(draft: str, patterns_path: Path = DEFAULT_PATTERNS) -> dict:
    """Match a draft against the patterns file and return a result dict.

    Returns the FIRST match found (obvious patterns first, then subtle, in
    file order). If no match, returns category="none", score=0.
    """
    if not draft:
        return {"score": 0, "category": "none", "pattern": "", "position": -1, "stripped": draft}

    compiled = _compile_patterns(str(patterns_path))
    for category, regex in compiled:
        m = regex.search(draft)
        if m:
            position = m.start()
            score = 50 if category == "subtle" else 90
            if category == "obvious" and position < 50:
                score = 95
            stripped = draft[: m.start()] + draft[m.end():]
            stripped = stripped.lstrip(" ,.;:!*_")
            return {
                "score": score,
                "category": category,
                "pattern": regex.pattern,
                "position": position,
                "stripped": stripped,
            }
    return {"score": 0, "category": "none", "pattern": "", "position": -1, "stripped": draft}


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="lexical-strip",
        description="SPEC-192 Layer 1: detect adulation patterns in a draft.",
    )
    p.add_argument("--draft", required=True, help="Text to analyze (the LLM draft); '-' reads stdin")
    p.add_argument(
        "--patterns",
        default=str(DEFAULT_PATTERNS),
        help=f"Path to regex-patterns.json (default: {DEFAULT_PATTERNS})",
    )
    p.add_argument("--json", action="store_true", help="Emit JSON to stdout")
    return p


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    draft = sys.stdin.read() if args.draft == "-" else args.draft
    try:
        result = detect(draft, Path(args.patterns))
    except (FileNotFoundError, ValueError, re.error) as exc:
        # ValueError covers json.JSONDecodeError. The hook treats exit 3 as fail-open.
        print(f"lexical-strip: {exc}", file=sys.stderr)
        return 3
    if args.json:
        sys.stdout.write(json.dumps(result, ensure_ascii=False) + "\n")
    else:
        sys.stdout.write(f"score={result['score']} category={result['category']} ")
        sys.stdout.write(f"pos={result['position']} pattern={result['pattern']!r}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
