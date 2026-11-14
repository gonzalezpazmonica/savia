#!/usr/bin/env python3
"""Punto de llamada del adaptador de Codex: sustituye a `timeout … codex exec …`.

Uso: codex_launch.py --worktree W --run-dir L --prompt-file P --model M --effort E
                     --hours H [--add-dir D ...] [--espera-efecto] [--grace S]

Escribe `L/log.txt`, `L/ultimo.md` (lo escribe Codex) y `L/recibo.json` (lo
observado). Salida: 0 succeeded · 1 failed · 3 unknown (incluye plazo vencido) ·
4 blocked · 2 uso. Un 0 de Codex NO produce un 0 aquí sin efecto observado.
"""
import argparse
import json
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from contracts import execution_request, execution_result  # noqa: E402
from protocol import ProtocolError  # noqa: E402
import codex_executor as ce  # noqa: E402
from runtime import _execute_with_deadline  # noqa: E402

FICHA = Path(__file__).resolve().parents[2] / "contracts/runtime/codex.yaml"
EXIT = {"succeeded": 0, "failed": 1, "unknown": 3, "blocked": 4, "cancelled": 3}


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--worktree", required=True)
    p.add_argument("--run-dir", required=True)
    p.add_argument("--prompt-file", required=True)
    p.add_argument("--model", required=True)
    p.add_argument("--effort", required=True)
    p.add_argument("--hours", type=float, required=True)
    p.add_argument("--add-dir", action="append", default=[])
    p.add_argument("--espera-efecto", action="store_true")
    p.add_argument("--grace", type=float, default=5.0)
    a = p.parse_args(argv)
    run = Path(a.run_dir)
    run.mkdir(parents=True, exist_ok=True)
    try:
        prompt = Path(a.prompt_file).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        print("prompt ilegible", file=sys.stderr)
        return 2
    job = ce.CodexJob(prompt=prompt, workdir=a.worktree, run_dir=str(run), model=a.model,
                      effort=a.effort, add_dirs=tuple(a.add_dir), espera_efecto=a.espera_efecto)
    adapter = ce.CodexAdapter(FICHA, {"in": job}, grace_s=a.grace)
    request = execution_request({
        "request_id": "codex-launch", "capability_id": ce.BASE_CAPABILITY, "context_ref": "ctx",
        "scope_ref": "scope", "input_ref": "in", "required_capabilities": [],
        "deadline_ms": max(1, int(a.hours * 3600 * 1000)), "external_effect_intent": False})
    try:
        result = execution_result(_execute_with_deadline(adapter, request))
    except ProtocolError as error:  # AMBIGUOUS_EXECUTION: plazo vencido o excepción
        result = {"request_id": request["request_id"], "state": "unknown", "reason": error.code,
                  "artifacts": [], "usage": None, "external_effect_observed": None}
    receipt = {"resultado": result, "observado": adapter.observe(request["request_id"])}
    (run / "recibo.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(f"codex_launch: {result['state']} ({result['reason']})")
    return EXIT[result["state"]]


if __name__ == "__main__":
    sys.exit(main())
