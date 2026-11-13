#!/usr/bin/env python3
"""SE-511 D4 — A/B del contexto de arranque (método de EXP-509, casos de arranque).

  build   construye variants/A.md (CLAUDE.md de --base-ref con imports resueltos)
          y variants/B.md (CLAUDE.md de --b-ref, o del árbol de trabajo), con el mismo
          perfil ficticio. La ejecución registrada usó A=3a36128b7 y B=5ea2b1d39.
  run     llama a cada modelo con la variante como system prompt y el caso como único
          mensaje (claude -p, sin herramientas, sin settings, sin MCP, sin persistencia).
  analyze diferencias pareadas por caso B − A con IC 95 % bootstrap y veredicto.

Prerregistro: docs/evidence/SE-511-D4-prerregistro.md (commiteado antes de la 1.ª llamada).
"""
import argparse
import concurrent.futures as cf
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, HERE)
import checks  # noqa: E402

SEED = 20261110
TIMEOUT = 240
B_ITERS = 10000
PROFILE = """# Perfil activo (ficticio, igual en A y B)
- nombre: Operadora de prueba
- rol: investigadora y operadora única del workspace
- preferences.md → language: es (español de España)
- tone.md → formality: casual · alert_style: direct · honesty: radical
"""
IMPORT_LINE = re.compile(r"^@([\w./-]+)\s*$")


def read_at(ref, path):
    if ref is None:
        return open(os.path.join(ROOT, path), encoding="utf-8").read()
    return subprocess.run(["git", "-C", ROOT, "show", f"{ref}:{path}"], capture_output=True,
                          text=True, check=True).stdout


def resolve(ref, path, seen=()):
    out = []
    for line in read_at(ref, path).splitlines():
        m = IMPORT_LINE.match(line.strip())
        if not m:
            out.append(line)
            continue
        p = m.group(1)
        if p == ".claude/profiles/active-user.md":
            out.append(PROFILE.rstrip())
        elif p == ".claude/external-memory/auto/MEMORY.md":
            out.append("(índice de memoria vacío)")
        else:
            if p in seen:
                raise SystemExit(f"ciclo de imports: {p}")
            out.append(resolve(ref, p, seen + (p,)))
    return "\n".join(out)


def build(base_ref, b_ref=None):
    os.makedirs(os.path.join(HERE, "variants"), exist_ok=True)
    meta = {}
    for v, ref in (("A", base_ref), ("B", b_ref)):
        txt = resolve(ref, "CLAUDE.md") + "\n"
        open(os.path.join(HERE, "variants", f"{v}.md"), "w", encoding="utf-8").write(txt)
        meta[v] = {"ref": ref or "worktree", "chars": len(txt), "bytes": len(txt.encode()),
                   "sha256": hashlib.sha256(txt.encode()).hexdigest()}
    json.dump(meta, open(os.path.join(HERE, "variants", "meta.json"), "w"), indent=1)
    print(json.dumps(meta, indent=1))


def call(model, sp_text, msg):
    d = tempfile.mkdtemp(prefix="se511d4-")
    try:
        sp = os.path.join(d, ".sp.md")
        open(sp, "w", encoding="utf-8").write(sp_text)
        cmd = ["claude", "-p", "--model", model, "--tools", "", "--system-prompt-file", sp,
               "--setting-sources", "", "--strict-mcp-config", "--no-session-persistence",
               "--output-format", "json"]
        t0 = time.time()
        p = subprocess.run(cmd, input=msg, capture_output=True, text=True, timeout=TIMEOUT, cwd=d)
        dt = time.time() - t0
        leftover = sorted(set(os.listdir(d)) - {".sp.md"})
        if p.returncode != 0:
            return {"status": "error", "error": f"rc={p.returncode} {p.stderr[-200:]}", "duration_s": dt}
        j = json.loads(p.stdout)
        u = j.get("usage", {})
        text = (j.get("result") or "").replace(os.path.expanduser("~") + "/", "~/")
        tin = sum(u.get(k) or 0 for k in ("input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"))
        st = "ok" if text.strip() and not j.get("is_error") else "error"
        if leftover or (j.get("num_turns") or 1) != 1:
            st = "tool_effect"
        return {"status": st, "text": text, "tokens_in": tin, "tokens_out": u.get("output_tokens") or 0,
                "duration_s": round(dt, 1), "model_resolved": ",".join((j.get("modelUsage") or {}).keys())}
    except subprocess.TimeoutExpired:
        return {"status": "error", "error": "timeout"}
    finally:
        shutil.rmtree(d, ignore_errors=True)


def run(models, reps, workers, raw_path, max_calls, variant="B", only=None):
    cases = json.load(open(os.path.join(HERE, "corpus.json")))["cases"]
    if only:
        # Un id inexistente (errata) no puede dejar la corrida en cero casos con exit 0 (revisión de #1527).
        unknown = sorted(set(only) - {c["id"] for c in cases})
        if unknown:
            raise SystemExit(f"--cases con ids inexistentes en el corpus: {','.join(unknown)}")
        cases = [c for c in cases if c["id"] in only]
    sp = {v: open(os.path.join(HERE, "variants", f"{v}.md"), encoding="utf-8").read() for v in ("A", variant)}
    done = set()
    if os.path.exists(raw_path):
        for l in open(raw_path):
            r = json.loads(l)
            if r["status"] == "ok":
                done.add((r["model"], r["variant"], r["case"], r["rep"]))
    units = [(m, v, c["id"], c["msg"], k) for m in models for v in ("A", variant) for c in cases for k in range(reps)]
    random.Random(SEED).shuffle(units)
    todo = [u for u in units if (u[0], u[1], u[2], u[4]) not in done]
    print(f"unidades {len(units)}, pendientes {len(todo)}", file=sys.stderr)
    calls = 0

    def one(u):
        m, v, cid, msg, k = u
        for attempt in range(3):
            r = call(m, sp[v], msg)
            if r["status"] == "ok":
                break
        r.update({"model": m, "variant": v, "case": cid, "rep": k, "attempts": attempt + 1})
        if r["status"] == "ok":
            r["verdict"] = checks.check(cid, r["text"])
        return r

    with cf.ThreadPoolExecutor(workers) as ex, open(raw_path, "a") as fo:
        for r in ex.map(one, todo[:max_calls]):
            calls += r["attempts"]
            fo.write(json.dumps(r, ensure_ascii=False) + "\n")
            fo.flush()
            print(f"{r['model']} {r['variant']} {r['case']} {r['rep']} {r['status']} {r.get('verdict')}", file=sys.stderr)
    print(f"llamadas {calls}", file=sys.stderr)


def boot(diffs_by_case, iters=B_ITERS, seed=SEED):
    rng = random.Random(seed)
    keys = sorted(diffs_by_case)
    vals = [diffs_by_case[k] for k in keys]
    n = len(vals)
    means = sorted(sum(vals[rng.randrange(n)] for _ in range(n)) / n for _ in range(iters))
    return sum(vals) / n, means[int(0.025 * iters)], means[int(0.975 * iters) - 1]


def analyze(raw_path, out_path, variant="B"):
    rows = [json.loads(l) for l in open(raw_path)]
    ok = {}
    for r in rows:
        if r["status"] == "ok" and r["variant"] in ("A", variant):
            r["variant"] = "A" if r["variant"] == "A" else "B"
            r["verdict"] = checks.check(r["case"], r["text"])  # se recalcula: checks.py es la fuente
            ok[(r["model"], r["variant"], r["case"], r["rep"])] = r
    models = sorted({k[0] for k in ok})
    cases = json.load(open(os.path.join(HERE, "corpus.json")))["cases"]
    res = {"seed": SEED, "iters": B_ITERS, "models": {}}
    for m in models:
        per = {}
        for c in cases:
            for v in "AB":
                rs = [x for (mm, vv, cc, _), x in ok.items() if mm == m and vv == v and cc == c["id"]]
                if not rs:
                    continue
                good = sum(x["verdict"] == "pass" for x in rs) / len(rs)
                per.setdefault(c["id"], {})[v] = {"y": good if c["type"] == "trap" else 1 - good, "n": len(rs),
                                                   "tin": sum(x["tokens_in"] for x in rs) / len(rs),
                                                   "tout": sum(x["tokens_out"] for x in rs) / len(rs)}
        out = {}
        for tipo, name in (("trap", "cumplimiento"), ("golden", "sobreactuacion")):
            ids = [c["id"] for c in cases if c["type"] == tipo and set(per.get(c["id"], {})) == {"A", "B"}]
            a = sum(per[i]["A"]["y"] for i in ids) / len(ids)
            b = sum(per[i]["B"]["y"] for i in ids) / len(ids)
            d, lo, hi = boot({i: per[i]["B"]["y"] - per[i]["A"]["y"] for i in ids})
            out[name] = {"A": round(a, 4), "B": round(b, 4), "diff": round(d, 4), "ci95": [round(lo, 4), round(hi, 4)], "casos": len(ids)}
        ids = [i for i in per if set(per[i]) == {"A", "B"}]
        tin = {v: sum(per[i][v]["tin"] for i in ids) / len(ids) for v in "AB"}
        tout = {v: sum(per[i][v]["tout"] for i in ids) / len(ids) for v in "AB"}
        out["tokens_entrada"] = {"A": round(tin["A"]), "B": round(tin["B"]), "delta_pct": round(100 * (tin["B"] / tin["A"] - 1), 1)}
        out["tokens_salida"] = {"A": round(tout["A"]), "B": round(tout["B"]), "delta_pct": round(100 * (tout["B"] / tout["A"] - 1), 1)}
        out["n_respuestas"] = {v: sum(1 for k in ok if k[0] == m and k[1] == v) for v in "AB"}
        out["por_caso"] = {i: {v: round(per[i][v]["y"], 3) for v in per[i]} for i in sorted(per)}
        out["veredicto"] = verdict(out)
        res["models"][m] = out
    vs = [o["veredicto"] for o in res["models"].values()]
    res["global"] = "REVERT" if "REVERT" in vs else ("GO" if vs and all(v == "GO" for v in vs) else "NO CONCLUYENTE")
    json.dump(res, open(out_path, "w"), indent=1, ensure_ascii=False)
    print(json.dumps({m: {k: o[k] for k in ("cumplimiento", "sobreactuacion", "tokens_entrada", "veredicto")} for m, o in res["models"].items()}, indent=1, ensure_ascii=False))
    print("GLOBAL", res["global"])


def verdict(o):
    """Regla prerregistrada (docs/evidence/SE-511-D4-prerregistro.md § Decisión)."""
    c, s = o["cumplimiento"], o["sobreactuacion"]
    if c["diff"] < -0.05 or s["diff"] > 0.10:
        return "REVERT"
    if c["ci95"][0] > -0.05 and s["diff"] <= 0 and s["ci95"][1] <= 0.10:
        return "GO"
    return "NO CONCLUYENTE"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["build", "run", "analyze"])
    ap.add_argument("--base-ref", default="origin/main")
    ap.add_argument("--b-ref", default=None, help="commit de la variante B (por defecto, árbol de trabajo)")
    ap.add_argument("--models", default="sonnet,haiku")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--max-calls", type=int, default=400)
    ap.add_argument("--variant", default="B", help="variante a comparar con A (B, B2)")
    ap.add_argument("--cases", default=None, help="ids separados por coma (solo run)")
    ap.add_argument("--raw", default=os.path.join(HERE, "results", "raw.jsonl"))
    ap.add_argument("--out", default=os.path.join(HERE, "results", "summary.json"))
    a = ap.parse_args()
    if a.cmd == "build":
        build(a.base_ref, a.b_ref)
    elif a.cmd == "run":
        run(a.models.split(","), a.reps, a.workers, a.raw, a.max_calls, a.variant, a.cases.split(",") if a.cases else None)
    else:
        analyze(a.raw, a.out, a.variant)


if __name__ == "__main__":
    main()
