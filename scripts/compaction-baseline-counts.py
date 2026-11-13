#!/usr/bin/env python3
"""SE-529 S0.3/S0.4 — líneas base de compactación: SOLO recuentos y tamaños.

Nunca copia ni imprime texto de transcripciones ni del almacén; los nombres de
proyecto se sustituyen por etiquetas P01.. (por orden de recuento). Salida: JSON.
"""
import argparse, glob, json, os, subprocess, sys, tempfile

TURN_TYPES = ("user", "assistant")


def pctl(vals, p):
    if not vals:
        return 0
    s = sorted(vals)
    return s[min(len(s) - 1, int(round(p * (len(s) - 1))))]


def anon(counter):
    ranked = sorted(counter.items(), key=lambda kv: -kv[1])
    return {"P%02d" % (i + 1): n for i, (_, n) in enumerate(ranked)}


def s03(tdir, hot_glob):
    out = {"sessions_scanned": 0, "compactions": 0, "by_trigger": {}, "by_project": {},
           "with_summary_line": 0, "session_hot_rows": 0}
    per_proj, tails = {}, []
    files = sorted(glob.glob(os.path.join(tdir, "*", "*.jsonl")))
    for f in files:
        out["sessions_scanned"] += 1
        proj = os.path.basename(os.path.dirname(f))
        lens, kinds = [], []
        try:
            with open(f, "rb") as fh:
                for ln in fh:
                    lens.append(len(ln))
                    k = None
                    if b"compact_boundary" in ln or b"isCompactSummary" in ln or b'"type":"user"' in ln or b'"type":"assistant"' in ln or b'"type": "user"' in ln or b'"type": "assistant"' in ln:
                        try:
                            o = json.loads(ln)
                        except Exception:
                            o = None
                        if isinstance(o, dict):
                            if o.get("type") == "system" and o.get("subtype") == "compact_boundary":
                                md = o.get("compactMetadata")
                                trig = md.get("trigger") if isinstance(md, dict) else None
                                k = ("B", trig if trig in ("auto", "manual") else "unknown")
                            elif o.get("isCompactSummary") is True:
                                k = ("S", None)
                            elif o.get("type") in TURN_TYPES:
                                k = ("T", None)
                    kinds.append(k)
        except OSError:
            continue
        for i, k in enumerate(kinds):
            if k and k[0] == "S":
                out["with_summary_line"] += 1
            if k and k[0] == "B":
                out["compactions"] += 1
                out["by_trigger"][k[1]] = out["by_trigger"].get(k[1], 0) + 1
                per_proj[proj] = per_proj.get(proj, 0) + 1
                # bytes desde el final del transcript previo a esta frontera, cubriendo 30 turnos
                turns, j, total = 0, i - 1, 0
                while j >= 0 and turns < 30:
                    total += lens[j]
                    if kinds[j] and kinds[j][0] == "T":
                        turns += 1
                    j -= 1
                tails.append({"bytes": total, "turns": turns})
    out["by_project"] = anon(per_proj)
    out["tail_bytes_30_turns"] = {
        "n": len(tails), "p50": pctl([t["bytes"] for t in tails], .5),
        "p90": pctl([t["bytes"] for t in tails], .9), "max": max([t["bytes"] for t in tails], default=0),
        "boundaries_with_fewer_than_30_turns": sum(1 for t in tails if t["turns"] < 30)}
    for h in glob.glob(hot_glob):
        try:
            with open(h, "rb") as fh:
                out["session_hot_rows"] += sum(1 for ln in fh if ln.startswith(b"## Session Context"))
        except OSError:
            pass
    return out


def s04(store, post_script, active):
    out = {"store_present": os.path.isfile(store), "entries": 0, "corrupt_lines": 0}
    rows = []
    if out["store_present"]:
        with open(store, "rb") as fh:
            for ln in fh:
                if not ln.strip():
                    continue
                try:
                    o = json.loads(ln)
                except Exception:
                    out["corrupt_lines"] += 1
                    continue
                if isinstance(o, dict):
                    rows.append(o)
    n = len(rows)
    out["entries"] = n
    proj, tier = {}, {}
    for r in rows:
        p = str(r.get("project"))
        proj[p] = proj.get(p, 0) + 1
        t = str(r.get("importance_tier"))
        tier[t] = tier.get(t, 0) + 1
    nulls = proj.pop("null", 0) + proj.pop("None", 0)
    out["null_project"] = nulls
    out["null_share"] = round(nulls / n, 3) if n else 0
    out["named_projects"] = len(proj)
    out["by_project_named"] = anon(proj)
    out["by_tier"] = dict(sorted(tier.items()))
    out["tier_a_share"] = round(tier.get("A", 0) / n, 3) if n else 0
    out["precompact_autosave_entries"] = sum(
        1 for r in rows if "pre-compact" in str(r.get("title", "")).lower()
        or "pre-compact" in str(r.get("goal", "")).lower())
    last = rows[-20:]
    out["active_project_in_last20"] = {
        "count": sum(1 for r in last if active and str(r.get("project")) == active),
        "of": len(last), "active_project_given": bool(active)}
    out["post_compaction_stdout_bytes"] = None
    out["post_compaction_exit"] = None
    if post_script and os.path.isfile(post_script) and out["store_present"]:
        root = os.path.dirname(os.path.dirname(os.path.abspath(store)))
        with tempfile.TemporaryDirectory() as home:
            env = {"PATH": os.environ.get("PATH", ""), "HOME": home, "PROJECT_ROOT": root,
                   "CLAUDE_PROJECT_DIR": home}
            try:
                p = subprocess.run(["bash", post_script], cwd=root, env=env, capture_output=True,
                                   timeout=30)
                out["post_compaction_stdout_bytes"] = len(p.stdout)
                out["post_compaction_exit"] = p.returncode
                out["post_compaction_stdout_lines"] = p.stdout.count(b"\n")
            except Exception as e:
                out["post_compaction_exit"] = type(e).__name__
    return out


def main():
    ap = argparse.ArgumentParser()
    home = os.path.expanduser("~")
    ap.add_argument("--transcripts-dir", default=os.path.join(home, ".claude", "projects"))
    ap.add_argument("--store", required=True)
    ap.add_argument("--post-script", default="")
    ap.add_argument("--active-project", default="")
    a = ap.parse_args()
    hot = os.path.join(a.transcripts_dir, "*", "memory", "session-hot.md")
    print(json.dumps({"s03": s03(a.transcripts_dir, hot),
                      "s04": s04(a.store, a.post_script, a.active_project)}, indent=1, sort_keys=True))


if __name__ == "__main__":
    main()
