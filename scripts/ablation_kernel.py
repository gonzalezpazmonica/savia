#!/usr/bin/env python3
"""SE-400 F3 — kernel candidato aislado frente a SAVIA_FULL.

Materializa dos snapshots del mismo árbol versionado en un directorio fuera
del repositorio: ``SAVIA_FULL`` (todo) y ``SAVIA_KERNEL_CANDIDATE`` (cierre de
dependencias de las semillas de ``config/kernel-candidate.json`` sobre el
grafo F2, con ``settings.json`` proyectado a sus hooks). Ejecuta en ambos el
Golden Kernel Corpus determinista (``config/kernel-corpus.json``) con un
despachador que reproduce la semántica de eventos y matchers de settings, y
emite un receipt que liga contrato, candidato, corpus, SAM/SCM y resultado.

Nunca borra ni mueve nada en el repositorio. Cero invocaciones de modelo:
los hooks ``type: prompt`` se registran como no evaluados. Un falso allow
aborta (``ABORT_FALSE_ALLOW``); ningún resultado clasifica un recurso como
CORE_* ni autoriza retiradas.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter, deque
from pathlib import Path

import ablation_graphs as graphs
from ablation_inventory import (CONTRACT_PATH, DEFAULT_OUT, MODEL_KEYS, InventoryError, _git,
                                _walk_keys, canonical, sha256, tracked_files, validate_contract)

CANDIDATE_PATH = "config/kernel-candidate.json"
CORPUS_PATH = "config/kernel-corpus.json"
REPORT_NAME = "f3-kernel-receipt"
PROBE_BRANCH = "agent/kernel-probe"
CLOSURE_RELATIONS = frozenset({"SOURCES", "INVOKES", "IMPORTS", "DECLARES_SKILL",
                               "DELEGATES_TO", "USES_DECISION_TREE"})
SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
DENY_RE = re.compile(r'"(?:permissionDecision|decision)"\s*:\s*"(?:deny|block)"')
DEFAULT_TIMEOUT = 60
# Secretos sintéticos montados en ejecución: ningún fichero versionado contiene el literal.
SYNTHETIC = {"{{SYNTHETIC_GITHUB_TOKEN}}": "gh" + "p_" + "A1b2C3d4" * 4 + "e5f6"}
LIMITATIONS = [
    "SIMULATED_DISPATCHER_NOT_A_LIVE_RUNTIME",
    "PROMPT_AND_ASYNC_HOOKS_NOT_EVALUATED",
    "CORPUS_IS_A_SAMPLE_NOT_EXHAUSTIVE",
    "STATIC_CLOSURE_DYNAMIC_DISPATCH_NOT_RESOLVED",
    "NO_ESSENTIALITY_CLASSIFICATION_FROM_THIS_RECEIPT",
]
GIT = ["git", "-c", "user.name=se400-probe", "-c", "user.email=probe@invalid",
       "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"]


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        raise InventoryError("JSON_MISSING", str(path)) from exc


def _no_model(doc: dict, code: str) -> None:
    bad = sorted(set(_walk_keys(doc)) & MODEL_KEYS)
    if bad:
        raise InventoryError(code, ",".join(bad))


def validate_candidate(candidate: dict) -> dict:
    if candidate.get("schema") != 1 or not SEMVER_RE.match(str(candidate.get("version", ""))):
        raise InventoryError("CANDIDATE_SCHEMA", "schema/version")
    _no_model(candidate, "MODEL_AS_BASELINE")
    areas = candidate.get("areas") or {}
    if not areas or not all(isinstance(v, list) and v for v in areas.values()):
        raise InventoryError("CANDIDATE_AREAS", "areas")
    return candidate


def validate_corpus(corpus: dict) -> dict:
    if corpus.get("schema") != 1:
        raise InventoryError("CORPUS_SCHEMA", "schema")
    _no_model(corpus, "MODEL_AS_BASELINE")
    ids = [c.get("id") for c in corpus.get("cases", [])]
    if not ids or len(ids) != len(set(ids)):
        raise InventoryError("CORPUS_CASES", "cases")
    for case in corpus["cases"]:
        ok = case.get("type") == "event" and case.get("expect") in ("BLOCK", "ALLOW") \
            or case.get("type") == "exec" and isinstance(case.get("argv"), list) \
            and isinstance(case.get("expect_exit"), int)
        if not ok or not case.get("category"):
            raise InventoryError("CORPUS_CASE", str(case.get("id")))
    for item in corpus.get("not_verified", []):
        if not item.get("category") or not item.get("reason"):
            raise InventoryError("CORPUS_NOT_VERIFIED", str(item))
    return corpus


def plan_kernel(root: Path, files: dict, candidate: dict) -> dict:
    """Cierre de dependencias de las semillas y dependencias de packs no permitidos."""
    validate_candidate(candidate)
    seeds = sorted({p for paths in candidate["areas"].values() for p in paths})
    missing = [p for p in seeds if p not in files]
    if missing:
        raise InventoryError("KERNEL_SEED_MISSING", ",".join(missing))
    adjacency: dict[str, list[str]] = {}
    for edge in graphs.dependency_edges(root, files):
        if edge["relation"] in CLOSURE_RELATIONS:
            adjacency.setdefault(edge["source"], []).append(edge["target"])
    closure, dangling, queue = set(seeds), set(), deque(seeds)
    while queue:
        for dep in adjacency.get(queue.popleft(), []):
            if dep.startswith("MISSING:"):
                dangling.add(dep)
            elif dep not in closure:
                closure.add(dep)
                queue.append(dep)
    allowed = set(candidate.get("allowed_packs", []))
    registry = load_json(root / "config/domain-packs.json") \
        if "config/domain-packs.json" in files else {"packs": []}
    pack_deps = sorted(({"path": ref, "pack": pack["id"]}
                        for pack in registry.get("packs", []) if pack["id"] not in allowed
                        for key in ("rule_refs", "context_refs", "test_refs")
                        for ref in pack.get(key, []) if ref in closure),
                       key=lambda d: (d["path"], d["pack"]))
    origins = Counter(p.split("/", 1)[0] if p.startswith((".claude/", ".opencode/", ".agents/"))
                      else "neutral" for p in closure)
    return {"seeds": seeds, "paths": sorted(closure), "dangling": sorted(dangling),
            "pack_dependencies": pack_deps, "by_origin": dict(sorted(origins.items()))}


def project_settings(settings: dict, hooks: set[str]) -> dict:
    """Solo registros ``command`` cuyos hooks están en el kernel; mismo orden."""
    out: dict[str, list] = {}
    for event, groups in (settings.get("hooks") or {}).items():
        kept_groups = []
        for group in groups:
            kept = [h for h in group.get("hooks", []) if h.get("type", "command") == "command"
                    and any(f".claude/hooks/{n}" in hooks
                            for n in graphs.HOOK_CMD_RE.findall(str(h.get("command", ""))))]
            if kept:
                kept_groups.append({**{k: v for k, v in group.items() if k != "hooks"},
                                    "hooks": kept})
        if kept_groups:
            out[event] = kept_groups
    return {"hooks": out}


def ensure_isolated(root: Path, dest: Path) -> None:
    root, dest = root.resolve(), dest.resolve()
    if dest == root or root in dest.parents or dest in root.parents:
        raise InventoryError("DEST_NOT_ISOLATED", str(dest))
    if dest.exists() and any(dest.iterdir()):
        raise InventoryError("DEST_NOT_EMPTY", str(dest))


def materialize(root: Path, files: dict, paths: list[str], dest: Path,
                settings: dict | None) -> Path:
    """Copia ``paths`` del árbol de trabajo a ``dest`` y lo convierte en repo git."""
    ensure_isolated(root, dest)
    dest.mkdir(parents=True, exist_ok=True)
    for rel in paths:
        src, dst = root / rel, dest / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if files[rel][0] == "120000":
            os.symlink(os.readlink(src), dst)
        elif src.is_file():
            shutil.copy2(src, dst)
    if settings is not None:
        target = dest / ".claude/settings.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
    for args in (["init", "-q", "-b", PROBE_BRANCH], ["add", "-A"],
                 ["commit", "-qm", "se400 snapshot", "--allow-empty"]):
        subprocess.run(GIT + ["-C", str(dest), *args], check=True, capture_output=True)
    return dest


def _env(snap: Path, home: Path) -> dict:
    home.mkdir(parents=True, exist_ok=True)
    return {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(home),
            "LANG": "C.UTF-8", "CLAUDE_PROJECT_DIR": str(snap),
            "SAVIA_HOOK_PROFILE": "standard"}


def dispatch(snap: Path, home: Path, event: str, tool: str, tool_input: dict) -> dict:
    """Simula un evento: corre en orden los hooks de settings cuyo matcher casa."""
    settings = load_json(snap / ".claude/settings.json")
    payload = json.dumps({"hook_event_name": event, "tool_name": tool, "tool_input": tool_input,
                          "cwd": str(snap), "session_id": "se400-probe"})
    command, runs, start = str(tool_input.get("command", "")), [], time.monotonic()
    for group in (settings.get("hooks") or {}).get(event, []):
        if not graphs.matcher_matches(group.get("matcher", "*") or "*", tool, command):
            continue
        for hook in group.get("hooks", []):
            names = graphs.HOOK_CMD_RE.findall(str(hook.get("command", "")))
            entry = {"hook": names[0] if names else "inline", "exit": None}
            if hook.get("type", "command") != "command" or hook.get("async"):
                entry["exit"] = "NOT_EVALUATED"
                runs.append(entry)
                continue
            t0 = time.monotonic()
            try:
                proc = subprocess.run(["bash", "-c", hook["command"]], input=payload, text=True,
                                      capture_output=True, cwd=snap, env=_env(snap, home),
                                      timeout=hook.get("timeout") or DEFAULT_TIMEOUT)
                entry["exit"] = 2 if DENY_RE.search(proc.stdout) else proc.returncode
            except subprocess.TimeoutExpired:
                entry["exit"] = "TIMEOUT_FAIL_OPEN"
            entry["ms"] = round((time.monotonic() - t0) * 1000)
            runs.append(entry)
    blocked = any(r["exit"] == 2 for r in runs)
    return {"decision": "BLOCK" if blocked else "ALLOW", "hooks": runs,
            "ms": round((time.monotonic() - start) * 1000)}


def run_exec(snap: Path, home: Path, case: dict) -> dict:
    t0 = time.monotonic()
    try:
        proc = subprocess.run(case["argv"], text=True, capture_output=True, cwd=snap,
                              env=_env(snap, home), timeout=case.get("timeout", DEFAULT_TIMEOUT))
        code, out = proc.returncode, proc.stdout + proc.stderr
    except (subprocess.TimeoutExpired, OSError) as exc:
        code, out = "ERROR", type(exc).__name__
    want = case.get("expect_output", "")
    result = {"exit": code, "pass": code == case["expect_exit"] and want in out,
              "ms": round((time.monotonic() - t0) * 1000)}
    if not result["pass"]:
        result["output_tail"] = out.strip()[-300:]
    return result


def compare_case(case: dict, control: dict, variant: dict) -> str:
    if case["type"] == "event":
        if control["decision"] != case["expect"]:
            return "CONTROL_INVALID"
        if variant["decision"] == case["expect"]:
            return "MATCH"
        return "FALSE_ALLOW" if case["expect"] == "BLOCK" else "FALSE_BLOCK"
    if not control["pass"]:
        return "CONTROL_INVALID"
    return "MATCH" if variant["pass"] else "REGRESSION"


def decide(cases: list[dict]) -> str:
    verdicts = {c["verdict"] for c in cases}
    if "FALSE_ALLOW" in verdicts:
        return "ABORT_FALSE_ALLOW"
    if "CONTROL_INVALID" in verdicts:
        return "INCONCLUSIVE"
    if verdicts & {"FALSE_BLOCK", "REGRESSION"}:
        return "KERNEL_INSUFFICIENT"
    return "KERNEL_PRESERVES_CORPUS"


def _checkout(snap: Path, branch: str) -> None:
    subprocess.run(GIT + ["-C", str(snap), "checkout", "-q", "-B", branch],
                   check=True, capture_output=True)


def expand(value):
    """Sustituye los marcadores ``SYNTHETIC`` en cadenas, listas y dicts."""
    if isinstance(value, str):
        for marker, secret in SYNTHETIC.items():
            value = value.replace(marker, secret)
        return value
    if isinstance(value, list):
        return [expand(v) for v in value]
    if isinstance(value, dict):
        return {k: expand(v) for k, v in value.items()}
    return value


def _run_case(snap: Path, home: Path, case: dict) -> dict:
    case = expand(case)
    if case.get("branch"):
        _checkout(snap, case["branch"])
    try:
        if case["type"] == "event":
            return dispatch(snap, home, case["event"], case["tool"], case["input"])
        return run_exec(snap, home, case)
    finally:
        if case.get("branch"):
            _checkout(snap, PROBE_BRANCH)


def _vector(snap: Path, results: list[dict]) -> dict:
    files = tracked_files(snap)
    rows = graphs.hook_matrix(snap, files)
    return {"files": len(files),
            "bytes": sum((snap / p).stat().st_size for p, (m, _) in files.items()
                         if m != "120000" and (snap / p).is_file()),
            "scripts": sum(p.startswith("scripts/") for p in files),
            "hook_registrations": len(rows),
            "blocking_registrations": sum(r["blocking_capable"] for r in rows),
            "hook_processes": sum(len(r.get("hooks", [])) for r in results),
            "latency_ms": sum(r.get("ms", 0) for r in results)}


def _optional(root: Path, rel: str, key: str) -> str:
    path = root / rel
    return str(load_json(path).get(key, "UNKNOWN")) if path.exists() else "UNKNOWN"


def run_experiment(root: Path, candidate: dict, corpus: dict, workdir: Path) -> dict:
    root = root.resolve()
    contract = validate_contract(load_json(root / CONTRACT_PATH))
    validate_corpus(corpus)
    files = tracked_files(root)
    plan = plan_kernel(root, files, candidate)
    settings = load_json(root / ".claude/settings.json")
    hooks = {p for p in plan["paths"] if p.startswith(".claude/hooks/")}
    full = materialize(root, files, sorted(files), workdir / "full", None)
    kern = materialize(root, files, plan["paths"], workdir / "kernel",
                       project_settings(settings, hooks))
    cases, ctrl_runs, var_runs = [], [], []
    for case in corpus["cases"]:
        ctrl = _run_case(full, workdir / "home-full", case)
        var = _run_case(kern, workdir / "home-kernel", case)
        ctrl_runs.append(ctrl)
        var_runs.append(var)
        cases.append({"id": case["id"], "category": case["category"],
                      "expected": case.get("expect", case.get("expect_exit")),
                      "control": ctrl, "variant": var,
                      "verdict": compare_case(case, ctrl, var)})
    verdicts = Counter(c["verdict"] for c in cases)
    receipt = {
        "schema": 1, "spec": "SE-400", "phase": "F3", "unit": "kernel-candidate",
        "mode": "A5-isolated-snapshot", "model_invocations": 0,
        "provenance": {
            "contract_version": contract["contract_version"],
            "contract_sha256": sha256(canonical(contract)),
            "candidate_sha256": sha256(canonical(candidate)),
            "corpus_sha256": sha256(canonical(corpus)),
            "surface_sha256": sha256(canonical(sorted([p, b] for p, (_m, b) in files.items()))),
            "sam_model_revision": _optional(root, ".scm/sam.json", "model_revision"),
            "scm_hash": _optional(root, ".scm/resources.json", "hash"),
        },
        "configs": {"control": "SAVIA_FULL",
                    "variant": f"{candidate.get('candidate_id')}@{candidate['version']}"},
        "runtime": {"dispatcher": "settings-event-simulator", "hook_profile": "standard",
                    "abort_conditions": contract["baseline"]["abort_conditions"]},
        "plan": {k: v for k, v in plan.items() if k != "paths"} | {"files": len(plan["paths"])},
        "cases": cases, "not_verified": corpus.get("not_verified", []),
        "verdicts": dict(sorted(verdicts.items())),
        "invariants": {"false_allows": verdicts["FALSE_ALLOW"],
                       "pack_dependencies": len(plan["pack_dependencies"])},
        "vector": {"full": _vector(full, ctrl_runs), "kernel": _vector(kern, var_runs)},
        "decision": decide(cases), "limitations": LIMITATIONS,
    }
    receipt["receipt_sha256"] = sha256(canonical(receipt))
    receipt["head"] = _git(root, "rev-parse", "HEAD").strip()
    return receipt


def render_md(r: dict) -> str:
    v, k = r["vector"]["full"], r["vector"]["kernel"]
    lines = [f"# SE-400 F3 — Kernel candidato `{r['configs']['variant']}`", "",
             f"Decisión: **{r['decision']}** · receipt `{r['receipt_sha256'][:12]}` · "
             f"HEAD (informativo) `{r['head'][:12]}`", "",
             "| Medida | SAVIA_FULL | KERNEL | Δ |", "|---|---:|---:|---:|"]
    lines += [f"| {m} | {v[m]} | {k[m]} | {k[m] - v[m]} |" for m in v]
    lines += ["", "| Caso | Categoría | Esperado | FULL | KERNEL | Veredicto |",
              "|---|---|---|---|---|---|"]
    for c in r["cases"]:
        obs = [c[s].get("decision", c[s].get("exit")) for s in ("control", "variant")]
        lines.append(f"| {c['id']} | {c['category']} | {c['expected']} | {obs[0]} "
                     f"| {obs[1]} | {c['verdict']} |")
    lines += ["", "Dependencias de packs no permitidos: "
              + (", ".join(f"`{d['path']}` ({d['pack']})" for d in r["plan"]["pack_dependencies"])
                 or "ninguna") + ".",
              "No verificado: " + ", ".join(f"{n['category']} ({n['reason']})"
                                            for n in r["not_verified"]) + ".",
              "Limitaciones: " + ", ".join(r["limitations"]) + ".", ""]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("command", choices=("plan", "run"))
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[1]))
    ap.add_argument("--out", default=None, help=f"directorio (por defecto {DEFAULT_OUT})")
    ap.add_argument("--keep", action="store_true", help="conservar los snapshots temporales")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    out = Path(args.out) if args.out else root / DEFAULT_OUT
    try:
        candidate = load_json(root / CANDIDATE_PATH)
        if args.command == "plan":
            plan = plan_kernel(root, tracked_files(root), candidate)
            print(json.dumps({k: v for k, v in plan.items() if k != "paths"}
                             | {"files": len(plan["paths"])}, indent=2, sort_keys=True))
            return 0
        workdir = Path(tempfile.mkdtemp(prefix="se400-kernel-"))
        try:
            receipt = run_experiment(root, candidate, load_json(root / CORPUS_PATH), workdir)
        finally:
            if not args.keep:
                shutil.rmtree(workdir, ignore_errors=True)
    except InventoryError as exc:
        print(f"ABLATION-F3: INVALID {exc}", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    (out / f"{REPORT_NAME}.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                             encoding="utf-8")
    (out / f"{REPORT_NAME}.md").write_text(render_md(receipt), encoding="utf-8")
    print(f"ABLATION-F3: {receipt['decision']} {receipt['verdicts']} -> {out / REPORT_NAME}.json")
    return {"KERNEL_PRESERVES_CORPUS": 0, "ABORT_FALSE_ALLOW": 3}.get(receipt["decision"], 1)


if __name__ == "__main__":
    sys.exit(main())
