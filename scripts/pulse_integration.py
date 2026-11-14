#!/usr/bin/env python3
"""SE-518 S2 — política de integración, cabeza sin pruebas y huella de contenido.

Tres decisiones del latido (Pulse), cada una pura o con efectos inyectados:

1. `plan_integration`: política `solo_conflicto` (D4). Se integra la rama principal
   en una propuesta solo si choca o si es la siguiente en fusionarse y va por detrás.
2. `content_fingerprint` + `reviewers_decision`: las revisoras se relanzan solo si
   cambió la diferencia de la propuesta respecto a su base (D5). Fail-closed: ante
   cualquier error se relanzan. La puerta de fusión (atada al SHA) no cambia.
3. `classify_head_ci` + `ci_step`: cabeza sin pruebas o con pruebas en cola durante
   `ci_umbral` (15 min, D12) → un único relanzamiento registrado en el ledger antes
   del efecto; si no arranca, una petición. Nunca un segundo relanzamiento automático.

Sin dependencias (Python >= 3.9). Sin modo `--apply` no hay efectos sobre el forge:
solo se informa qué se haría (modo `observar`, D3).

Uso:
  gh pr list --json number,mergeable,mergeStateStatus | pulse_integration.py plan --next N
  pulse_integration.py fingerprint --base origin/main --head HEAD [--repo DIR]
  pulse_integration.py reviewers --pr N --base origin/main --head SHA [--record]
  pulse_integration.py ci --pr N [--apply]
Entorno: PULSE_LEDGER (ruta del ledger; por defecto bajo XDG_STATE_HOME), GH_BIN (gh).
Exit: 0 decisión tomada; 2 entrada o entorno no válidos (sin efectos).
"""
import argparse
import datetime as dt
import json
import os
import subprocess
import sys

SCHEMA_VERSION = 1
POLICIES = ("solo_conflicto",)
CI_UMBRAL_S = 15 * 60

# Un evento sin estos campos es inválido (fail-closed): se rechaza, no se rellena.
REQUIRED = {
    "cabeza_observada": ("pr", "sha"),
    "ci_relanzamiento": ("pr", "sha", "estado", "mecanismo"),
    "ci_relanzamiento_resultado": ("pr", "sha", "resultado"),
    "ci_atascada_peticion": ("pr", "sha", "motivo"),
    "ci_arrancada": ("pr", "sha", "tras_relanzar"),
    "huella_revisoras": ("pr", "sha", "huella"),
}


class Invalid(Exception):
    """Entrada o entorno no válido: exit 2, sin efectos."""


# ── 1. Política de integración ─────────────────────────────────────────────

def _classify(pr):
    m = pr.get("mergeable") or ""
    s = pr.get("mergeStateStatus") or ""
    if m == "CONFLICTING" or s == "DIRTY":
        return "conflicto"
    if m == "UNKNOWN" or s == "UNKNOWN" or not m or not s:
        return "desconocido"
    if s == "BEHIND":
        return "detras"
    return "otro"


def plan_integration(prs, next_pr=None, policy="solo_conflicto"):
    """Devuelve [{number, action: integrar|omitir, reason}] en el orden de entrada.

    Integra solo si hay conflicto real, o si es la siguiente en fusionarse y va por
    detrás. Estado desconocido: no se toca (lo recoge la siguiente pasada).
    """
    if policy not in POLICIES:
        raise Invalid("política desconocida: %r (solo %s)" % (policy, ", ".join(POLICIES)))
    if not isinstance(prs, list) or not all(
            isinstance(p, dict) and isinstance(p.get("number"), int)
            and not isinstance(p.get("number"), bool) for p in prs):
        raise Invalid("se esperaba un array de PR con `number` entero")
    if next_pr is not None and (not isinstance(next_pr, int) or isinstance(next_pr, bool)):
        raise Invalid("`next` debe ser un número de PR")
    out = []
    for p in prs:
        n, state = p["number"], _classify(p)
        if state == "conflicto":
            out.append({"number": n, "action": "integrar", "reason": "conflicto"})
        elif state == "desconocido":
            out.append({"number": n, "action": "omitir", "reason": "desconocido"})
        elif n == next_pr and state == "detras":
            out.append({"number": n, "action": "integrar", "reason": "siguiente"})
        elif n == next_pr:
            out.append({"number": n, "action": "omitir", "reason": "siguiente_al_dia"})
        else:
            out.append({"number": n, "action": "omitir", "reason": "sin_conflicto"})
    return out


# ── 2. Huella de contenido ─────────────────────────────────────────────────

def _git(repo, *args, stdin=None):
    return subprocess.run(["git", "-C", repo] + list(args), input=stdin,
                          capture_output=True, check=True, timeout=120).stdout


def content_fingerprint(repo, base, head):
    """patch-id estable de la diferencia head vs merge-base(base, head), sin contexto.

    Sin contexto (-U0) para que cambios ajenos alrededor de lo que toca la propuesta
    no alteren la huella. None ante cualquier fallo o diferencia vacía (fail-closed).
    """
    try:
        mb = _git(repo, "merge-base", base, head).decode().strip()
        if not mb:
            return None
        diff = _git(repo, "diff", "-U0", "--binary", mb, head)
        if not diff.strip():
            return None
        pid = _git(repo, "patch-id", "--stable", stdin=diff).decode().split()
        return pid[0] if pid else None
    except (subprocess.SubprocessError, OSError, UnicodeDecodeError):
        return None


def reviewers_decision(prev, cur):
    """('omitir','huella_igual') solo si ambas huellas existen y coinciden."""
    if not cur:
        return ("relanzar", "huella_actual_ilegible")
    if not prev:
        return ("relanzar", "sin_huella_anterior")
    if prev != cur:
        return ("relanzar", "huella_distinta")
    return ("omitir", "huella_igual")


# ── Ledger (solo añadir) ───────────────────────────────────────────────────

def _now():
    return dt.datetime.now(dt.timezone.utc)


def _iso(t):
    return t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _parse(ts):
    return dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)


def ledger_path(arg=None):
    p = arg or os.environ.get("PULSE_LEDGER")
    if p:
        return p
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "savia", "pulse", "ledger.jsonl")


class Ledger:
    def __init__(self, path):
        self.path = path

    def read(self):
        if not os.path.exists(self.path):
            return []
        rows = []
        with open(self.path, encoding="utf-8") as f:
            for i, line in enumerate(f, 1):
                if not line.strip():
                    continue
                try:
                    rows.append(json.loads(line))
                except ValueError:
                    raise Invalid("ledger corrupto en la línea %d: no se actúa" % i)
        return rows

    def append(self, kind, now, **fields):
        missing = [k for k in REQUIRED.get(kind, ()) if fields.get(k) in (None, "")]
        if kind not in REQUIRED or missing:
            raise Invalid("evento %r inválido (faltan: %s)" % (kind, ",".join(missing) or "tipo"))
        row = {"schema_version": SCHEMA_VERSION, "ts": _iso(now), "kind": kind,
               "nivel": "N4"}
        row.update(fields)
        os.makedirs(os.path.dirname(self.path) or ".", exist_ok=True)
        fd = os.open(self.path, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, (json.dumps(row, sort_keys=True) + "\n").encode())
            os.fsync(fd)
        finally:
            os.close(fd)
        return row

    def find(self, kind, pr, sha=None):
        return [r for r in self.read() if r.get("kind") == kind and r.get("pr") == pr
                and (sha is None or r.get("sha") == sha)]


# ── 3. Cabeza sin pruebas ──────────────────────────────────────────────────

def classify_head_ci(checks):
    """sin_pruebas | en_cola | en_marcha | desconocido, desde statusCheckRollup."""
    if checks is None or not isinstance(checks, list):
        return "desconocido"
    if not checks:
        return "sin_pruebas"
    if not all(isinstance(c, dict) for c in checks):
        return "desconocido"
    # CheckRun: status; StatusContext: state (PENDING sin ejecutar = en cola).
    sts = [str(c.get("status") or c.get("state") or "").upper() for c in checks]
    if any(s == "" for s in sts):
        return "desconocido"
    if all(s in ("QUEUED", "PENDING", "WAITING", "REQUESTED") for s in sts):
        return "en_cola"
    return "en_marcha"


def ci_step(ledger, pr, sha, state, committed_at, now, relaunch, apply=False,
            umbral=CI_UMBRAL_S, checks=None):
    """Una pasada sobre una cabeza. Devuelve (acción, motivo).

    acciones: nada | esperar | relanzar | peticion | peticion_ya_emitida |
              observar_relanzar (dry-run)
    El instante de partida es el posterior entre el commit y la primera vez que
    Pulse vio la cabeza: un commit antiguo recién empujado no cuenta como atascado.
    """
    seen = ledger.find("cabeza_observada", pr, sha)
    if not seen:
        ledger.append("cabeza_observada", now, pr=pr, sha=sha, estado=state)
        first_seen = now
    else:
        first_seen = _parse(seen[0]["ts"])
    relanz = ledger.find("ci_relanzamiento", pr, sha)

    if state == "desconocido":
        return ("nada", "estado_desconocido")
    if state == "en_marcha":
        if relanz and not ledger.find("ci_arrancada", pr, sha):
            ledger.append("ci_arrancada", now, pr=pr, sha=sha, tras_relanzar=True,
                          intento_en=relanz[0]["ts"])
        return ("nada", "en_marcha")

    since = max(committed_at, first_seen) if committed_at else first_seen
    obs = {"estado": state, "edad_s": int((now - since).total_seconds()),
           "pruebas": [{"nombre": str(c.get("name") or c.get("context") or "?"),
                        "estado": str(c.get("status") or c.get("state") or "?")}
                       for c in (checks or [])][:20]}

    if not relanz:
        if (now - since).total_seconds() < umbral:
            return ("esperar", "bajo_umbral")
        if not apply:
            return ("observar_relanzar", state)
        # Intención ANTES del efecto: si el proceso muere a mitad, no se repite.
        ledger.append("ci_relanzamiento", now, pr=pr, sha=sha, estado=state,
                      mecanismo="reabrir_pr", observado=obs)
        try:
            relaunch(pr)
            res = "ok"
        except Exception as e:  # el intento ya cuenta, aunque falle
            res = "error:%s" % type(e).__name__
        ledger.append("ci_relanzamiento_resultado", _now(), pr=pr, sha=sha, resultado=res)
        return ("relanzar", res)

    # Ya hubo un relanzamiento para esta cabeza: nunca otro automático.
    if (now - _parse(relanz[0]["ts"])).total_seconds() < umbral:
        return ("esperar", "tras_relanzar")
    if ledger.find("ci_atascada_peticion", pr, sha):
        return ("peticion_ya_emitida", "una_por_cabeza")
    if not apply:
        return ("peticion", "no_arranca_tras_relanzar")
    ledger.append("ci_atascada_peticion", now, pr=pr, sha=sha,
                  motivo="no_arranca_tras_relanzar", observado=obs)
    return ("peticion", "no_arranca_tras_relanzar")


# ── CLI ────────────────────────────────────────────────────────────────────

def _gh(*args):
    r = subprocess.run([os.environ.get("GH_BIN", "gh")] + list(args),
                       capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        raise Invalid("gh %s falló: %s" % (args[0], r.stderr.strip()[:200]))
    return r.stdout


def _relaunch_reopen(pr):
    _gh("pr", "close", str(pr))
    _gh("pr", "reopen", str(pr))


def _cmd_plan(a):
    try:
        prs = json.load(sys.stdin)
    except ValueError:
        raise Invalid("stdin no es JSON")
    for d in plan_integration(prs, a.next, a.policy):
        print(json.dumps(d, sort_keys=True))
    return 0


def _cmd_fingerprint(a):
    fp = content_fingerprint(a.repo, a.base, a.head)
    if not fp:
        print("huella no calculable", file=sys.stderr)
        return 1
    print(fp)
    return 0


def _cmd_reviewers(a):
    led = Ledger(ledger_path(a.ledger))
    prev = None
    for r in led.find("huella_revisoras", a.pr):
        prev = r.get("huella")
    cur = content_fingerprint(a.repo, a.base, a.head)
    action, why = reviewers_decision(prev, cur)
    if action == "relanzar" and a.record and cur:
        led.append("huella_revisoras", _now(), pr=a.pr, sha=a.head, huella=cur)
    print(json.dumps({"action": action, "reason": why, "huella": cur}, sort_keys=True))
    return 0


def _cmd_ci(a):
    led = Ledger(ledger_path(a.ledger))
    try:
        info = json.loads(_gh("pr", "view", str(a.pr), "--json",
                              "headRefOid,statusCheckRollup,commits"))
        sha = info["headRefOid"]
        commits = info.get("commits") or []
        cdate = (commits[-1].get("committedDate") if commits else None)
        committed = _parse(cdate) if cdate else None
    except (KeyError, ValueError, TypeError, IndexError):
        raise Invalid("respuesta de gh no interpretable: no se actúa")
    checks = info.get("statusCheckRollup")
    state = classify_head_ci(checks)
    action, why = ci_step(led, a.pr, sha, state, committed, _now(), _relaunch_reopen,
                          apply=a.apply, umbral=a.umbral, checks=checks)
    print(json.dumps({"pr": a.pr, "sha": sha, "estado": state, "action": action,
                      "reason": why, "apply": bool(a.apply)}, sort_keys=True))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="pulse_integration")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("--next", type=int, default=None)
    p.add_argument("--policy", default="solo_conflicto")
    p.set_defaults(fn=_cmd_plan)
    p = sub.add_parser("fingerprint")
    p.add_argument("--repo", default=".")
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.set_defaults(fn=_cmd_fingerprint)
    p = sub.add_parser("reviewers")
    p.add_argument("--repo", default=".")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--record", action="store_true")
    p.add_argument("--ledger")
    p.set_defaults(fn=_cmd_reviewers)
    p = sub.add_parser("ci")
    p.add_argument("--pr", type=int, required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--umbral", type=int, default=CI_UMBRAL_S)
    p.add_argument("--ledger")
    p.set_defaults(fn=_cmd_ci)
    try:
        a = ap.parse_args(argv)
        return a.fn(a)
    except Invalid as e:
        print("pulse_integration: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
