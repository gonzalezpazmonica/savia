#!/usr/bin/env python3
"""llm-router.py — routing de modelo LLM por incertidumbre (SE-346, piloto).

Solo `--check`/report (read-only): para cada tipo de tarea predice con el GP
qué modelo elegiría y con qué incertidumbre, sin cambiar el runtime. El fallo
sigue escalando (no se sustituye la escalación por fallo, se antecede).

Decisión por std:
    std < threshold_barato  -> FAST
    std >= threshold_caro   -> AGENT
    resto                   -> MID

CRIT-001: todo local; telemetría en output/ (disco propio, gitignored).
"""

import argparse
import json
import os
import sys
import datetime

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gp_surrogate import GPSurrogate  # noqa: E402
from storage import History  # noqa: E402

TASK_TYPES = ["routing", "code", "audit", "report"]
THRESHOLD_BARATO = float(os.environ.get("SURROGATE_THRESHOLD_BARATO", "0.10"))
THRESHOLD_CARO = float(os.environ.get("SURROGATE_THRESHOLD_CARO", "0.30"))
HISTORY_DEFAULT = os.path.join(os.environ.get("WORKSPACE_DIR", os.getcwd()), "output", "surrogate-history.csv")
TELEMETRY_DEFAULT = os.path.join(os.environ.get("WORKSPACE_DIR", os.getcwd()), "output", "surrogate-telemetry.jsonl")


def features_for(task_type: str, n_files: float = 0.3, n_specs: float = 0.2,
                 tokens: float = 0.4, success: float = 0.8) -> list:
    """Vector 8D: [onehot tipo(4), n_files, n_specs, tokens, success_rate]."""
    onehot = [1.0 if t == task_type else 0.0 for t in TASK_TYPES]
    return onehot + [float(n_files), float(n_specs), float(tokens), float(success)]


def default_profiles() -> dict:
    """Perfiles cold-start por tipo (historial sintético de arranque)."""
    return {
        "routing": features_for("routing", 0.1, 0.1, 0.2, 0.9),
        "code": features_for("code", 0.6, 0.3, 0.5, 0.7),
        "audit": features_for("audit", 0.8, 0.6, 0.7, 0.5),
        "report": features_for("report", 0.4, 0.5, 0.6, 0.75),
    }


def seed_history():
    """Historial sintético determinista para arrancar el GP (sin datos reales)."""
    rng = np.random.default_rng(7)
    items = []
    for t in TASK_TYPES:
        base = default_profiles()[t]
        for _ in range(4):
            feats = list(base)
            feats[4:] = [min(1.0, max(0.0, v + rng.normal(0, 0.15))) for v in feats[4:]]
            # Outcome = coste normalizado; tareas complejas más caras
            complexity = (feats[4] + feats[5] + feats[6]) / 3.0
            outcome = 0.2 + 0.8 * complexity + rng.normal(0, 0.1)
            items.append((feats, float(np.clip(outcome, 0.05, 1.0))))
    return History(items)


def decide(model_std: float) -> str:
    if model_std < THRESHOLD_BARATO:
        return "fast"
    if model_std >= THRESHOLD_CARO:
        return "agent"
    return "mid"


def verdict_for(std: float) -> str:
    if std < THRESHOLD_BARATO:
        return "confiar-bajo"
    if std >= THRESHOLD_CARO:
        return "necesita-caro"
    return "dudoso-mid"


def main():
    ap = argparse.ArgumentParser(description="SE-346 llm-router --check (read-only)")
    ap.add_argument("--check", action="store_true", help="modo report: emite JSON por tipo de tarea")
    ap.add_argument("--history", default=HISTORY_DEFAULT, help="CSV de historial real (si existe)")
    ap.add_argument("--telemetry", default=TELEMETRY_DEFAULT, help="JSONL de telemetría (output/, gitignored)")
    ap.add_argument("--thresholds", default=f"{THRESHOLD_BARATO},{THRESHOLD_CARO}",
                    help="threshold_barato,threshold_caro")
    args = ap.parse_args()

    if not args.check:
        print("Uso: llm-router.py --check [--history path] [--thresholds a,c]", file=sys.stderr)
        sys.exit(2)

    t_barato, t_caro = (float(x) for x in args.thresholds.split(","))

    hist = History.from_csv(args.history) if os.path.exists(args.history) else seed_history()
    gp = GPSurrogate(random_state=0).fit(hist)

    results = {}
    for t in TASK_TYPES:
        feats = default_profiles()[t]
        mu, std = gp.predict([feats])
        std = float(std[0])
        results[t] = {
            "model": decide(std),
            "std": round(std, 4),
            "verdict": verdict_for(std),
            "predicted_cost": round(float(mu[0]), 4),
        }

    # Telemetría local (output/, gitignored — read-only respecto al repo)
    try:
        os.makedirs(os.path.dirname(args.telemetry), exist_ok=True)
        with open(args.telemetry, "a") as f:
            f.write(json.dumps({
                "ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "event": "llm-router-check",
                "thresholds": [t_barato, t_caro],
                "results": results,
            }) + "\n")
    except Exception:
        pass

    print(json.dumps({"mode": "check", "thresholds": [t_barato, t_caro], "results": results},
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
