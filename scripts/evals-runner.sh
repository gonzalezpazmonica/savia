#!/usr/bin/env bash
# evals-runner.sh — SPEC-151 local evaluation runner, honest result (SE-468).
set -uo pipefail
#
# Reads tests/evals/datasets/**/*.jsonl, executes the evaluated artifact of each
# dataset (declared in tests/evals/datasets/artifacts.json) through an executor,
# compares against baselines and outputs a paired-delta report JSON.
#
# A dataset is only declared evaluated (clean/findings) when the artifact was
# actually executed AND the sabotage run (same executor, artifact replaced by an
# empty file) produced findings. Otherwise the result is `unknown` with gaps
# (contract: docs/rules/domain/gate-result-contract.md, SE-453).
#
# Usage:
#   ./scripts/evals-runner.sh [--mock] [--dataset NAME] [--output FILE]
#
# Options:
#   --mock       Do not execute any artifact: every dataset is `unknown`
#                (gap not_executed). This is what CI runs today.
#   --dataset    Run only the specified dataset (e.g. pbi-decomposition).
#   --output     Write report to FILE (default: stdout).
#   --threshold  Override degradation threshold (default 0.05 or env).
#
# Live mode (no --mock) requires SAVIA_EVAL_EXECUTOR: a command that receives one
# dataset row (JSON) on stdin, the artifact path in SAVIA_EVAL_ARTIFACT and the
# dataset name in SAVIA_EVAL_DATASET, and prints a score in [0,1] as its last
# stdout line. Without it the runner fails closed (exit 2).
#
# Output JSON (one entry per dataset):
#   [{dataset, result, gaps, label, baseline_score, current_score, delta,
#     threshold_pass, sabotage_detected}, ...]
#   threshold_pass is null whenever result is unknown.
#
# Reference: SPEC-151, SE-468, paired-delta pattern (DeepEval CI docs).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATASETS_DIR="$ROOT_DIR/tests/evals/datasets"
BASELINES_DIR="$ROOT_DIR/tests/evals/baselines"
RESULTS_DIR="$ROOT_DIR/tests/evals/results"
DELTA_SCRIPT="$SCRIPT_DIR/evals-paired-delta.py"

MOCK=false
TARGET_DATASET=""
OUTPUT_FILE=""
THRESHOLD="${SAVIA_EVAL_DELTA_THRESHOLD:-0.05}"

# ── argument parsing ───────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mock)       MOCK=true ;;
    --dataset)    TARGET_DATASET="$2"; shift ;;
    --output)     OUTPUT_FILE="$2"; shift ;;
    --threshold)  THRESHOLD="$2"; shift ;;
    -h|--help)
      grep '^#' "${BASH_SOURCE[0]}" | sed 's/^# //'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

# ── fail closed: live mode without executor (SE-468 S2) ───────────────────────
if [[ "$MOCK" == "false" && -z "${SAVIA_EVAL_EXECUTOR:-}" ]]; then
  echo "ERROR: modo vivo sin ejecutor: falta SAVIA_EVAL_EXECUTOR (comando que ejecuta el artefacto y puntúa cada caso). Usa --mock para un informe 'unknown'." >&2
  exit 2
fi

mkdir -p "$RESULTS_DIR"

output=$(python3 "$DELTA_SCRIPT" --run-datasets \
  --root "$ROOT_DIR" \
  --datasets-dir "$DATASETS_DIR" \
  --baselines-dir "$BASELINES_DIR" \
  --threshold "$THRESHOLD" \
  --mode "$([[ "$MOCK" == "true" ]] && echo mock || echo live)" \
  ${TARGET_DATASET:+--dataset "$TARGET_DATASET"})
rc=$?
if [[ $rc -ne 0 ]]; then
  exit "$rc"
fi

if [[ -n "$OUTPUT_FILE" ]]; then
  echo "$output" > "$OUTPUT_FILE"
  echo "Report written to $OUTPUT_FILE" >&2
else
  echo "$output"
fi
