#!/usr/bin/env python3
"""Batería SE-496 (R5): 15 denegaciones + casos técnicos, cada una con su gemelo positivo.

Construye un mundo hermético en un directorio temporal (repo git con origin/main propio, dos
operadores ficticios con claves ed25519 generadas aquí, `gh` falso, HOME temporal). No lee el
perfil real ni ~/.savia real (AC-9).

  denegaciones.py list
  denegaciones.py run <caso> neg|twin        -> RC=<exit> REASON=<codigo> SUGG=<n>
Como módulo lo usa tests/helpers/se496_mutation.py (modo en proceso, con pasos parcheados).
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
REAL_KERNEL = os.path.join(REPO, "scripts", "lib", "authority_kernel.py")
# El kernel no admite overrides por entorno: los tests lo invocan por un envoltorio que solo vive en tests/.
KERNEL = os.path.join(REPO, "tests", "helpers", "se496_kernel_entry.py")
INSTALL = "github.com/acme/widgets"
NOW = "2026-11-12T10:00:00Z"
CAPS = ("pr.create-draft", "pr.merge", "project.publish", "vault.note-write")

FAKE_GH = """#!/usr/bin/env bash
d="$SE496_FAKE_DIR"
printf '%s\n' "$*" >>"$d/calls.log"
case "$1 $2" in
  "run list") cat "$d/runs.json" ;;
  "pr view") cat "$d/pr-$3.json" ;;
  "api --hostname") n="${5#*/pulls/}"; cat "$d/pr-${n%/files}-api.txt" ;;
  *) exit 1 ;;
esac
"""


def sha_file(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def canon(o):
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sh(*a, cwd=None, **kw):
    return subprocess.run(a, cwd=cwd, check=True, capture_output=True, **kw)


class World:
    def __init__(self, inproc=False):
        self.inproc = inproc
        self.t = tempfile.mkdtemp(prefix="se496-")
        self.home = os.path.join(self.t, "home")
        self.root = os.path.join(self.t, "repo")
        self.keys = os.path.join(self.t, "keys")
        self.fake = os.path.join(self.t, "fake")
        self.bin = os.path.join(self.t, "bin")
        for d in (self.home, self.root, self.keys, self.fake, self.bin):
            os.makedirs(d)
        self.n = 0
        self.env_extra = {}
        gh = os.path.join(self.bin, "gh")
        with open(gh, "w") as f:
            f.write(FAKE_GH)
        os.chmod(gh, 0o755)
        self.set_runs([{"status": "COMPLETED", "conclusion": "SUCCESS"}])
        self.set_pr(7)
        for k in ("op-a", "op-b", "op-c"):
            sh("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", k, "-f", os.path.join(self.keys, k))
        self._init_repo()

    # ---- repo
    def _git(self, *a):
        return sh("git", "-C", self.root, *a)

    def _init_repo(self):
        for rel in ("contracts", os.path.join("docs", "rules", "domain", "agent-permission-levels.md")):
            src = os.path.join(REPO, rel)
            dst = os.path.join(self.root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copytree(src, dst) if os.path.isdir(src) else shutil.copy(src, dst)
        os.makedirs(os.path.join(self.root, "config", "delegations"))
        os.makedirs(os.path.join(self.root, ".claude", "profiles"))
        self.set_profile("op-a")
        lines = []
        for slug in ("op-a", "op-b"):
            pub = open(os.path.join(self.keys, slug + ".pub")).read().split()
            lines.append('%s namespaces="savia-delegation" %s %s' % (slug, pub[0], pub[1]))
        self.write_signers(lines)
        self._git("init", "-q", "-b", "main")
        self._git("config", "user.email", "t@example.invalid")
        self._git("config", "user.name", "t")
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "base")
        self._git("update-ref", "refs/remotes/origin/main", "HEAD")
        self._git("remote", "add", "origin", "https://%s.git" % INSTALL)
        for b in ("agent/work", "feature/x"):
            self._git("branch", b)

    def write_signers(self, lines):
        p = os.path.join(self.root, "config", "operator-grant-" + "signers")
        with open(p, "w") as f:
            f.write("\n".join(lines) + "\n")

    def set_profile(self, slug):
        with open(os.path.join(self.root, ".claude", "profiles", "active-user.md"), "w") as f:
            f.write('active_slug: "%s"\n' % slug)

    def commit_to_main(self, relpath, text):
        p = os.path.join(self.root, relpath)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text)
        self._git("add", "-A")
        self._git("commit", "-q", "-m", "x")
        self._git("update-ref", "refs/remotes/origin/main", "HEAD")

    # ---- fakes
    def set_runs(self, runs):
        json.dump(runs, open(os.path.join(self.fake, "runs.json"), "w"))

    def set_pr(self, n, **over):
        pr = {"isDraft": True, "headRefName": "agent/work", "headRefOid": "a" * 40, "reviewDecision": "",
              "state": "OPEN", "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS"}],
              "files": [{"path": "docs/x.md"}]}
        pr.update(over)
        pr.setdefault("changedFiles", len(pr["files"]))
        json.dump(pr, open(os.path.join(self.fake, "pr-%d.json" % n), "w"))

    # ---- contratos
    def cap_sha(self, cap="pr.create-draft"):
        return sha_file(os.path.join(self.root, "contracts", "capabilities", cap + ".yaml"))

    def contract(self, signer="op-a", sign=True, ns="savia-delegation", where="repo", **over):
        self.n += 1
        cap = over.pop("cap", "pr.create-draft")
        c = {"schema": "delegation-contract/1", "id": "c-%d" % self.n, "nonce": "%016x" % (0xABC000 + self.n),
             "principal": signer, "delegate": "yema",
             "capability": {"id": cap, "version": 1, "sha256": self.cap_sha(cap)},
             "authority": {"level": "L3", "tier": 2},
             "scope": {"repo": [INSTALL], "branches": ["agent/*"]},
             "preconditions": [], "declared_effects": ["git.commit", "git.push", "pr.open-draft"],
             "not_before": "2026-11-10T00:00:00Z", "expires_at": "2026-11-14T00:00:00Z",
             "installation": INSTALL}
        c.update(over)
        base = os.path.join(self.root, "config", "delegations") if where == "repo" \
            else os.path.join(self.home, ".savia", "delegations")
        os.makedirs(base, exist_ok=True)
        path = os.path.join(base, c["id"] + ".json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(canon(c))
        if sign:
            sh("ssh-keygen", "-q", "-Y", "sign", "-f", os.path.join(self.keys, signer if signer.startswith("op-") else "op-a"),
               "-n", ns, path)
        c["_path"] = path
        return c

    def request(self, **over):
        r = {"delegate": "yema", "capability": "pr.create-draft",
             "action": {"name": "pr.create-draft", "params": {"branch": "agent/work", "title": "x"}},
             "target": {"branch": "agent/work"}}
        r.update(over)
        return r

    # ---- ejecución
    def env(self):
        e = dict(os.environ)
        e.update({"SAVIA_AUTHORITY_TEST": "1", "SAVIA_AUTHORITY_ROOT": self.root, "HOME": self.home,
                  "SAVIA_AUTHORITY_NOW": NOW, "SAVIA_AUTHORITY_TOOL_GH": os.path.join(self.bin, "gh"),
                  "SE496_FAKE_DIR": self.fake, "SE496_KERNEL": KERNEL})
        e.update(self.env_extra)
        return e

    def ev(self, req, cmd="evaluate", prior=None):
        """-> (rc, dict|None). rc 2 = sin decisión."""
        text = req if isinstance(req, str) else json.dumps(req)
        args = [cmd] + (["--prior", prior] if prior else [])
        if self.inproc:
            sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
            import authority_kernel as k
            sys.path.insert(0, os.path.join(REPO, "tests", "helpers"))
            from se496_kernel_entry import overrides_from
            saved = dict(os.environ)
            os.environ.update(self.env())
            k.OVERRIDES.clear()
            k.OVERRIDES.update(overrides_from(os.environ))
            try:
                rc, out = k.main(args, text)
            finally:
                k.OVERRIDES.clear()
                os.environ.clear()
                os.environ.update(saved)
            return rc, (json.loads(out) if out else None)
        r = subprocess.run([sys.executable, "-I", KERNEL] + args, input=text.encode(), capture_output=True,
                           env=self.env())
        return r.returncode, (json.loads(r.stdout) if r.stdout.strip() else None)

    def receipt(self, out):
        p = os.path.join(self.t, "receipt-%d.json" % self.n)
        self.n += 1
        json.dump(out, open(p, "w"))
        return p

    def close(self):
        shutil.rmtree(self.t, ignore_errors=True)


# ============================================================================ casos
# Cada caso: fn(w, variant) -> (rc, dict|None). variant "neg" rompe UN dato; "twin" lo deja bien.
def basic(w, v, tweak=None, contract_over=None, req_over=None, cap="pr.create-draft"):
    over = dict(contract_over or {})
    if tweak:
        tweak(w)
    w.contract(cap=cap, **over)
    return w.ev(w.request(**(req_over or {})))


def d01(w, v):
    if v == "twin":
        w.contract()
    return w.ev(w.request())


def d02(w, v):
    c = w.contract()
    if v == "neg":
        w.commit_to_main("config/delegations/REVOKED", c["nonce"] + "\n")
    return w.ev(w.request())


def d03(w, v):
    c = w.contract()
    if v == "neg":
        os.makedirs(os.path.join(w.home, ".savia", "delegations"), exist_ok=True)
        open(os.path.join(w.home, ".savia", "delegations", "REVOKED"), "w").write("# local\n%s\n" % c["nonce"])
    return w.ev(w.request())


def d04(w, v):  # revocación entre evaluar y ejecutar (arnés de F0)
    c = w.contract()
    rc, out = w.ev(w.request())
    assert rc == 0, (rc, out)
    if v == "neg":
        os.makedirs(os.path.join(w.home, ".savia", "delegations"), exist_ok=True)
        open(os.path.join(w.home, ".savia", "delegations", "REVOKED"), "w").write(c["nonce"] + "\n")
    return w.ev(w.request(), "recheck", w.receipt(out))


def d05(w, v):
    w.contract(expires_at="2026-11-12T09:00:00Z" if v == "neg" else "2026-11-14T00:00:00Z")
    return w.ev(w.request())


def d05b(w, v):  # límite: now == expires_at
    w.contract(expires_at=NOW if v == "neg" else "2026-11-12T10:00:01Z")
    return w.ev(w.request())


def d05c(w, v):
    w.contract(not_before="2026-11-12T10:00:01Z" if v == "neg" else NOW)
    return w.ev(w.request())


def d06(w, v):  # firma alterada
    c = w.contract()
    if v == "neg":
        p = c["_path"] + ".sig"
        lines = open(p).read().split("\n")
        mid = lines[2]
        lines[2] = mid[:5] + ("A" if mid[5] != "A" else "B") + mid[6:]
        open(p, "w").write("\n".join(lines))
    return w.ev(w.request())


def d06b(w, v):  # firmante en la rama pero no en origin/main
    if v == "neg":
        pub = open(os.path.join(w.keys, "op-c.pub")).read().split()
        extra = open(os.path.join(w.root, "config", "operator-grant-" + "signers")).read().splitlines()
        w.write_signers(extra + ['op-c namespaces="savia-delegation" %s %s' % (pub[0], pub[1])])
        w.set_profile("op-c")
        w.contract(signer="op-c")
        # op-c firma con su propia clave
    else:
        w.contract()
    return w.ev(w.request())


def d06c(w, v):  # namespace de otro uso
    w.contract(ns="savia-operator-grant" if v == "neg" else "savia-delegation")
    return w.ev(w.request())


def d07(w, v):  # sin firma
    w.contract(sign=(v == "twin"))
    return w.ev(w.request())


def d07b(w, v):  # principal self
    w.contract(principal="self") if v == "neg" else w.contract()
    return w.ev(w.request())


def d07c(w, v):  # principal = agente
    if v == "neg":
        w.contract(principal="yema")
    else:
        w.contract()
    return w.ev(w.request())


def d08(w, v):  # firmado por B, perfil activo A
    if v == "neg":
        w.contract(signer="op-b")
    else:
        w.contract()
    return w.ev(w.request())


def d08b(w, v):  # perfil editado para decir B cuando la firma es de A
    w.contract()
    if v == "neg":
        w.set_profile("op-b")
    return w.ev(w.request())


def d09(w, v):  # versión distinta
    w.contract(capability={"id": "pr.create-draft", "version": 2 if v == "neg" else 1, "sha256": w.cap_sha()})
    return w.ev(w.request())


def d09b(w, v):  # descriptor cambiado tras firmar
    w.contract()
    if v == "neg":
        with open(os.path.join(w.root, "contracts", "capabilities", "pr.create-draft.yaml"), "a") as f:
            f.write("# cambiado tras firmar\n")
    return w.ev(w.request())


def _vault(w, v, project, branch="agent/work", scope_projects=("projects/alpha",), req_extra=None):
    w.contract(cap="vault.note-write", declared_effects=["vault.write", "git.commit"],
               scope={"repo": [INSTALL], "branches": ["agent/*"], "projects": list(scope_projects)})
    req = {"capability": "vault.note-write",
           "action": {"name": "vault.note-write", "params": {"path": "n.md"}},
           "target": {"branch": branch, "project": project}}
    req.update(req_extra or {})
    return w.ev(w.request(**req))


def d10(w, v):  # prefijo engañoso de proyecto
    return _vault(w, v, "projects/alpha-x" if v == "neg" else "projects/alpha")


def d10b(w, v):  # agent/* no cubre agent/x/y
    w._git("branch", "agent/x")
    w.contract()
    return w.ev(w.request(target={"branch": "agent/x/y" if v == "neg" else "agent/x"}))


def d10c(w, v):  # segmento ..
    w.contract()
    return w.ev(w.request(target={"branch": "agent/../main" if v == "neg" else "agent/work"}))


def d10d(w, v):  # otro repo
    w.contract()
    return w.ev(w.request(target={"repo": "github.com/acme/other" if v == "neg" else INSTALL, "branch": "agent/work"}))


def d10e(w, v):  # contrato de otra instalación
    w.contract(installation="github.com/acme/other" if v == "neg" else INSTALL)
    return w.ev(w.request())


def d11(w, v):
    w.contract(declared_effects=["git.commit", "pr.open-draft"] if v == "neg"
               else ["git.commit", "git.push", "pr.open-draft"])
    return w.ev(w.request())


def d11b(w, v):  # efecto extra que aporta la orden
    w.contract()
    return w.ev(w.request(action={"name": "pr.create-draft", "params": {"title": "x"},
                                  "effects": ["pr.merge"] if v == "neg" else ["git.push"]}))


def d12(w, v):  # CI roja
    w.set_runs([{"status": "COMPLETED", "conclusion": "FAILURE" if v == "neg" else "SUCCESS"}])
    w.contract()
    return w.ev(w.request())


def d12b(w, v):  # CI pendiente
    w.set_runs([{"status": "IN_PROGRESS" if v == "neg" else "COMPLETED", "conclusion": "" if v == "neg" else "SUCCESS"}])
    w.contract()
    return w.ev(w.request())


def d12c(w, v):  # CI cancelada
    w.set_runs([{"status": "COMPLETED", "conclusion": "CANCELLED" if v == "neg" else "SUCCESS"}])
    w.contract()
    return w.ev(w.request())


def d12d(w, v):  # rama humana
    w.contract(scope={"repo": [INSTALL], "branches": ["agent/*", "feature/*"]})
    return w.ev(w.request(target={"branch": "feature/x" if v == "neg" else "agent/work"}))


def d12e(w, v):  # PR que no está abierto (project.publish)
    w.set_pr(7, state="CLOSED" if v == "neg" else "OPEN")
    return _publish(w)


def d13(w, v):  # gh ausente
    w.contract()
    if v == "neg":
        w.env_extra["SAVIA_AUTHORITY_TOOL_GH"] = os.path.join(w.bin, "no-existe")
    return w.ev(w.request())


def d13b(w, v):  # origin/main ilegible
    w.contract()
    if v == "neg":
        w._git("update-ref", "-d", "refs/remotes/origin/main")
    return w.ev(w.request())


def d13c(w, v):  # sin ssh-keygen
    w.contract()
    if v == "neg":
        w.env_extra["SAVIA_AUTHORITY_TOOL_SSH_KEYGEN"] = os.path.join(w.bin, "no-existe")
    return w.ev(w.request())


def d13d(w, v):  # sin git
    w.contract()
    if v == "neg":
        w.env_extra["SAVIA_AUTHORITY_TOOL_GIT"] = os.path.join(w.bin, "no-existe")
    return w.ev(w.request())


def d14(w, v):  # NFD
    w._git("branch", "agent/wörk")
    w.contract()
    b = unicodedata.normalize("NFD", "agent/wörk") if v == "neg" else "agent/work"
    return w.ev(w.request(target={"branch": b}))


def d14b(w, v):  # homoglifo (a cirílica)
    w.contract()
    return w.ev(w.request(target={"branch": "agent/work".replace("a", "а", 1) if v == "neg" else "agent/work"}))


def d14c(w, v):  # ramas que solo difieren en mayúsculas
    if v == "neg":
        w._git("branch", "agent/Work")
    w.contract()
    return w.ev(w.request())


def d14d(w, v):  # alias sin dueño
    w.contract()
    t = {"branch": "agent/work"}
    if v == "neg":
        t["alias"] = "la-rama-de-ayer"
    return w.ev(w.request(target=t))


def d14e(w, v):  # dos candidatos
    w.contract()
    t = {"branch": "agent/work"}
    if v == "neg":
        t["candidates"] = ["agent/work", "agent/other"]
    return w.ev(w.request(target=t))


def p2(w, v):  # precedencia: homoglifo de proyecto del ámbito -> AMBIGUOUS, no OUT_OF_SCOPE
    return _vault(w, v, "projects/аlpha" if v == "neg" else "projects/alpha")


def d15(w, v):
    fact = {"fact": "Project.repo_membership", "kind": "membership", "provenance": "inferred",
            "value": "projects/alpha", "suggest": "pedir un contrato para projects/beta"}
    return _vault(w, v, "projects/beta", scope_projects=("projects/alpha", "projects/beta") if v == "twin"
                  else ("projects/alpha",), req_extra={"facts": [fact]})


def t_malformed(w, v):
    if v == "neg":
        return w.ev("{no es json")
    w.contract()
    return w.ev(w.request())


def t_malformed_field(w, v):
    r = w.request()
    if v == "neg":
        del r["delegate"]
    else:
        w.contract()
    return w.ev(r)


def t_level(w, v):  # contrato de un delegado L2 para una capacidad que exige L3
    w.contract(delegate="tech-writer" if v == "neg" else "yema", authority={"level": "L4", "tier": 2})
    return w.ev(w.request(delegate="tech-writer" if v == "neg" else "yema"))


def t_uses(w, v):  # evaluate tras consumir el único uso
    w.contract(max_uses=1)
    rc, out = w.ev(w.request())
    assert rc == 0
    if v == "neg":
        rc2, out2 = w.ev(w.request(), "recheck", w.receipt(out))
        assert rc2 == 0, (rc2, out2)
    return w.ev(w.request())


def t_action(w, v):  # orden distinta de la evaluada
    w.contract()
    rc, out = w.ev(w.request())
    assert rc == 0
    other = w.request(action={"name": "pr.create-draft", "params": {"branch": "agent/work", "title": "OTRA"}}) \
        if v == "neg" else w.request()
    return w.ev(other, "recheck", w.receipt(out))


def _publish(w, **over):
    c = dict(cap="project.publish", declared_effects=["project.publish"], max_uses=1,
             scope={"repo": [INSTALL], "prs": [7]})
    c.update(over)
    w.contract(**c)
    return w.ev(w.request(capability="project.publish", action={"name": "project.publish", "params": {"project": "p"}},
                          target={"pr": 7}))


def t_state(w, v):  # head_sha nuevo: no viola precondición, cambia el digest
    w.set_pr(7)
    w.contract(cap="project.publish", declared_effects=["project.publish"], max_uses=1,
               scope={"repo": [INSTALL], "prs": [7]})
    req = w.request(capability="project.publish", action={"name": "project.publish", "params": {"project": "p"}},
                    target={"pr": 7})
    rc, out = w.ev(req)
    assert rc == 0, (rc, out)
    if v == "neg":
        w.set_pr(7, headRefOid="b" * 40)
    return w.ev(req, "recheck", w.receipt(out))


def t_tier(w, v):  # tier 3/4 sin revisión humana
    w.set_pr(7, files=[{"path": "scripts/operator-grant.sh"}], reviewDecision="" if v == "neg" else "APPROVED")
    return _publish(w, authority={"level": "L3", "tier": 4})


CASES = {
    # id: (esperado neg, paso del kernel que lo cubre, fn)
    "D01": ("NO_CONTRACT", 1, d01), "D02": ("REVOKED", 5, d02), "D03": ("REVOKED", 5, d03),
    "D04": ("REVOKED", 5, d04),
    "D05": ("EXPIRED", 6, d05), "D05b": ("EXPIRED", 6, d05b), "D05c": ("NOT_YET_VALID", 6, d05c),
    "D06": ("BAD_SIGNATURE", 3, d06), "D06b": ("BAD_SIGNATURE", 3, d06b), "D06c": ("BAD_SIGNATURE", 3, d06c),
    "D07": ("SELF_ISSUED", 2, d07), "D07b": ("SELF_ISSUED", 2, d07b), "D07c": ("SELF_ISSUED", 2, d07c),
    "D08": ("PRINCIPAL_MISMATCH", 4, d08), "D08b": ("PRINCIPAL_MISMATCH", 4, d08b),
    "D09": ("CAPABILITY_MISMATCH", 7, d09), "D09b": ("CAPABILITY_MISMATCH", 7, d09b),
    "D10": ("OUT_OF_SCOPE", 10, d10), "D10b": ("OUT_OF_SCOPE", 10, d10b), "D10c": ("OUT_OF_SCOPE", 10, d10c),
    "D10d": ("OUT_OF_SCOPE", 10, d10d), "D10e": ("OUT_OF_SCOPE", 10, d10e),
    "D11": ("UNDECLARED_EFFECT", 14, d11), "D11b": ("UNDECLARED_EFFECT", 14, d11b),
    "D12": ("PRECONDITION_FAILED:ci_not_red", 13, d12), "D12b": ("PRECONDITION_FAILED:ci_not_red", 13, d12b),
    "D12c": ("PRECONDITION_FAILED:ci_not_red", 13, d12c),
    "D12d": ("PRECONDITION_FAILED:branch_is_agent", 13, d12d),
    "D12e": ("PRECONDITION_FAILED:pr_open", 13, d12e),
    "D13": ("UNKNOWN_STATE", 12, d13), "D13b": ("UNKNOWN_STATE", 3, d13b), "D13c": ("UNKNOWN_STATE", 3, d13c),
    "D13d": ("UNKNOWN_STATE", 3, d13d),
    "D14": ("AMBIGUOUS", 8, d14), "D14b": ("AMBIGUOUS", 8, d14b), "D14c": ("AMBIGUOUS", 8, d14c),
    "D14d": ("AMBIGUOUS", 8, d14d), "D14e": ("AMBIGUOUS", 8, d14e),
    "D15": ("INFERRED_NOT_AUTHORITY", 9, d15),
    "P2": ("AMBIGUOUS", 8, p2),
    "T-level": ("LEVEL_EXCEEDED", 15, t_level), "T-uses": ("MAX_USES_EXHAUSTED", 11, t_uses),
    "T-action": ("ACTION_MISMATCH", 17, t_action), "T-state": ("STATE_CHANGED", 18, t_state),
    "T-tier": ("REVIEW_REQUIRED", 16, t_tier),
}
# Casos donde el gemelo/neg tiene una forma distinta de la general.
RC_FOR_NEG = {"T-tier": 4}
MALFORMED = {"T-malformed": (2, t_malformed), "T-malformed-field": (2, t_malformed_field)}

# El gemelo de D12e y T-tier necesita un PR: lo prepara _publish. D12e/T-tier twin = ALLOW.


def run_case(case, variant, inproc=False):
    w = World(inproc=inproc)
    try:
        fn = CASES[case][2] if case in CASES else MALFORMED[case][1]
        rc, out = fn(w, variant)
        return rc, out
    finally:
        w.close()


def reason_of(out):
    return None if out is None else out["reason"]


if __name__ == "__main__":
    if sys.argv[1] == "list":
        print("\n".join(list(CASES) + list(MALFORMED)))
    elif sys.argv[1] == "run":
        rc, out = run_case(sys.argv[2], sys.argv[3])
        print("RC=%s REASON=%s SUGG=%s" % (rc, reason_of(out), len(out["suggestions"]) if out else "-"))
