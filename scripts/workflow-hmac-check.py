#!/usr/bin/env python3
"""workflow-hmac-check.py — SE-501 AC-6 y AC-15: chequeo estático de workflows de GitHub Actions.

Uso:
  workflow-hmac-check.py pr-secrets <workflow.yml>...   AC-15/I3: ningún workflow disparado por
      pull_request, pull_request_target o workflow_run referencia CONFIDENTIALITY_HMAC_KEY ni expone
      todos los secretos (toJSON(secrets), secrets: inherit); ninguno declara
      pull_request_target junto a un checkout de la ref de la PR (AC-6).
  workflow-hmac-check.py main-audit <workflow.yml>       AC-6: el workflow de auditoría de main solo
      se dispara con push a main, sus permisos son exactamente contents: read (a nivel de workflow y de
      cada job), no referencia secrets., y cada acción va fijada por SHA de 40 hex.
Salida: 0 PASS · 1 FAIL (motivo por línea) · 2 entrada ilegible (fail-closed).
"""
import re
import sys

try:
    import yaml
except ImportError:  # sin parser no hay veredicto
    print("FAIL: falta PyYAML", file=sys.stderr)
    sys.exit(2)

SECRET = "CONFIDENTIALITY_HMAC_KEY"
PR_EVENTS = ("pull_request", "pull_request_target")
# workflow_run hereda los secretos y suele procesar artefactos de una PR: mismo trato que un evento de PR.
SECRET_EVENTS = PR_EVENTS + ("workflow_run",)
# Formas que exponen la clave sin nombrarla (expresiones de Actions: sin distinguir mayúsculas).
SECRET_BULK = re.compile(r"tojson\(\s*secrets\s*\)|^\s*secrets:\s*inherit\s*$", re.I | re.M)
EXPR_TOKEN = re.compile(r"'(?:[^']|'')*'|\bsecrets\b", re.I)
STATIC_SECRET = re.compile(r"secrets\s*(?:\.\s*([A-Za-z_][A-Za-z0-9_]*)|"
                           r"\[\s*'([A-Za-z_][A-Za-z0-9_]*)'\s*\])", re.I)
PR_HEAD_REF = re.compile(r"github\.event\.pull_request\.head\.(sha|ref)|github\.head_ref")
PINNED = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


def load(path):
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f.read())
    if not isinstance(doc, dict):
        raise ValueError("no es un mapa YAML")
    # PyYAML 1.1 lee la clave «on» como True.
    on = doc.get("on", doc.get(True))
    # Se busca en el YAML ya parseado y volcado: un comentario que nombra la clave no es una referencia.
    body = yaml.safe_dump(doc, allow_unicode=True, sort_keys=True, width=10**9)
    return body, doc, on


def events(on):
    if isinstance(on, str):
        return {on: None}
    if isinstance(on, list):
        return {e: None for e in on}
    if isinstance(on, dict):
        return on
    return {}


def expressions(value):
    """Yield expression bodies from YAML values; quoted '}}' never closes an expression."""
    if isinstance(value, dict):
        for child in value.values():
            yield from expressions(child)
    elif isinstance(value, list):
        for child in value:
            yield from expressions(child)
    elif isinstance(value, str):
        pos = 0
        while (start := value.find("${{", pos)) != -1:
            pos, quoted = start + 3, False
            while pos < len(value):
                if value[pos] == "'":
                    if quoted and value[pos:pos + 2] == "''":
                        pos += 2
                        continue
                    quoted = not quoted
                elif not quoted and value[pos:pos + 2] == "}}":
                    break
                pos += 1
            yield value[start + 3:pos]
            pos += 2


def dynamic_secret_access(doc):
    # Access by a computed key or the whole context can expose HMAC without naming it.
    # Quoted text is a literal, not a context reference; only static named accesses are allowed.
    for expression in expressions(doc):
        for token in EXPR_TOKEN.finditer(expression):
            if token.group().startswith("'"):
                continue
            named = STATIC_SECRET.match(expression, token.start())
            if named is None:
                return True
            if (named.group(1) or named.group(2)).upper() == SECRET:
                return True
    return False


def secret_context_used(doc):
    return any(not token.group().startswith("'")
               for expression in expressions(doc) for token in EXPR_TOKEN.finditer(expression))


def check_pr_secrets(path):
    text, doc, on = load(path)
    ev = events(on)
    bad = []
    if any(e in ev for e in SECRET_EVENTS):
        if SECRET.lower() in text.lower():
            bad.append(f"{path}: un workflow disparado por PR o workflow_run referencia {SECRET}")
        if SECRET_BULK.search(text):
            bad.append(f"{path}: un workflow disparado por PR o workflow_run expone todos los secretos "
                       "(toJSON(secrets) o secrets: inherit)")
        if dynamic_secret_access(doc):
            bad.append(f"{path}: un workflow disparado por PR o workflow_run usa un acceso no estático "
                       "al contexto de secretos o a la clave de auditoría")
    if "pull_request_target" in ev and PR_HEAD_REF.search(text):
        bad.append(f"{path}: pull_request_target con checkout de la ref de la PR")
    return bad


def check_main_audit(path):
    text, doc, on = load(path)
    bad = []
    ev = events(on)
    push = ev.get("push") if isinstance(ev, dict) else None
    if set(ev) != {"push"} or not isinstance(push, dict) or push.get("branches") != ["main"] or \
            set(push) - {"branches"}:
        bad.append(f"{path}: debe dispararse solo con push a main")
    if doc.get("permissions") != {"contents": "read"}:
        bad.append(f"{path}: permisos de workflow distintos de contents: read")
    for name, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            bad.append(f"{path}: job {name} ilegible")
            continue
        if "permissions" in job and job["permissions"] != {"contents": "read"}:
            bad.append(f"{path}: job {name} con permisos distintos de contents: read")
        for step in job.get("steps") or []:
            uses = step.get("uses") if isinstance(step, dict) else None
            if uses and not uses.startswith("./") and not PINNED.match(uses):
                bad.append(f"{path}: acción no fijada por SHA: {uses}")
    if secret_context_used(doc) or SECRET_BULK.search(text):
        bad.append(f"{path}: referencia al contexto secrets o herencia de secretos")
    if not doc.get("jobs"):
        bad.append(f"{path}: sin jobs")
    return bad


def main(argv):
    if len(argv) < 2 or argv[0] not in ("pr-secrets", "main-audit") or (argv[0] == "main-audit" and len(argv) != 2):
        print(__doc__, file=sys.stderr)
        return 2
    bad = []
    for p in argv[1:]:
        try:
            bad += check_pr_secrets(p) if argv[0] == "pr-secrets" else check_main_audit(p)
        except (OSError, ValueError, yaml.YAMLError):
            # Los errores de PyYAML pueden incluir el contenido de la línea.
            # El workflow inspeccionado no debe acabar volcado en el log.
            print(f"FAIL: {p}: YAML inválido o fichero ilegible", file=sys.stderr)
            return 2
    for b in bad:
        print(f"FAIL: {b}")
    if bad:
        return 1
    print(f"PASS: {argv[0]} ({len(argv) - 1} workflow(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
