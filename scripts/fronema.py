#!/usr/bin/env python3
"""fronema.py — Frónesis como Código (SE-344): CLI de fronemas.

Captura, verifica, consulta y entrena con casos de juicio vivido (fronemas)
destilados a N2 en la cúpula Frónesis de SaviaVaults. CRIT-001: cero red,
cero datos N3+ (los casos destilados no llevan datos identificativos).

Principio rector: sin consecuencia verificada no hay fronema; el sistema
expulsa lo que deja de requerir juicio (graduate → regla).

Persistencia: notas markdown con frontmatter YAML (subset mínimo) en --vault.
Stdlib puro (sin deps nuevas).
"""

import argparse
import json
import os
import random
import re
import sys
from datetime import datetime, timezone

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(SCRIPT_DIR)
DEFAULT_VAULT = os.path.join(ROOT, "vaults", "Fronesia")

# L23 taxonomía (IDs de dominio válidos) — fuente docs/domains/savia-domains-catalog.md
L23_DOMAINS = {
    "PUA", "CON", "LEG", "CMP", "BNK", "INS", "FNC", "CTR", "SFT", "AID",
    "CYB", "TLC", "ELC", "SEM", "RBT", "AUT", "EDU", "EVA", "POW", "REN",
    "EFF", "INF", "MOV", "IDS", "LOG", "RTL", "SLS", "MKT", "HRS", "AGR",
    "TUR", "CUL", "MDS",
}
VALID_NIVEL = {"N1", "N2"}
VALID_MADUREZ = {"draft", "verified", "calibrated", "overruled"}
VALID_VERIF = {"pending", "T+30", "T+90", "T+180", "T+0"}
MADUREZ_RANK = {"verified": 0, "calibrated": 1, "draft": 2, "overruled": 3}


# ── Frontmatter YAML subset (serializar + parsear lo que este CLI escribe) ──

def _dump_value(v, indent=0):
    pad = "  " * indent
    lines = []
    if isinstance(v, dict):
        # flow mapping {k: v} (valores escalares) — un solo párrafo
        inner = ", ".join(f"{k}: {_dump_scalar(val)}" for k, val in v.items())
        lines.append(f"{pad}{{{inner}}}")
    elif isinstance(v, list):
        for item in v:
            lines.append(f"{pad}- {_dump_scalar(item)}")
    return lines


def _dump_scalar(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return str(v)
    s = str(v)
    if ":" in s or s.startswith(("-", "{", "[", '"', "'")):
        return '"' + s.replace('"', '\\"') + '"'
    return s


def frontmatter_to_yaml(case: dict) -> str:
    out = ["---"]
    for k, v in case.items():
        if isinstance(v, dict):
            inner = ", ".join(f"{k2}: {_dump_scalar(val)}" for k2, val in v.items())
            out.append(f"{k}: {{{inner}}}")
        elif isinstance(v, list):
            out.append(f"{k}:")
            for item in v:
                out.append(f"  - {_dump_scalar(item)}")
        else:
            out.append(f"{k}: {_dump_scalar(v)}")
    out.append("---")
    out.append("")
    out.append(f"# Fronema {case.get('id', '')}")
    out.append("")
    out.append(f"Decisión: {case.get('decision', '')}")
    out.append("")
    return "\n".join(out) + "\n"


def parse_frontmatter(text: str) -> dict:
    """Parsea el frontmatter YAML (subset) de una nota de fronema."""
    m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
    if not m:
        return {}
    case = {}
    cur_list_key = None
    for raw in m.group(1).splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        line = raw.strip()
        if line.startswith("- "):
            item = _parse_scalar(line[2:].strip())
            if cur_list_key:
                case.setdefault(cur_list_key, []).append(item)
            continue
        if ":" in line:
            key, _, val = line.partition(":")
            key = key.strip()
            val = val.strip()
            cur_list_key = None
            if val.startswith("{") and val.endswith("}"):
                # flow mapping {k: v, ...}
                d = {}
                for pair in val[1:-1].split(","):
                    if ":" in pair:
                        k2, _, v2 = pair.partition(":")
                        d[k2.strip()] = _parse_scalar(v2.strip())
                case[key] = d
            elif val == "":
                # lista
                case.setdefault(key, [])
                cur_list_key = key
            else:
                case[key] = _parse_scalar(val)
    return case


def _parse_scalar(s):
    if s in ("true", "false"):
        return s == "true"
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    if s.startswith('"') and s.endswith('"'):
        return s[1:-1].replace('\\"', '"')
    return s


# ── IO ──

def case_path(vault, cid):
    return os.path.join(vault, f"{cid}.md")


def load_case(vault, cid):
    p = case_path(vault, cid)
    if not os.path.exists(p):
        return None, None
    return parse_frontmatter(open(p, encoding="utf-8").read()), p


def save_case(path, case):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(frontmatter_to_yaml(case))


def next_id(vault):
    ids = [int(m.group(1)) for f in os.listdir(vault)
           if (m := re.match(r"pc-(\d+)\.md$", f))] if os.path.isdir(vault) else []
    return f"pc-{max(ids) + 1:04d}" if ids else "pc-0001"


def scan_cases(vault):
    out = []
    if not os.path.isdir(vault):
        return out
    for f in sorted(os.listdir(vault)):
        if not f.endswith(".md"):
            continue
        c = parse_frontmatter(open(os.path.join(vault, f), encoding="utf-8").read())
        if c.get("entity", {}).get("type") == "phronesis-case":
            c["_file"] = f
            out.append(c)
    return out


def cid(case):
    return (case.get('entity') or {}).get('id') or case.get('id') or '?'


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ── Validación ──

def validate(case: dict) -> list:
    errs = []
    for field in ("tension", "decision", "razon", "limites", "fuente"):
        if not str(case.get(field, "")).strip():
            errs.append(f"campo obligatorio vacío: {field}")
    if not case.get("prototipo") or not isinstance(case["prototipo"], list) or not case["prototipo"]:
        errs.append("prototipo: al menos 1 señal")
    if not case.get("deliberacion") or not isinstance(case["deliberacion"], list) or not case["deliberacion"]:
        errs.append("deliberacion: al menos 1 pregunta")
    dom = case.get("dominio")
    if not dom or (isinstance(dom, list) and not dom) or (isinstance(dom, str) and not dom.strip()):
        errs.append("dominio: al menos 1 (L23)")
    else:
        doms = dom if isinstance(dom, list) else [dom]
        for d in doms:
            if d.strip().upper() not in L23_DOMAINS:
                errs.append(f"dominio no-L23: {d}")
    if str(case.get("nivel", "N2")).upper() not in VALID_NIVEL:
        errs.append(f"nivel inválido: {case.get('nivel')} (solo N1/N2)")
    cons = case.get("consequence", {}) or {}
    mad = str(case.get("madurez", "draft"))
    verif = str(cons.get("verificacion", "pending"))
    if mad in ("verified", "calibrated", "overruled") and (verif == "pending" or not cons.get("resultado")):
        errs.append("madurez avanzada requiere consecuencia.verificacion != pending y resultado != null")
    return errs


# ── Comandos ──

def cmd_register(args):
    case = {
        "entity": {"type": "phronesis-case", "id": args.id or next_id(args.vault)},
        "dominio": [d.upper() for d in args.dominio],
        "tension": args.tension,
        "prototipo": args.senal,
        "deliberacion": args.pregunta,
        "decision": args.decision,
        "razon": args.razon,
        "consequence": {"verificacion": args.verificacion or "pending", "resultado": args.resultado},
        "limites": args.limites,
        "madurez": "verified" if (args.resultado and args.verificacion) else "draft",
        "fuente": args.fuente,
        "nivel": args.nivel.upper(),
        "ts": now_iso(),
    }
    errs = validate(case)
    if errs:
        for e in errs:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(2)
    save_case(case_path(args.vault, case["entity"]["id"]), case)
    print(f"ok {case['entity']['id']} madurez={case['madurez']}")
    return 0


def _mutate(args, mutator):
    case, path = load_case(args.vault, args.id)
    if case is None:
        print(f"ERROR: caso {args.id} no existe", file=sys.stderr)
        sys.exit(3)
    if case.get("madurez") == "overruled" and args.command != "overrule":
        print(f"ERROR: caso {args.id} ya overruled", file=sys.stderr)
        sys.exit(3)
    mutator(case)
    save_case(path, case)
    return 0


def cmd_verify(args):
    def m(c):
        c["consequence"]["verificacion"] = args.ventana
        c["consequence"]["resultado"] = args.resultado
        if args.arrepentimiento:
            c["consequence"]["arrepentimiento"] = args.arrepentimiento
        if args.correccion:
            c["consequence"]["correccion"] = args.correccion
        c["madurez"] = "verified"
        c["verified_at"] = now_iso()
        print(f"ok {cid(c)} -> verified")
    return _mutate(args, m)


def cmd_overrule(args):
    def m(c):
        c["consequence"]["resultado"] = args.resultado
        if args.correccion:
            c["consequence"]["correccion"] = args.correccion
        c["madurez"] = "overruled"
        c["overruled_at"] = now_iso()
        print(f"ok {cid(c)} -> overruled (no borrado; es historial)")
    return _mutate(args, m)


def cmd_calibrate(args):
    def m(c):
        c.setdefault("calibracion", []).append({"sesiones": args.aciertos, "total": args.total, "ts": now_iso()})
        ratio = args.aciertos / args.total if args.total > 0 else 0
        print(f"ok {cid(c)} aciertos={args.aciertos}/{args.total} ratio={ratio:.2f}")
        if args.total > 0 and ratio >= 0.9 and len(c["calibracion"]) >= 3:
            print(f"SUGERENCIA: caso {cid(c)} estable >=90% en >=3 sesiones — considerar: fronema.py graduate --id {cid(c)}")
    return _mutate(args, m)


def cmd_graduate(args):
    def m(c):
        c["madurez"] = "overruled"
        c["graduate_note"] = "graduado a regla"
        c["graduate_dest"] = "CRITERIO.md o regla de dominio"
        c["overruled_at"] = now_iso()
        print(f"ok {cid(c)} -> graduado a regla (historial preservado)")
        print(f"  destino sugerido: {c['graduate_dest']}")
    return _mutate(args, m)


def cmd_query(args):
    cases = scan_cases(args.vault)
    dom = getattr(args, 'dominio', None)
    mad = getattr(args, 'madurez', None)
    ten = getattr(args, 'tension', None)
    if dom:
        cases = [c for c in cases if dom.upper() in [str(d).upper() for d in c.get("dominio", [])]]
    if mad:
        cases = [c for c in cases if c.get("madurez") == mad]
    if ten:
        t = ten.lower()
        cases = [c for c in cases if t in str(c.get("tension", "")).lower()]
    cases.sort(key=lambda c: (MADUREZ_RANK.get(c.get("madurez"), 9), str(c.get("ts", ""))), reverse=False)
    if not cases:
        print("(sin precedentes)", file=sys.stderr)
        sys.exit(1)
    for c in cases:
        doms = ",".join(c.get("dominio", []))
        print(f"{cid(c)}\t{c.get('madurez')}\t{c.get('tension')}\t[{doms}]\t{c.get('decision','')[:60]}")
    return 0


def cmd_list(args):
    return cmd_query(args)


def cmd_train(args):
    candidates = [c for c in scan_cases(args.vault)
                  if c.get("madurez") in ("verified", "calibrated")]
    if not candidates:
        print("ERROR: no hay casos verified/calibrated para entrenar", file=sys.stderr)
        sys.exit(1)
    rng = random.Random(f"{args.sesion}:{args.dominio}")
    case = rng.choice(candidates)
    doms = ",".join(case.get("dominio", []))
    masked = (f"Dominio: {doms}\nTensión: {case.get('tension')}\nSeñales: "
              + "; ".join(case.get("prototipo", []))
              + f"\nLímites: {case.get('limites')}\n")
    print("=== CASO ENMASCARADO ===")
    print(masked)
    respuesta = input("¿Qué harías? (respuesta corta) > ").strip()
    conf = 0.5
    try:
        conf = float(input("¿Confianza 0-100? > ").strip()) / 100.0
    except ValueError:
        pass
    print("\n=== REVELACIÓN ===")
    print(f"Decisión real: {case.get('decision')}")
    print(f"Razón: {case.get('razon')}")
    print(f"Consecuencia: {case.get('consequence', {}).get('resultado')}")
    correct = 1 if (respuesta and str(case.get("decision", "")).lower() in respuesta.lower()) else 0
    brier = (conf - correct) ** 2
    out_dir = os.environ.get("FRONESIS_TRAIN_DIR") or os.path.join(ROOT, "output", "fronesis-training")
    os.makedirs(out_dir, exist_ok=True)
    rec = {"sesion": args.sesion, "dominio": args.dominio, "id": case["entity"]["id"],
           "confianza": round(conf, 3), "acierto": correct, "brier": round(brier, 4), "ts": now_iso()}
    with open(os.path.join(out_dir, f"{args.sesion}.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"\nbrier={brier:.4f} (confianza={conf:.2f}, acierto={correct}) → output/fronesis-training/{args.sesion}.jsonl")
    return 0


# ── Dispatcher ──

def main():
    ap = argparse.ArgumentParser(prog="fronema.py", description="Frónesis como Código (SE-344)")
    sub = ap.add_subparsers(dest="command", required=True)

    def add_vault(p):
        p.add_argument("--vault", default=DEFAULT_VAULT)

    r = sub.add_parser("register", help="registrar un fronema")
    r.add_argument("--id")
    r.add_argument("--tension", required=True)
    r.add_argument("--decision", required=True)
    r.add_argument("--razon", required=True)
    r.add_argument("--limites", required=True)
    r.add_argument("--senal", action="append", required=True)
    r.add_argument("--pregunta", action="append", required=True)
    r.add_argument("--dominio", action="append", required=True)
    r.add_argument("--fuente", required=True)
    r.add_argument("--nivel", default="N2")
    r.add_argument("--verificacion", choices=VALID_VERIF)
    r.add_argument("--resultado")
    add_vault(r)

    for cmd in ("verify", "overrule"):
        p = sub.add_parser(cmd)
        p.add_argument("--id", required=True)
        p.add_argument("--resultado", required=True)
        p.add_argument("--correccion")
        if cmd == "verify":
            p.add_argument("--arrepentimiento")
            p.add_argument("--ventana", choices=VALID_VERIF, default="T+90")
        add_vault(p)

    for cmd in ("calibrate", "graduate"):
        p = sub.add_parser(cmd)
        p.add_argument("--id", required=True)
        if cmd == "calibrate":
            p.add_argument("--aciertos", type=int, required=True)
            p.add_argument("--total", type=int, required=True)
        add_vault(p)

    q = sub.add_parser("query")
    q.add_argument("--tension")
    q.add_argument("--dominio")
    q.add_argument("--madurez", choices=VALID_MADUREZ)
    add_vault(q)

    l = sub.add_parser("list")
    l.add_argument("--madurez", choices=VALID_MADUREZ)
    l.add_argument("--dominio")
    add_vault(l)

    t = sub.add_parser("train")
    t.add_argument("--dominio", required=True)
    t.add_argument("--sesion", default="s1")
    add_vault(t)

    args = ap.parse_args()
    dispatch = {
        "register": cmd_register,
        "verify": cmd_verify,
        "overrule": cmd_overrule,
        "calibrate": cmd_calibrate,
        "graduate": cmd_graduate,
        "query": cmd_query,
        "list": cmd_list,
        "train": cmd_train,
    }
    return dispatch[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
