#!/usr/bin/env python3
"""ledger-bitemporal.py — SE-366: Decision Ledger bitemporal.

Dos ejes temporales (spec §3):
- Mundo:  valid_from / valid_to — cuándo el hecho fue cierto en el mundo.
- Savia:  asserted_at / superseded_at — cuándo Savia lo registró / corrigió.

No-overwrite: corregir cierra la fila (superseded_at) y crea una nueva
enlazada (supersedes). El historial completo es derivable por fold.

Evidence rows: cada versión referencia su fuente (ref local o URL + quote +
chunk_id). Un ref local inexistente rechaza la escritura (grounding, AC-5).

Receipts: cada escritura emite receipt SE-355 via scripts/audit-receipts.sh
(metadata-only, respeta SAVIA_AUDIT_DIR) — AC-6.

CRIT-001: JSONL append-only local; cero red, cero egress.

Uso:
  ledger-bitemporal.py add --predicate P --subject S --object O
      --valid-from D [--valid-to D] [--evidence-json '[{...}]']
      [--origin X] [--source agent|human] [--ledger F] [--asserted-at TS]
  ledger-bitemporal.py correct FACT_ID [--object O | --valid-from D | --valid-to D]
      [--evidence-json JSON] [--origin X] [--ledger F] [--asserted-at TS]
  ledger-bitemporal.py as-of YYYY-MM-DD [--ledger F]
  ledger-bitemporal.py history FACT_ID [--ledger F]
  ledger-bitemporal.py evidence FACT_ID [--ledger F]
  ledger-bitemporal.py --validate [--ledger F]
Exit: 0 ok · 1 estado invalido (validate) · 2 uso/input invalido.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

DEFAULT_LEDGER = "data/decision-ledger/ledger.jsonl"
REQUIRED_FIELDS = ("fact_id", "predicate", "subject", "object", "valid_from",
                   "valid_to", "asserted_at", "superseded_at", "supersedes",
                   "evidence", "origin", "source")
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(SCRIPT_DIR)


def now_iso():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def today():
    return datetime.now(timezone.utc).strftime("%Y-%m-%d")


def _is_date(s):
    try:
        datetime.strptime(s, "%Y-%m-%d")
        return True
    except (ValueError, TypeError):
        return False


def _is_ts(s):
    try:
        datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
        return True
    except (ValueError, TypeError):
        return False


def load_ledger(path):
    if not os.path.exists(path):
        return []
    rows = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{i}: JSON invalido: {exc}")
    return rows


def append_row(path, row):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def check_evidence_refs(evidence):
    """AC-5: los refs locales deben existir; las URLs se aceptan."""
    for ev in evidence or []:
        ref = ev.get("ref", "")
        if ref.startswith(("http://", "https://")):
            continue
        target = ref if os.path.isabs(ref) else os.path.join(REPO_ROOT, ref)
        if not os.path.exists(target):
            raise ValueError(f"evidence ref inexistente (grounding): {ref}")


def next_fact_id(rows, day):
    n = 1
    prefix = f"fact-{day.replace('-', '')}-"
    for r in rows:
        if r.get("fact_id", "").startswith(prefix):
            try:
                n = max(n, int(r["fact_id"][len(prefix):]) + 1)
            except ValueError:
                pass
    return f"{prefix}{n}"


def emit_receipt(action, actor, gate="savia-ledger"):
    """AC-6: receipt SE-355 metadata-only por cada escritura."""
    script = os.path.join(SCRIPT_DIR, "audit-receipts.sh")
    if not os.path.exists(script):
        print(f"WARN: receipt no emitido (falta {script})", file=sys.stderr)
        return
    try:
        subprocess.run(
            ["bash", script, "write", "--action", action, "--actor", actor,
             "--outcome", "success", "--gate", gate],
            check=True, capture_output=True, text=True, timeout=10)
    except (subprocess.SubprocessError, OSError) as exc:
        print(f"WARN: receipt fallo: {exc}", file=sys.stderr)


def _check_interval(valid_from, valid_to):
    """El ledger no se reescribe: un intervalo invertido quedaría para siempre
    (y --validate lo rechazaría), así que se corta antes de escribir."""
    if valid_to not in (None, "null") and valid_to < valid_from:
        raise ValueError(f"valid_to ({valid_to}) anterior a valid_from ({valid_from})")


def build_fact(rows, args):
    if not _is_date(args.valid_from):
        raise ValueError(f"--valid-from debe ser YYYY-MM-DD: {args.valid_from}")
    if args.valid_to is not None and args.valid_to != "null":
        if not _is_date(args.valid_to):
            raise ValueError(f"--valid-to debe ser YYYY-MM-DD o null: {args.valid_to}")
    _check_interval(args.valid_from, args.valid_to)
    if args.source not in ("agent", "human"):
        raise ValueError(f"--source debe ser agent|human: {args.source}")
    evidence = json.loads(args.evidence_json) if args.evidence_json else []
    if not isinstance(evidence, list):
        raise ValueError("--evidence-json debe ser un array")
    check_evidence_refs(evidence)
    asserted = args.asserted_at or now_iso()
    if not _is_ts(asserted):
        raise ValueError(f"--asserted-at debe ser ISO UTC: {asserted}")
    return {
        "fact_id": next_fact_id(rows, asserted[:10]),
        "predicate": args.predicate,
        "subject": args.subject,
        "object": args.object,
        "valid_from": args.valid_from,
        "valid_to": None if args.valid_to in (None, "null") else args.valid_to,
        "asserted_at": asserted,
        "superseded_at": None,
        "supersedes": None,
        "evidence": evidence,
        "origin": args.origin or "cli",
        "source": args.source,
    }


def cmd_add(args):
    rows = load_ledger(args.ledger)
    fact = build_fact(rows, args)
    if args.predicate is None or args.subject is None or args.object is None:
        raise ValueError("add exige --predicate --subject --object")
    append_row(args.ledger, fact)
    emit_receipt("ledger_bitemporal_add", fact["origin"])
    print(json.dumps({"added": fact["fact_id"]}, ensure_ascii=False))
    return 0


def cmd_correct(args):
    rows = load_ledger(args.ledger)
    target = next((r for r in rows if r.get("fact_id") == args.fact_id), None)
    if target is None:
        raise ValueError(f"fact_id no encontrado: {args.fact_id}")
    if target.get("superseded_at"):
        raise ValueError(f"{args.fact_id} ya esta cerrado (superseded)")
    superseded = args.asserted_at or now_iso()
    evidence = json.loads(args.evidence_json) if args.evidence_json else target["evidence"]
    if not isinstance(evidence, list):
        raise ValueError("--evidence-json debe ser un array")
    check_evidence_refs(evidence)
    new = dict(target)
    new["fact_id"] = next_fact_id(rows, superseded[:10])
    new["object"] = args.object if args.object is not None else target["object"]
    new["valid_from"] = args.valid_from or target["valid_from"]
    if args.valid_to is not None:
        new["valid_to"] = None if args.valid_to == "null" else args.valid_to
    if not _is_date(new["valid_from"]):
        raise ValueError(f"--valid-from debe ser YYYY-MM-DD: {new['valid_from']}")
    if new["valid_to"] is not None and not _is_date(new["valid_to"]):
        raise ValueError(f"--valid-to debe ser YYYY-MM-DD o null: {new['valid_to']}")
    _check_interval(new["valid_from"], new["valid_to"])
    new["asserted_at"] = superseded
    new["superseded_at"] = None
    new["supersedes"] = target["fact_id"]
    new["evidence"] = evidence
    # cierre no destructivo: fila vieja SOLO recibe superseded_at (append
    # de la fila cerrada + nueva; el fichero original se reescribe completo
    # porque JSONL append no puede mutar la linea previa)
    closed = dict(target)
    closed["superseded_at"] = superseded
    out = [closed if r.get("fact_id") == target["fact_id"] else r for r in rows]
    os.makedirs(os.path.dirname(args.ledger) or ".", exist_ok=True)
    with open(args.ledger, "w", encoding="utf-8") as f:
        for r in out:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    append_row(args.ledger, new)
    emit_receipt("ledger_bitemporal_correct", new["origin"])
    print(json.dumps({"corrected": target["fact_id"], "new": new["fact_id"]},
                     ensure_ascii=False))
    return 0


def chain_of(rows, fact_id):
    chain = []
    current = next((r for r in rows if r.get("fact_id") == fact_id), None)
    while current is not None:
        chain.append(current)
        nxt = current.get("supersedes")
        current = next((r for r in rows if r.get("fact_id") == nxt), None) if nxt else None
    return chain  # [mas reciente ... origen]


def cmd_as_of(args):
    if not _is_date(args.date):
        raise ValueError(f"as-of exige YYYY-MM-DD: {args.date}")
    rows = load_ledger(args.ledger)
    roots = []
    superseded_ids = {r["supersedes"] for r in rows if r.get("supersedes")}
    for r in rows:
        if r["fact_id"] not in superseded_ids:
            roots.append(r["fact_id"])
    state = []
    for fact_id in roots:
        chain = list(reversed(chain_of(rows, fact_id)))  # [origen ... reciente]
        candidates = [v for v in chain if v["asserted_at"][:10] <= args.date]
        if not candidates:
            continue  # Savia aun no lo creia en esa fecha
        latest = candidates[-1]
        if latest["valid_from"] > args.date:
            continue  # aun no era cierto en el mundo
        if latest["valid_to"] is not None and latest["valid_to"] < args.date:
            continue  # ya dejo de ser cierto en el mundo
        state.append(latest)
    print(json.dumps({"as_of": args.date, "facts": state},
                     ensure_ascii=False, indent=2))
    return 0


def cmd_history(args):
    rows = load_ledger(args.ledger)
    chain = chain_of(rows, args.fact_id)
    if not chain:
        raise ValueError(f"fact_id no encontrado: {args.fact_id}")
    print(json.dumps({"fact_id": args.fact_id, "versions": chain},
                     ensure_ascii=False, indent=2))
    return 0


def cmd_evidence(args):
    rows = load_ledger(args.ledger)
    chain = chain_of(rows, args.fact_id)
    if not chain:
        raise ValueError(f"fact_id no encontrado: {args.fact_id}")
    version = chain[0]
    if args.version is not None:
        if not (1 <= args.version <= len(chain)):
            raise ValueError(f"--version fuera de rango 1..{len(chain)}")
        version = chain[args.version - 1]
    print(json.dumps({"fact_id": version["fact_id"],
                      "evidence": version["evidence"]},
                     ensure_ascii=False, indent=2))
    return 0


def cmd_validate(args):
    rows = load_ledger(args.ledger)
    errors = []
    ids = set()
    for r in rows:
        fid = r.get("fact_id", "?")
        ids.add(fid)
        for field in REQUIRED_FIELDS:
            if field not in r:
                errors.append(f"{fid}: falta campo {field}")
        if not _is_date(r.get("valid_from")):
            errors.append(f"{fid}: valid_from invalido")
        if r.get("valid_to") is not None and not _is_date(r["valid_to"]):
            errors.append(f"{fid}: valid_to invalido")
        if r.get("valid_to") and r["valid_to"] < r.get("valid_from", ""):
            errors.append(f"{fid}: valid_to < valid_from")
        if not _is_ts(r.get("asserted_at", "")):
            errors.append(f"{fid}: asserted_at invalido")
        sup = r.get("superseded_at")
        if sup is not None:
            if not _is_ts(sup):
                errors.append(f"{fid}: superseded_at invalido")
            elif sup < r.get("asserted_at", ""):
                errors.append(f"{fid}: superseded_at < asserted_at")
        if r.get("supersedes") and r["supersedes"] not in ids and \
           r["supersedes"] not in {x.get("fact_id") for x in rows}:
            errors.append(f"{fid}: supersedes a id inexistente {r['supersedes']}")
    for r in rows:
        try:
            check_evidence_refs(r.get("evidence"))
        except ValueError as exc:
            errors.append(f"{r.get('fact_id', '?')}: {exc}")
    if errors:
        print(json.dumps({"validate": "FAIL", "errors": errors},
                         ensure_ascii=False, indent=2))
        return 1
    print(json.dumps({"validate": "OK", "facts": len(rows)}, ensure_ascii=False))
    return 0


def main():
    # pre-scan: --ledger/--validate aceptados antes o despues del subcomando
    global_args = {"ledger": DEFAULT_LEDGER, "validate": False}
    rest = []
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        if argv[i] == "--ledger":
            global_args["ledger"] = argv[i + 1]
            i += 2
        elif argv[i] == "--validate":
            global_args["validate"] = True
            i += 1
        else:
            rest.append(argv[i])
            i += 1

    ap = argparse.ArgumentParser(description="SE-366 Decision Ledger bitemporal")
    sub = ap.add_subparsers(dest="cmd")

    p_add = sub.add_parser("add")
    p_add.add_argument("--predicate")
    p_add.add_argument("--subject")
    p_add.add_argument("--object")
    p_add.add_argument("--valid-from", default=None)
    p_add.add_argument("--valid-to", default=None)
    p_add.add_argument("--evidence-json", default=None)
    p_add.add_argument("--origin", default=None)
    p_add.add_argument("--source", default="agent")
    p_add.add_argument("--asserted-at", default=None)

    p_cor = sub.add_parser("correct")
    p_cor.add_argument("fact_id")
    p_cor.add_argument("--object")
    p_cor.add_argument("--valid-from")
    p_cor.add_argument("--valid-to")
    p_cor.add_argument("--evidence-json", default=None)
    p_cor.add_argument("--origin", default=None)
    p_cor.add_argument("--asserted-at", default=None)

    p_asof = sub.add_parser("as-of")
    p_asof.add_argument("date")

    p_hist = sub.add_parser("history")
    p_hist.add_argument("fact_id")

    p_ev = sub.add_parser("evidence")
    p_ev.add_argument("fact_id")
    p_ev.add_argument("--version", type=int, default=None)

    args = ap.parse_args(rest)
    args.ledger = global_args["ledger"]
    try:
        if global_args["validate"]:
            sys.exit(cmd_validate(args))
        if args.cmd == "add":
            if args.valid_from is None:
                raise ValueError("add exige --valid-from")
            sys.exit(cmd_add(args))
        if args.cmd == "correct":
            if all(v is None for v in (args.object, args.valid_from, args.valid_to)):
                raise ValueError("correct exige --object o --valid-from/--valid-to")
            sys.exit(cmd_correct(args))
        if args.cmd == "as-of":
            sys.exit(cmd_as_of(args))
        if args.cmd == "history":
            sys.exit(cmd_history(args))
        if args.cmd == "evidence":
            sys.exit(cmd_evidence(args))
        ap.print_help()
        sys.exit(2)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)
    except (OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
