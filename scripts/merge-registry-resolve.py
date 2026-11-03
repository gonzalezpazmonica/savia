#!/usr/bin/env python3
"""merge-registry-resolve.py — SE-500 S2: resolutor determinista de registros y tabla canónica de derivados.

Lo ejecuta merge-sprint.sh desde una copia congelada (resolver_blob del manifiesto), nunca desde la rama
de la PR. Python stdlib, sin red, sin reloj: misma entrada, misma salida byte a byte.

  refs    --repo R --head H0 --base-ref REF [--branch B]      ids SE-NNN referenciados por la PR (JSON)
  resolve --repo R --base MB --head H0 --main M --refs JSON --path P --out F
                                                              registro resuelto en F · 2 = rechazo (imprime P)
  kind    P                                                   «forma generador…» del derivado · 2 = sin fila
  same    P A B                                               0 iguales en forma canónica · 1 distintos · 2 inválido

Rechazar es salir con 2: merge-sprint.sh aparca la PR con conflicto_real. Nunca consulta un LLM.
"""
import json
import os
import re
import subprocess
import sys

REGISTRIES = ("docs/propuestas/planning-state.json", "docs/propuestas/LOG.md")

# Tabla cerrada de derivados (SE-500 §Comparación canónica): forma comparada y generadores que la producen.
# Un derivado sin fila no es equivalente (fail-closed). Se aplica con re.fullmatch.
DERIVED = (
    (r"\.scm/.+", "bytes", ("scripts/generate-capability-map.py", "scripts/sam.py")),
    (r"docs/rules/INDEX\.md", "bytes", ("scripts/rules-index-generate.sh",)),
    (r"docs/propuestas/ROADMAP-CURRENT\.md", "bytes", ("scripts/roadmap.sh",)),
    (r"docs/propuestas/INDEX\.md", "index_md", ("scripts/propuestas-index-gen.sh",)),
    (r"docs/rules/domain/rule-manifest\.json", "rule_manifest", ("scripts/rule-manifest-generate.sh",)),
    (r"\.confidentiality-signature", "audit", ("scripts/confidentiality-scan.sh", "scripts/confidentiality-sign.sh")),
)
INDEX_DATE = re.compile(r"<!-- Last regenerated: [0-9TZ:-]+ -->")
MANIFEST_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z")
SPEC_ID = re.compile(r"SE-[0-9]+")


class Reject(Exception):
    pass


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True)
    return r.stdout if r.returncode == 0 else None


def blob(repo, rev, path):
    return git(repo, "show", f"{rev}:{path}")


def spec_num(i):
    return int(i[3:])


# ── refs: lista congelada en el manifiesto; nunca sale del título ni del cuerpo de la PR ──
def cmd_refs(a):
    found = set(SPEC_ID.findall(a.get("branch", "")))
    mb = git(a["repo"], "merge-base", a["head"], a["base-ref"])
    if mb is not None:
        log = git(a["repo"], "log", "--format=%B", f"{mb.decode().strip()}..{a['head']}")
        if log is None:
            raise Reject("log ilegible")
        found |= set(SPEC_ID.findall(log.decode("utf-8", "replace")))
        summary = blob(a["repo"], a["head"], ".pr-summary.md")
        if summary is not None:
            found |= set(SPEC_ID.findall(summary.decode("utf-8", "replace")))
    print(json.dumps(sorted(found, key=spec_num)))


# ── planning-state.json: main + delta de iniciativas de H0 frente al merge-base ──
def load_state(raw, name):
    if raw is None:
        raise Reject(f"{name}: ausente")
    try:
        d = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise Reject(f"{name}: JSON inválido")
    if not isinstance(d, dict) or not isinstance(d.get("initiatives"), list):
        raise Reject(f"{name}: sin lista initiatives")
    ids = []
    for it in d["initiatives"]:
        if not isinstance(it, dict) or not isinstance(it.get("id"), str):
            raise Reject(f"{name}: iniciativa sin id")
        ids.append(it["id"])
    if len(ids) != len(set(ids)):
        raise Reject(f"{name}: ids duplicados")
    return d, {it["id"]: it for it in d["initiatives"]}


def resolve_state(base_raw, head_raw, main_raw, refs):
    base, bmap = load_state(base_raw, "merge-base")
    head, hmap = load_state(head_raw, "head")
    main, mmap = load_state(main_raw, "main")
    for k in sorted(set(base) | set(head)):
        if k != "initiatives" and base.get(k, Reject) != head.get(k, Reject):
            raise Reject(f"la PR cambia la clave {k}")
    if set(bmap) - set(hmap):
        raise Reject("la PR borra iniciativas: " + ",".join(sorted(set(bmap) - set(hmap))))
    changed = [i for i in hmap if bmap.get(i) != hmap[i]]          # orden de H0: determinista
    for i in changed:
        if i not in refs:
            raise Reject(f"la PR cambia {i}, que no referencia")
        if i in bmap and mmap.get(i) not in (bmap[i], hmap[i]):
            raise Reject(f"main también cambió {i} con otro valor")
        if i not in bmap and i in mmap and mmap[i] != hmap[i]:
            raise Reject(f"main también dio de alta {i} con otro valor")
    out = [hmap[it["id"]] if it["id"] in changed else it for it in main["initiatives"]]
    out += [hmap[i] for i in changed if i not in mmap]
    main["initiatives"] = out
    return (json.dumps(main, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


# ── LOG.md: append-only; las entradas nuevas de H0 van arriba, sobre las de main ──
def split_log(raw, name):
    if raw is None:
        raise Reject(f"{name}: ausente")
    try:
        lines = raw.decode("utf-8").splitlines(keepends=True)
    except UnicodeDecodeError:
        raise Reject(f"{name}: no es UTF-8")
    head, entries = [], []
    for l in lines:
        if l.startswith("## "):
            entries.append([l])
        elif entries:
            entries[-1].append(l)
        else:
            head.append(l)
    return "".join(head), ["".join(e) for e in entries]


def resolve_log(base_raw, head_raw, main_raw):
    bh, be = split_log(base_raw, "merge-base")
    hh, he = split_log(head_raw, "head")
    mh, me = split_log(main_raw, "main")
    if bh != hh:
        raise Reject("la PR cambia la cabecera de LOG.md")
    # Las entradas de la base deben seguir en H0, intactas y en orden; lo demás es lo que la PR añade.
    added, j = [], 0
    for e in he:
        if j < len(be) and e == be[j]:
            j += 1
        else:
            added.append(e)
    if j != len(be):
        raise Reject("la PR modifica o borra entradas existentes de LOG.md")
    if added and not added[-1].endswith("\n\n") and me:
        raise Reject("entrada nueva sin línea en blanco final")
    added = [e for e in added if e not in me]
    return (mh + "".join(added) + "".join(me)).encode("utf-8")


def cmd_resolve(a):
    path = a["path"]
    if path not in REGISTRIES:
        raise Reject(f"{path}: no es un registro")
    try:
        refs = set(json.loads(a["refs"]))
    except json.JSONDecodeError:
        raise Reject("refs ilegible")
    if not all(isinstance(r, str) and SPEC_ID.fullmatch(r) for r in refs):
        raise Reject("refs con ids inválidos")
    raws = [blob(a["repo"], a[k], path) for k in ("base", "head", "main")]
    out = resolve_state(*raws, refs) if path.endswith(".json") else resolve_log(*raws)
    # O_NOFOLLOW: si --out es un enlace simbólico, error en vez de escribir en su destino.
    try:
        fd = os.open(a["out"], os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
    except OSError as e:
        raise Reject(f"{a['out']}: no se escribe ({e.strerror})")
    with os.fdopen(fd, "wb") as f:
        f.write(out)


# ── derivados: forma canónica ──
def row(path):
    for rx, kind, gens in DERIVED:
        if re.fullmatch(rx, path):
            return kind, gens
    return None


def canon(kind, raw):
    if raw is None:
        return None
    if kind == "bytes":
        return raw
    if kind == "index_md":
        lines = raw.decode("utf-8").split("\n")
        dates = [i for i, l in enumerate(lines) if INDEX_DATE.fullmatch(l)]
        stamps = [l for l in lines if "Last regenerated:" in l]
        if len(dates) != 1 or len(stamps) != 1:
            raise Reject("INDEX.md sin exactamente una línea de fecha válida")
        return "\n".join(l for i, l in enumerate(lines) if i != dates[0])
    if kind == "rule_manifest":
        d = json.loads(raw.decode("utf-8"))
        g = d.pop("generated", None) if isinstance(d, dict) else None
        if not isinstance(g, str) or not MANIFEST_DATE.fullmatch(g):
            raise Reject("rule-manifest.json sin generated válido")
        return d
    raise Reject(f"forma {kind} no comparable")


def read_opt(p):
    try:
        with open(p, "rb") as f:
            return f.read()
    except FileNotFoundError:
        return None


def cmd_same(path, a, b):
    r = row(path)
    if r is None:
        raise Reject(f"{path}: derivado sin fila en la tabla canónica")
    try:
        return 0 if canon(r[0], read_opt(a)) == canon(r[0], read_opt(b)) else 1
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise Reject(f"{path}: contenido ilegible")


def opts(argv):
    a, it = {}, iter(argv)
    for k in it:
        if not k.startswith("--"):
            raise Reject(f"argumento inesperado {k}")
        a[k[2:]] = next(it, "")
    return a


def main(argv):
    try:
        cmd = argv[0] if argv else ""
        if cmd == "refs":
            cmd_refs(opts(argv[1:]))
        elif cmd == "resolve":
            cmd_resolve(opts(argv[1:]))
        elif cmd == "kind" and len(argv) == 2:
            r = row(argv[1])
            if r is None:
                raise Reject(f"{argv[1]}: derivado sin fila en la tabla canónica")
            print(r[0], *r[1])
        elif cmd == "same" and len(argv) == 4:
            return cmd_same(*argv[1:])
        else:
            print(__doc__, file=sys.stderr)
            return 64
    except (Reject, KeyError) as e:
        print(f"merge-registry-resolve: {e}", file=sys.stderr)
        if cmd == "resolve":
            print(dict(zip(argv[1::2], argv[2::2])).get("--path", ""))
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
