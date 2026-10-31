#!/usr/bin/env python3
"""SE-489 M2 — tablas Markdown a partir de los JSON de m2-bench.ts.

Uso: m2_report.py m2-mmarco.json [m2-bge.json ...]
Por conjunto y configuración: diferencia pareada frente a M0 (IC 95 % bootstrap) por categoría,
con la regla AC-6: no inferioridad en A/B (límite inferior del IC > -1 pp) y ganancia en C/D/E
(el IC excluye 0 por arriba). Solo lee los JSON; no escribe nada.
"""
import json
import sys

CATS = "ABCDEF"
HEAD = ["recallAt5", "recallAt10", "mrr", "ndcgAt10", "evidenceRecall"]
SHOWN = ["recallAt10", "mrr", "ndcgAt10", "evidenceRecall"]


def f(x):
    return "-" if x is None else f"{x:.3f}"


def fb(d):
    return "-" if d is None else (", ".join(f"{k}:{v}" for k, v in sorted(d.items())) or "0")


def diff(d):
    return "-" if not d else f"{d['diff']:+.3f} [{d['lo']:+.3f}, {d['hi']:+.3f}]"


def verdict(cat, d):
    if not d:
        return "sin datos"
    if cat in "AB":
        return "no inferior" if d["lo"] > -0.01 else "inferior o no concluyente"
    if cat in "CDE":
        return "gana" if d["lo"] > 0 else ("pierde" if d["hi"] < 0 else "no concluyente")
    return "-"


def atlas(m0_cases, m2_cases, threshold=0.5):
    """Casos pareados por id: MRR que sube o baja al menos `threshold` con M2 frente a M0."""
    base = {c["id"]: c["metrics"].get("mrr") for c in m0_cases}
    recupera, pierde, quieto = [], [], 0
    for c in m2_cases:
        a, b = base.get(c["id"]), c["metrics"].get("mrr")
        if a is None or b is None:
            continue
        if b - a >= threshold:
            recupera.append((c["id"], a, b))
        elif a - b >= threshold:
            pierde.append((c["id"], a, b))
        else:
            quieto += 1
    return {"recupera": sorted(recupera), "pierde": sorted(pierde), "sin_cambio": quieto}


def main(paths):
    for p in paths:
        with open(p) as fh:
            r = json.load(fh)
        print(f"\n## {p}\n")
        print("Modelos fijados (sha256):", json.dumps(r["models"]))
        for sname, s in r["sets"].items():
            m0 = s["M0"]
            print(f"\n### Conjunto {sname} (n={s['n']})\n")
            print("| Config | Cat | " + " | ".join(f"{m} (M0→M2, Δ IC95)" for m in SHOWN) + " | AC-6 (evidenceRecall) | AC-6 (ndcgAt10) |")
            print("|---|---|" + "---|" * 6)
            for label, c in s["configs"].items():
                rep = c["report"]
                for cat in CATS:
                    a, b = rep["byCategory"].get(cat), m0["byCategory"].get(cat)
                    if not a or not b:
                        continue
                    cmp_ = c["vsM0"]["byCategory"].get(cat, {})
                    cells = [f"{f(b[m]['mean'])}→{f(a[m]['mean'])}, {diff(cmp_.get(m))}" for m in SHOWN]
                    print(f"| {label} | {cat} | " + " | ".join(cells) + f" | {verdict(cat, cmp_.get('evidenceRecall'))} | {verdict(cat, cmp_.get('ndcgAt10'))} |")
                ov = c["vsM0"]["overall"]
                print(f"| {label} | todas | " + " | ".join(diff(ov.get(m)) for m in SHOWN) + " | - | - |")
            print("\n| Config | errores | violaciones | lecturas no autorizadas | p50/p95 ruta (ms) | p50/p95 reranker (ms) | ms/par | llamadas | fallos reranker | fallbacks a M0 | RSS pico MB |")
            print("|---|---|---|---|---|---|---|---|---|---|---|")
            unauth = sum(c["metrics"]["unauthorizedReads"] for c in m0["cases"])
            print(f"| M0 | {m0['errors']} | {m0['violations']} | {unauth} | {m0['latency']['p50Ms']:.0f}/{m0['latency']['p95Ms']:.0f} | - | - | {m0['cost']['modelCalls']} | - | - | {m0['rssPeakMb']:.0f} |")
            for label, c in s["configs"].items():
                a = atlas(m0["cases"], c["report"]["cases"])
                fmt = lambda xs: ", ".join(f"{i} ({x:.2f}→{y:.2f})" for i, x, y in xs) or "ninguno"  # noqa: E731
                print(f"\nAtlas {label} (ΔMRR ≥ 0,5): M2 recupera {len(a['recupera'])}: {fmt(a['recupera'])}; M2 pierde {len(a['pierde'])}: {fmt(a['pierde'])}; sin cambio relevante {a['sin_cambio']}")
            print()
            for label, c in s["configs"].items():
                rep, lat = c["report"], c["rerankerLatency"]
                un = sum(x["metrics"]["unauthorizedReads"] for x in rep["cases"])
                print(f"| {label} | {rep['errors']} | {rep['violations']} | {un} | {rep['latency']['p50Ms']:.0f}/{rep['latency']['p95Ms']:.0f} | {lat['p50Ms']}/{lat['p95Ms']} | {f(lat['meanMsPerPair'])} | {rep['cost']['modelCalls']} | {lat['failed']} | {fb(c.get('fallbacks'))} | {rep['rssPeakMb']:.0f} |")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("uso: m2_report.py m2-*.json")
    main(sys.argv[1:])
