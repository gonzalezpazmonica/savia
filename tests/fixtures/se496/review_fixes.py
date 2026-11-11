#!/usr/bin/env python3
"""Regresiones de la revisión independiente de la PR #1528 (SE-496 F0).

  review_fixes.py <nombre>     imprime OK o la lista de fallos; exit 1 si falla algo
Cada caso tiene su control positivo en el mismo mundo, para que el test pueda fallar de verdad.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from denegaciones import INSTALL, NOW, REAL_KERNEL, World  # noqa: E402

TESTS = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(TESTS, "helpers"))


def reason(out):
    return (out or {}).get("reason")


def publish(w, files, changed=None, api=None, review="", tier=4):
    """project.publish sobre el PR 7 con la lista de ficheros indicada (tier_gate activo)."""
    pr = {"files": [{"path": f} for f in files], "reviewDecision": review}
    if changed is not None:
        pr["changedFiles"] = changed
    w.set_pr(7, **pr)
    if changed is None:
        p = os.path.join(w.fake, "pr-7.json")
        d = json.load(open(p))
        del d["changedFiles"]
        json.dump(d, open(p, "w"))
    if api is not None:
        with open(os.path.join(w.fake, "pr-7-api.txt"), "w") as f:
            f.write("".join(json.dumps(x) + "\n" for x in api))
    w.contract(cap="project.publish", declared_effects=["project.publish"], max_uses=1,
               scope={"repo": [INSTALL], "prs": [7], "projects": ["p"]}, authority={"level": "L3", "tier": tier})
    return w.ev(w.request(capability="project.publish",
                          action={"name": "project.publish", "params": {"project": "p"}},
                          target={"pr": 7, "project": "p"}))


# ---------------------------------------------------------------- P1-1: sin bypass por entorno
def fx_env_bypass():
    """El kernel real, invocado como programa, ignora SAVIA_AUTHORITY_* aunque venga TEST=1 y una
    ssh-keygen que siempre acepta. Control: el envoltorio de tests da ALLOW en el mismo mundo."""
    bad = []
    w = World()
    w.contract()
    rc, out = w.ev(w.request())
    if rc != 0:
        bad.append("control: el envoltorio de tests no da ALLOW (%s %s)" % (rc, reason(out)))
    env = w.env()
    env.update({"SAVIA_AUTHORITY_TEST": "1", "SAVIA_AUTHORITY_TOOL_SSH_KEYGEN": "/bin/true",
                "SAVIA_AUTHORITY_PROFILE": os.path.join(w.root, ".claude", "profiles", "active-user.md")})
    r = subprocess.run([sys.executable, "-I", REAL_KERNEL, "evaluate"], input=json.dumps(w.request()).encode(),
                       capture_output=True, env=env)
    o = json.loads(r.stdout) if r.stdout.strip() else {}
    if r.returncode == 0 or reason(o) != "NO_CONTRACT":
        bad.append("kernel real honra overrides del entorno: rc=%s %s" % (r.returncode, reason(o)))
    if o.get("evaluated_at") == NOW:
        bad.append("kernel real usa el reloj del entorno")
    w.close()
    return bad


# ---------------------------------------------------------------- P1-2: lista de ficheros completa
def fx_tier_files():
    bad = []
    docs = ["docs/d%03d.md" % i for i in range(100)]
    # control: un solo doc, lista completa -> ALLOW (tier 1, contrato tier 4)
    w = World()
    rc, out = publish(w, ["docs/x.md"], changed=1)
    if rc != 0:
        bad.append("control 1 fichero: %s %s" % (rc, reason(out)))
    w.close()
    # 101 ficheros: gh pr view corta en 100 docs; el 101 es un workflow -> la API paginada lo trae
    w = World()
    rc, out = publish(w, docs, changed=101, api=docs + [".github/workflows/x.yml"])
    if (rc, reason(out)) != (4, "REVIEW_REQUIRED"):
        bad.append("PR de 101 ficheros con workflow en el 101: %s %s (esperado 4 REVIEW_REQUIRED)" % (rc, reason(out)))
    calls = open(os.path.join(w.fake, "calls.log")).read()
    if "--paginate repos/acme/widgets/pulls/7/files" not in calls:
        bad.append("no se pidio la lista paginada: %s" % calls[-300:])
    w.close()
    # la API tampoco cuadra -> UNKNOWN_STATE
    w = World()
    rc, out = publish(w, docs, changed=101, api=docs)
    if (rc, reason(out)) != (1, "UNKNOWN_STATE"):
        bad.append("lista incompleta tras paginar: %s %s" % (rc, reason(out)))
    w.close()
    # sin changedFiles -> UNKNOWN_STATE
    w = World()
    rc, out = publish(w, ["docs/x.md"], changed=None)
    if (rc, reason(out)) != (1, "UNKNOWN_STATE"):
        bad.append("sin changedFiles: %s %s" % (rc, reason(out)))
    w.close()
    # ruta con espacios -> UNKNOWN_STATE (risk-tier.py trocea por espacios)
    w = World()
    rc, out = publish(w, ["docs/a b.md"], changed=1)
    if (rc, reason(out)) != (1, "UNKNOWN_STATE"):
        bad.append("ruta con espacios: %s %s" % (rc, reason(out)))
    w.close()
    return bad


# ---------------------------------------------------------------- P2-1: confianza en origin/main
def fx_level_from_main():
    """Subir la fila de tech-writer a L4 en el arbol de trabajo no cambia nada: manda origin/main."""
    bad = []
    w = World()
    p = os.path.join(w.root, "docs", "rules", "domain", "agent-permission-levels.md")
    txt = open(p, encoding="utf-8").read()
    if "| tech-writer | L2 |" not in txt:
        bad.append("fixture: fila tech-writer L2 no encontrada")
    open(p, "w", encoding="utf-8").write(txt.replace("| tech-writer | L2 |", "| tech-writer | L4 |"))
    w.contract(delegate="tech-writer", authority={"level": "L4", "tier": 2})
    rc, out = w.ev(w.request(delegate="tech-writer"))
    if (rc, reason(out)) != (1, "LEVEL_EXCEEDED"):
        bad.append("nivel editado en el arbol de trabajo honrado: %s %s" % (rc, reason(out)))
    w.commit_to_main("docs/rules/domain/agent-permission-levels.md",
                     txt.replace("| tech-writer | L2 |", "| tech-writer | L4 |"))
    rc, out = w.ev(w.request(delegate="tech-writer"))
    if rc != 0:  # control: el mismo cambio en origin/main si cuenta
        bad.append("control: nivel en origin/main ignorado: %s %s" % (rc, reason(out)))
    w.close()
    return bad


def fx_ontology_from_main():
    """Marcar Branch.name como inferred en el arbol de trabajo no altera la decision: manda origin/main."""
    bad = []
    w = World()
    w.contract()
    p = os.path.join(w.root, "contracts", "ontology", "savia-operational.yaml")
    txt = open(p, encoding="utf-8").read()
    tampered = txt.replace("name: { owner: source-backed, reader: git }", "name: { owner: inferred, reader: git }", 1)
    if tampered == txt:
        bad.append("fixture: atributo Branch.name no encontrado")
    open(p, "w", encoding="utf-8").write(tampered)
    rc, out = w.ev(w.request())
    if rc != 0:
        bad.append("ontologia del arbol de trabajo honrada: %s %s" % (rc, reason(out)))
    w.commit_to_main("contracts/ontology/savia-operational.yaml", tampered)
    rc, out = w.ev(w.request())
    if (rc, reason(out)) != (1, "UNKNOWN_STATE"):  # control: en origin/main si manda
        bad.append("control: ontologia de origin/main ignorada: %s %s" % (rc, reason(out)))
    w.close()
    return bad


# ---------------------------------------------------------------- P2-3 / corr. 4: CI y repo coherentes
def fx_ci_head():
    bad = []
    w = World()
    w.contract()
    rc, out = w.ev(w.request())
    sha_ = subprocess.run(["git", "-C", w.root, "rev-parse", "refs/heads/agent/work"],
                          capture_output=True).stdout.decode().strip()
    calls = open(os.path.join(w.fake, "calls.log")).read()
    if rc != 0:
        bad.append("control: %s %s" % (rc, reason(out)))
    if "--commit %s" % sha_ not in calls or "--limit 1 " in calls:
        bad.append("gh run list no filtra por el head exacto: %s" % calls.strip()[-200:])
    w.close()
    # una de varias ejecuciones del head en rojo -> no cumple (antes solo contaba la ultima)
    w = World()
    w.set_runs([{"status": "COMPLETED", "conclusion": "SUCCESS"}, {"status": "COMPLETED", "conclusion": "FAILURE"}])
    w.contract()
    rc, out = w.ev(w.request())
    if (rc, reason(out)) != (1, "PRECONDITION_FAILED:ci_not_red"):
        bad.append("un workflow en rojo ignorado: %s %s" % (rc, reason(out)))
    w.close()
    return bad


def fx_branch_other_repo():
    """Hechos de Branch se leen del git local: con target.repo distinto del remoto local -> UNKNOWN_STATE."""
    bad = []
    other = "github.com/acme/otro"
    for repo, want in ((INSTALL, (0, "OK")), (other, (1, "UNKNOWN_STATE"))):
        w = World()
        w.contract(scope={"repo": [INSTALL, other], "branches": ["agent/*"]})
        rc, out = w.ev(w.request(target={"branch": "agent/work", "repo": repo}))
        if (rc, reason(out)) != want:
            bad.append("target.repo=%s: %s %s (esperado %s)" % (repo, rc, reason(out), want))
        w.close()
    return bad


# ---------------------------------------------------------------- P2-4: recibo con plazo
def fx_prior_age():
    bad = []
    for label, ts, want in (("9 min", "2026-11-12T09:51:00Z", (0, "OK")),
                            ("10 min (limite)", "2026-11-12T09:50:00Z", (0, "OK")),
                            ("10 min 1 s", "2026-11-12T09:49:59Z", (1, "STATE_CHANGED")),
                            ("futuro", "2026-11-12T10:00:01Z", (1, "STATE_CHANGED")),
                            ("sin fecha", None, (1, "STATE_CHANGED"))):
        w = World()
        w.contract()
        rc, out = w.ev(w.request())
        out["evaluated_at"] = ts
        rc2, out2 = w.ev(w.request(), "recheck", w.receipt(out))
        if (rc2, reason(out2)) != want:
            bad.append("recibo %s: %s %s (esperado %s)" % (label, rc2, reason(out2), want))
        w.close()
    return bad


# ---------------------------------------------------------------- corr. P2-3: pr.merge
def fx_merge_preconditions():
    bad = []
    cases = (("borrador", {"isDraft": True}, "PRECONDITION_FAILED:not_draft"),
             ("CI roja", {"isDraft": False, "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "FAILURE"}]},
              "PRECONDITION_FAILED:ci_green"),
             ("sin checks", {"isDraft": False, "statusCheckRollup": []}, "PRECONDITION_FAILED:ci_green"),
             # control: pasa las precondiciones y para en el nivel (yema es L3; merge exige L4)
             ("listo", {"isDraft": False}, "LEVEL_EXCEEDED"))
    for label, pr, want in cases:
        w = World()
        w.set_pr(7, **pr)
        w.contract(cap="pr.merge", declared_effects=["pr.merge"], scope={"repo": [INSTALL], "prs": [7]},
                   authority={"level": "L4", "tier": 4}, max_uses=1)
        rc, out = w.ev(w.request(capability="pr.merge", action={"name": "pr.merge", "params": {"pr_number": 7}},
                                 target={"pr": 7}))
        if (rc, reason(out)) != (1, want):
            bad.append("pr.merge %s: %s %s (esperado %s)" % (label, rc, reason(out), want))
        w.close()
    return bad


# ---------------------------------------------------------------- P2-5 / corr. 2: mutación honesta
def fx_mutation_crash():
    import se496_mutation as m
    bad = []
    if m.verdict("D01", ("EXC", "TypeError")) != "CRASHED":
        bad.append("una excepcion cuenta como KILLED")
    if m.verdict("D01", (1, "NO_CONTRACT")) != "SURVIVED":
        bad.append("mismo motivo no cuenta como SURVIVED")
    if m.verdict("D01", (1, "UNKNOWN_STATE")) != "KILLED":
        bad.append("motivo distinto sin excepcion no cuenta como KILLED")
    return bad


# ---------------------------------------------------------------- seg. ronda 2, P1-1: params atados al objetivo
def _case(bad, label, got, want):
    if got != want:
        bad.append("%s: %s %s (esperado %s %s)" % (label, got[0], got[1], want[0], want[1]))


INPROC = False  # se496_mutation.py lo activa para que un parche en proceso afecte al kernel


def _ev(contract, req, pr=None, tweak=None):
    w = World(inproc=INPROC)
    if tweak:
        tweak(w)
    if pr is not None:
        w.set_pr(7, **pr)
    w.contract(**contract)
    rc, out = w.ev(w.request(**req))
    w.close()
    return rc, reason(out)


def _draft(params, target=None, name="pr.create-draft"):
    return {"action": {"name": name, "params": params}, "target": target or {"branch": "agent/work"}}


def _pub_req(proj, target):
    return {"capability": "project.publish",
            "action": {"name": "project.publish", "params": {"project": proj}}, "target": target}


def _merge_req(n):
    return {"capability": "pr.merge", "action": {"name": "pr.merge", "params": {"pr_number": n}}, "target": {"pr": 7}}


def _vault_req(path, tpath):
    return {"capability": "vault.note-write", "action": {"name": "vault.note-write", "params": {"path": path}},
            "target": {"branch": "agent/work", "path": tpath}}


def fx_params_scope():
    """El ambito se firma sobre el objetivo y lo que se ejecuta son los parametros: tienen que coincidir.
    Cada denegacion nueva tiene su control en el mismo mundo, que da ALLOW (o pasa el paso 10)."""
    bad = []
    ok = {"branch": "agent/work", "title": "x"}
    _case(bad, "draft control", _ev({}, _draft(ok)), (0, "OK"))
    _case(bad, "draft params.branch=main", _ev({}, _draft({"branch": "main", "title": "x"})), (1, "OUT_OF_SCOPE"))
    _case(bad, "draft params.branch sin target.branch", _ev({}, _draft(ok, {"repo": INSTALL})), (1, "OUT_OF_SCOPE"))
    _case(bad, "draft parametro no declarado", _ev({}, _draft(dict(ok, base="main"))), (1, "OUT_OF_SCOPE"))
    _case(bad, "draft falta parametro obligatorio", _ev({}, _draft({"branch": "agent/work"})), (1, "OUT_OF_SCOPE"))
    _case(bad, "action.name de otra capacidad", _ev({}, _draft(ok, name="pr.merge")), (1, "CAPABILITY_MISMATCH"))
    _case(bad, "ambito con projects y objetivo sin project",
          _ev({"scope": {"repo": [INSTALL], "branches": ["agent/*"], "projects": ["projects/alpha"]}}, _draft(ok)),
          (1, "OUT_OF_SCOPE"))

    pub = dict(cap="project.publish", declared_effects=["project.publish"], max_uses=1,
               scope={"repo": [INSTALL], "prs": [7], "projects": ["p"]})
    _case(bad, "publish control", _ev(pub, _pub_req("p", {"pr": 7, "project": "p"}), pr={}), (0, "OK"))
    _case(bad, "publish params.project=otro", _ev(pub, _pub_req("otro", {"pr": 7, "project": "p"}), pr={}),
          (1, "OUT_OF_SCOPE"))
    _case(bad, "publish sin target.project", _ev(pub, _pub_req("p", {"pr": 7}), pr={}), (1, "OUT_OF_SCOPE"))

    merge = dict(cap="pr.merge", declared_effects=["pr.merge"], scope={"repo": [INSTALL], "prs": [7]},
                 authority={"level": "L4", "tier": 4}, max_uses=1)
    # control: pasa el paso 10 y para en el nivel (yema es L3; merge exige L4)
    _case(bad, "merge control", _ev(merge, _merge_req(7), pr={"isDraft": False}), (1, "LEVEL_EXCEEDED"))
    _case(bad, "merge pr_number=8", _ev(merge, _merge_req(8), pr={"isDraft": False}), (1, "OUT_OF_SCOPE"))
    _case(bad, "merge pr_number texto", _ev(merge, _merge_req("7"), pr={"isDraft": False}), (1, "OUT_OF_SCOPE"))

    effects = ["vault.write", "git" + ".commit"]
    vault = dict(cap="vault.note-write", declared_effects=effects,
                 scope={"repo": [INSTALL], "branches": ["agent/*"], "paths": ["notas"]})
    _case(bad, "vault control", _ev(vault, _vault_req("notas/n.md", "notas/n.md")), (0, "OK"))
    _case(bad, "vault ruta fuera de paths", _ev(vault, _vault_req("otras/n.md", "otras/n.md")), (1, "OUT_OF_SCOPE"))
    _case(bad, "vault prefijo enganoso", _ev(vault, _vault_req("notas-x/n.md", "notas-x/n.md")), (1, "OUT_OF_SCOPE"))
    _case(bad, "vault segmento ..", _ev(vault, _vault_req("notas/../x.md", "notas/../x.md")), (1, "OUT_OF_SCOPE"))
    _case(bad, "vault params.path distinto", _ev(vault, _vault_req("otras/n.md", "notas/n.md")), (1, "OUT_OF_SCOPE"))
    no_paths = dict(vault, scope={"repo": [INSTALL], "branches": ["agent/*"]})
    _case(bad, "vault contrato sin paths", _ev(no_paths, _vault_req("notas/n.md", "notas/n.md")), (1, "OUT_OF_SCOPE"))
    return bad


# ---------------------------------------------------------------- seg. ronda 2, P2-2: todo saltado no es verde
def fx_ci_skipped():
    bad = []
    merge = dict(cap="pr.merge", declared_effects=["pr.merge"], scope={"repo": [INSTALL], "prs": [7]},
                 authority={"level": "L4", "tier": 4}, max_uses=1)
    skipped = {"status": "COMPLETED", "conclusion": "SKIPPED"}
    neutral = {"status": "COMPLETED", "conclusion": "NEUTRAL"}
    green = {"status": "COMPLETED", "conclusion": "SUCCESS"}
    _case(bad, "merge solo saltados", _ev(merge, _merge_req(7), pr={"isDraft": False, "statusCheckRollup": [skipped]}),
          (1, "PRECONDITION_FAILED:ci_green"))
    _case(bad, "merge saltados y neutros",
          _ev(merge, _merge_req(7), pr={"isDraft": False, "statusCheckRollup": [skipped, neutral]}),
          (1, "PRECONDITION_FAILED:ci_green"))
    # control: un SUCCESS real junto a un saltado cumple ci_green y para en el nivel
    _case(bad, "merge success + saltado",
          _ev(merge, _merge_req(7), pr={"isDraft": False, "statusCheckRollup": [green, skipped]}),
          (1, "LEVEL_EXCEEDED"))
    return bad


# ---------------------------------------------------------------- corr. ronda 2: run list truncado
def fx_runs_limit():
    bad = []
    for n, want in ((199, (0, "OK")), (200, (1, "UNKNOWN_STATE"))):
        w = World()
        w.set_runs([{"status": "COMPLETED", "conclusion": "SUCCESS"}] * n)
        w.contract()
        rc, out = w.ev(w.request())
        _case(bad, "%d ejecuciones del head" % n, (rc, reason(out)), want)
        w.close()
    return bad


# ---------------------------------------------------------------- seg. ronda 3, P1-1: vida y un solo uso en evaluate
def _drop_reversibility(w):
    """Descriptor de vault.note-write sin `reversibility` (antes de firmar: el contrato fija su sha)."""
    p = os.path.join(w.root, "contracts", "capabilities", "vault.note-write.yaml")
    with open(p) as f:
        lines = [x for x in f if "reversibility:" not in x]
    with open(p, "w") as f:
        f.write("".join(lines))


def fx_contract_invariants():
    """evaluate aplica las invariantes del contrato que antes solo miraba check-contract: vida maxima
    de 7 dias y max_uses 1 para capacidades no reversibles. Cada denegacion con su control."""
    bad = []
    ok = {"branch": "agent/work", "title": "x"}
    nb = "2026-11-10T00:00:00Z"
    _case(bad, "vida 7 dias exactos", _ev({"not_before": nb, "expires_at": "2026-11-17T00:00:00Z"}, _draft(ok)),
          (0, "OK"))
    _case(bad, "vida 7 dias y 1 s", _ev({"not_before": nb, "expires_at": "2026-11-17T00:00:01Z"}, _draft(ok)),
          (1, "LIFETIME_EXCEEDS_7D"))
    _case(bad, "vida de un ano", _ev({"not_before": nb, "expires_at": "2027-11-10T00:00:00Z"}, _draft(ok)),
          (1, "LIFETIME_EXCEEDS_7D"))

    pub = dict(cap="project.publish", declared_effects=["project.publish"],
               scope={"repo": [INSTALL], "prs": [7], "projects": ["p"]})
    req = _pub_req("p", {"pr": 7, "project": "p"})
    _case(bad, "publish max_uses 1", _ev(dict(pub, max_uses=1), req, pr={}), (0, "OK"))
    _case(bad, "publish sin max_uses", _ev(pub, req, pr={}), (1, "IRREVERSIBLE_NEEDS_MAX_USES_1"))
    _case(bad, "publish max_uses 2", _ev(dict(pub, max_uses=2), req, pr={}), (1, "IRREVERSIBLE_NEEDS_MAX_USES_1"))
    merge = dict(cap="pr.merge", declared_effects=["pr.merge"], scope={"repo": [INSTALL], "prs": [7]},
                 authority={"level": "L4", "tier": 4})
    _case(bad, "merge sin max_uses", _ev(merge, _merge_req(7), pr={"isDraft": False}),
          (1, "IRREVERSIBLE_NEEDS_MAX_USES_1"))
    # control: con max_uses 1 pasa el paso 7 y para en el nivel (yema es L3; merge exige L4)
    _case(bad, "merge max_uses 1", _ev(dict(merge, max_uses=1), _merge_req(7), pr={"isDraft": False}),
          (1, "LEVEL_EXCEEDED"))

    vault = dict(cap="vault.note-write", declared_effects=["vault.write", "git" + ".commit"],
                 scope={"repo": [INSTALL], "branches": ["agent/*"], "paths": ["notas"]})
    vreq = _vault_req("notas/n.md", "notas/n.md")
    _case(bad, "vault reversible sin max_uses", _ev(vault, vreq), (0, "OK"))
    # fail-closed: un descriptor sin reversibility declarada cuenta como irreversible
    _case(bad, "vault sin reversibility", _ev(vault, vreq, tweak=_drop_reversibility),
          (1, "IRREVERSIBLE_NEEDS_MAX_USES_1"))
    _case(bad, "vault sin reversibility y max_uses 1",
          _ev(dict(vault, max_uses=1), vreq, tweak=_drop_reversibility), (0, "OK"))
    return bad


# ---------------------------------------------------------------- ronda 3, P2: tipos de params y nivel por familia
def _as(delegate):
    w = World(inproc=INPROC)
    w.contract(delegate=delegate)
    rc, out = w.ev(w.request(delegate=delegate))
    w.close()
    return rc, reason(out)


def fx_params_types_level():
    bad = []
    ok = {"branch": "agent/work", "title": "x"}
    _case(bad, "title texto (control)", _ev({}, _draft(ok)), (0, "OK"))
    _case(bad, "title entero", _ev({}, _draft(dict(ok, title=5))), (1, "OUT_OF_SCOPE"))
    _case(bad, "title booleano", _ev({}, _draft(dict(ok, title=True))), (1, "OUT_OF_SCOPE"))
    _case(bad, "title nulo", _ev({}, _draft(dict(ok, title=None))), (1, "OUT_OF_SCOPE"))
    # nivel: solo savia-worker:<id> hereda el de su familia; yema:<x> o codex:<x> no
    _case(bad, "savia-worker:fix-1 hereda L3", _as("savia-worker:fix-1"), (0, "OK"))
    _case(bad, "yema exacto (control)", _as("yema"), (0, "OK"))
    _case(bad, "yema:x no hereda", _as("yema:x"), (1, "UNKNOWN_STATE"))
    _case(bad, "codex:x no hereda", _as("codex:x"), (1, "UNKNOWN_STATE"))
    _case(bad, "savia-worker: sin id", _as("savia-worker:"), (1, "UNKNOWN_STATE"))
    return bad


# ---------------------------------------------------------------- ronda 4 (codex P1-1, P1-2, P2; seg. P1-1, P2-4)
L4_DELEGATE = "commit-guardian"  # L4 en agent-permission-levels.md: pr.merge exige L4


def _merge_world(pr, branches=True, extra_pre=None, drop=None):
    """pr.merge del PR 7 con un delegado L4 y contrato tier 2 (el PR de docs es tier 1)."""
    w = World(inproc=INPROC)
    w.set_pr(7, **pr)
    if drop:
        p = os.path.join(w.fake, "pr-7.json")
        d = json.load(open(p))
        del d[drop]
        json.dump(d, open(p, "w"))
    scope = {"repo": [INSTALL], "prs": [7]}
    target = {"pr": 7}
    if branches:
        scope["branches"] = ["agent/*"]
        target["branch"] = "agent/work"
    over = {"cap": "pr.merge", "delegate": L4_DELEGATE, "declared_effects": ["pr.merge"], "scope": scope,
            "authority": {"level": "L4", "tier": 2}, "max_uses": 1}
    if extra_pre:
        over["preconditions"] = extra_pre
    w.contract(**over)
    rc, out = w.ev(w.request(delegate=L4_DELEGATE, capability="pr.merge",
                             action={"name": "pr.merge", "params": {"pr_number": 7}}, target=target))
    w.close()
    return rc, reason(out)


def fx_pr_branch():
    """target.branch lo declara quien pide: tiene que ser la rama real del PR (headRefName)."""
    bad = []
    _case(bad, "PR de agent/work (control)", _merge_world({"isDraft": False}), (0, "OK"))
    _case(bad, "PR de feature/unapproved con target.branch=agent/work",
          _merge_world({"isDraft": False, "headRefName": "feature/unapproved"}), (1, "OUT_OF_SCOPE"))
    _case(bad, "PR sin headRefName", _merge_world({"isDraft": False}, drop="headRefName"), (1, "UNKNOWN_STATE"))
    _case(bad, "ambito sin ramas, objetivo sin rama (control)",
          _merge_world({"isDraft": False, "headRefName": "feature/x"}, branches=False), (0, "OK"))
    return bad


def fx_pr_branch_sha():
    """Con PR en el objetivo y una accion que publica la rama local, avanzar esa rama entre evaluate y
    recheck tiene que dar STATE_CHANGED (antes solo contaba el head del PR)."""
    bad = []
    for move, want in ((False, (0, "OK")), (True, (1, "STATE_CHANGED"))):
        w = World()
        w.contract(scope={"repo": [INSTALL], "branches": ["agent/*"], "prs": [7]})
        req = w.request(target={"branch": "agent/work", "pr": 7})
        w.set_runs([])
        rc, out = w.ev(req)
        if rc != 0:
            bad.append("evaluate: %s %s" % (rc, reason(out)))
            w.close()
            continue
        if move:
            sh_ = ["git", "-C", w.root]
            tree = subprocess.run(sh_ + ["rev-parse", "agent/work^{tree}"], capture_output=True).stdout.decode().strip()
            new = subprocess.run(sh_ + ["commit-tree", tree, "-p", "agent/work", "-m", "B"],
                                 capture_output=True).stdout.decode().strip()
            subprocess.run(sh_ + ["update-ref", "refs/heads/agent/work", new], check=True)
        rc2, out2 = w.ev(req, "recheck", w.receipt(out))
        _case(bad, "recheck con rama %s" % ("avanzada" if move else "quieta"), (rc2, reason(out2)), want)
        w.close()
    return bad


def fx_absent_typed_facts():
    """Un hecho ausente no cumple una precondicion negativa (UNKNOWN_STATE) y los tipos no se mezclan."""
    bad = []
    pre = [{"id": "review", "fact": "PullRequest.review_decision", "op": "!=", "value": "CHANGES_REQUESTED"}]
    _case(bad, "reviewDecision vacio (control)", _merge_world({"isDraft": False}, extra_pre=pre), (0, "OK"))
    _case(bad, "reviewDecision CHANGES_REQUESTED",
          _merge_world({"isDraft": False, "reviewDecision": "CHANGES_REQUESTED"}, extra_pre=pre),
          (1, "PRECONDITION_FAILED:review"))
    _case(bad, "sin reviewDecision", _merge_world({"isDraft": False}, extra_pre=pre, drop="reviewDecision"),
          (1, "UNKNOWN_STATE"))
    _case(bad, "isDraft 0 no es false", _merge_world({"isDraft": 0}), (1, "PRECONDITION_FAILED:not_draft"))
    _case(bad, "sin isDraft", _merge_world({"isDraft": False}, drop="isDraft"), (1, "UNKNOWN_STATE"))
    return bad


PROBE = r"""
import json, os, pwd, sys
sys.path.insert(0, sys.argv[1])
import authority_kernel as k
real = pwd.getpwuid(os.getuid()).pw_dir
seen = {}
k.subprocess.run = lambda argv, **kw: seen.setdefault("env", kw.get("env"))
k.run(["true"])
out = {"home": k.home(), "real": real, "run_home": seen["env"].get("HOME")}
k.OVERRIDES["_"] = "1"
out["test_home"] = k.home()
print(json.dumps(out))
"""


def fx_home_real():
    """Fuera de test_mode el home sale de la base de usuarios, no de $HOME (ledger, REVOKED, audit, git/gh)."""
    bad = []
    import tempfile
    fake = tempfile.mkdtemp(prefix="se496-home-")
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": fake}
    r = subprocess.run([sys.executable, "-I", "-c", PROBE, os.path.dirname(REAL_KERNEL)],
                       capture_output=True, env=env)
    os.rmdir(fake)
    try:
        o = json.loads(r.stdout)
    except ValueError:
        return ["sonda sin salida: %s" % r.stderr.decode(errors="replace")[-300:]]
    if o["real"] == fake:
        return ["entorno de prueba invalido: el home real coincide con el temporal"]
    if o["home"] != o["real"]:
        bad.append("home() sigue $HOME: %s" % o["home"])
    if o["run_home"] != o["real"]:
        bad.append("run() pasa a git/gh el HOME del llamante: %s" % o["run_home"])
    if o["test_home"] != fake:
        bad.append("control: en test_mode home() no usa el HOME temporal del arnes (%s)" % o["test_home"])
    src = open(REAL_KERNEL, encoding="utf-8").read().splitlines()
    uses = [i for i, l in enumerate(src) if "expanduser" in l]
    if len(uses) != 1 or "if test_mode()" not in src[uses[0] - 1]:
        bad.append("expanduser fuera de la rama test_mode: lineas %s" % [i + 1 for i in uses])
    return bad


def fx_error_audited():
    """Un contrato firmado mal formado que revienta la evaluacion sale sin decision (exit 2) pero deja
    linea ERROR en el audit; un DENY normal sigue auditado como DENY (control)."""
    bad = []
    for label, over, want_rc, want_dec in (
            ("precondicion con fact no textual", {"preconditions": [{"id": "x", "fact": ["Branch.name"]}]}, 2, "ERROR"),
            ("control rama fuera", {"scope": {"repo": [INSTALL], "branches": ["feature/*"]}}, 1, "DENY")):
        w = World()
        w.contract(**over)
        rc, _ = w.ev(w.request())
        path = os.path.join(w.home, ".savia", "authority", "audit.jsonl")
        lines = open(path).read().splitlines() if os.path.exists(path) else []
        dec = json.loads(lines[-1]).get("decision") if lines else None
        if (rc, dec) != (want_rc, want_dec):
            bad.append("%s: rc=%s audit=%s (esperado %s %s)" % (label, rc, dec, want_rc, want_dec))
        w.close()
    return bad


FIXES = {"env-bypass": fx_env_bypass, "tier-files": fx_tier_files, "level-main": fx_level_from_main,
         "ontology-main": fx_ontology_from_main, "ci-head": fx_ci_head, "branch-repo": fx_branch_other_repo,
         "prior-age": fx_prior_age, "merge-pre": fx_merge_preconditions, "mutation-crash": fx_mutation_crash,
         "params-scope": fx_params_scope, "ci-skipped": fx_ci_skipped, "runs-limit": fx_runs_limit,
         "contract-invariants": fx_contract_invariants, "params-types-level": fx_params_types_level,
         "pr-branch": fx_pr_branch, "pr-branch-sha": fx_pr_branch_sha, "absent-typed-facts": fx_absent_typed_facts,
         "home-real": fx_home_real, "error-audited": fx_error_audited}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in FIXES:
        print("uso: review_fixes.py " + "|".join(FIXES))
        sys.exit(2)
    fails = FIXES[sys.argv[1]]()
    print("\n".join(fails) if fails else "OK")
    sys.exit(1 if fails else 0)
