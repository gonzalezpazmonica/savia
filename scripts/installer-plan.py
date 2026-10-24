#!/usr/bin/env python3
"""installer-plan.py — SE-399 F1: read-only installation plan preview.

Usage: installer-plan.py --manifests DIR --host FIXTURE.json --select ID [--select ID ...]
Prints the deterministic plan as JSON. Exit 0 ready, 2 blocked, 1 invalid input.
Executes nothing and installs nothing.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provisioning.adapter import FixtureAdapter  # noqa: E402
from provisioning.planner import build_plan, find_secrets, load_manifests, validate  # noqa: E402


class _Parser(argparse.ArgumentParser):
    """Usage errors exit 1 (invalid input); exit 2 is reserved for a blocked plan."""

    def error(self, message):
        self.print_usage(sys.stderr)
        print(f"ERROR: {message}", file=sys.stderr)
        sys.exit(1)


def main() -> int:
    ap = _Parser(description=__doc__)
    ap.add_argument("--manifests", required=True)
    ap.add_argument("--host", required=True, help="fixture JSON for the fake platform adapter")
    ap.add_argument("--select", action="append", required=True)
    a = ap.parse_args()
    try:
        plan = build_plan(load_manifests(a.manifests), FixtureAdapter(a.host).discover(), a.select)
    except (ValueError, OSError, KeyError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    errs = validate(plan, "installation-plan") or [f"secret-like content at {p}" for p in find_secrets(plan)]
    if errs:
        print(f"ERROR: plan failed self-check: {errs[0]}", file=sys.stderr)
        return 1
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 2 if plan["status"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
