#!/usr/bin/env python3
"""SE-387 §17 — output/coherence-closure-status.{json,md}.

Informe de cierre del programa SE-387 derivado SOLO de evidencia ya producida:
log de coherence-gates.sh, matrices de cobertura (output/eval-coverage-matrix,
output/constitutional-coverage), presupuesto de deuda (SE-376), benchmark
(tests/self-evolution/results/aggregate.json) y log de frescura de derivados.
No vuelve a ejecutar los gates (coste ~30 s): los consume.

Fail-closed: lo que no se puede medir sale NOT_MEASURED y su criterio de la
Definition of Closed (§14) queda met=false. Salida determinista (sin fechas).

Uso: coherence-closure-status.py [--root R] [--gates-log F] [--fresh-log F]
                                 [--out-dir D] [--check-policy]
--check-policy: exit 1 si la evidencia N/M de coherence-gate-policy.yaml no
casa con lo medido (deriva de verdad escrita a mano, §10).
"""
import argparse, json, os, re, sys

LINE = re.compile(r"^(PASS|WARN|BLOCK|OBSERVE|INFO) coherence/([\w.-]+?)(?::\s*(.*)|\s+\((.*)\))?$")
HARNESS = {"f2_grounding_fail_closed": "grounding-verify.sh",
           "f3_handoff_active": "validate-handoff-integrity.sh",
           "f4_checkpoint_proven": "checkpoint.sh"}


def load_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def read_text(path):
    if not path:
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_policy(path):
    gates, cur = [], None
    for raw in (read_text(path) or "").splitlines():
        m = re.match(r"^\s*-\s*id:\s*(\S+)", raw)
        if m:
            cur = {"id": m.group(1)}
            gates.append(cur)
            continue
        m = re.match(r"^\s+(\w+):\s*(.*)$", raw)
        if cur is not None and m:
            cur[m.group(1)] = m.group(2).strip()
    return gates


def parse_gates_log(text):
    verdicts, info = {}, {}
    for raw in (text or "").splitlines():
        m = LINE.match(raw.strip())
        if not m:
            continue
        kind, gid, detail = m.group(1), m.group(2), m.group(3) or m.group(4) or ""
        if kind == "INFO":
            info[gid] = detail
        elif kind == "BLOCK" or gid not in verdicts or verdicts[gid][0] == "PASS":
            verdicts[gid] = (kind, detail)
    return verdicts, info


def crit(met, evidence):
    return {"met": bool(met), "evidence": evidence}


def build(root, gates_text, fresh_text):
    policy = parse_policy(os.path.join(root, "scripts", "coherence-gate-policy.yaml"))
    pol = {g["id"]: g for g in policy}
    measured = gates_text is not None
    verdicts, info = parse_gates_log(gates_text)
    s, doc = {}, {}

    # gates
    blocks = sorted(g for g, (k, _) in verdicts.items() if k == "BLOCK")
    warns = sorted(g for g, (k, _) in verdicts.items() if k == "WARN")
    l4 = [g for g in policy if "L4" in g.get("risk_scope", "")]
    l4_graduated = bool(l4) and all(g.get("status") == "BLOCK" and g.get("calibration") == "complete" for g in l4)
    s["gates"] = {"status": "NOT_MEASURED" if not measured else "BLOCK" if blocks else "WARN" if warns else "PASS",
                  "blocking": blocks, "advisory": warns,
                  "policy": [{k: g.get(k, "") for k in ("id", "status", "risk_scope", "calibration")} for g in policy]}
    doc["gates_l4_blocking"] = crit(measured and not blocks and l4_graduated,
                                    f"log={'sí' if measured else 'no'}; BLOCK={len(blocks)}; L4 graduados={l4_graduated}")

    # constitutional
    cc = load_json(os.path.join(root, "output", "constitutional-coverage.json"))
    if cc is None:
        s["constitutional_coverage"] = {"status": "NOT_MEASURED"}
        c_done = c_tot = 0
    else:
        c_tot = len(cc.get("rows", []))
        c_done = sum(1 for r in cc.get("rows", []) if r.get("coverage_status") == "COMPLETE")
        s["constitutional_coverage"] = {"status": "COMPLETE" if c_tot and c_done == c_tot else "PARTIAL",
                                        "complete": c_done, "total": c_tot}
    doc["constitutional_l4_100"] = crit(c_tot and c_done == c_tot, f"{c_done}/{c_tot} COMPLETE")

    # harness
    closure = {g[len("closure-"):]: v for g, v in verdicts.items() if g.startswith("closure-")}
    s["harness"] = {"status": "NOT_MEASURED" if not measured or not closure
                    else "DECLARED" if any(k != "PASS" for k, _ in closure.values()) else "WIRED",
                    "scripts": {t: ("WIRED" if k == "PASS" else "DECLARED") for t, (k, _) in sorted(closure.items())}}
    for key, script in HARNESS.items():
        st = closure.get(script, ("NOT_MEASURED", ""))[0]
        label = {"PASS": "en el camino del efecto", "WARN": "DECLARED (sin hook ni CI que lo aplique)"}.get(st, st)
        doc[key] = crit(st == "PASS", f"{script}: {label}")
    doc["f5_exactly_once_l4"] = crit(False, "NOT_MEASURED: no derivable de la evidencia que consume este informe")

    # evals
    em = load_json(os.path.join(root, "output", "eval-coverage-matrix.json"))
    ev = verdicts.get("eval-coverage-L4", ("NOT_MEASURED", ""))[0]
    rows = [r for r in (em or {}).get("rows", []) if r.get("risk") == "L4"]
    e_cov = sum(1 for r in rows if r.get("covered"))
    s["evals"] = {"status": "NOT_MEASURED" if not measured or em is None else ev,
                  "l4_covered": e_cov, "l4_total": len(rows),
                  "l4_missing": sorted(r.get("capability", "?") for r in rows if not r.get("covered"))}
    egate = pol.get("eval-coverage", {})
    doc["eval_l4_blocking"] = crit(ev == "PASS" and em is not None and rows and e_cov == len(rows)
                                   and egate.get("status") == "BLOCK",
                                   f"{e_cov}/{len(rows)}; gate={ev}; política={egate.get('status', '?')}")

    # debt
    budget = read_text(os.path.join(root, "docs", "propuestas", "SE-376-debt-budget.yaml")) or ""
    wave1 = re.search(r"^\s*1:\s*(\d+)", budget, re.M)
    m = re.search(r"deuda (\d+) <= target wave (\d+) \((\d+)\)", info.get("debt-budget", ""))
    cur = int(m.group(1)) if m else None
    s["debt"] = {"status": "NOT_MEASURED" if cur is None else "OK",
                 "current": cur, "wave": int(m.group(2)) if m else None,
                 "wave_target": int(m.group(3)) if m else None,
                 "wave1_target": int(wave1.group(1)) if wave1 else None}
    doc["debt_wave1_target"] = crit(cur is not None and wave1 and cur <= int(wave1.group(1)),
                                    f"deuda {cur} vs objetivo wave 1 {s['debt']['wave1_target']}")

    # generated truth
    fl = (fresh_text or "").splitlines()
    fp = sum(1 for x in fl if x.startswith("PASS"))
    ff = [x.split(":", 1)[-1].split("→")[0].strip() for x in fl if x.startswith("FAIL")]
    s["generated_truth"] = {"status": "NOT_MEASURED" if fresh_text is None or not (fp or ff)
                            else "DRIFT" if ff else "OK", "fresh": fp, "drift": ff}
    doc["truth_derived_no_drift"] = crit(s["generated_truth"]["status"] == "OK", f"{fp} al día, {len(ff)} desfasados")
    doc["planning_reflects_evidence"] = crit(False, "NOT_MEASURED: roadmap validate no entra en este informe")

    # benchmark
    ag = load_json(os.path.join(root, "tests", "self-evolution", "results", "aggregate.json"))
    counts = (ag or {}).get("aggregate", {})
    executed = counts.get("PASS", 0) + counts.get("CHECK_FAIL", 0)
    s["benchmark"] = {"status": "NOT_MEASURED" if ag is None else "MEASURED", "total": (ag or {}).get("total", 0),
                      "executed": executed, "by_status": dict(sorted(counts.items()))}
    doc["benchmark_real_20"] = crit(executed >= 20, f"{executed} ejecutadas de {s['benchmark']['total']}")

    # entropy
    m = re.search(r"entrop\w+ (\d+) <= baseline (\d+)", info.get("entropy", ""))
    ent = pol.get("entropy", {})
    s["entropy"] = {"status": "NOT_MEASURED" if not m else "OK", "value": int(m.group(1)) if m else None,
                    "baseline": int(m.group(2)) if m else None, "calibration": ent.get("calibration", "")}
    provisional = ent.get("calibration", "") != "complete" or "provisional" in ent.get("evidence", "")
    doc["entropy_v1_or_v0_provisional"] = crit(ent and provisional, f"calibración={ent.get('calibration', '?')}")

    # deriva de la evidencia escrita a mano en la política
    drift, unverified = [], []
    for gid, got in (("eval-coverage", (e_cov, len(rows)) if em is not None else None),
                     ("constitutional-coverage", (c_done, c_tot) if cc is not None else None)):
        mm = re.search(r"(\d+)/(\d+)", pol.get(gid, {}).get("evidence", ""))
        if got is None:
            unverified.append(gid)
        if got is not None and mm and (int(mm.group(1)), int(mm.group(2))) != got:
            drift.append({"gate": gid, "declared": mm.group(0), "measured": f"{got[0]}/{got[1]}"})

    return {"spec": "SE-387", "report": "coherence-closure-status", "sections": s,
            "definition_of_closed": doc, "closed": all(c["met"] for c in doc.values()),
            "open_criteria": sorted(k for k, c in doc.items() if not c["met"]),
            "policy_evidence_drift": drift, "policy_unverified": unverified}


def to_md(d):
    out = ["<!-- AUTO-GENERATED — DO NOT EDIT — scripts/coherence-closure-status.py -->",
           "# SE-387 — coherence-closure-status", "",
           f"**Cerrado:** {'sí' if d['closed'] else 'no'} · criterios abiertos: {len(d['open_criteria'])}", "",
           "## Definition of Closed (§14)", "", "| Criterio | Cumple | Evidencia |", "|---|---|---|"]
    out += [f"| {k} | {'sí' if c['met'] else 'no'} | {c['evidence']} |" for k, c in d["definition_of_closed"].items()]
    out += ["", "## Secciones (§17)", ""]
    out += [f"- **{k}**: {v.get('status')}" for k, v in sorted(d["sections"].items())]
    if d["policy_evidence_drift"]:
        out += ["", "## Deriva de la política", ""]
        out += [f"- {x['gate']}: declara {x['declared']}, medido {x['measured']}" for x in d["policy_evidence_drift"]]
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--gates-log")
    ap.add_argument("--fresh-log")
    ap.add_argument("--out-dir")
    ap.add_argument("--check-policy", action="store_true")
    a = ap.parse_args()
    d = build(a.root, read_text(a.gates_log), read_text(a.fresh_log))
    out = a.out_dir or os.path.join(a.root, "output")
    os.makedirs(out, exist_ok=True)
    with open(os.path.join(out, "coherence-closure-status.json"), "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    with open(os.path.join(out, "coherence-closure-status.md"), "w", encoding="utf-8") as f:
        f.write(to_md(d))
    print(f"coherence-closure-status: {len(d['open_criteria'])} criterios abiertos → {out}/coherence-closure-status.{{json,md}}")
    if a.check_policy:
        for x in d["policy_evidence_drift"]:
            print(f"DRIFT {x['gate']}: política declara {x['declared']}, medido {x['measured']}")
        for g in d["policy_unverified"]:
            print(f"UNVERIFIED {g}: falta la matriz medida (fail-closed)")
        return 1 if d["policy_evidence_drift"] else 2 if d["policy_unverified"] else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
