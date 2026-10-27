#!/usr/bin/env python3
"""evals-paired-delta.py — SPEC-151 paired-delta calculation.

Compares baseline scores against current scores to detect regressions.
Uses paired-delta (per-test comparison) instead of aggregate pass-rate,
as recommended by DeepEval CI docs and Future AGI 2026.

Threshold: 5% degradation on mean_delta = fail.
Configurable via SAVIA_EVAL_DELTA_THRESHOLD env var.

Input:
  --baseline  path to baseline JSON (list of {id, score, ...})
  --current   path to current JSON  (list of {id, score, ...})

Output JSON:
  {mean_delta, std_delta, degradation_count, improvement_count,
   threshold_pass, threshold_used, pairs_evaluated}
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def load_scores(path: str) -> dict[str, float]:
    """Load scores from a JSON file. Returns {id: score}."""
    data = json.loads(Path(path).read_text())
    # Support both list-of-dicts and dict-of-dicts
    if isinstance(data, list):
        return {item["id"]: float(item["score"]) for item in data}
    if isinstance(data, dict):
        return {k: float(v["score"]) if isinstance(v, dict) else float(v) for k, v in data.items()}
    raise ValueError(f"Unexpected format in {path}")


def compute_paired_delta(
    baseline: dict[str, float],
    current: dict[str, float],
    threshold: float = 0.05,
) -> dict[str, Any]:
    """Compute paired delta between baseline and current score sets.

    Returns:
        mean_delta:        mean(current_score - baseline_score) per pair
        std_delta:         std dev of deltas
        degradation_count: number of pairs where delta < -threshold
        improvement_count: number of pairs where delta > 0
        threshold_pass:    True if mean_delta >= -threshold
        threshold_used:    threshold value applied
        pairs_evaluated:   number of matched pairs
    """
    # Only evaluate IDs present in both
    common_ids = sorted(set(baseline.keys()) & set(current.keys()))
    if not common_ids:
        return {
            "mean_delta": 0.0,
            "std_delta": 0.0,
            "degradation_count": 0,
            "improvement_count": 0,
            "threshold_pass": True,
            "threshold_used": threshold,
            "pairs_evaluated": 0,
            "warning": "no common IDs between baseline and current",
        }

    deltas = [current[id_] - baseline[id_] for id_ in common_ids]
    mean_delta = sum(deltas) / len(deltas)
    variance = sum((d - mean_delta) ** 2 for d in deltas) / len(deltas) if len(deltas) > 1 else 0.0
    std_delta = math.sqrt(variance)

    degradation_count = sum(1 for d in deltas if d < -threshold)
    improvement_count = sum(1 for d in deltas if d > 0)

    # Fail if mean_delta falls below -threshold (5% degradation on average)
    threshold_pass = mean_delta >= -threshold

    return {
        "mean_delta": round(mean_delta, 6),
        "std_delta": round(std_delta, 6),
        "degradation_count": degradation_count,
        "improvement_count": improvement_count,
        "threshold_pass": threshold_pass,
        "threshold_used": threshold,
        "pairs_evaluated": len(common_ids),
    }


# ── SE-468: honest dataset evaluation ─────────────────────────────────────────
# Result per dataset follows docs/rules/domain/gate-result-contract.md (SE-453):
# clean | findings | unknown, with gaps[{check, reason}]. A dataset is only
# evaluated when its artifact was executed and the sabotage run was detected.

LABELS = {"clean": "evaluado: sin degradación", "findings": "degradación", "unknown": "no evaluado"}
ARTIFACTS_MANIFEST = "artifacts.json"


def _entry(name: str, result: str, gaps: list[dict], **extra: Any) -> dict[str, Any]:
    entry = {
        "dataset": name, "result": result, "gaps": gaps, "label": LABELS[result],
        "baseline_score": None, "current_score": None, "delta": None,
        "threshold_pass": None, "sabotage_detected": None,
    }
    entry.update(extra)
    if result == "unknown":
        entry["threshold_pass"] = None
    return entry


def _mean(values: list[float]) -> float:
    return round(sum(values) / len(values), 4) if values else 0.0


def _execute(executor: str, name: str, artifact: Path, rows: list[dict]) -> dict[str, float] | None:
    """Run the executor once per row. None if any call fails, prints no score or a row id repeats."""
    env = dict(os.environ, SAVIA_EVAL_ARTIFACT=str(artifact), SAVIA_EVAL_DATASET=name)
    scores: dict[str, float] = {}
    for i, row in enumerate(rows):
        try:
            proc = subprocess.run(["bash", "-c", executor], input=json.dumps(row), text=True,
                                  capture_output=True, env=env, timeout=600)
            lines = proc.stdout.strip().splitlines()
            score = float(lines[-1]) if proc.returncode == 0 and lines else None
        except (subprocess.TimeoutExpired, ValueError, OSError):
            score = None
        if score is None or not 0.0 <= score <= 1.0:
            return None
        key = str(row.get("id", f"row-{i}"))
        if key in scores:
            return None
        scores[key] = score
    return scores


def evaluate_dataset(path: Path, root: Path, baselines_dir: Path, artifacts: dict[str, Any],
                     mode: str, threshold: float) -> dict[str, Any]:
    name = path.stem
    gaps: list[dict] = []
    baseline_file = baselines_dir / f"{name}-baseline.json"
    try:
        baseline = load_scores(str(baseline_file)) if baseline_file.is_file() else {}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return _entry(name, "unknown", [{"check": f"{name}/baseline", "reason": "unreadable"}])
    if not baseline:
        gaps.append({"check": name, "reason": "no_baseline"})
    artifact_rel = artifacts.get(name)
    artifact_path = None
    if mode == "mock":
        gaps.append({"check": name, "reason": "not_executed"})
    elif not artifact_rel:
        gaps.append({"check": f"{name}/artifact", "reason": "not_executed"})
    else:
        artifact_path = (root / str(artifact_rel)).resolve()
        if not artifact_path.is_relative_to(root.resolve()) or not artifact_path.is_file():
            gaps.append({"check": f"{name}/artifact", "reason": "unreadable"})
    base_extra = {"baseline_score": _mean(list(baseline.values())) if baseline else None}
    if gaps:
        return _entry(name, "unknown", gaps, **base_extra)

    unreadable = lambda check: _entry(name, "unknown", [{"check": f"{name}/{check}", "reason": "unreadable"}], **base_extra)
    try:
        rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    except (OSError, ValueError):
        return unreadable("dataset")
    if not rows or not all(isinstance(r, dict) for r in rows):
        return unreadable("dataset")
    executor = os.environ["SAVIA_EVAL_EXECUTOR"]
    current = _execute(executor, name, artifact_path, rows)
    with tempfile.NamedTemporaryFile(suffix=".md") as empty:
        sabotaged = _execute(executor, name, Path(empty.name), rows) if current is not None else None
    if current is None or sabotaged is None:
        return unreadable("executor")

    real = compute_paired_delta(baseline, current, threshold)
    # The sabotage run is compared with the real run: a baseline-relative test would hide a
    # discriminating executor whenever the baseline is low.
    sabotage = compute_paired_delta(current, sabotaged, threshold)
    if real["pairs_evaluated"] != len(baseline):
        # Every baseline row must be paired; a partial overlap proves nothing about the rest.
        return _entry(name, "unknown", [{"check": name, "reason": "no_baseline"}], **base_extra)
    extra = dict(base_extra, current_score=_mean(list(current.values())),
                 delta=real["mean_delta"], sabotage_detected=not sabotage["threshold_pass"])
    if not real["threshold_pass"]:
        # A degradation seen in the real run needs no sabotage proof: it cannot be a false green.
        return _entry(name, "findings", [], threshold_pass=False, **extra)
    if sabotage["threshold_pass"]:
        # The executor scored an empty artifact as well as the baseline: it is not measuring it.
        return _entry(name, "unknown", [{"check": f"{name}/sabotage", "reason": "not_executed"}], **extra)
    return _entry(name, "clean", [], threshold_pass=True, **extra)


def run_datasets(args: argparse.Namespace, threshold: float) -> int:
    datasets_dir = Path(args.datasets_dir)
    manifest = datasets_dir / ARTIFACTS_MANIFEST
    artifacts = json.loads(manifest.read_text()) if manifest.is_file() else {}
    files = sorted(datasets_dir.rglob("*.jsonl"))
    if args.dataset:
        files = [f for f in files if f.stem == args.dataset]
        if not files:
            print(json.dumps({"error": f"dataset '{args.dataset}' not found in {datasets_dir}"}), file=sys.stderr)
            return 1
    report = [evaluate_dataset(f, Path(args.root), Path(args.baselines_dir), artifacts, args.mode, threshold)
              for f in files]
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


def check_report(path: str) -> int:
    """Gate step: 1 on findings, 2 on unreadable report, 0 otherwise. Never calls unknown a pass."""
    try:
        report = json.loads(Path(path).read_text())
        results = [(r["dataset"], r["result"]) for r in report]
        if not all(isinstance(res, str) for _, res in results):
            raise TypeError("result must be a string")
        unknown_rows = [r for r in report if r["result"] == "unknown"]
        if any(not (r.get("gaps") or []) for r in unknown_rows):
            raise TypeError("unknown sin gaps: el contrato exige al menos un hueco")
        reasons = {id(r): ", ".join(f"{g['check']}:{g['reason']}" for g in r.get("gaps") or []) for r in unknown_rows}
    except (OSError, json.JSONDecodeError, KeyError, TypeError, AttributeError) as exc:
        print(f"ERROR: informe de evals ilegible ({exc!r}): sin veredicto.")
        return 2
    if not results or any(res not in LABELS for _, res in results):
        print("ERROR: informe sin resultado válido por dataset (clean|findings|unknown): sin veredicto.")
        return 2
    findings = [r for r in report if r["result"] == "findings"]
    clean = [r["dataset"] for r in report if r["result"] == "clean"]
    if findings:
        print("DEGRADATION DETECTED:")
        for r in findings:
            print(f"  {r['dataset']}: delta={r.get('delta')}")
    if unknown_rows:
        print(f"UNKNOWN (no evaluado, sin veredicto): {len(unknown_rows)} dataset(s)")
        print(f"::warning::evals: {len(unknown_rows)} dataset(s) sin evaluar (unknown); no es un verde")
        for r in unknown_rows:
            print(f"  {r['dataset']}: {reasons[id(r)]}")
    if clean:
        print(f"PASS (evaluado y sin degradación): {', '.join(clean)}")
    if unknown_rows and os.environ.get("SAVIA_GATE_UNKNOWN") == "block":
        return 1
    return 1 if findings else 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compute paired-delta between eval baseline and current results.",
    )
    parser.add_argument("--baseline", metavar="PATH", help="Path to baseline JSON scores")
    parser.add_argument("--current", metavar="PATH", help="Path to current JSON scores")
    parser.add_argument("--threshold", type=float, default=None, metavar="FLOAT",
                        help="Degradation threshold (default: SAVIA_EVAL_DELTA_THRESHOLD or 0.05)")
    parser.add_argument("--check-report", metavar="PATH",
                        help="Gate step over an evals-runner report (SE-468)")
    parser.add_argument("--run-datasets", action="store_true", help="Evaluate datasets (used by evals-runner.sh)")
    parser.add_argument("--root", default=".")
    parser.add_argument("--datasets-dir")
    parser.add_argument("--baselines-dir")
    parser.add_argument("--mode", choices=["mock", "live"], default="mock")
    parser.add_argument("--dataset")

    args = parser.parse_args()

    # Threshold: CLI arg > env var > default 0.05
    if args.threshold is not None:
        threshold = args.threshold
    else:
        env_threshold = os.environ.get("SAVIA_EVAL_DELTA_THRESHOLD")
        try:
            threshold = float(env_threshold) if env_threshold else 0.05
        except ValueError:
            print(f"ERROR: SAVIA_EVAL_DELTA_THRESHOLD no numérico ({env_threshold!r}): sin veredicto.", file=sys.stderr)
            sys.exit(2)

    if args.check_report:
        sys.exit(check_report(args.check_report))
    if args.run_datasets:
        if not args.datasets_dir or not args.baselines_dir:
            parser.error("--run-datasets requires --datasets-dir and --baselines-dir")
        if args.mode == "live" and not os.environ.get("SAVIA_EVAL_EXECUTOR"):
            print("ERROR: modo vivo sin ejecutor: falta SAVIA_EVAL_EXECUTOR.", file=sys.stderr)
            sys.exit(2)
        sys.exit(run_datasets(args, threshold))
    if not args.baseline or not args.current:
        parser.error("--baseline and --current are required")

    try:
        baseline_scores = load_scores(args.baseline)
        current_scores = load_scores(args.current)
    except (json.JSONDecodeError, KeyError, ValueError) as exc:
        print(json.dumps({"error": str(exc)}), file=sys.stderr)
        sys.exit(1)

    result = compute_paired_delta(baseline_scores, current_scores, threshold)
    print(json.dumps(result, indent=2))

    # Exit code: 0 = pass, 1 = degradation detected
    sys.exit(0 if result["threshold_pass"] else 1)


if __name__ == "__main__":
    main()
