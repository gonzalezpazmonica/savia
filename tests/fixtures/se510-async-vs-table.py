#!/usr/bin/env python3
"""SE-510 S3: comprueba de forma independiente del generador que la columna bloqueante
de la tabla refleja `async` de settings.json (async:true => no; si no, yes).
Uso: se510-async-vs-table.py <settings.json> <routing-pretooluse.tsv>; exit 0 si coincide."""
import json
import sys


def main(settings_path, table_path):
    s = json.load(open(settings_path, encoding="utf-8"))
    want = {}
    for g in s["hooks"]["PreToolUse"]:
        for h in g["hooks"]:
            if h.get("type") == "command":
                name = h["command"].split("/")[-1].split()[0]
                want.setdefault(name, set()).add("no" if h.get("async") is True else "yes")
    got = {}
    for line in open(table_path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        f = line.rstrip("\n").split("\t")
        got.setdefault(f[1].split()[0].split("/")[-1], set()).add(f[3])
    if "no" not in want.get("live-progress-hook.sh", set()):
        print("settings.json sin el hook async esperado (live-progress-hook)", file=sys.stderr)
        return 1
    if got != want:
        diff = {k: (got.get(k), want.get(k)) for k in set(got) | set(want) if got.get(k) != want.get(k)}
        print(f"bloqueante no refleja async: {diff}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
