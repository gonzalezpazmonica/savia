#!/usr/bin/env python3
"""validate-agent-catalog.py — SE-532 S1: esquema de cabecera y referencias cruzadas.

Fuente de verdad: .opencode/agents/*.md. Falla cerrado.

Uso:
  validate-agent-catalog.py [--root DIR] [--skip-steps]
  validate-agent-catalog.py [--root DIR] --freeze
  validate-agent-catalog.py [--root DIR] --retired NOMBRE...   (todo lo que sigue son nombres)

Salida: 0 todo pasa · 1 hay errores · 2 uso o entorno (sin PyYAML, sin directorio de agentes,
sin esquema). Cada error nombra fichero y línea.

Reglas: R1 cabecera ilegible/sin cerrar/clave duplicada · R2 falta clave obligatoria o valor
fuera de dominio · R3 clave desconocida · R4 tools no es mapa de booleanos · R5 name distinto
del fichero · R6 routing cita agente inexistente · R7 protegidos cita agente inexistente ·
R8 contrato agent.<x> sin agente o id incoherente · R9 decision_tree inexistente ·
R10 (--retired) agente retirado aún presente o citado en una referencia viva.

Excepciones congeladas (docs/agent-catalog-exceptions.txt): solo R1, R2 y R3, solo pueden encoger.
`--skip-steps` omite los pasos delegados (agents-catalog-sync, judge-routing-verify); solo para
tests, nunca lo usa la CI.
"""
import datetime
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("ERROR: python3 con PyYAML es obligatorio (fail-closed)", file=sys.stderr)
    sys.exit(2)

SCHEMA_REL = "config/agent-frontmatter.schema.json"
EXC_REL = "docs/agent-catalog-exceptions.txt"
AGENTS_REL = ".opencode/agents"
MIRROR_REL = ".claude/agents"
EXCEPTABLE = ("R1", "R2", "R3")
BASE_REF = os.environ.get("AGENT_CATALOG_BASE_REF", "origin/main")


class DupKeyLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader, node, deep=False):
    seen = {}
    for knode, _ in node.value:
        key = loader.construct_object(knode, deep=deep)
        if key in seen:
            raise yaml.constructor.ConstructorError(
                None, None, "clave duplicada %r" % (key,), knode.start_mark)
        seen[key] = True
    return yaml.SafeLoader.construct_mapping(loader, node, deep)


DupKeyLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


class Report:
    def __init__(self):
        self.errors = []      # (rule, file, line, detail, agent)
        self.notes = []

    def add(self, rule, file, line, detail, agent=None, key=None):
        self.errors.append((rule, file, line, detail, agent, key))


def split_header(text):
    """Devuelve (header_text, first_line_of_header) o (None, motivo)."""
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None, "sin cabecera (la primera línea no es ---)"
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            return "\n".join(lines[1:i]), 2
    return None, "cabecera sin cerrar (falta ---)"


def parse_header(path):
    """(mapping, key_lines, error). key_lines: clave -> línea 1-based."""
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return None, {}, "ilegible: %s" % exc
    head, first = split_header(text)
    if head is None:
        return None, {}, first
    try:
        node = yaml.compose(head, Loader=DupKeyLoader)
        data = yaml.load(head, Loader=DupKeyLoader)
    except yaml.YAMLError as exc:
        mark = getattr(exc, "problem_mark", None)
        ln = (mark.line + first) if mark else first
        return None, {}, "YAML inválido en línea %d: %s" % (ln, getattr(exc, "problem", exc))
    if not isinstance(data, dict) or node is None:
        return None, {}, "cabecera vacía o no es un mapa"
    klines = {}
    for knode, _ in node.value:
        klines[knode.value] = knode.start_mark.line + first
    return data, klines, None


def load_schema(root):
    p = os.path.join(root, SCHEMA_REL)
    try:
        with open(p, encoding="utf-8") as fh:
            sch = json.load(fh)
    except (OSError, ValueError) as exc:
        print("ERROR: esquema ilegible %s: %s" % (SCHEMA_REL, exc), file=sys.stderr)
        sys.exit(2)
    if not isinstance(sch.get("properties"), dict) or not isinstance(sch.get("required"), list):
        print("ERROR: esquema sin properties/required: %s" % SCHEMA_REL, file=sys.stderr)
        sys.exit(2)
    return sch


TYPES = {
    "string": lambda v: isinstance(v, str),
    "integer": lambda v: isinstance(v, int) and not isinstance(v, bool),
    "boolean": lambda v: isinstance(v, bool),
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
}


def value_problem(value, spec):
    """Mensaje si value incumple spec (subconjunto de JSON Schema), o None."""
    t = spec.get("type")
    if t is not None:
        ts = t if isinstance(t, list) else [t]
        if not any(TYPES.get(x, lambda v: False)(value) for x in ts):
            return "tipo %s, se esperaba %s" % (type(value).__name__, "/".join(ts))
    if "enum" in spec and value not in spec["enum"]:
        return "valor %r fuera de dominio %s" % (value, spec["enum"])
    if isinstance(value, str) and spec.get("minLength") and not value.strip():
        return "cadena vacía"
    if isinstance(value, int) and not isinstance(value, bool) and "minimum" in spec \
            and value < spec["minimum"]:
        return "valor %r menor que %s" % (value, spec["minimum"])
    if isinstance(value, dict) and "properties" in spec:
        for k, v in value.items():
            if k not in spec["properties"]:
                if spec.get("additionalProperties") is False:
                    return "subclave desconocida %r" % (k,)
                continue
            sub = value_problem(v, spec["properties"][k])
            if sub:
                return "%s: %s" % (k, sub)
    return None


def agent_files(root):
    d = os.path.join(root, AGENTS_REL)
    return sorted(f for f in os.listdir(d)
                  if f.endswith(".md") and f != "README.md"
                  and os.path.isfile(os.path.join(d, f)))


def check_headers(root, schema, rep):
    props = schema["properties"]
    required = schema["required"]
    agents = []
    for fn in agent_files(root):
        name = fn[:-3]
        agents.append(name)
        rel = "%s/%s" % (AGENTS_REL, fn)
        data, klines, err = parse_header(os.path.join(root, rel))
        if err:
            rep.add("R1", rel, 1, err, name, "cabecera")
            continue
        for k in required:
            if k not in data:
                rep.add("R2", rel, 1, "falta la clave obligatoria '%s'" % k, name, k)
        for k, v in data.items():
            ln = klines.get(k, 1)
            if k not in props:
                rep.add("R3", rel, ln, "clave desconocida '%s'" % k, name, k)
                continue
            if k == "tools":
                if not isinstance(v, dict) or not v or \
                        any(not isinstance(x, bool) for x in v.values()):
                    rep.add("R4", rel, ln, "tools debe ser un mapa no vacío herramienta→booleano", name)
                continue
            if k == "name":
                if not isinstance(v, str) or not v.strip():
                    rep.add("R2", rel, ln, "name: cadena vacía o de otro tipo", name)
                elif v != name:
                    rep.add("R5", rel, ln, "name '%s' distinto del nombre de fichero '%s'" % (v, name), name)
                continue
            prob = value_problem(v, props[k])
            if prob:
                rep.add("R2", rel, ln, "%s: %s" % (k, prob), name)
            if k == "decision_tree" and isinstance(v, str):
                if not os.path.isfile(os.path.join(root, AGENTS_REL, v)):
                    rep.add("R9", rel, ln, "decision_tree '%s' no existe bajo %s/" % (v, AGENTS_REL), name)
    return agents


def line_of(path, pattern):
    try:
        with open(path, encoding="utf-8") as fh:
            for i, line in enumerate(fh, 1):
                if re.search(pattern, line):
                    return i
    except OSError:
        pass
    return 1


def load_yaml(root, rel, rep, rule):
    p = os.path.join(root, rel)
    if not os.path.isfile(p):
        return None
    try:
        with open(p, encoding="utf-8") as fh:
            return yaml.load(fh, Loader=DupKeyLoader)
    except (yaml.YAMLError, OSError, UnicodeDecodeError) as exc:
        rep.add(rule, rel, 1, "YAML ilegible: %s" % str(exc).splitlines()[0])
        return None


def check_refs(root, agents, rep):
    names = set(agents)
    rel = "config/judge-routing.yaml"
    data = load_yaml(root, rel, rep, "R6")
    if isinstance(data, dict):
        for row in data.get("judges") or []:
            a = row.get("agent") if isinstance(row, dict) else None
            if not isinstance(a, str) or a not in names:
                rep.add("R6", rel, line_of(os.path.join(root, rel), r"agent:\s*%s\b" % re.escape(str(a))),
                        "fila de routing cita agente inexistente '%s'" % (a,))
    rel = ".opencode/protected-jobs.yaml"
    data = load_yaml(root, rel, rep, "R7")
    if isinstance(data, dict):
        for a in data.get("protected_agents") or []:
            if a not in names:
                rep.add("R7", rel, line_of(os.path.join(root, rel), r"^\s*-\s+%s\s*$" % re.escape(str(a))),
                        "protected_agents cita agente inexistente '%s'" % (a,))
    cdir = os.path.join(root, "contracts/capabilities")
    if os.path.isdir(cdir):
        for fn in sorted(os.listdir(cdir)):
            m = re.fullmatch(r"agent\.(.+)\.yaml", fn)
            if not m:
                continue
            x, crel = m.group(1), "contracts/capabilities/%s" % fn
            if x not in names:
                rep.add("R8", crel, 1, "contrato sin agente '%s' en %s/" % (x, AGENTS_REL))
            d = load_yaml(root, crel, rep, "R8")
            cid = d.get("id") if isinstance(d, dict) else None
            if cid != "agent.%s" % x:
                rep.add("R8", crel, line_of(os.path.join(root, crel), r"^id:"),
                        "id %r distinto de 'agent.%s'" % (cid, x))


# ── R10 ────────────────────────────────────────────────────────────────────
SKIP_DIRS = {".git", "node_modules", "external-memory", "__pycache__", "profiles"}
HISTORY = ("CHANGELOG",)
CONTEXT_EXT = (".md", ".yaml", ".yml", ".json", ".txt", ".sh", ".py", ".ts", ".js", ".bats")


def contextual_patterns(name):
    n = re.escape(name)
    b = r"(?![A-Za-z0-9_-])"
    return [
        re.compile(r"subagent_type[\"']?\s*[:=]\s*[\"']?" + n + b),
        re.compile(r"(?<![A-Za-z0-9_-])agent[\"']?\s*:\s*[\"']?" + n + b),
        re.compile(r"(?:Task|Agent)\(\s*[\"']?" + n + b),
        re.compile(r"agents?\s*[:=]\s*\[[^\]]*(?<![A-Za-z0-9_-])" + n + b),
        re.compile(r"^\s*-\s+[\"']?" + n + r"[\"']?\s*$"),
        re.compile(r"\|\s*`?" + n + r"`?\s*\|"),
        re.compile(r"handler:\s*[\"']?agent\s+" + n + b),
    ]


def literal_pattern(name):
    return re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(name) + r"(?![A-Za-z0-9_-])")


def iter_scan_files(root):
    roots = [".opencode", ".claude", "config", "contracts", "scripts", "docs/rules",
             "docs/agents-sync-allowlist.md"]
    for r in roots:
        p = os.path.join(root, r)
        if os.path.isfile(p):
            yield r
            continue
        for dp, dns, fns in os.walk(p):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                if fn.startswith(HISTORY) or not fn.endswith(CONTEXT_EXT):
                    continue
                full = os.path.join(dp, fn)
                if os.path.islink(full) or os.path.getsize(full) > 1_000_000:
                    continue
                yield os.path.relpath(full, root)


def check_retired(root, retired, rep):
    for name in retired:
        for side in (AGENTS_REL, MIRROR_REL):
            if os.path.isfile(os.path.join(root, side, name + ".md")):
                rep.add("R10", "%s/%s.md" % (side, name), 1, "agente retirado '%s' aún tiene fichero" % name)
        own = {"%s/%s.md" % (AGENTS_REL, name), "%s/%s.md" % (MIRROR_REL, name)}
        ctx = contextual_patterns(name)
        lit = literal_pattern(name)
        for rel in iter_scan_files(root):
            if rel in own or rel == "scripts/validate-agent-catalog.py":
                continue
            use_literal = rel.startswith("scripts/")
            try:
                with open(os.path.join(root, rel), encoding="utf-8", errors="ignore") as fh:
                    for i, line in enumerate(fh, 1):
                        pats = [lit] if use_literal else ctx
                        if any(p.search(line) for p in pats):
                            rep.add("R10", rel, i, "agente retirado '%s' citado en una referencia viva" % name)
                            break
            except OSError:
                rep.add("R10", rel, 1, "no se pudo leer para comprobar '%s'" % name)
        cdir = os.path.join(root, "contracts/capabilities")
        if os.path.isfile(os.path.join(cdir, "agent.%s.yaml" % name)):
            rep.add("R10", "contracts/capabilities/agent.%s.yaml" % name, 1,
                    "contrato del agente retirado '%s' sigue presente" % name)


# ── Excepciones ────────────────────────────────────────────────────────────
def read_exceptions(text, rel, rep):
    """Devuelve dict clave(agent,rule,detail) -> línea."""
    out = {}
    for i, raw in enumerate(text.split("\n"), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 5 or not all(parts):
            rep.add("EXC", rel, i, "línea mal formada (agente|regla|detalle|fecha|motivo)")
            continue
        agent, rule, detail, date, _ = parts
        if rule not in EXCEPTABLE:
            rep.add("EXC", rel, i, "regla %s no admite excepciones" % rule)
            continue
        try:
            datetime.date.fromisoformat(date)
        except ValueError:
            rep.add("EXC", rel, i, "fecha inválida '%s'" % date)
            continue
        key = (agent, rule, detail)
        if key in out:
            rep.add("EXC", rel, i, "excepción duplicada")
        out[key] = i
    return out


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), capture_output=True, text=True)


def base_exceptions(root, rep):
    """Claves de la base. None si no hay base (PR que crea el fichero). Error -> rep + False."""
    ref = git(root, "rev-parse", "--verify", "-q", BASE_REF + "^{commit}")
    if ref.returncode != 0:
        rep.add("EXC", EXC_REL, 1, "no se puede leer %s (fail-closed): comprueba el fetch" % BASE_REF)
        return False
    exists = git(root, "cat-file", "-e", "%s:%s" % (BASE_REF, EXC_REL))
    if exists.returncode != 0:
        return None
    shown = git(root, "show", "%s:%s" % (BASE_REF, EXC_REL))
    if shown.returncode != 0:
        rep.add("EXC", EXC_REL, 1, "fallo leyendo %s:%s" % (BASE_REF, EXC_REL))
        return False
    scratch = Report()
    keys = read_exceptions(shown.stdout, "%s:%s" % (BASE_REF, EXC_REL), scratch)
    return set(keys)


def apply_exceptions(root, agents, rep):
    p = os.path.join(root, EXC_REL)
    base = base_exceptions(root, rep)
    if base is False:
        return
    if base is not None and not os.path.isfile(p):
        rep.add("EXC", EXC_REL, 1, "el fichero de excepciones existe en %s y falta aquí" % BASE_REF)
        return
    if not os.path.isfile(p):
        # Sin fichero en HEAD ni en la base: no hay excepciones congeladas; los errores pasan tal cual.
        if base is None:
            return
    try:
        with open(p, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        rep.add("EXC", EXC_REL, 1, "ilegible: %s" % exc)
        return
    exc = read_exceptions(text, EXC_REL, rep)
    current = {}
    for e in rep.errors:
        rule, f, line, detail, agent, k = e
        if rule in EXCEPTABLE and agent and k:
            current[(agent, rule, k)] = e
    names = set(agents)
    for key, ln in exc.items():
        agent, rule, detail = key
        if agent not in names:
            rep.add("EXC", EXC_REL, ln, "excepción de agente inexistente o retirado '%s'" % agent)
        elif key not in current:
            rep.add("EXC", EXC_REL, ln, "excepción obsoleta (la violación ya no existe): %s %s %s" % key)
        if base is not None and key not in base:
            rep.add("EXC", EXC_REL, ln, "excepción nueva respecto a %s: %s %s %s" % ((BASE_REF,) + key))
    rep.errors = [e for e in rep.errors if not (
        e[0] in EXCEPTABLE and e[4] and e[5] and (e[4], e[0], e[5]) in exc)]
    rep.notes.append("excepciones congeladas aplicadas: %d" % len(exc))


def freeze(root, rep):
    p = os.path.join(root, EXC_REL)
    if os.path.exists(p):
        print("ERROR: %s ya existe; --freeze solo se usa una vez" % EXC_REL, file=sys.stderr)
        return 2
    rows = []
    today = datetime.date.today().isoformat()
    for rule, f, line, detail, agent, k in rep.errors:
        if rule not in EXCEPTABLE or not agent or not k:
            print("ERROR: no congelable %s %s:%s %s" % (rule, f, line, detail), file=sys.stderr)
            return 1
        motive = {"R1": "cabecera YAML ilegible (dos puntos sin comillas en description); estado previo a SE-532 S1",
                  "R2": "falta tools: el agente hereda todas las herramientas; estado previo a SE-532 S1",
                  "R3": "clave sin definición de agente; estado previo a SE-532 S1"}[rule]
        rows.append("%s | %s | %s | %s | %s" % (agent, rule, k, today, motive))
    head = ("# Excepciones congeladas del catálogo de agentes (SE-532 S1, D4).\n"
            "# agente | regla | detalle | alta | motivo. Solo pueden encoger: una obsoleta, una nueva\n"
            "# respecto a la base o una de un agente retirado hacen fallar el validador.\n")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(head + "\n".join(sorted(rows)) + "\n")
    print("congeladas %d excepciones en %s" % (len(rows), EXC_REL))
    return 0


def run_steps(root, rep):
    for rel, args in (("scripts/agents-catalog-sync.sh", ["--check"]),
                      ("scripts/judge-routing-verify.sh", [])):
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            rep.add("STEP", rel, 1, "paso delegado ausente (fail-closed)")
            continue
        env = dict(os.environ, PROJECT_ROOT=root)
        r = subprocess.run(["bash", p] + args, capture_output=True, text=True, env=env, cwd=root)
        if r.returncode != 0:
            tail = (r.stdout + r.stderr).strip().splitlines()[-1:] or [""]
            rep.add("STEP", rel, 1, "falló (exit %d): %s" % (r.returncode, tail[0]))


def main(argv):
    root, skip, do_freeze, retired = None, False, False, []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--root":
            if i + 1 >= len(argv):
                print("ERROR: --root necesita un directorio", file=sys.stderr)
                return 2
            root = argv[i + 1]
            i += 1
        elif a == "--skip-steps":
            skip = True
        elif a == "--freeze":
            do_freeze = True
        elif a == "--retired":
            retired = argv[i + 1:]
            if retired and retired[0] == "--":
                retired = retired[1:]
            if not retired:
                print("ERROR: --retired necesita al menos un nombre", file=sys.stderr)
                return 2
            break
        else:
            print("ERROR: argumento desconocido %r" % a, file=sys.stderr)
            return 2
        i += 1
    root = os.path.abspath(root or os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    if not os.path.isdir(os.path.join(root, AGENTS_REL)):
        print("ERROR: no existe %s" % AGENTS_REL, file=sys.stderr)
        return 2
    schema = load_schema(root)
    rep = Report()
    agents = check_headers(root, schema, rep)
    check_refs(root, agents, rep)
    if retired:
        check_retired(root, retired, rep)
    if do_freeze:
        return freeze(root, rep)
    apply_exceptions(root, agents, rep)
    if not skip:
        run_steps(root, rep)
    for note in rep.notes:
        print("INFO " + note)
    for rule, f, line, detail, _a, _k in rep.errors:
        print("ERROR %s %s:%s %s" % (rule, f, line, detail))
    print("agentes: %d · errores: %d" % (len(agents), len(rep.errors)))
    return 1 if rep.errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
