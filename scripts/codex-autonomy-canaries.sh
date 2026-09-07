#!/usr/bin/env bash
# Contract tests plus real frontend probes. A policy-only PASS is not graduation.
set -uo pipefail
ROOT="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
python3 -m unittest discover -s "$ROOT/tests/dual-cli" -p 'test_autonomy.py' || exit 2
python3 "$ROOT/scripts/dual-cli/autonomy_doctor.py"
