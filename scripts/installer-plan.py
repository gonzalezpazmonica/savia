#!/usr/bin/env python3
"""installer-plan.py — SE-399 F1: read-only installation plan preview.

Usage: installer-plan.py --manifests DIR (--host FIXTURE.json | --local) --select ID [--select ID ...]
       installer-plan.py --manifests DIR (--host FIXTURE.json | --local) --retire ID
Prints the deterministic plan (or the retirement report) as JSON. Exit 0 ready, 2 blocked or
retirement unsafe, 1 invalid input. --local detects the real host read-only (no commands run).
Executes nothing and installs nothing.
"""
from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from provisioning.adapter import FixtureAdapter  # noqa: E402
from provisioning.graph import retirement  # noqa: E402
from provisioning.local import LocalAdapter  # noqa: E402
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
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--host", help="fixture JSON for the fake platform adapter")
    src.add_argument("--local", action="store_true", help="detect the real host (read-only, runs nothing)")
    act = ap.add_mutually_exclusive_group(required=True)
    act.add_argument("--select", action="append")
    act.add_argument("--retire", metavar="ID", help="report what depends on ID (can it be removed safely?)")
    a = ap.parse_args()
    try:
        manifests = load_manifests(a.manifests)
        host = (LocalAdapter(manifests) if a.local else FixtureAdapter(a.host)).discover()
        if a.retire:
            if a.retire not in manifests and a.retire not in host.installed:
                print(f"ERROR: unknown component(s): {a.retire}", file=sys.stderr)
                return 1
            report = retirement(manifests, set(host.installed), a.retire)
            print(json.dumps(report, indent=2, sort_keys=True))
            return 0 if report["safe"] else 2
        unknown = sorted(set(a.select) - set(manifests) - set(host.installed))
        if unknown:  # a mistyped id is invalid input, not a blocked plan
            print(f"ERROR: unknown component(s): {', '.join(unknown)}", file=sys.stderr)
            return 1
        plan = build_plan(manifests, host, a.select)
    except (ValueError, OSError, KeyError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1
    errs = validate(plan, "installation-plan")
    if errs:  # schema messages carry paths, never document values
        print(f"ERROR: plan failed self-check: {errs[0]}", file=sys.stderr)
        return 1
    hits = len(find_secrets(plan))
    if hits:  # report only the count: the matched content must not reach logs
        print(f"ERROR: plan failed self-check: secret-like content in {hits} location(s)", file=sys.stderr)
        return 1
    print(json.dumps(plan, indent=2, sort_keys=True))
    return 2 if plan["status"] == "blocked" else 0


if __name__ == "__main__":
    sys.exit(main())
