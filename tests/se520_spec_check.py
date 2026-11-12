#!/usr/bin/env python3
"""SE-520: comprobador de la spec y del prototipo (hallazgos de la revisión de la PR #1539).

Uso: python3 -I tests/se520_spec_check.py <spec.md> <prototipo.md>
Exit 0 si es coherente; 1 con un motivo por línea en stderr; 2 si no se puede leer.

Parte ejecutable: extrae las reglas de ejemplo del prototipo y corre sus casos con la
semántica de D2 (re.ASCII, search/fullmatch, when = Y, unless = O).
Parte textual: cada hallazgo de las revisoras tiene una frase obligatoria en la spec.
"""
import re
import sys

ERR = []


def err(msg):
    ERR.append(msg)


def parse_rules(text):
    rules = []
    for block in re.findall(r"```markdown\n(---\n.*?\n---)\n", text, re.S):
        r = {"when": [], "unless": [], "block": [], "allow": [], "id": None, "action": None}
        sec = None
        cur = None
        for line in block.splitlines():
            m = re.match(r"id:\s*(\S+)", line)
            if m:
                r["id"] = m.group(1)
            m = re.match(r"action:\s*(\w+)", line)
            if m:
                r["action"] = m.group(1)
            if re.match(r"(when|unless):", line):
                sec = line.split(":")[0]
                cur = None
                continue
            if re.match(r"cases:", line):
                sec = "cases"
                continue
            if sec == "cases":
                m = re.match(r"\s+(block|allow):", line)
                if m:
                    cur = m.group(1)
                    continue
                m = re.search(r'\{tool: (\w+), input: \{command: "((?:[^"\\]|\\.)*)"\}\}', line)
                if m and cur:
                    r[cur].append(m.group(2).replace('\\"', '"').replace("\\\\", "\\"))
                continue
            if sec in ("when", "unless"):
                if re.match(r"\s+- field:", line):
                    r[sec].append({"field": line.split(":", 1)[1].strip()})
                m = re.match(r"\s+op:\s*(\w+)", line)
                if m and r[sec]:
                    r[sec][-1]["op"] = m.group(1)
                m = re.match(r"\s+pattern:\s*'(.*)'\s*$", line)
                if m and r[sec]:
                    r[sec][-1]["pattern"] = m.group(1)
                m = re.match(r"\s+flags:\s*\[(.*)\]", line)
                if m and r[sec]:
                    r[sec][-1]["flags"] = m.group(1)
            if re.match(r"\S", line) and not re.match(r"(when|unless|cases)", line):
                sec = None
        if r["id"]:
            rules.append(r)
    return rules


def cond_match(c, cmd):
    flags = re.ASCII | (re.I if "i" in c.get("flags", "") else 0)
    fn = re.fullmatch if c.get("op") == "fullmatch" else re.search
    return fn(c["pattern"], cmd, flags) is not None


def blocks(rule, cmd, drop_unless=False):
    if not all(cond_match(c, cmd) for c in rule["when"]):
        return False
    if not drop_unless and any(cond_match(c, cmd) for c in rule["unless"]):
        return False
    return True


def check_prototype(text):
    rules = parse_rules(text)
    if len(rules) < 3:
        err("prototipo: menos de 3 reglas de ejemplo parseadas")
    for r in rules:
        i = r["id"]
        if r["action"] == "block" and not (r["block"] and r["allow"]):
            err(f"{i}: regla block sin cases.block o sin cases.allow")
        for c in r["when"] + r["unless"]:
            if re.search(r"(?<![\[\\])\^|(?<!\\)\$", c.get("pattern", "")):
                err(f"{i}: ^ o $ en el patrón (prohibidos, D2)")
            if len(c.get("pattern", "")) > 256:
                err(f"{i}: patrón de más de 256 caracteres")
        for c in r["unless"]:
            if c["field"] == "tool_input.command" and c.get("op") != "fullmatch":
                err(f"{i}: unless sobre tool_input.command sin op fullmatch")
        for cmd in r["block"]:
            if not blocks(r, cmd):
                err(f"{i}: el caso block no bloquea: {cmd!r}")
        for cmd in r["allow"]:
            if blocks(r, cmd):
                err(f"{i}: el caso allow bloquea: {cmd!r}")
        for k, u in enumerate(r["unless"]):
            ejerce = [a for a in r["allow"]
                      if all(cond_match(c, a) for c in r["when"]) and cond_match(u, a)
                      and blocks(r, a, drop_unless=True)]
            if not ejerce:
                err(f"{i}: unless[{k}] sin allow que case con when y con el unless y bloquee sin él")
            if not [b for b in r["block"] if ";" in b and blocks(r, b)]:
                err(f"{i}: unless[{k}] sin block encadenado")


REQUIRED = [
    ("P1-1 exclusión de ids de la PR", "la base **excluye los `id` que esa PR modifica"),
    ("P1-1 base sigue si se borra o desactiva", "o está con `enabled: false` en local, la base sigue aplicando"),
    ("P1-2 allow del unless ejerce", "casa con `when` y con ese `unless`"),
    ("P1-2 block encadenado", "`cases.block` encadenado"),
    ("P1-3 salida de recuperación", "**Salida de recuperación.**"),
    ("P1-3 diagnose", "`diagnose`"),
    ("P1-3 eval no ejecuta cases", "**`eval` no ejecuta los `cases`.**"),
    ("P1-4 canal de warn", "`additionalContext`"),
    ("P2-1 gramática", "**Gramática del frontmatter**"),
    ("P2-2 semántica de regex", "re.ASCII"),
    ("P2-3 backtracking ampliado", "`.*.*x`"),
    ("P2-4 test aislado", "la aísla (conjunto = solo esa regla"),
    ("P2-5 motor tier 3", "`scripts/guard_rules.py`, `config/guard-rules.yaml`"),
    ("P2-5 opencode tier 4", "tier 4"),
    ("sec P2-1 unless fullmatch", "solo con `op: fullmatch`"),
    ("sec P2-3 modelo de amenaza", "**Modelo de amenaza, dicho con honestidad.**"),
    ("sec P2-4 perfil por entorno", "`SAVIA_HOOK_PROFILE`"),
    ("sec P2-5 python3 incondicional", "exit 2, incondicional"),
    ("sec P2-6 base configurable", "**Ref de base configurable.**"),
]


def check_spec(text):
    for name, frag in REQUIRED:
        if frag not in text:
            err(f"spec: falta {name}: {frag!r}")
    for ac in ("AC-3b", "AC-3c"):
        if not re.search(rf"^\| {ac} \|", text, re.M):
            err(f"spec: falta la fila {ac}")


def main():
    if len(sys.argv) != 3:
        print("uso: se520_spec_check.py <spec.md> <prototipo.md>", file=sys.stderr)
        return 2
    try:
        spec = open(sys.argv[1], encoding="utf-8").read()
        proto = open(sys.argv[2], encoding="utf-8").read()
    except (OSError, UnicodeDecodeError) as e:
        print(f"no se puede leer: {e}", file=sys.stderr)
        return 2
    check_spec(spec)
    check_prototype(proto)
    for e in ERR:
        print(e, file=sys.stderr)
    return 1 if ERR else 0


if __name__ == "__main__":
    sys.exit(main())
