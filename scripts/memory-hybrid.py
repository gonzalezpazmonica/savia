#!/usr/bin/env python3
"""Hybrid memory search — vector + graph + grep + domain routing (SPEC-035/038).

Source of truth: JSONL (.md-backed). Indices are derived caches.
Fallback: hybrid -> vector -> graph -> grep (always works).

Usage:
    python3 memory-hybrid.py search "query" [--top K] [--store PATH] [--mode MODE]
    python3 memory-hybrid.py status [--store PATH]
"""
import argparse, json, os, subprocess, importlib.util
from pathlib import Path

ROOT = Path(os.environ.get("PROJECT_ROOT", Path(__file__).parent.parent))
SCRIPTS = ROOT / "scripts"
DEFAULT_STORE = os.environ.get("STORE_FILE", str(ROOT / "output/.memory-store.jsonl"))

def _run_vector(query, top, store):
    try:
        r = subprocess.run(["python3", str(SCRIPTS / "memory-vector.py"), "search", query,
             "--top", str(top * 2), "--store", store], capture_output=True, text=True, timeout=15)
        if r.returncode == 0 and r.stdout.strip():
            data = json.loads(r.stdout)
            if not data.get("fallback") and data.get("results"):
                return [{"source": "vector", **e} for e in data["results"]]
    except Exception: pass
    return []

def _run_graph(query, top, store):
    try:
        r = subprocess.run(["python3", str(SCRIPTS / "memory-graph.py"), "search", query,
             "--store", store], capture_output=True, text=True, timeout=15)
        if r.returncode == 0 and r.stdout.strip():
            results = []
            for line in r.stdout.strip().split("\n"):
                line = line.strip()
                if line.startswith("-") or line.startswith("["):
                    results.append({"source": "graph", "title": line.lstrip("- "),
                                    "score": 0.5, "topic_key": "", "type": "graph"})
            return results[:top * 2]
    except Exception: pass
    return []

def _load_domains():
    p = SCRIPTS / "memory-domains.py"
    if not p.exists(): return None
    try:
        spec = importlib.util.spec_from_file_location("memory_domains", str(p))
        mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
        return mod
    except Exception: return None

def _domain_filter(query):
    mod = _load_domains()
    if not mod: return None, None
    domains = mod.top_domains(query)
    return (set(domains[:2]) if domains else None), mod

def _run_grep(query, top, store, df=None, dmod=None, min_origin=None):
    results = []
    if not os.path.exists(store): return results
    ql = query.lower()
    with open(store) as f:
        for line in f:
            if ql not in line.lower(): continue
            try:
                e = json.loads(line.strip())
                if e.get("valid_to"): continue
                if df and dmod and dmod.classify_entry(e) not in df: continue
                results.append({"source": "grep", "title": e.get("title", ""),
                    "score": 0.3, "topic_key": e.get("topic_key", ""),
                    "type": e.get("type", ""), "ts": e.get("ts", ""),
                    "sector": e.get("sector", "semantic"), "origin": e.get("origin") or "untrusted"})
            except json.JSONDecodeError: continue
    # SE-352: filtrar antes del recorte a top; si no, untrusted recientes tapan owner antiguos.
    if min_origin: results = _origin_mod().filter_origin(results, store, min_origin)
    return results[-top:]

def _origin_mod():
    # SE-352. Sin el módulo no se puede filtrar: la excepción sube, el proceso sale != 0 y sin salida.
    spec = importlib.util.spec_from_file_location("memory_origin", str(SCRIPTS / "memory-origin.py"))
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

def _dedup(vec, graph, grep, top):
    seen = {}
    for item in vec + graph + grep:
        key = item.get("title", "")[:80]
        if key in seen:
            seen[key]["score"] = min(1.0, seen[key]["score"] + 0.15)
            seen[key]["sources"] = seen[key].get("sources", seen[key]["source"]) + "+" + item["source"]
        else: seen[key] = item
    return sorted(seen.values(), key=lambda x: x.get("score", 0), reverse=True)[:top]

def cmd_search(query, top, store, mode, min_origin=None):
    vec, graph, grep = [], [], []
    df, dmod = _domain_filter(query) if mode != "naive" else (None, None)
    if mode in ("hybrid", "vector"): vec = _run_vector(query, top, store)
    if mode in ("hybrid", "graph"): graph = _run_graph(query, top, store)
    if mode == "naive" or (mode == "hybrid" and not vec and not graph):
        grep = _run_grep(query, top, store, df, dmod, min_origin)
    if mode == "hybrid" and (vec or graph):
        grep = _run_grep(query, top, store, df, dmod, min_origin)
    # SE-352: grep ya viene filtrado; vector y grafo, antes de dedup/top.
    if min_origin:
        fo = _origin_mod().filter_origin
        vec, graph = fo(vec, store, min_origin), fo(graph, store, min_origin)
    results = _dedup(vec, graph, grep, top)
    if not results:
        print(json.dumps({"results": [], "mode": mode, "fallback": True})); return
    print(json.dumps({"results": results, "mode": mode, "fallback": False,
          "domains": list(df) if df else [],
          "sources": {"vector": len(vec), "graph": len(graph), "grep": len(grep)}}, ensure_ascii=False))

def cmd_status(store):
    vi, gi = store.replace(".jsonl", "-index.idx"), store.replace(".jsonl", "-graph.json")
    print(f"Store: {store} — {'exists' if os.path.exists(store) else 'MISSING'}")
    print(f"Vector: {'available' if os.path.exists(vi) else 'not built'}")
    print(f"Graph: {'available' if os.path.exists(gi) else 'not built'}")
    a = [];
    if os.path.exists(vi): a.append("vector")
    if os.path.exists(gi): a.append("graph")
    a.append("grep")
    print(f"Best: {'hybrid' if len(a)>=3 else a[0]} ({'+'.join(a)})")

if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Hybrid memory search (SPEC-035/038)")
    sub = p.add_subparsers(dest="cmd")
    s = sub.add_parser("search"); s.add_argument("query")
    s.add_argument("--top", type=int, default=5); s.add_argument("--store", default=DEFAULT_STORE)
    s.add_argument("--mode", choices=["hybrid","vector","graph","naive"], default="hybrid")
    s.add_argument("--min-origin", choices=["owner","agent","untrusted","system"], default=None)
    st = sub.add_parser("status"); st.add_argument("--store", default=DEFAULT_STORE)
    args = p.parse_args()
    if args.cmd == "search": cmd_search(args.query, args.top, args.store, args.mode, args.min_origin)
    elif args.cmd == "status": cmd_status(args.store)
    else: p.print_help()
