#!/usr/bin/env python3
"""Casos de la batería SE-496 que no son un par neg/twin (AC-1, 2, 5b, 5c, 6b, 7, 9, 12).

  ledger_digest_audit.py check <caso...>     pares neg/twin de denegaciones.py
  ledger_digest_audit.py extra <nombre>      ledger | digest | nocache | audit | exit | signers-empty | validators
Imprime OK o la lista de fallos; exit 1 si falla algo.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from denegaciones import (CASES, INSTALL, KERNEL, MALFORMED, RC_FOR_NEG, World, canon, reason_of,  # noqa: E402
                     run_case)


def cli(w, args, stdin=""):
    r = subprocess.run([sys.executable, "-I", KERNEL] + args, input=stdin.encode(), capture_output=True, env=w.env())
    return r.returncode, r.stdout.decode().strip()


def pub_world(max_uses=1):
    w = World()
    w.set_pr(7)
    w.contract(cap="project.publish", declared_effects=["project.publish"], max_uses=max_uses,
               scope={"repo": [INSTALL], "prs": [7]})
    return w


def pub_req(w, title="p"):
    return w.request(capability="project.publish", action={"name": "project.publish", "params": {"project": title}},
                     target={"pr": 7})


def ex_ledger():
    bad = []
    w = pub_world()
    req = pub_req(w)
    out = None
    for _ in range(3):  # evaluate repetido no consume
        rc, out = w.ev(req)
        if rc != 0:
            bad.append("evaluate repetido: %s" % (out,))
    if os.path.exists(os.path.join(w.home, ".savia", "authority", "uses")):
        bad.append("evaluate escribio en el ledger")
    rec = w.receipt(out)
    if w.ev(req, "recheck", rec)[0] != 0:
        bad.append("primer recheck no dio ALLOW")
    rc, o2 = w.ev(req, "recheck", rec)
    if (rc, o2 and o2["reason"]) != (1, "MAX_USES_EXHAUSTED"):
        bad.append("segundo recheck: %s %s" % (rc, o2))
    w.close()
    for i in range(5):  # carrera: exactamente un ALLOW
        w = pub_world()
        req = pub_req(w)
        rc, out = w.ev(req)
        rec = w.receipt(out)
        ps = [subprocess.Popen([sys.executable, "-I", KERNEL, "recheck", "--prior", rec], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, env=w.env()) for _ in range(2)]
        res = []
        for pr in ps:
            o, _ = pr.communicate(json.dumps(req).encode())
            res.append((pr.returncode, json.loads(o)["reason"]))
        if sorted(res) != [(0, "OK"), (1, "MAX_USES_EXHAUSTED")]:
            bad.append("carrera %d: %s" % (i, res))
        w.close()
    return bad


def ex_digest():
    bad = []
    w = pub_world(max_uses=2)
    req = pub_req(w)
    rc, out = w.ev(req)
    w.set_pr(7, reviewDecision="REVIEW_REQUIRED")  # no referenciado por ninguna precondición
    w.set_pr(8, headRefOid="c" * 40)               # otro PR
    rc2, out2 = w.ev(req)
    if out["state_digest"] != out2["state_digest"]:
        bad.append("un cambio no referenciado altero el digest")
    if w.ev(req, "recheck", w.receipt(out))[0] != 0:
        bad.append("recheck tras cambio irrelevante no dio ALLOW")
    w.set_pr(7, headRefOid="d" * 40)
    rc3, out3 = w.ev(req)
    if out["state_digest"] == out3["state_digest"]:
        bad.append("head_sha nuevo no altero el digest")
    rc4, out4 = w.ev(req, "recheck", w.receipt(out))
    if (rc4, out4["reason"]) != (1, "STATE_CHANGED"):
        bad.append("recheck con head_sha nuevo: %s" % out4)
    w.close()
    # max_uses 2: dos órdenes evaluadas a la vez -> dos ALLOW (los usos no entran en el digest)
    w = pub_world(max_uses=2)
    r1, r2 = pub_req(w, "uno"), pub_req(w, "dos")
    _, o1 = w.ev(r1)
    _, o2 = w.ev(r2)
    a = w.ev(r1, "recheck", w.receipt(o1))[0]
    b = w.ev(r2, "recheck", w.receipt(o2))[0]
    if (a, b) != (0, 0):
        bad.append("dos ordenes con max_uses 2: %s %s" % (a, b))
    c = w.ev(pub_req(w, "uno"), "recheck", w.receipt(o1))
    if c[0] != 1:
        bad.append("tercer recheck no denegado: %s" % (c,))
    w.close()
    return bad


def ex_nocache():
    w = World()
    c = w.contract()
    rc1, _ = w.ev(w.request())
    os.makedirs(os.path.join(w.home, ".savia", "delegations"), exist_ok=True)
    with open(os.path.join(w.home, ".savia", "delegations", "REVOKED"), "w") as f:
        f.write(c["nonce"] + "\n")
    rc2, o2 = w.ev(w.request())
    w.close()
    return [] if (rc1, rc2, o2["reason"]) == (0, 1, "REVOKED") else ["sin cache: %s %s %s" % (rc1, rc2, o2)]


def ex_audit():
    bad = []
    w = World()
    w.contract()
    for title in ("SECRETO-123", "otro-secreto-456"):
        w.ev(w.request(action={"name": "pr.create-draft", "params": {"branch": "agent/work", "title": title}}))
    w.set_runs([{"status": "COMPLETED", "conclusion": "FAILURE"}])
    w.ev(w.request())  # denegado: también se registra
    w.set_runs([{"status": "COMPLETED", "conclusion": "SUCCESS"}])
    w.ev(w.request())
    path = os.path.join(w.home, ".savia", "authority", "audit.jsonl")
    text = open(path).read()
    lines = text.splitlines()
    if len(lines) != 4:
        bad.append("lineas de audit: %d" % len(lines))
    if "SECRETO-123" in text or "otro-secreto-456" in text:
        bad.append("un parametro no declarado salio en claro")
    if '"branch":"agent/work"' not in text:
        bad.append("el parametro audit_plain no aparece en claro")
    if '"decision":"DENY"' not in text or '"decision":"ALLOW"' not in text:
        bad.append("el audit no registra permitidos y denegados")
    if cli(w, ["verify-audit"])[0] != 0:
        bad.append("verify-audit falla en una cadena integra")

    def mutated(ls):
        with open(path, "w") as f:
            f.write("\n".join(ls) + "\n")
        return cli(w, ["verify-audit"])[0]
    e = list(lines)
    e[1] = e[1].replace('"mode":"evaluate"', '"mode":"recheck"')
    if mutated(e) != 1:
        bad.append("linea editada no detectada")
    if mutated([lines[0]] + lines[2:]) != 1:
        bad.append("linea borrada no detectada")
    if mutated([lines[0], lines[2], lines[1], lines[3]]) != 1:
        bad.append("lineas reordenadas no detectadas")
    if mutated(lines) != 0:
        bad.append("verify-audit no recupera la cadena restaurada")
    w.close()
    return bad


def ex_exit():
    bad = []
    w = World()
    w.contract()
    checks = [("ALLOW", 0, w.request()), ("NO_CONTRACT", 1, w.request(delegate="codex")),
              ("malformada", 2, "{x"), ("malformada2", 2, json.dumps([1, 2]))]
    for name, want, req in checks:
        rc, _ = w.ev(req)
        if rc != want:
            bad.append("%s: exit %s != %s" % (name, rc, want))
    # fallo interno del kernel: el audit no se puede escribir => no se concede (exit 2, nunca 0)
    w2 = World()
    w2.contract()
    os.makedirs(os.path.join(w2.home, ".savia"))
    with open(os.path.join(w2.home, ".savia", "authority"), "w") as f:
        f.write("no es un directorio")
    rc, _ = w2.ev(w2.request())
    if rc != 2:
        bad.append("fallo interno: exit %s != 2" % rc)
    w.close()
    w2.close()
    return bad


def ex_signers_empty():
    bad = []
    w = World()
    w.contract()
    w.write_signers([])
    w.commit_to_main("config/touch", "x")
    rc, o = w.ev(w.request())
    if (rc, o["reason"]) != (1, "BAD_SIGNATURE"):
        bad.append("firmantes vacios: %s %s" % (rc, o))
    w.close()
    return bad


def ex_validators():
    bad = []
    w = World()
    onto = os.path.join(w.root, "contracts", "ontology", "savia-operational.yaml")
    rc, out = cli(w, ["check-ontology", onto])
    if rc != 0:
        bad.append("ontologia real no pasa: " + out)
    dpath = os.path.join(w.root, "contracts", "capabilities", "pr.create-draft.yaml")
    d = open(dpath).read()
    with open(dpath, "w") as f:  # atributo inferred en una precondición
        f.write(d.replace("fact: Branch.name", "fact: Project.repo_membership"))
    rc, out = cli(w, ["check-ontology", onto])
    if rc != 1 or "INFERRED_IN_RULE" not in out:
        bad.append("inferred en precondicion no detectado: %s %s" % (rc, out))
    with open(dpath, "w") as f:
        f.write(d)
    o = open(onto).read()
    with open(onto, "w") as f:  # estado sin dueño
        f.write(o.replace("slug: { owner: contract-owned,", "slug: { owner: nadie,"))
    rc, out = cli(w, ["check-ontology", onto])
    if rc != 1 or "NO_OWNER" not in out:
        bad.append("estado sin dueno no detectado: %s %s" % (rc, out))
    with open(onto, "w") as f:
        f.write(o)
    with open(dpath, "w") as f:  # acción sin efectos
        f.write(d.replace("declared_effects: [git.commit, git.push, pr.open-draft]", "declared_effects: []"))
    rc, out = cli(w, ["check-ontology", onto])
    if rc != 1 or "NO_EFFECTS" not in out:
        bad.append("accion sin efectos no detectada: %s %s" % (rc, out))
    with open(dpath, "w") as f:
        f.write(d)
    good = w.contract()
    rc, out = cli(w, ["check-contract", good["_path"]])
    if rc != 0:
        bad.append("contrato valido rechazado: " + out)
    base = json.load(open(good["_path"]))
    pub_cap = {"id": "project.publish", "version": 1, "sha256": w.cap_sha("project.publish")}

    def variant(mutate, want, raw=None):
        c = json.loads(json.dumps(base))
        mutate(c)
        p = os.path.join(w.t, "v.json")
        with open(p, "w") as f:
            f.write(raw(c) if raw else canon(c))
        rc, out = cli(w, ["check-contract", p])
        if rc != 1 or want not in out:
            bad.append("%s no detectado: %s %s" % (want, rc, out))
    variant(lambda c: c.pop("scope"), "MISSING_FIELD:scope")
    variant(lambda c: c.update(expires_at="2026-11-20T00:00:00Z"), "LIFETIME_EXCEEDS_7D")
    variant(lambda c: None, "NOT_CANONICAL", raw=lambda c: json.dumps(c, indent=2))
    variant(lambda c: c.update(capability=pub_cap), "IRREVERSIBLE_NEEDS_MAX_USES_1")
    variant(lambda c: c.update(scope={"repo": [INSTALL], "branches": ["*"]}), "BAD_SCOPE:branches")
    c = json.loads(json.dumps(base))
    c.update(capability=pub_cap, max_uses=1)
    p = os.path.join(w.t, "irrev-ok.json")
    with open(p, "w") as f:
        f.write(canon(c))
    rc, out = cli(w, ["check-contract", p])
    if rc != 0:
        bad.append("irreversible con max_uses 1 rechazado: " + out)
    w.close()
    return bad


HARNESS = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                       "helpers", "se496-eep-harness.sh")


def ex_harness():
    """AC-5 (D04 en F0): la orden real es un marcador; revocar entre evaluate y recheck lo deja sin crear."""
    bad = []
    for revoke in (False, True):
        w = World()
        c = w.contract()
        req = os.path.join(w.t, "req.json")
        with open(req, "w") as f:
            json.dump(w.request(), f)
        mark = os.path.join(w.t, "marker")
        rev = os.path.join(w.home, ".savia", "delegations")
        hook = "mkdir -p %s && echo %s > %s/REVOKED" % (rev, c["nonce"], rev) if revoke else ""
        r = subprocess.run(["bash", HARNESS, req, mark, hook], capture_output=True, env=w.env())
        if revoke and (os.path.exists(mark) or r.returncode == 0):
            bad.append("revocado entre evaluar y ejecutar: marcador=%s rc=%s" % (os.path.exists(mark), r.returncode))
        if not revoke and (not os.path.exists(mark) or r.returncode != 0):
            bad.append("sin revocar el marcador debe crearse: rc=%s %s" % (r.returncode, r.stderr[-200:]))
        w.close()
    w = World()
    w.contract()
    req = os.path.join(w.t, "req.json")
    with open(req, "w") as f:
        json.dump(w.request(), f)
    mark = os.path.join(w.t, "marker")
    env = w.env()
    env["SE496_KERNEL"] = os.path.join(w.t, "no-existe.py")
    r = subprocess.run(["bash", HARNESS, req, mark], capture_output=True, env=env)
    if r.returncode == 0 or os.path.exists(mark):
        bad.append("kernel ausente: el EEP ejecuto (rc=%s)" % r.returncode)
    w.close()
    return bad


def ex_noenv():
    """Sin SAVIA_AUTHORITY_TEST=1 los overrides se ignoran: el mismo mundo que da ALLOW en modo de pruebas
    da NO_CONTRACT (el kernel usa su propio repo, no el redirigido)."""
    bad = []
    w = World()
    w.contract()
    rc, _ = w.ev(w.request())
    if rc != 0:
        bad.append("el mundo de control no da ALLOW")
    env = w.env()
    del env["SAVIA_AUTHORITY_TEST"]
    r = subprocess.run([sys.executable, "-I", KERNEL, "evaluate"], input=json.dumps(w.request()).encode(),
                       capture_output=True, env=env)
    out = json.loads(r.stdout) if r.stdout.strip() else {}
    if (r.returncode, out.get("reason")) != (1, "NO_CONTRACT"):
        bad.append("override honrado fuera del modo de pruebas: rc=%s %s" % (r.returncode, out.get("reason")))
    w.close()
    return bad


EXTRAS = {"ledger": ex_ledger, "digest": ex_digest, "nocache": ex_nocache, "audit": ex_audit, "exit": ex_exit,
          "signers-empty": ex_signers_empty, "validators": ex_validators,
          "harness": ex_harness, "noenv": ex_noenv}


def check(ids):
    """Cada caso: neg da el código esperado (y exit 1, 4 o 2) y su gemelo da ALLOW."""
    fails = []
    for cid in ids:
        if cid in MALFORMED:
            want_rc = MALFORMED[cid][0]
            rc, _ = run_case(cid, "neg")
            rc_t, _ = run_case(cid, "twin")
            if rc != want_rc or rc_t != 0:
                fails.append("%s: neg rc=%s twin rc=%s" % (cid, rc, rc_t))
            continue
        want = CASES[cid][0]
        rc, out = run_case(cid, "neg")
        rc_t, out_t = run_case(cid, "twin")
        if (rc, reason_of(out)) != (RC_FOR_NEG.get(cid, 1), want):
            fails.append("%s: neg dio rc=%s %s, esperado %s" % (cid, rc, reason_of(out), want))
        if (rc_t, reason_of(out_t)) != (0, "OK"):
            fails.append("%s: el gemelo positivo dio rc=%s %s" % (cid, rc_t, reason_of(out_t)))
    return fails


if __name__ == "__main__":
    fails = check(sys.argv[2:]) if sys.argv[1] == "check" else EXTRAS[sys.argv[2]]()
    print("\n".join(fails) if fails else "OK")
    sys.exit(1 if fails else 0)
