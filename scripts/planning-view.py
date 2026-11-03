#!/usr/bin/env python3
"""planning-view.py — SE-500 S1: fragmentos de planificación y vista consolidada.

Cada PR registra su spec con ficheros nuevos y no edita ninguno compartido:

  docs/propuestas/planning.d/SE-NNN.json        registro completo de la iniciativa
  docs/propuestas/LOG.d/SE-NNN-<ESTADO>.md      una entrada «## YYYY-MM-DD SE-NNN ESTADO»

planning-state.json y LOG.md son la base consolidada. La vista es base + fragmentos.

Uso:
  planning-view.py [--root DIR] state [--lenient]      vista de planning-state.json
  planning-view.py [--root DIR] log [--lenient]        vista de LOG.md
  planning-view.py [--root DIR] check                  valida los fragmentos (FAIL/WARN)
  planning-view.py [--root DIR] diff REF               consolidación pura frente a merge-base(REF, HEAD)
  planning-view.py [--root DIR] consolidate            escribe la vista en la base y borra los fragmentos
  planning-view.py [--root DIR] register SE-NNN --status S [--priority P] [--phase F]
                   [--title T] [--note N] [--evidence E] [--approval A] [--date D] [--log-text X]
  planning-view.py [--root DIR] log-entry SE-NNN ESTADO [--date D] [--text X] [--log-dir DIR]

Propiedades: determinista (sin locale ni orden del sistema de ficheros), idempotente,
conservadora. Python stdlib, sin red. Los nombres de fragmento se validan con
re.fullmatch antes de usarse como ruta; nunca pasan por un shell.
Salida: 0 OK · 1 FAIL de validación · 2 error de uso o vista no construible.
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

STATES = ("IDEA", "PROPOSED", "APPROVED", "IMPLEMENTING", "IMPLEMENTED",
          "REJECTED", "SUPERSEDED", "DEFERRED", "RETIRED")
RANK = {s: i for i, s in enumerate(STATES)}
_ST = "|".join(STATES)
STATE_FRAG_RE = re.compile(r"SE-([0-9]+)\.json")
LOG_FRAG_RE = re.compile(r"SE-([0-9]+)-(" + _ST + r")\.md")
LOG_HEAD_RE = re.compile(r"## ([0-9]{4}-[0-9]{2}-[0-9]{2}) (SE-[0-9]+) (" + _ST + r")")
BASE_DATE_RE = re.compile(r"## ([0-9]{4}-[0-9]{2}-[0-9]{2})(?: .*)?")
ID_RE = re.compile(r"SE-[0-9]+")
DATE_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
REQUIRED = ("id", "status", "title", "evidence")
ALLOWED_EXTRA = ("README.md",)

PROP = "docs/propuestas"
STATE_BASE = PROP + "/planning-state.json"
LOG_BASE = PROP + "/LOG.md"
STATE_D = PROP + "/planning.d"
LOG_D = PROP + "/LOG.d"


class ViewError(Exception):
    pass


# ── Fuentes: árbol de trabajo o una referencia git ──────────────────────────
class FsTree:
    def __init__(self, root):
        self.root = root

    def read(self, rel):
        try:
            with open(os.path.join(self.root, rel), encoding="utf-8", newline="") as fh:
                return fh.read()
        except (FileNotFoundError, NotADirectoryError):
            return None

    def listdir(self, rel):
        path = os.path.join(self.root, rel)
        if not os.path.isdir(path):
            return []
        out = []
        for name in os.listdir(path):
            full = os.path.join(path, name)
            out.append((name, os.path.isfile(full) and not os.path.islink(full)))
        return sorted(out)


class GitTree:
    def __init__(self, root, ref):
        self.root, self.ref = root, ref

    def read(self, rel):
        res = subprocess.run(["git", "-C", self.root, "show", "%s:%s" % (self.ref, rel)],
                             capture_output=True)
        if res.returncode != 0:
            return None
        return res.stdout.decode("utf-8")

    def listdir(self, rel):
        res = subprocess.run(["git", "-C", self.root, "ls-tree", "-z", self.ref, rel + "/"],
                             capture_output=True)
        if res.returncode != 0:
            return []
        out = []
        for item in res.stdout.decode("utf-8").split("\0"):
            if not item:
                continue
            meta, path = item.split("\t", 1)
            out.append((path.rsplit("/", 1)[-1], meta.split()[1] == "blob"))
        return sorted(out)


# ── Carga y validación de fragmentos ────────────────────────────────────────
def load_state_fragments(tree, errors):
    """Devuelve [(num, name, record)] aplicables, en orden numérico."""
    frags = []
    for name, isfile in tree.listdir(STATE_D):
        if name in ALLOWED_EXTRA and isfile:
            continue
        m = STATE_FRAG_RE.fullmatch(name)
        if not m or not isfile:
            errors.append("planning.d: nombre de fragmento inválido: %r" % name)
            continue
        text = tree.read(STATE_D + "/" + name)
        try:
            rec = json.loads(text)
        except (TypeError, ValueError) as exc:
            errors.append("planning.d/%s: JSON inválido (%s)" % (name, exc))
            continue
        if not isinstance(rec, dict):
            errors.append("planning.d/%s: no es un objeto JSON" % name)
            continue
        stem = name[:-len(".json")]
        if rec.get("id") != stem:
            errors.append("planning.d/%s: nombre e id no coinciden (id=%r)" % (name, rec.get("id")))
            continue
        missing = [k for k in REQUIRED if not isinstance(rec.get(k), str)]
        if missing:
            errors.append("planning.d/%s: faltan campos obligatorios: %s" % (name, ", ".join(missing)))
        if rec.get("status") not in STATES:
            errors.append("planning.d/%s: estado inválido: %r" % (name, rec.get("status")))
        frags.append((int(m.group(1)), name, rec))
    frags.sort(key=lambda f: (f[0], f[1]))
    by_num = {}
    for num, name, _ in frags:
        by_num.setdefault(num, []).append(name)
    for num in sorted(by_num):
        if len(by_num[num]) > 1:
            errors.append("planning.d: id duplicado en varios fragmentos: %s" % ", ".join(by_num[num]))
    dups = {n for n, names in by_num.items() if len(names) > 1}
    return [f for f in frags if f[0] not in dups]


def load_log_fragments(tree, errors):
    """Devuelve [((date, num, rank, name), entry)] aplicables, en orden de la vista."""
    out = []
    for name, isfile in tree.listdir(LOG_D):
        if name in ALLOWED_EXTRA and isfile:
            continue
        m = LOG_FRAG_RE.fullmatch(name)
        if not m or not isfile:
            errors.append("LOG.d: nombre de fragmento inválido: %r" % name)
            continue
        text = tree.read(LOG_D + "/" + name) or ""
        if "\r" in text:
            errors.append("LOG.d/%s: contiene retornos de carro" % name)
            continue
        lines = text.rstrip("\n").split("\n")
        hm = LOG_HEAD_RE.fullmatch(lines[0])
        if not hm:
            errors.append("LOG.d/%s: la primera línea no es «## YYYY-MM-DD SE-NNN ESTADO»" % name)
            continue
        if hm.group(2) != "SE-" + m.group(1) or hm.group(3) != m.group(2):
            errors.append("LOG.d/%s: la cabecera no coincide con el nombre (%s)" % (name, lines[0]))
            continue
        try:
            datetime.date.fromisoformat(hm.group(1))
        except ValueError:
            errors.append("LOG.d/%s: fecha inválida %s" % (name, hm.group(1)))
            continue
        if any(line.startswith("#") for line in lines[1:]):
            errors.append("LOG.d/%s: más de una cabecera" % name)
            continue
        key = (hm.group(1), int(m.group(1)), RANK[m.group(2)], name)
        out.append((key, "\n".join(lines)))
    out.sort(key=lambda e: e[0], reverse=True)
    return out


# ── Vista ───────────────────────────────────────────────────────────────────
def apply_state(initiatives, frags):
    result = list(initiatives)
    index = {}
    for i, rec in enumerate(result):
        if isinstance(rec, dict) and isinstance(rec.get("id"), str):
            index.setdefault(rec["id"], i)
    for _, _, rec in frags:
        if rec["id"] in index:
            result[index[rec["id"]]] = rec
        else:
            index[rec["id"]] = len(result)
            result.append(rec)
    return result


def parse_base_state(text):
    if text is None:
        raise ViewError("falta %s" % STATE_BASE)
    try:
        base = json.loads(text)
    except ValueError as exc:
        raise ViewError("%s no es JSON válido (%s)" % (STATE_BASE, exc))
    if not isinstance(base, dict) or not isinstance(base.get("initiatives"), list):
        raise ViewError("%s sin lista initiatives" % STATE_BASE)
    return base


def view_state(base_text, frags):
    base = parse_base_state(base_text)
    base["initiatives"] = apply_state(base["initiatives"], frags)
    return base


def dump_state(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def split_log(text):
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if line.startswith("## "):
            return "".join(lines[:i]), "".join(lines[i:])
    return text, ""


def view_log(base_text, entries):
    base_text = base_text or ""
    if not entries:
        return base_text
    head, body = split_log(base_text)
    if head and not head.endswith("\n"):
        head += "\n"
    return head + "".join(entry + "\n\n" for _, entry in entries) + body


def latest_base_date(base_text):
    for line in (base_text or "").split("\n"):
        m = BASE_DATE_RE.fullmatch(line)
        if m:
            return m.group(1)
    return None


def build(tree, lenient):
    errors = []
    sfrags = load_state_fragments(tree, errors)
    lfrags = load_log_fragments(tree, errors)
    if errors and not lenient:
        raise ViewError("fragmentos inválidos:\n  " + "\n  ".join(errors))
    return sfrags, lfrags, errors


# ── Comandos ────────────────────────────────────────────────────────────────
def atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-")
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    os.replace(tmp, path)


def cmd_state(root, args):
    tree = FsTree(root)
    sfrags, _, _ = build(tree, args.lenient)
    sys.stdout.write(dump_state(view_state(tree.read(STATE_BASE), sfrags)))
    return 0


def cmd_log(root, args):
    tree = FsTree(root)
    _, lfrags, _ = build(tree, args.lenient)
    sys.stdout.write(view_log(tree.read(LOG_BASE), lfrags))
    return 0


def cmd_check(root, _args):
    tree = FsTree(root)
    errors = []
    load_state_fragments(tree, errors)
    lfrags = load_log_fragments(tree, errors)
    latest = latest_base_date(tree.read(LOG_BASE))
    for msg in errors:
        print("FAIL: " + msg)
    if latest:
        for key, _ in lfrags:
            if key[0] < latest:
                print("WARN: LOG.d/%s tiene fecha %s anterior a la entrada más reciente de la base (%s); "
                      "la vista lo muestra encima" % (key[3], key[0], latest))
    return 1 if errors else 0


def cmd_consolidate(root, _args):
    tree = FsTree(root)
    sfrags, lfrags, _ = build(tree, lenient=False)
    if not sfrags and not lfrags:
        print("consolidate: sin fragmentos; nada que hacer")
        return 0
    state = dump_state(view_state(tree.read(STATE_BASE), sfrags))
    log = view_log(tree.read(LOG_BASE), lfrags)
    atomic_write(os.path.join(root, STATE_BASE), state)
    atomic_write(os.path.join(root, LOG_BASE), log)
    for _, name, _ in sfrags:
        os.remove(os.path.join(root, STATE_D, name))
    for key, _ in lfrags:
        os.remove(os.path.join(root, LOG_D, key[3]))
    print("consolidate: %d fragmento(s) de planning.d y %d de LOG.d pasados a la base"
          % (len(sfrags), len(lfrags)))
    return 0


def _differing_ids(actual, expected):
    def as_map(lst):
        out = {}
        for rec in lst:
            key = rec.get("id") if isinstance(rec, dict) else None
            out.setdefault(str(key), []).append(rec)
        return out
    a, e = as_map(actual), as_map(expected)
    ids = sorted(k for k in set(a) | set(e) if a.get(k) != e.get(k))
    return ids or ["(orden de initiatives)"]


def cmd_diff(root, args):
    res = subprocess.run(["git", "-C", root, "merge-base", args.ref, "HEAD"], capture_output=True)
    if res.returncode != 0:
        print("FAIL: validate --diff no evaluable: sin merge-base entre %s y HEAD" % args.ref)
        return 1
    mb = res.stdout.decode().strip()
    ref_tree, cur = GitTree(root, mb), FsTree(root)
    ignored = []
    ref_s = load_state_fragments(ref_tree, ignored)
    ref_l = load_log_fragments(ref_tree, ignored)
    cur_s = {n for n, _ in cur.listdir(STATE_D)}
    cur_l = {n for n, _ in cur.listdir(LOG_D)}
    gone_s = [f for f in ref_s if f[1] not in cur_s]
    gone_l = [e for e in ref_l if e[0][3] not in cur_l]
    err = 0
    try:
        ref_base = parse_base_state(ref_tree.read(STATE_BASE))
        cur_base = parse_base_state(cur.read(STATE_BASE))
    except ViewError as exc:
        print("FAIL: validate --diff no evaluable: %s" % exc)
        return 1
    expected = apply_state(ref_base["initiatives"], gone_s)
    if cur_base["initiatives"] != expected:
        print("FAIL: initiatives de la base cambiadas sin ser consolidación pura de fragmentos borrados "
              "en la misma PR: %s (registra con roadmap.sh register)"
              % ", ".join(_differing_ids(cur_base["initiatives"], expected)))
        err = 1
    ref_log = ref_tree.read(LOG_BASE) or ""
    if (cur.read(LOG_BASE) or "") != view_log(ref_log, gone_l):
        print("FAIL: LOG.md editado sin ser consolidación pura de fragmentos de LOG.d borrados "
              "en la misma PR (las entradas nuevas van en LOG.d/; las existentes no se tocan)")
        err = 1
    if not err:
        print("PASS: base de planificación sin cambios fuera de consolidación (%d+%d fragmentos consolidados)"
              % (len(gone_s), len(gone_l)))
    return err


def _check_id_status(sid, status):
    if not ID_RE.fullmatch(sid or ""):
        raise ViewError("id inválido %r: se espera SE-NNN" % sid)
    if status not in STATES:
        raise ViewError("estado inválido %r: uno de %s" % (status, " ".join(STATES)))


def _today(date):
    if date is None:
        return datetime.date.today().isoformat()
    if not DATE_RE.fullmatch(date):
        raise ViewError("fecha inválida %r" % date)
    try:
        datetime.date.fromisoformat(date)
    except ValueError:
        raise ViewError("fecha inválida %r" % date)
    return date


def write_log_entry(log_dir, sid, status, date, text):
    path = os.path.join(log_dir, "%s-%s.md" % (sid, status))
    content = "## %s %s %s\n" % (date, sid, status)
    text = (text or "").strip()
    if text:
        if any(line.startswith("#") for line in text.split("\n")):
            raise ViewError("el párrafo de la entrada no puede contener cabeceras")
        content += "\n" + text + "\n"
    if os.path.exists(path):
        print("WARN: %s ya existe; se conserva (append-only hasta consolidar)" % path, file=sys.stderr)
        return path
    atomic_write(path, content)
    return path


def cmd_log_entry(root, args):
    _check_id_status(args.id, args.status)
    log_dir = args.log_dir or os.path.join(root, LOG_D)
    print(write_log_entry(log_dir, args.id, args.status, _today(args.date), args.text))
    return 0


def cmd_register(root, args):
    _check_id_status(args.id, args.status)
    date = _today(args.date)
    tree = FsTree(root)
    sfrags, _, _ = build(tree, lenient=False)
    view = view_state(tree.read(STATE_BASE), sfrags)
    rec = next((dict(r) for r in view["initiatives"] if isinstance(r, dict) and r.get("id") == args.id),
               {"id": args.id})
    rec["status"] = args.status
    for key in ("priority", "phase", "title", "evidence", "note", "approval"):
        val = getattr(args, key)
        if val is not None:
            rec[key] = val
    rec.setdefault("evidence", "")
    if not isinstance(rec.get("title"), str) or not rec["title"]:
        raise ViewError("--title es obligatorio para una iniciativa nueva")
    atomic_write(os.path.join(root, STATE_D, args.id + ".json"), dump_state(rec))
    text = args.log_text if args.log_text is not None else (args.note or rec["title"])
    path = write_log_entry(os.path.join(root, LOG_D), args.id, args.status, date, text)
    print("registrado: %s/%s.json y %s" % (STATE_D, args.id, os.path.relpath(path, root)))
    return 0


def main(argv=None):
    p = argparse.ArgumentParser(prog="planning-view.py", description="SE-500 S1: vista de planificación")
    p.add_argument("--root", default=os.environ.get("REPO_ROOT")
                   or os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("state", "log"):
        sp = sub.add_parser(name)
        sp.add_argument("--lenient", action="store_true")
    sub.add_parser("check")
    sub.add_parser("consolidate")
    sp = sub.add_parser("diff")
    sp.add_argument("ref")
    sp = sub.add_parser("register")
    sp.add_argument("id")
    sp.add_argument("--status", required=True)
    for key in ("priority", "phase", "title", "note", "evidence", "approval", "date"):
        sp.add_argument("--" + key)
    sp.add_argument("--log-text", dest="log_text")
    sp = sub.add_parser("log-entry")
    sp.add_argument("id")
    sp.add_argument("status")
    sp.add_argument("--date")
    sp.add_argument("--text")
    sp.add_argument("--log-dir", dest="log_dir")
    args = p.parse_args(argv)
    handlers = {"state": cmd_state, "log": cmd_log, "check": cmd_check, "diff": cmd_diff,
                "consolidate": cmd_consolidate, "register": cmd_register, "log-entry": cmd_log_entry}
    try:
        return handlers[args.cmd](os.path.abspath(args.root), args)
    except ViewError as exc:
        print("ERROR: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
