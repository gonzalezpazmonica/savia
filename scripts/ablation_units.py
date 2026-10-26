#!/usr/bin/env python3
"""SE-400 F4 — ablación determinista por unidad (A0 discovery, A2 execution).

Lee un preregistro versionado (``config/ablation-preregistrations.json``) que
fija, antes de correr, las unidades de un grupo de interceptación de F2, sus
modos, la hipótesis y los fallos que se espera que cada unidad atrape en
exclusiva. Materializa un único snapshot ``SAVIA_FULL`` fuera del repositorio
y, por cada unidad y modo, aplica la mutación como commit del snapshot, corre
el corpus con el despachador de F3 y vuelve al commit base:

- ``A0``: quita de ``settings.json`` todos los registros del hook; el fichero
  se conserva (deja de estar en routing).
- ``A2``: sustituye el hook por un no-op que consume la entrada y sale con 0;
  los registros se conservan (destapa también invocaciones indirectas).

Control y variantes comparten snapshot, entrada, perfil de hooks y HOME
aislado. Un caso BLOCK que pasa a ALLOW es ``UNIQUE_FAILURES_CAUGHT`` de la
unidad y aborta su ablación (``ABORT_FALSE_ALLOW``): en un snapshot aislado
no hay efectos, así que se terminan todos los casos para conservar el vector.
Cero invocaciones de modelo. Nada se borra ni se mueve en el repositorio y
ningún resultado clasifica essentiality ni autoriza retiradas.
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

import ablation_graphs as graphs
import ablation_kernel as kernel
from ablation_inventory import (CONTRACT_PATH, DEFAULT_OUT, InventoryError, _git, canonical,
                                sha256, tracked_files, validate_contract)

PREREG_PATH = "config/ablation-preregistrations.json"
REPORT_NAME = "f4-unit-receipts"
MODES = ("A0", "A2")
NOOP_HOOK = "#!/bin/bash\n# SE-400 F4 A2: no-op controlado en snapshot aislado.\ncat >/dev/null\nexit 0\n"
LIMITATIONS = [
    "SIMULATED_DISPATCHER_NOT_A_LIVE_RUNTIME",
    "PROMPT_AND_ASYNC_HOOKS_NOT_EVALUATED",
    "CORPUS_IS_A_SAMPLE_NOT_EXHAUSTIVE",
    "DEFAULT_ENV_OPT_IN_CONTROLS_DORMANT",
    "A0_RUNS_ONLY_CASES_THAT_TRAVERSE_THE_UNIT",
    "NO_ESSENTIALITY_CLASSIFICATION_FROM_THIS_RECEIPT",
]


def validate_prereg(prereg: dict) -> dict:
    if prereg.get("schema") != 1 or prereg.get("phase") != "F4" \
            or not kernel.SEMVER_RE.match(str(prereg.get("version", ""))):
        raise InventoryError("PREREG_SCHEMA", "schema/phase/version")
    kernel._no_model(prereg, "MODEL_AS_BASELINE")
    scope = prereg.get("scope") or {}
    if not scope.get("event") or not scope.get("matcher"):
        raise InventoryError("PREREG_SCOPE", "scope")
    if not prereg.get("corpora") or not prereg.get("decision_rule"):
        raise InventoryError("PREREG_FIELDS", "corpora/decision_rule")
    units = prereg.get("units") or []
    ids = [u.get("id") for u in units]
    if not units or len(ids) != len(set(ids)) or len({u.get("unit") for u in units}) != len(units):
        raise InventoryError("PREREG_UNITS", "units")
    for unit in units:
        modes = unit.get("modes") or []
        if not unit.get("hypothesis") or not modes or set(modes) - set(MODES) \
                or not isinstance(unit.get("expected_unique_catches"), list):
            raise InventoryError("PREREG_UNIT", str(unit.get("id")))
    for item in prereg.get("excluded_cases", []):
        if not item.get("id") or not item.get("reason"):
            raise InventoryError("PREREG_EXCLUSION", str(item))
    return prereg


def check_committed(root: Path, rel: str) -> None:
    """El preregistro tiene que estar versionado y sin cambios: se fija antes de correr."""
    if rel not in tracked_files(root):
        raise InventoryError("PREREG_NOT_COMMITTED", rel)
    if _git(root, "status", "--porcelain", "--", rel).strip():
        raise InventoryError("PREREG_NOT_COMMITTED", rel)


def check_scope(root: Path, files: dict, prereg: dict) -> list[str]:
    """Las unidades son exactamente los hooks bloqueantes del grupo de F2."""
    scope = prereg["scope"]
    rows = graphs.hook_matrix(root, files)
    group = next((g for g in graphs.defense_groups(rows) if g["event"] == scope["event"]
                  and g["matcher"] == "|".join(sorted(scope["matcher"].split("|")))), None)
    expected = set(group["blocking_hooks"]) if group else set()
    declared = {u["unit"] for u in prereg["units"]}
    if declared - expected:
        raise InventoryError("PREREG_UNIT_OUT_OF_SCOPE", ",".join(sorted(declared - expected)))
    if expected - declared:
        raise InventoryError("PREREG_SCOPE_INCOMPLETE", ",".join(sorted(expected - declared)))
    return sorted(expected)


def load_corpus(root: Path, paths: list[str]) -> dict:
    corpora = [kernel.validate_corpus(kernel.load_json(root / p)) for p in paths]
    merged = {"schema": 1, "cases": [c for doc in corpora for c in doc["cases"]],
              "not_verified": [n for doc in corpora for n in doc.get("not_verified", [])]}
    ids = [c["id"] for c in merged["cases"]]
    if len(ids) != len(set(ids)):
        raise InventoryError("CORPUS_CASES", "ids duplicados entre corpus")
    return merged


def drop_registrations(settings: dict, unit: str) -> dict:
    """``settings`` sin ningún registro del hook ``unit``; grupos vacíos fuera."""
    name = unit.rsplit("/", 1)[-1]
    out: dict[str, list] = {}
    for event, groups in (settings.get("hooks") or {}).items():
        kept_groups = []
        for group in groups:
            kept = [h for h in group.get("hooks", [])
                    if name not in graphs.HOOK_CMD_RE.findall(str(h.get("command", "")))]
            if kept:
                kept_groups.append({**group, "hooks": kept})
        if kept_groups:
            out[event] = kept_groups
    return {**settings, "hooks": out}


def _snap_git(snap: Path, *args: str) -> str:
    return subprocess.run(kernel.GIT + ["-C", str(snap), *args], check=True,
                          capture_output=True, text=True).stdout


def apply_mode(snap: Path, unit: str, mode: str) -> None:
    """Aplica la mutación como commit del snapshot, para que el árbol siga limpio."""
    if mode == "A0":
        path = snap / ".claude/settings.json"
        settings = kernel.load_json(path)
        path.write_text(json.dumps(drop_registrations(settings, unit), indent=2) + "\n",
                        encoding="utf-8")
    else:
        path = snap / unit
        if path.is_symlink():
            path.unlink()
        path.write_text(NOOP_HOOK, encoding="utf-8")
        path.chmod(0o755)
    _snap_git(snap, "commit", "-qam", f"se400 F4 {mode} {unit}")


def _traverses(run: dict, unit: str) -> bool:
    name = unit.rsplit("/", 1)[-1]
    return any(h.get("hook") == name for h in run.get("hooks", []))


def decide_unit(verdicts: Counter) -> str:
    if verdicts["CONTROL_INVALID"]:
        return "INCONCLUSIVE"
    if verdicts["FALSE_ALLOW"]:
        return "ABORT_FALSE_ALLOW"
    if verdicts["FALSE_BLOCK"] or verdicts["REGRESSION"]:
        return "ANOMALY_FALSE_BLOCK"
    return "NO_UNIQUE_CATCH_ON_CORPUS"


def ablate_unit(snap: Path, home: Path, unit: dict, mode: str, cases: list[dict],
                control: dict[str, dict], base: str) -> dict:
    name = unit["unit"].rsplit("/", 1)[-1]
    traversed = [c for c in cases if c["type"] == "event" and _traverses(control[c["id"]], name)]
    selected = traversed if mode == "A0" else cases
    apply_mode(snap, unit["unit"], mode)
    try:
        rows = []
        for case in selected:
            var = kernel._run_case(snap, home, case)
            rows.append({"id": case["id"], "variant": var.get("decision", var.get("exit")),
                         "verdict": kernel.compare_case(case, control[case["id"]], var),
                         "hook_processes": len(var.get("hooks", [])), "ms": var.get("ms", 0)})
    finally:
        _snap_git(snap, "reset", "-q", "--hard", base)
    verdicts = Counter(r["verdict"] for r in rows)
    caught = sorted(r["id"] for r in rows if r["verdict"] == "FALSE_ALLOW")
    expected = sorted(unit["expected_unique_catches"])
    control_blocks = sorted(c["id"] for c in traversed if any(
        h.get("hook") == name and h.get("exit") == 2 for h in control[c["id"]]["hooks"]))
    return {"unit_id": unit["id"], "unit": unit["unit"], "mode": mode,
            "decision": decide_unit(verdicts), "verdicts": dict(sorted(verdicts.items())),
            "unique_failures_caught": caught,
            "false_blocks": sorted(r["id"] for r in rows if r["verdict"] == "FALSE_BLOCK"),
            "traversed_cases": len(traversed), "cases_run": len(rows),
            "control_blocks_by_unit": control_blocks,
            "expected_unique_catches": expected,
            "expectation": "MATCH" if caught == expected else "MISMATCH",
            "unexpected_catches": sorted(set(caught) - set(expected)),
            "predicted_not_caught": sorted(set(expected) - set(caught)),
            "cases": rows}


def run_units(root: Path, prereg: dict, workdir: Path, only: list[str] | None = None,
              require_committed: bool = True) -> dict:
    root = root.resolve()
    contract = validate_contract(kernel.load_json(root / CONTRACT_PATH))
    validate_prereg(prereg)
    if require_committed:
        check_committed(root, PREREG_PATH)
    files = tracked_files(root)
    scope_units = check_scope(root, files, prereg)
    corpus = load_corpus(root, prereg["corpora"])
    exclusions = {e["id"]: e["reason"] for e in prereg.get("excluded_cases", [])}
    unknown = sorted(set(exclusions) - {c["id"] for c in corpus["cases"]})
    if unknown:
        raise InventoryError("PREREG_EXCLUSION_UNKNOWN", ",".join(unknown))
    units = [u for u in prereg["units"] if not only or u["unit"].rsplit("/", 1)[-1] in only
             or u["id"] in only]
    if only and not units:
        raise InventoryError("UNIT_FILTER_EMPTY", ",".join(only))
    snap = kernel.materialize(root, files, sorted(files), workdir / "full", None)
    base = _snap_git(snap, "rev-parse", "HEAD").strip()
    home = workdir / "home"
    control, results = {}, []
    for case in corpus["cases"]:
        control[case["id"]] = kernel._run_case(snap, home, case)
    invalid = {c["id"] for c in corpus["cases"]
               if (control[c["id"]]["decision"] != c["expect"] if c["type"] == "event"
                   else not control[c["id"]]["pass"])}
    # Exclusión preregistrada: el control incumple por un defecto conocido. Sigue corriendo y
    # se informa; si el control vuelve a cumplir, la exclusión está caducada y hay que quitarla.
    excluded = [{"id": cid, "reason": why, "control": control[cid].get("decision"),
                 "stale": cid not in invalid} for cid, why in sorted(exclusions.items())]
    cases = [c for c in corpus["cases"] if c["id"] not in exclusions]
    for unit in units:
        for mode in unit["modes"]:
            results.append(ablate_unit(snap, home, unit, mode, cases, control, base))
    decisions = Counter(r["decision"] for r in results)
    receipt = {
        "schema": 1, "spec": "SE-400", "phase": "F4", "model_invocations": 0,
        "provenance": {
            "contract_version": contract["contract_version"],
            "contract_sha256": sha256(canonical(contract)),
            "prereg_id": f"{prereg.get('registry_id')}@{prereg['version']}",
            "prereg_sha256": sha256(canonical(prereg)),
            "corpus_sha256": sha256(canonical(corpus)),
            "surface_sha256": sha256(canonical(sorted([p, b] for p, (_m, b) in files.items()))),
            "sam_model_revision": kernel._optional(root, ".scm/sam.json", "model_revision"),
            "scm_hash": kernel._optional(root, ".scm/resources.json", "hash"),
        },
        "scope": prereg["scope"] | {"units": scope_units},
        "runtime": {"dispatcher": "settings-event-simulator",
                    "hook_profile": prereg.get("hook_profile", "standard"),
                    "abort_conditions": contract["baseline"]["abort_conditions"]},
        "control": {"config": prereg.get("control", "SAVIA_FULL"), "cases": len(control),
                    "invalid": sorted(invalid - set(exclusions)), "excluded": excluded},
        "units": results, "not_verified": corpus["not_verified"],
        "summary": {"decisions": dict(sorted(decisions.items())),
                    "expectation_mismatches": sorted(f"{r['unit_id']}:{r['mode']}" for r in results
                                                     if r["expectation"] == "MISMATCH"),
                    "a0_a2_divergent": sorted(
                        u["id"] for u in units if len({tuple(r["unique_failures_caught"])
                                                       for r in results
                                                       if r["unit_id"] == u["id"]}) > 1)},
        "limitations": LIMITATIONS,
    }
    receipt["receipt_sha256"] = sha256(canonical(receipt))
    receipt["head"] = _git(root, "rev-parse", "HEAD").strip()
    return receipt


def render_md(r: dict) -> str:
    lines = [f"# SE-400 F4 — Ablación por unidad `{r['provenance']['prereg_id']}`", "",
             f"Grupo `{r['scope']['event']}/{r['scope']['matcher']}` · receipt "
             f"`{r['receipt_sha256'][:12]}` · HEAD (informativo) `{r['head'][:12]}` · "
             f"control: {r['control']['cases']} casos, inválidos: "
             f"{', '.join(r['control']['invalid']) or 'ninguno'}", "",
             *[f"Excluido por preregistro: `{e['id']}` (control {e['control']}"
               f"{', CADUCADA' if e['stale'] else ''}): {e['reason']}"
               for e in r["control"]["excluded"]], "",
             "| Unidad | Modo | Decisión | Únicos atrapados | Esperado | Predicción | Recorre |",
             "|---|---|---|---|---|---|---:|"]
    for u in r["units"]:
        lines.append(f"| `{u['unit'].rsplit('/', 1)[-1]}` | {u['mode']} | {u['decision']} | "
                     f"{', '.join(u['unique_failures_caught']) or '—'} | "
                     f"{', '.join(u['expected_unique_catches']) or '—'} | {u['expectation']} | "
                     f"{u['traversed_cases']} |")
    s = r["summary"]
    lines += ["", f"Decisiones: {s['decisions']}.",
              f"Predicciones fallidas: {', '.join(s['expectation_mismatches']) or 'ninguna'}.",
              f"A0 y A2 divergen: {', '.join(s['a0_a2_divergent']) or 'en ninguna unidad'}.",
              "No verificado: " + ", ".join(f"{n['category']} ({n['reason']})"
                                            for n in r["not_verified"]) + ".",
              "Limitaciones: " + ", ".join(r["limitations"]) + ".", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=("check", "run"))
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--out", default=None, help=f"directorio (por defecto {DEFAULT_OUT})")
    ap.add_argument("--unit", action="append", default=None,
                    help="limitar a una unidad (nombre del hook o id); repetible")
    ap.add_argument("--keep", action="store_true", help="conservar el snapshot temporal")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    out = Path(args.out) if args.out else root / DEFAULT_OUT
    try:
        prereg = validate_prereg(kernel.load_json(root / PREREG_PATH))
        if args.command == "check":
            check_committed(root, PREREG_PATH)
            units = check_scope(root, tracked_files(root), prereg)
            load_corpus(root, prereg["corpora"])
            print(f"ABLATION-F4: PREREG_OK {prereg['registry_id']}@{prereg['version']} "
                  f"units={len(units)}")
            return 0
        workdir = Path(tempfile.mkdtemp(prefix="se400-units-"))
        try:
            receipt = run_units(root, prereg, workdir, args.unit)
        finally:
            if not args.keep:
                shutil.rmtree(workdir, ignore_errors=True)
    except InventoryError as exc:
        print(f"ABLATION-F4: INVALID {exc}", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{REPORT_NAME}.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                             encoding="utf-8")
    (out / f"{REPORT_NAME}.md").write_text(render_md(receipt), encoding="utf-8")
    print(f"ABLATION-F4: {receipt['summary']['decisions']} "
          f"control_invalid={len(receipt['control']['invalid'])} -> {out / REPORT_NAME}.json")
    stale = [e["id"] for e in receipt["control"]["excluded"] if e["stale"]]
    if stale:
        print(f"ABLATION-F4: STALE_EXCLUSION {','.join(stale)}", file=sys.stderr)
    return 1 if receipt["control"]["invalid"] or stale else 0


if __name__ == "__main__":
    sys.exit(main())
