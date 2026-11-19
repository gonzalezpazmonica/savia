#!/usr/bin/env python3
"""Casos del adaptador en sombra SE-343 -> kernel (SE-496 F1, AC-10).

Mundo hermético de denegaciones.World (repo con origin/main propio, operadores ficticios con claves
generadas aquí, `gh` falso, HOME temporal) más una copia de scripts/operator-grant.sh y un ledger de
grants de prueba firmado con esas claves. No lee el perfil real ni ~/.savia real.

  shadow_se343.py <caso>      -> imprime OK o la lista de fallos; exit 1 si falla algo
"""
import datetime
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from denegaciones import INSTALL, REPO, KERNEL, World, sh  # noqa: E402

SHADOW = os.path.join(REPO, "tests", "helpers", "se496_shadow_entry.py")
GRANT_FIELDS = ("id", "scope", "repo", "resource", "grantor", "request_context",
                "issued_at", "issued_epoch", "expires_at", "expires_epoch", "head_sha")
HEAD = "a" * 40
# gh que ve operator-grant.sh (solo con SAVIA_GRANT_TEST_MODE=1): la cabeza del PR falso.
GH_GRANT = """#!/usr/bin/env bash
n="$3"
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"], end="")' "$SE496_FAKE_DIR/pr-$n.json"
"""


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


class ShadowWorld(World):
    def __init__(self):
        super().__init__()
        os.makedirs(os.path.join(self.root, "scripts"))
        shutil.copy(os.path.join(REPO, "scripts", "operator-grant.sh"), os.path.join(self.root, "scripts"))
        lines = []
        for slug in ("op-a", "op-b"):
            pub = open(os.path.join(self.keys, slug + ".pub")).read().split()
            lines.append('%s namespaces="savia-delegation,savia-operator-grant" %s %s' % (slug, pub[0], pub[1]))
        self.commit_to_main("config/operator-grant-" + "signers", "\n".join(lines) + "\n")
        gh = os.path.join(self.bin, "gh-grant")
        with open(gh, "w") as f:
            f.write(GH_GRANT)
        os.chmod(gh, 0o755)
        self.grants = os.path.join(self.home, ".savia", "grants")
        os.makedirs(self.grants)
        self.now = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
        # operator-grant.sh usa el reloj real: el kernel, inyectado, ve el mismo instante.
        self.env_extra.update({"SAVIA_GRANT_TEST_MODE": "1", "SAVIA_GH_BIN": gh,
                               "SAVIA_AUTHORITY_NOW": iso(self.now)})
        self.set_pr(7, isDraft=False)

    def merge_grant(self, pr=7, signer="op-a", key=None, ttl=3600, resource=None):
        issued = self.now - datetime.timedelta(seconds=60)
        exp = issued + datetime.timedelta(seconds=ttl)
        rec = {"id": os.urandom(16).hex(), "scope": "merge", "repo": INSTALL,
               "resource": resource or "pr:%d" % pr, "grantor": signer, "request_context": "prueba",
               "issued_at": iso(issued), "issued_epoch": int(issued.timestamp()),
               "expires_at": iso(exp), "expires_epoch": int(exp.timestamp()),
               "head_sha": HEAD if (resource or "pr:").startswith("pr:") else ""}
        payload = json.dumps({f: rec.get(f) for f in GRANT_FIELDS}, sort_keys=True, ensure_ascii=True,
                             separators=(",", ":")).encode()
        p = os.path.join(self.t, "grant-payload")
        with open(p, "wb") as f:
            f.write(payload)
        sh("ssh-keygen", "-q", "-Y", "sign", "-f", os.path.join(self.keys, key or signer),
           "-n", "savia-operator-grant", p)
        rec.update(source="operator-signature", sig=open(p + ".sig").read())
        os.remove(p + ".sig")
        with open(os.path.join(self.grants, "merge.json"), "w") as f:
            json.dump(rec, f)
        return rec

    def autonomy_grant(self, skill="overnight-sprint"):
        exp = self.now + datetime.timedelta(hours=1)
        rec = {"scope": "autonomy:" + skill, "grantor": "op-a", "source": "express-request",
               "request_context": "prueba", "issued_at": iso(self.now), "expires_at": iso(exp),
               "expires_epoch": int(exp.timestamp())}
        with open(os.path.join(self.grants, "autonomy:%s.json" % skill), "w") as f:
            json.dump(rec, f)

    def grant_check(self, rec):
        e = self.env()
        e["SAVIA_GRANTS_DIR"] = self.grants
        r = subprocess.run(["bash", os.path.join(self.root, "scripts", "operator-grant.sh"), "check",
                            "--scope", "merge", "--resource", rec["resource"]], capture_output=True, env=e)
        return r.returncode

    def shadow(self, *args):
        r = subprocess.run([sys.executable, "-I", SHADOW] + list(args), capture_output=True, env=self.env())
        rows = [json.loads(l) for l in r.stdout.decode().splitlines() if l.strip()]
        return r.returncode, rows, r.stderr.decode()

    def audit(self):
        p = os.path.join(self.home, ".savia", "authority", "audit.jsonl")
        if not os.path.exists(p):
            return []
        return [json.loads(l) for l in open(p) if l.strip()]

    def verify_audit(self):
        r = subprocess.run([sys.executable, "-I", KERNEL, "verify-audit"], capture_output=True, env=self.env())
        return r.returncode


def grant_rows(rows):
    return [r for r in rows if "summary" not in r]


def expect(bad, cond, msg):
    if not cond:
        bad.append(msg)


def c_allow():
    """Grant vigente que el kernel también permitiría: sin discrepancia; no consume ni el grant ni usos."""
    bad, w = [], ShadowWorld()
    rec = w.merge_grant()
    expect(bad, w.grant_check(rec) == 0, "el grant de prueba no está vigente para SE-343")
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, rc == 0, "exit %s (%s)" % (rc, err))
    expect(bad, len(g) == 1 and g[0].get("kernel_decision") == "ALLOW" and g[0].get("discrepancy") is False,
           "fila: %s" % g)
    expect(bad, all(r.get("shadow") is True for r in rows), "falta shadow: true")
    a = [e for e in w.audit() if e.get("mode") == "shadow-se343"]
    expect(bad, len(a) == 1 and a[0]["discrepancy"] is False and a[0]["grant_id"] == rec["id"]
           and a[0]["decision"] == "ALLOW", "audit: %s" % a)
    expect(bad, w.verify_audit() == 0, "verify-audit roto tras la sombra")
    expect(bad, w.grant_check(rec) == 0, "la sombra alteró el grant (check ya no da 0)")
    expect(bad, not os.path.exists(os.path.join(w.home, ".savia", "authority", "uses")), "la sombra consumió usos")
    w.close()
    return bad


def c_draft():
    """Grant vigente sobre un PR en borrador: el kernel deniega en el paso 13 -> discrepancia en el audit."""
    bad, w = [], ShadowWorld()
    w.set_pr(7, isDraft=True)
    rec = w.merge_grant()
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, rc == 0, "la sombra no decide: exit %s con discrepancia (%s)" % (rc, err))
    expect(bad, len(g) == 1 and g[0].get("grant_exit") == 0 and g[0].get("kernel_decision") == "DENY"
           and g[0].get("kernel_reason") == "PRECONDITION_FAILED:not_draft" and g[0].get("kernel_step") == 13
           and g[0].get("discrepancy") is True, "fila: %s" % g)
    a = [e for e in w.audit() if e.get("mode") == "shadow-se343"]
    expect(bad, len(a) == 1 and a[0]["discrepancy"] is True and a[0]["kernel_step"] == 13, "audit: %s" % a)
    expect(bad, a and a[0]["params"] == {"pr_number": 7}, "pr_number no va en claro (audit_plain)")
    expect(bad, w.grant_check(rec) == 0, "operator-grant.sh cambió su exit tras la sombra")
    rc, rows, _ = w.shadow("report")
    rep = rows[0] if rows else {}
    expect(bad, rc == 0 and rep.get("evaluaciones") == 1 and rep.get("discrepancias") == 1
           and rep.get("por_motivo") == {"DENY PRECONDITION_FAILED:not_draft": 1}, "report: %s" % rep)
    w.close()
    return bad


def c_revoked():
    """El nonce proyectado (16 primeros hex del id del grant) revocado en origin/main -> REVOKED, paso 5."""
    bad, w = [], ShadowWorld()
    rec = w.merge_grant()
    w.commit_to_main("config/delegations/REVOKED", rec["id"][:16] + "\n")
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, len(g) == 1 and g[0].get("kernel_reason") == "REVOKED" and g[0].get("kernel_step") == 5
           and g[0].get("discrepancy") is True, "fila: %s (%s)" % (g, err))
    w.close()
    return bad


def c_not_vigente():
    """Grant firmado con una clave que no está en los firmantes: SE-343 no lo da por vigente, no se proyecta."""
    bad, w = [], ShadowWorld()
    rec = w.merge_grant(key="op-c")
    expect(bad, w.grant_check(rec) == 1, "el grant mal firmado da %s en SE-343" % w.grant_check(rec))
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, rc == 0 and len(g) == 1 and g[0].get("grant_exit") == 1 and g[0].get("projected") is False
           and "kernel_decision" not in g[0], "fila: %s (%s)" % (g, err))
    expect(bad, not [e for e in w.audit() if e.get("mode") == "shadow-se343"], "un grant no vigente llegó al audit")
    w.close()
    return bad


def c_unmapped():
    """autonomy:* y merge sobre task:<id> no tienen capacidad equivalente -> UNMAPPED (discrepancia de cobertura)."""
    bad, w = [], ShadowWorld()
    w.autonomy_grant()
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, rc == 0 and len(g) == 1 and g[0].get("scope") == "autonomy:overnight-sprint"
           and g[0].get("kernel_decision") == "UNMAPPED" and g[0].get("discrepancy") is True,
           "autonomy: %s (%s)" % (g, err))
    w.close()
    w = ShadowWorld()
    rec = w.merge_grant(resource="task:t-1")
    expect(bad, w.grant_check(rec) == 0, "grant task: no vigente en SE-343")
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    expect(bad, len(g) == 1 and g[0].get("kernel_decision") == "UNMAPPED" and g[0].get("projected") is False,
           "task: %s (%s)" % (g, err))
    w.close()
    return bad


def c_default_delegate():
    """Sin --delegate, el delegado es savia, que no tiene nivel en agent-permission-levels.md: UNKNOWN_STATE
    en el paso 15. Es lo que la sombra mostrará hoy para cada merge."""
    bad, w = [], ShadowWorld()
    w.merge_grant()
    rc, rows, err = w.shadow("run")
    g = grant_rows(rows)
    expect(bad, len(g) == 1 and g[0].get("kernel_reason") == "UNKNOWN_STATE" and g[0].get("kernel_step") == 15
           and g[0].get("discrepancy") is True, "fila: %s (%s)" % (g, err))
    w.close()
    return bad


def c_fail_closed():
    """Ledger ilegible, argumentos no válidos o delegado con caracteres raros: exit 2, nunca 0."""
    bad, w = [], ShadowWorld()
    shutil.rmtree(w.grants)
    open(w.grants, "w").close()  # el ledger es un fichero, no un directorio
    rc, rows, _ = w.shadow("run", "--delegate", "commit-guardian")
    expect(bad, rc == 2 and not rows, "ledger ilegible: exit %s, salida %s" % (rc, rows))
    w.close()
    w = ShadowWorld()  # ledger legible: el exit 2 lo causan solo los argumentos
    rc, _, _ = w.shadow("run", "--delegate", "commit-guardian")
    expect(bad, rc == 0, "control: con argumentos válidos el exit es %s" % rc)
    for args in (["run", "--delegate", "../x"], ["run", "--delegate"], ["run", "extra"], ["nada"], []):
        rc, rows, _ = w.shadow(*args)
        expect(bad, rc == 2, "%s: exit %s" % (args, rc))
    w.close()
    return bad


def c_reserved_extra():
    """audit_append no deja que los campos extra pisen los del kernel."""
    bad = []
    sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
    import authority_kernel as k
    w = World()
    saved = dict(os.environ)
    os.environ["HOME"] = w.home
    k.OVERRIDES.clear()
    k.OVERRIDES.update({"SAVIA_AUTHORITY_ROOT": w.root})
    try:
        ctx = k.Ctx({"delegate": "x", "capability": "y", "action": {"name": "y"}, "target": {}})
        res = {"evaluated_at": "2026-11-12T10:00:00Z", "decision": "DENY", "reason": "X", "contract_id": None,
               "action_sha256": "0", "state_digest": None}
        for key in ("decision", "prev_sha256"):
            try:
                k.audit_append(ctx, res, "shadow-se343", extra={key: "ALLOW"})
                bad.append("extra %s pisó el campo del kernel" % key)
            except ValueError:
                pass
        k.audit_append(ctx, res, "shadow-se343", extra={"discrepancy": True})
        lines = [json.loads(l) for l in open(os.path.join(w.home, ".savia", "authority", "audit.jsonl"))]
        expect(bad, len(lines) == 1 and lines[0]["decision"] == "DENY" and lines[0]["discrepancy"] is True,
               "audit: %s" % lines)
    finally:
        k.OVERRIDES.clear()
        os.environ.clear()
        os.environ.update(saved)
        w.close()
    return bad


def c_no_check():
    """operator-grant.sh no puede correr: la pasada es incompleta -> exit 2, nunca 0 con 'vigentes: 0'."""
    bad, w = [], ShadowWorld()
    w.merge_grant()
    os.remove(os.path.join(w.root, "scripts", "operator-grant.sh"))
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    summ = [r["summary"] for r in rows if "summary" in r]
    expect(bad, rc == 2, "sin check: exit %s (%s)" % (rc, err))
    expect(bad, len(g) == 1 and g[0].get("grant_exit") is None and g[0].get("projected") is False
           and g[0].get("note") == "check no pudo correr", "fila: %s" % g)
    expect(bad, summ and summ[0].get("incompletos") == 1 and summ[0].get("vigentes") == 0, "summary: %s" % summ)
    expect(bad, not [e for e in w.audit() if e.get("mode") == "shadow-se343"], "sin check llegó al audit")
    w.close()
    return bad


def c_corrupt_grant():
    """Un grant ilegible no se pierde en silencio: el resto se evalúa, pero la pasada sale con exit 2."""
    bad, w = [], ShadowWorld()
    w.autonomy_grant()
    with open(os.path.join(w.grants, "merge.json"), "w") as f:
        f.write("{roto")
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    summ = [r["summary"] for r in rows if "summary" in r]
    expect(bad, rc == 2, "grant ilegible: exit %s (%s)" % (rc, err))
    expect(bad, any(r.get("note") == "grant ilegible" for r in g), "sin fila del ilegible: %s" % g)
    expect(bad, any(r.get("kernel_decision") == "UNMAPPED" for r in g), "el resto no se evaluó: %s" % g)
    expect(bad, summ and summ[0].get("incompletos") == 1, "summary: %s" % summ)
    w.close()
    return bad


def c_report_runs():
    """report separa runs y grants distintos de las líneas brutas y no salta en silencio las líneas
    ilegibles del audit. Un grant de otra operadora no es vigente para SE-343: no llega a proyectarse."""
    bad, w = [], ShadowWorld()
    w.set_pr(7, isDraft=True)
    w.merge_grant()
    for _ in range(2):
        rc, _, err = w.shadow("run", "--delegate", "commit-guardian")
        expect(bad, rc == 0, "run: exit %s (%s)" % (rc, err))
    rc, rows, _ = w.shadow("report")
    rep = rows[0] if rows else {}
    expect(bad, rc == 0 and rep.get("evaluaciones") == 2 and rep.get("runs") == 2
           and rep.get("grants_distintos") == 1 and rep.get("grants_con_discrepancia") == 1
           and rep.get("lineas_ilegibles") == 0, "report: %s" % rep)
    w.merge_grant(signer="op-b")  # firmante válido, pero no es el perfil activo (op-a)
    rc, rows, err = w.shadow("run", "--delegate", "commit-guardian")
    g = grant_rows(rows)
    summ = [r["summary"] for r in rows if "summary" in r]
    expect(bad, rc == 0 and len(g) == 1 and g[0].get("grant_exit") == 1 and g[0].get("projected") is False
           and summ and summ[0].get("no_vigentes") == 1, "op-b: %s %s (%s)" % (g, summ, err))
    rc, rows, _ = w.shadow("report")
    rep = rows[0] if rows else {}
    expect(bad, rep.get("evaluaciones") == 2 and rep.get("grants_distintos") == 1, "report op-b: %s" % rep)
    with open(os.path.join(w.home, ".savia", "authority", "audit.jsonl"), "a") as f:
        f.write("{roto\n")
    rc, rows, _ = w.shadow("report")
    rep = rows[0] if rows else {}
    expect(bad, rc == 2 and rep.get("lineas_ilegibles") == 1, "audit con línea rota: exit %s %s" % (rc, rep))
    w.close()
    return bad


CASES = {"allow": c_allow, "draft": c_draft, "revoked": c_revoked, "not-vigente": c_not_vigente,
         "unmapped": c_unmapped, "default-delegate": c_default_delegate, "fail-closed": c_fail_closed,
         "reserved-extra": c_reserved_extra,
         "no-check": c_no_check, "corrupt-grant": c_corrupt_grant, "report-runs": c_report_runs}

if __name__ == "__main__":
    bad = []
    for name in sys.argv[1:]:
        bad += ["%s: %s" % (name, b) for b in CASES[name]()]
    print("\n".join(bad) if bad else "OK")
    sys.exit(1 if bad else 0)
