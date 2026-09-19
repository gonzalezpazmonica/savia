#!/usr/bin/env bash
# SE-397 F5A: controlled effect-parity and local hot-path benchmark.
set -euo pipefail

SE397_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SE397_ROOT
exec python3 - "$@" <<'PY'
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


TARGET = ".opencode/hooks/validate-bash-global.sh"
LIMITATIONS = [
    "LOCAL_CONTROLLED_CORPUS",
    "NO_PRODUCTION_SLO",
    "NO_CROSS_FRONTEND_CLAIM",
    "NO_AUTHORITY_EFFECT",
]


def fail(message: str) -> "None":
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(2)


def percentile(samples: list[int], ratio: float) -> int:
    ordered = sorted(samples)
    return ordered[max(0, math.ceil(len(ordered) * ratio) - 1)]


def safe_output(root: Path, value: str) -> Path:
    candidate = Path(value)
    if candidate.is_absolute():
        fail("--output must be relative and below output/")
    output_root = root / "output"
    relative = Path(os.path.normpath(value))
    if relative == Path("output") or not relative.parts or relative.parts[0] != "output":
        fail("--output must be below output/")
    if ".." in relative.parts:
        fail("--output path escape")
    current = root
    for part in relative.parts[:-1]:
        current = current / part
        if current.exists() and current.is_symlink():
            fail("--output parent cannot be a symlink")
    destination = root / relative
    if destination.exists() and (destination.is_symlink() or not destination.is_file()):
        fail("--output must be a regular non-symlink file")
    if destination.parent.exists() and not destination.parent.is_dir():
        fail("--output parent must be a directory")
    if output_root.exists() and output_root.is_symlink():
        fail("output/ cannot be a symlink")
    return destination


def normalized_digest(stderr: bytes, root: Path, fixture: Path) -> str:
    text = stderr.decode("utf-8", errors="replace")
    for path in sorted((str(root), str(fixture)), key=len, reverse=True):
        text = text.replace(path, "<PATH>")
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def invoke(hook: Path, payload: str, cwd: Path, root: Path, fixture: Path) -> tuple[int, str, int]:
    env = os.environ.copy()
    env["SAVIA_HOOK_PROFILE"] = "standard"
    env["CLAUDE_PROJECT_DIR"] = str(root)
    started = time.monotonic_ns()
    result = subprocess.run(
        ["bash", str(hook)],
        input=payload.encode("utf-8"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        cwd=cwd,
        env=env,
        check=False,
        timeout=10,
    )
    elapsed_ms = (time.monotonic_ns() - started) // 1_000_000
    return result.returncode, normalized_digest(result.stderr, root, fixture), elapsed_ms


def main() -> None:
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--hook", default=TARGET)
    parser.add_argument("--runs", default="30")
    parser.add_argument("--output", default="output/se397-f5/hot-path.json")
    args = parser.parse_args()

    if args.hook != TARGET:
        fail(f"--hook must equal {TARGET}")
    try:
        runs = int(args.runs)
    except ValueError:
        fail("--runs must be an integer")
    if not 3 <= runs <= 100:
        fail("--runs must be between 3 and 100")

    root = Path(os.environ["SE397_ROOT"])
    hook = root / TARGET
    if not hook.is_file():
        fail("target hook is missing")
    destination = safe_output(root, args.output)
    fixtures = root / "tests/fixtures/se397-f5"
    cases = json.loads((fixtures / "cases.json").read_text(encoding="utf-8"))
    oracle = json.loads((fixtures / "oracle.json").read_text(encoding="utf-8"))
    expected = {case["id"]: case for case in oracle["cases"]}

    samples: list[int] = []
    with tempfile.TemporaryDirectory(prefix="se397-f5-") as tmp:
        fixture = Path(tmp) / "savia"
        fixture.mkdir()
        subprocess.run(
            ["git", "init", "-q", "-b", "main"],
            cwd=fixture,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )
        subprocess.run(
            [
                "git", "-c", "user.name=SE-397 Fixture",
                "-c", "user.email=fixture@invalid.example",
                "commit", "-q", "--allow-empty", "-m", "fixture",
            ],
            cwd=fixture,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
        )

        for _ in range(runs):
            for case in cases["safe"]:
                status, digest, elapsed_ms = invoke(
                    hook, case["stdin"], root, root, fixture
                )
                if status != 0 or digest != hashlib.sha256(b"").hexdigest():
                    fail(f"safe corpus failure: {case['id']}")
                samples.append(elapsed_ms)

        matched = 0
        for case in cases["parity"]:
            if case["id"] not in expected:
                fail(f"oracle case missing: {case['id']}")
            cwd = fixture if case["cwd"] == "isolated_main" else root
            status, digest, _ = invoke(hook, case["stdin"], cwd, root, fixture)
            baseline = expected[case["id"]]
            if status != baseline["exit"] or digest != baseline["stderr_sha256"]:
                fail(f"PARITY_FAILURE: {case['id']}")
            matched += 1

    report = {
        "schema_version": 1,
        "report": "se397-f5-hot-path",
        "target": TARGET,
        "runs": runs,
        "safe": {
            "samples": len(samples),
            "min_ms": min(samples),
            "p50_ms": percentile(samples, 0.50),
            "p95_ms": percentile(samples, 0.95),
            "p99_ms": percentile(samples, 0.99),
            "max_ms": max(samples),
        },
        "parity": {
            "cases": len(cases["parity"]),
            "matched": matched,
            "status": "MATCH",
        },
        "limitations": LIMITATIONS,
    }
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.tmp-{os.getpid()}")
    temporary.write_text(
        json.dumps(report, ensure_ascii=True, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    temporary.replace(destination)
    print(str(destination.relative_to(root)))


if __name__ == "__main__":
    main()
PY
