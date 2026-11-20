#!/usr/bin/env python3
"""SE-529 S0.1/S0.2 — sonda de un solo uso (sustituye a la versión en bash).

Fuerza /compact con `claude -p` en un directorio desechable, con el colector de forma
activo y dos marcas aleatorias sin significado (una impresa por PostCompact, otra por
SessionStart origen compact). En el turno siguiente pregunta qué marcas ve el modelo.
No toca settings.json: usa --settings con un fichero temporal. Cuesta tokens.

Uso: compaction-shape-probe.py [--rounds N] [--model M] [--out DIR] [--dry-run]
"""
import argparse, os, shlex, secrets, shutil, subprocess, sys, tempfile, uuid

HERE = os.path.dirname(os.path.abspath(__file__))
COL = os.path.join(HERE, "compaction-shape-collector.py")


def build(out, m1, m2):
    log = os.path.join(out, "shape.jsonl")
    hooks = {}
    for name, event, mark in (("pre", "PreCompact", None), ("post", "PostCompact", m1),
                              ("sc", "SessionStart", m2), ("ss", "SessionStart", None)):
        f = os.path.join(out, "hooks", name + ".sh")
        lines = ["#!/bin/bash",
                 f"cat | SAVIA_COMPACT_SHAPE=1 SAVIA_COMPACT_SHAPE_LOG={shlex.quote(log)} "
                 f"python3 -I {shlex.quote(COL)} --event {event} --frontend claude-code"]
        if mark:  # la marca se lee de un fichero: la orden del hook no la contiene
            lines.append(f"printf 'ZMK-%s\\n' \"$(cat {shlex.quote(mark)})\"")
        with open(f, "w") as fh:
            fh.write("\n".join(lines) + "\n")
        os.chmod(f, 0o755)
        hooks[name] = f
    import json
    cmd = lambda p: {"type": "command", "command": shlex.quote(p)}
    settings = {"hooks": {
        "PreCompact": [{"hooks": [cmd(hooks["pre"])]}],
        "PostCompact": [{"hooks": [cmd(hooks["post"])]}],
        "SessionStart": [{"matcher": "compact", "hooks": [cmd(hooks["sc"])]},
                         {"matcher": "startup", "hooks": [cmd(hooks["ss"])]},
                         {"matcher": "resume", "hooks": [cmd(hooks["ss"])]}]}}
    sp = os.path.join(out, "settings.json")
    with open(sp, "w") as fh:
        json.dump(settings, fh, indent=1)
    return sp, log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--model", default="haiku")
    ap.add_argument("--out", default="")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.rounds < 1:
        sys.exit("rounds debe ser >= 1")
    out = a.out or tempfile.mkdtemp(prefix="se529-probe-")
    os.makedirs(os.path.join(out, "work"), exist_ok=True)
    os.makedirs(os.path.join(out, "hooks"), exist_ok=True)
    m1, m2 = os.path.join(out, "m1"), os.path.join(out, "m2")
    sp, log = build(out, m1, m2)
    if a.dry_run:
        print(open(sp).read())
        return
    if not shutil.which("claude"):
        sys.exit("claude no disponible")
    print("round\tpostcompact_mark\tsessionstart_compact_mark")
    for i in range(1, a.rounds + 1):
        v1, v2 = secrets.token_hex(6), secrets.token_hex(6)
        open(m1, "w").write(v1 + "\n"); open(m2, "w").write(v2 + "\n")
        sid = str(uuid.uuid4())
        base = ["claude", "-p", "--model", a.model, "--settings", sp]
        def run(extra, timeout):
            return subprocess.run(base + extra, cwd=os.path.join(out, "work"), stdin=subprocess.DEVNULL,
                                  capture_output=True, text=True, timeout=timeout)
        try:
            run(["--session-id", sid, "Responde solo: ok. Dato de prueba: el color es azul."], 150)
            run(["--resume", sid, "/compact"], 200)
            ans = run(["--resume", sid, "Lista cada cadena con patron ZMK- y 12 hex visible en tu contexto, "
                       "sin adivinar. Si no ves ninguna, di NINGUNA."], 150).stdout
        except subprocess.TimeoutExpired:
            ans = ""
        print(f"{i}\t{'si' if 'ZMK-' + v1 in ans else 'no'}\t{'si' if 'ZMK-' + v2 in ans else 'no'}")
    print("registro de forma:", log, file=sys.stderr)


if __name__ == "__main__":
    main()
