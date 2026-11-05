#!/usr/bin/env python3
"""overnight_handoff_digest.py — SE-471: núcleo del relevo nocturno con evidencia.

Solo lectura. Lee las marcas de fin `<runs>/<nombre>/done` (y opcionalmente un log
`<ISO> start|end <nombre> [rc=N]`) y separa por run lo declarado por el worker, lo
validado (CI y revisión) y lo aceptado (merge). Offline, `validado` y `aceptado` son
siempre `desconocido`: nunca se infieren. Con --online consulta `gh pr view` solo para
URL que pasen la allowlist, con el argumento tras `--` y sin shell.

Invocar mediante scripts/overnight-handoff-digest.sh (misma interfaz).
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys

PR_URL_ALLOW = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+$")
ESTADO_RE = re.compile(r"^[\s*#>_`-]*ESTADO[\s*_`]*:\s*[*_`]*\s*([^\W\d_]*)", re.IGNORECASE)
ESTADO_VALUES = {"OK": "OK", "PARCIAL": "PARCIAL", "FALLO": "FALLO"}
SIGUIENTE_RE = re.compile(r"^[\s*#>_`-]*(Siguiente|Pendiente\w*|Next)\b", re.IGNORECASE)
LABELED_URL_RE = re.compile(r"^[\s*#>_`-]*(PR|URL)[\s*_`]*:\s*(.*)$", re.IGNORECASE)
URLISH_RE = re.compile(r"\S*(?:github\.com|/pull/)\S*")
LOG_RE = re.compile(r"^(\S+)\s+(start|end)\s+(\S+)(?:\s+rc=(-?\d+))?\s*$")
MAX_MARK_BYTES = 64 * 1024
GH_FIELDS = "state,isDraft,reviewDecision,statusCheckRollup,mergedAt"
GH_TIMEOUT_S = 30

UNKNOWN = "desconocido"
CATEGORIES = [  # orden de decisiones de S1
    ("sin_marca_rc", "sin marca con end rc≠0"),
    ("fallo", "FALLO"),
    ("ok_no_validado", "OK con validado: no"),
    ("parcial", "PARCIAL"),
    ("malformada", "marca malformada"),
]
RED_CONCLUSIONS = {"FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "STARTUP_FAILURE", "ERROR"}
GREEN_CONCLUSIONS = {"SUCCESS", "NEUTRAL", "SKIPPED"}


def parse_iso(value: str) -> dt.datetime:
    v = value.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    t = dt.datetime.fromisoformat(v)
    if t.tzinfo is None:
        t = t.astimezone()  # sin zona: hora local
    return t


def iso(ts: float) -> str:
    return dt.datetime.fromtimestamp(ts, dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def clean_token(tok: str) -> str:
    """Quita envoltorio y puntuación final, y el fragmento `#…` de una URL https.

    Solo recorta: lo que queda debe casar la allowlist entera, así que `…/pull/1;id`
    sigue rechazada y a `gh` nunca llega nada más que la URL limpia.
    """
    tok = tok.strip()
    tok = tok.lstrip("(<[\"'`*")
    if tok.startswith("https://") and "#" in tok:
        tok = tok.split("#", 1)[0]
    while tok and tok[-1] in ".,;:)>]\"'`*":
        tok = tok[:-1]
    return tok


def parse_mark(text: str) -> dict:
    """Parser tolerante: lo que no reconoce sale `malformada`, nunca se adivina."""
    lines = [ln.rstrip() for ln in text.splitlines()]
    nonempty = [ln.strip() for ln in lines if ln.strip()]
    declarado, motivo, estado_line = "malformada", None, None
    for i, ln in enumerate(lines):
        m = ESTADO_RE.match(ln)
        if m:
            estado_line = i
            raw = m.group(1).upper()
            declarado = ESTADO_VALUES.get(raw, "malformada")
            motivo = ln[m.end():].strip(" \t—–-:,;") or None
            break

    siguiente = None
    for ln in nonempty:
        if SIGUIENTE_RE.match(ln):
            siguiente = ln
            break
    if siguiente is None:
        rest = [ln.strip() for i, ln in enumerate(lines) if ln.strip() and i != estado_line]
        if rest:
            siguiente = rest[-1]

    # URL candidata: campo etiquetado PR:/URL: (valor entero) o token con github.com o /pull/.
    candidate = None
    for ln in lines:
        lm = LABELED_URL_RE.match(ln)
        if lm and lm.group(2).strip():
            val = lm.group(2).strip()
            first = clean_token(val.split()[0])
            candidate = first if PR_URL_ALLOW.fullmatch(first) else val
            break
        um = URLISH_RE.search(ln)
        if um:
            candidate = clean_token(um.group(0))
            break
    pr_url, url_rechazada = None, False
    if candidate is not None:
        if PR_URL_ALLOW.fullmatch(candidate):
            pr_url = candidate
        else:
            url_rechazada = True
    return {"declarado": declarado, "motivo": motivo, "siguiente": siguiente,
            "pr_url": pr_url, "url_rechazada": url_rechazada, "vacia": not nonempty}


def read_log(path: str) -> dict:
    runs: dict[str, dict] = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LOG_RE.match(line.strip())
            if not m:
                continue
            ts_s, kind, name, rc = m.groups()
            try:
                ts = parse_iso(ts_s).timestamp()
            except ValueError:
                continue
            r = runs.setdefault(name, {"start": None, "end": None, "rc": None})
            if kind == "start":
                r["start"] = ts
            else:
                r["end"] = ts
                r["rc"] = int(rc) if rc is not None else None
    return runs


def ci_state(rollup) -> str:
    """verde | rojo | pendiente | sin_ci. Fail-closed: lo que no es verde explícito no es verde."""
    if not isinstance(rollup, list) or not rollup:
        return "sin_ci"
    red = pending = False
    for item in rollup:
        if not isinstance(item, dict):
            pending = True
            continue
        concl = item.get("conclusion")
        state = item.get("state")
        val = (concl or state or "")
        val = val.upper() if isinstance(val, str) else ""
        if val in RED_CONCLUSIONS:
            red = True
        elif val in GREEN_CONCLUSIONS:
            continue
        else:
            pending = True
    if red:
        return "rojo"
    return "pendiente" if pending else "verde"


def evaluate_pr(data: dict) -> tuple[str, str, str]:
    ci = ci_state(data.get("statusCheckRollup"))
    review = data.get("reviewDecision") or ""
    if ci == "rojo" or review == "CHANGES_REQUESTED":
        validado = "no"
    elif ci == "verde":
        validado = "sí"
    else:
        validado = UNKNOWN
    state = (data.get("state") or "").upper()
    if data.get("mergedAt") or state == "MERGED":
        aceptado = "sí"
    elif state == "CLOSED":
        aceptado = "no"
    else:
        aceptado = UNKNOWN
    return validado, aceptado, ci


def gh_view(gh: str, url: str):
    """Devuelve (dict|None, error|None). Lista de argumentos, URL tras `--`, sin shell."""
    try:
        cp = subprocess.run([gh, "pr", "view", "--json", GH_FIELDS, "--", url],
                            capture_output=True, text=True, timeout=GH_TIMEOUT_S,
                            stdin=subprocess.DEVNULL, shell=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, type(exc).__name__
    if cp.returncode != 0:
        return None, f"rc={cp.returncode}"
    try:
        data = json.loads(cp.stdout)
    except ValueError:
        return None, "json inválido"
    if not isinstance(data, dict):
        return None, "json inválido"
    return data, None


def build(args) -> dict:
    runs_dir = os.path.abspath(args.runs_dir)
    since_ts = parse_iso(args.since).timestamp() if args.since else None
    log = read_log(args.log) if args.log else {}

    names = set(log)
    with os.scandir(runs_dir) as it:
        for e in it:
            if e.is_dir(follow_symlinks=False):
                names.add(e.name)

    avisos: list[str] = []
    runs = []
    for name in sorted(names):
        mark = os.path.join(runs_dir, name, "done")
        lg = log.get(name, {})
        entry = {"nombre": name, "marca": mark, "declarado": "sin_marca", "validado": UNKNOWN,
                 "aceptado": UNKNOWN, "pr_url": None, "motivo": None, "siguiente": None,
                 "rc": lg.get("rc"), "avisos": []}
        ts = None
        if os.path.isfile(mark):
            ts = os.stat(mark).st_mtime
            with open(mark, "rb") as fh:
                raw = fh.read(MAX_MARK_BYTES)
            p = parse_mark(raw.decode("utf-8", errors="replace"))
            entry.update(declarado=p["declarado"], pr_url=p["pr_url"], motivo=p["motivo"],
                         siguiente=p["siguiente"])
            if p["url_rechazada"]:
                entry["avisos"].append("url_rechazada")
        else:
            ts = lg.get("end") or lg.get("start")
            if ts is None and os.path.isdir(os.path.join(runs_dir, name)):
                ts = os.stat(os.path.join(runs_dir, name)).st_mtime
        if since_ts is not None and (ts is None or ts < since_ts):
            continue
        entry["ts"] = ts
        runs.append(entry)

    online = bool(args.online)
    degradado = False
    if online:
        gh = shutil.which("gh")
        if not gh:
            degradado = True
            avisos.append("degradado a offline: gh no disponible")
        else:
            for r in runs:
                if not r["pr_url"]:
                    continue
                data, err = gh_view(gh, r["pr_url"])
                if err:
                    degradado = True
                    avisos.append(f"degradado a offline: gh falló en {r['nombre']} ({err}); "
                                  "el resto queda desconocido")
                    break
                r["validado"], r["aceptado"], r["ci"] = evaluate_pr(data)
                r["draft"] = bool(data.get("isDraft"))
                r["review"] = data.get("reviewDecision") or None
    rejected = sum(1 for r in runs if "url_rechazada" in r["avisos"])
    if rejected:
        avisos.append(f"{rejected} run(s) con url_rechazada: URL fuera de la allowlist, no consultada")

    buckets: dict[str, list] = {k: [] for k, _ in CATEGORIES}
    for r in runs:
        d = r["declarado"]
        if d == "sin_marca" and r["rc"] not in (None, 0):
            buckets["sin_marca_rc"].append(r)
        elif d == "FALLO":
            buckets["fallo"].append(r)
        elif d == "OK" and r["validado"] == "no":
            buckets["ok_no_validado"].append(r)
        elif d == "PARCIAL":
            buckets["parcial"].append(r)
        elif d == "malformada":
            buckets["malformada"].append(r)
    candidates = []
    for pos, (key, label) in enumerate(CATEGORIES, start=1):
        for r in buckets[key]:
            candidates.append({"posicion": pos, "categoria": key, "etiqueta": label,
                               "run": r["nombre"], "siguiente": r["siguiente"],
                               "marca": r["marca"], "pr_url": r["pr_url"]})
    listed = candidates[:args.max_decisions]

    totals = {k: 0 for k in ("OK", "PARCIAL", "FALLO", "sin_marca", "malformada")}
    for r in runs:
        totals[r["declarado"]] += 1
    tss = [r["ts"] for r in runs if r["ts"] is not None]
    ventana = {"desde": args.since or (iso(min(tss)) if tss else None),
               "hasta": iso(max(tss)) if tss else None}
    for r in runs:
        r.pop("ts", None)
    return {"version": 1, "modo": "offline" if (not online or degradado) else "online",
            "online_solicitado": online, "degradado": degradado, "runs_dir": runs_dir,
            "ventana": ventana, "totales": {"runs": len(runs), **totals},
            "avisos": avisos, "decisiones": listed,
            "sin_listar": len(candidates) - len(listed), "runs": runs}


def render_md(d: dict) -> str:
    t = d["totales"]
    out = ["# Relevo nocturno (SE-471)", "",
           f"Ventana: {d['ventana']['desde'] or '—'} → {d['ventana']['hasta'] or '—'} · modo {d['modo']}",
           f"Runs: {t['runs']} · OK {t['OK']} · PARCIAL {t['PARCIAL']} · FALLO {t['FALLO']} · "
           f"sin marca {t['sin_marca']} · malformada {t['malformada']}", ""]
    if d["modo"] == "offline":
        out.append("Offline: validado y aceptado = desconocido (no se infieren).")
        out.append("")
    for a in d["avisos"]:
        out.append(f"> Aviso: {a}")
    if d["avisos"]:
        out.append("")
    out.append("## Decisiones")
    out.append("")
    if not d["decisiones"]:
        out.append("Sin decisiones pendientes.")
    for i, x in enumerate(d["decisiones"], start=1):
        out.append(f"{i}. [{x['etiqueta']}] {x['run']} — {x['siguiente'] or '(sin «Siguiente»)'}")
        out.append(f"   marca: {x['marca']}" + (f" · PR: {x['pr_url']}" if x["pr_url"] else ""))
    if d["sin_listar"]:
        out.append("")
        out.append(f"+{d['sin_listar']} sin listar")
    out += ["", "## Runs", "", "| run | declarado | validado | aceptado | PR | avisos |", "|---|---|---|---|---|---|"]
    for r in d["runs"]:
        out.append(f"| {r['nombre']} | {r['declarado']} | {r['validado']} | {r['aceptado']} | "
                   f"{r['pr_url'] or '—'} | {', '.join(r['avisos']) or '—'} |")
    return "\n".join(out) + "\n"


def nonneg_int(v: str) -> int:
    n = int(v)
    if n < 0:
        raise argparse.ArgumentTypeError("debe ser >= 0")
    return n


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="overnight-handoff-digest.sh", allow_abbrev=False,
                                 description="Relevo nocturno con evidencia (SE-471). Solo lectura.")
    ap.add_argument("--runs-dir", required=True)
    ap.add_argument("--since")
    ap.add_argument("--log")
    ap.add_argument("--online", action="store_true")
    ap.add_argument("--max-decisions", type=nonneg_int, default=7)
    ap.add_argument("--format", choices=("md", "json"), default="md")
    args = ap.parse_args(argv)
    if not os.path.isdir(args.runs_dir):
        print(f"ERROR: --runs-dir no es un directorio: {args.runs_dir}", file=sys.stderr)
        return 2
    if args.log and not os.path.isfile(args.log):
        print(f"ERROR: --log no existe: {args.log}", file=sys.stderr)
        return 2
    if args.since:
        try:
            parse_iso(args.since)
        except ValueError:
            print(f"ERROR: --since no es ISO 8601: {args.since}", file=sys.stderr)
            return 2
    d = build(args)
    if args.format == "json":
        sys.stdout.write(json.dumps(d, ensure_ascii=False, indent=2) + "\n")
    else:
        sys.stdout.write(render_md(d))
    return 0


if __name__ == "__main__":
    sys.exit(main())
