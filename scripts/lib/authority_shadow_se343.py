#!/usr/bin/env python3
"""Adaptador en sombra SE-343 -> kernel de autoridad (SE-496 F1, R7, AC-10). Solo stdlib.

Uso (siempre `python3 -I`):
  authority_shadow_se343.py run [--delegate NOMBRE]   # evalua en sombra cada grant vigente de SE-343
                                      # (delegado por defecto: savia, quien ejecuta push-pr.sh --merge)
  authority_shadow_se343.py report    # resume lo registrado en sombra en el audit del kernel

Que hace `run`:
1. Recorre el ledger de grants de SE-343 (`~/.savia/grants/<scope>.json`, home por la base de usuarios).
2. Pregunta a `scripts/operator-grant.sh check` si cada grant esta vigente. Esa respuesta es la unica
   que cuenta hoy y este adaptador no la cambia: `operator-grant.sh` no se toca (R7).
3. Proyecta cada grant vigente a su contrato de delegacion equivalente (grant de merge `pr:<n>` ->
   capacidad `pr.merge` acotada a ese PR, ese repo y esa vigencia, `max_uses: 1`) y lo evalua con el
   kernel en proceso, pasos 4 a 16 de R3.
4. Escribe en el audit del kernel una linea `mode: shadow-se343` por grant vigente, con la decision
   del kernel, el paso que la fijo y si discrepa del grant.

Lo que NO hace:
- No decide nada. El exit es 0 si la pasada termino (haya o no discrepancias) y 2 si no pudo hacerse.
  Nadie debe leer ese exit como autorizacion; la salida lleva `"shadow": true`.
- Los pasos 1-3 (contrato en disco y firma `savia-delegation`) no aplican: el contrato proyectado no
  existe en disco ni esta firmado. Su equivalente es la firma `savia-operator-grant` que ya verifico
  SE-343 en el paso 2, y por eso solo se proyectan grants vigentes. El contrato proyectado no se escribe
  nunca en `config/delegations/` ni en `~/.savia/delegations/`: un `recheck` con esta salida da
  `NO_CONTRACT`.
- No consume usos (no llama a `recheck`).
- Los grants `autonomy:*` y los de merge sobre `task:<id>` no tienen capacidad equivalente: se registran
  como `UNMAPPED` (discrepancia de cobertura), sin evaluar.
- SE-491 (`project.publish`) no tiene adaptador aqui: su spec no esta aprobada.
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import authority_kernel as k  # noqa: E402

MODE = "shadow-se343"
CAPABILITY = "pr.merge"
DEFAULT_DELEGATE = "savia"
GRANT_ID_RE = re.compile(r"^[0-9a-f]{32}$")
PR_RES_RE = re.compile(r"^pr:([0-9]{1,9})$")
SCOPE_RE = re.compile(r"^(merge|autonomy:[a-z0-9-]{1,64})$")
DELEGATE_RE = re.compile(r"^[a-z0-9][a-z0-9:._-]{0,63}$")


def grants_dir():
    return os.path.join(k.home(), ".savia", "grants")


def grant_files(d):
    """[(scope, ruta)] de los ficheros de grant del ledger. Directorio ilegible -> error (no 'vacio')."""
    try:
        names = sorted(os.listdir(d))
    except FileNotFoundError:
        return []
    out = []
    for n in names:
        if n.endswith(".json") and SCOPE_RE.match(n[:-5]):
            out.append((n[:-5], os.path.join(d, n)))
    return out


def grant_verdict(scope, rec, d):
    """Exit de `operator-grant.sh check` (0 vigente | 1 no | 2 invalido | 3 sin grant). None si no corre."""
    script = os.path.join(k.root_dir(), "scripts", "operator-grant.sh")
    bash = k.tool("bash")
    if bash is None or not os.path.isfile(script):
        return None
    argv = [bash, script, "check", "--scope", scope]
    if scope == "merge":
        res = rec.get("resource")
        if not isinstance(res, str) or not res:
            return 2
        argv += ["--resource", res]
    if k.test_mode():
        env = dict(os.environ)
    else:
        env = {"PATH": k.SAFE_PATH, "HOME": k.home(), "LC_ALL": "C"}
    env["SAVIA_GRANTS_DIR"] = d
    try:
        r = subprocess.run(argv, capture_output=True, timeout=60, env=env)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return r.returncode


def descriptor_ref(root):
    p = os.path.join(root, "contracts", "capabilities", CAPABILITY + ".yaml")
    with open(p, "rb") as f:
        data = f.read()
    d = k.yaml_load(data.decode("utf-8"))
    return {"id": CAPABILITY, "version": d.get("version"), "sha256": k.sha(data)}


def project(rec, delegate, root):
    """Grant de merge vigente -> (contrato, peticion), o None si no hay capacidad equivalente."""
    m = PR_RES_RE.match(str(rec.get("resource", "")))
    gid = rec.get("id")
    if not m or not isinstance(gid, str) or not GRANT_ID_RE.match(gid):
        return None
    pr = int(m.group(1))
    repo = rec.get("repo")
    contract = {
        "schema": "delegation-contract/1", "id": "se343-" + gid, "nonce": gid[:16],
        "principal": rec.get("grantor"), "delegate": delegate,
        "capability": descriptor_ref(root),
        "authority": {"level": "L4", "tier": 4},
        "scope": {"repo": [repo], "prs": [pr]},
        "preconditions": [], "declared_effects": ["pr.merge"],
        "not_before": rec.get("issued_at"), "expires_at": rec.get("expires_at"),
        "max_uses": 1, "installation": repo,
    }
    req = {"delegate": delegate, "capability": CAPABILITY,
           "action": {"name": CAPABILITY, "params": {"pr_number": pr}}, "target": {"pr": pr}}
    return contract, req


def shadow_evaluate(contract, req):
    """Pasos 4-16 del kernel sobre el contrato proyectado. -> (resultado, ctx). Nunca consume usos."""
    k.validate_request(req)
    ctx = k.Ctx(req)
    raw = k.canon(contract).encode("utf-8")
    ctx.contract, ctx.raw, ctx.path, ctx.contract_sha = contract, raw, None, k.sha(raw)
    decision, reason, detail, step = "ALLOW", "OK", "", None
    try:
        ctx.signers_blob, _ = k.base_blob(ctx.root, k.SIGNERS_REL)
        for n, _name, fn in k.STEPS:
            if n < 4:
                continue
            if n >= 17:
                break
            step = n
            fn(ctx)
        step = None
    except k.Deny as d:
        decision, reason, detail = "DENY", d.code, d.detail
    except k.Approval as a:
        decision, reason, detail = "REQUIRES_APPROVAL", a.code, a.detail
    except Exception as e:  # sombra: un fallo se registra como ERROR, nunca como ALLOW
        decision, reason, detail = "ERROR", type(e).__name__, str(e)
    result = {"decision": decision, "reason": reason, "detail": detail, "step": step,
              "contract_id": contract["id"], "action_sha256": k.action_hash(req),
              "state_digest": k.state_digest(ctx) if decision != "ERROR" else None,
              "evaluated_at": k.iso(ctx.now)}
    return result, ctx


def unmapped_ctx(scope):
    req = {"delegate": DEFAULT_DELEGATE, "capability": "unmapped",
           "action": {"name": scope, "params": {}}, "target": {}}
    return k.Ctx(req)


def run_shadow(delegate=DEFAULT_DELEGATE):
    d = grants_dir()
    root = k.root_dir()
    lines, n_vig, n_disc = [], 0, 0
    for scope, path in grant_files(d):
        try:
            with open(path, encoding="utf-8") as f:
                rec = json.load(f)
        except (OSError, ValueError):
            rec = None
        if not isinstance(rec, dict):
            lines.append({"scope": scope, "grant_exit": None, "projected": False, "note": "grant ilegible"})
            continue
        gx = grant_verdict(scope, rec, d)
        row = {"scope": scope, "grant_id": rec.get("id"), "resource": rec.get("resource"), "grant_exit": gx}
        if gx != 0:  # solo los vigentes se proyectan (la firma la verifica SE-343)
            row.update(projected=False)
            lines.append(row)
            continue
        n_vig += 1
        proj = project(rec, delegate, root) if scope == "merge" else None
        if proj is None:
            ctx = unmapped_ctx(scope)
            res = {"decision": "UNMAPPED", "reason": "NO_EQUIVALENT_CAPABILITY", "detail": "", "step": None,
                   "contract_id": None, "action_sha256": k.action_hash(ctx.req), "state_digest": None,
                   "evaluated_at": k.iso(ctx.now)}
        else:
            res, ctx = shadow_evaluate(*proj)
        disc = res["decision"] != "ALLOW"
        n_disc += disc
        extra = {"grant_scope": scope, "grant_id": rec.get("id"), "grant_exit": gx,
                 "kernel_step": res["step"], "discrepancy": disc}
        k.audit_append(ctx, res, MODE, extra=extra)
        row.update(projected=proj is not None, kernel_decision=res["decision"], kernel_reason=res["reason"],
                   kernel_step=res["step"], discrepancy=disc)
        lines.append(row)
    lines.append({"summary": {"grants": len(lines), "vigentes": n_vig, "discrepancias": n_disc}})
    return lines


def report():
    path = os.path.join(k.home(), ".savia", "authority", "audit.jsonl")
    counts, total, disc = {}, 0, 0
    try:
        with open(path, encoding="utf-8") as f:
            for l in f:
                try:
                    e = json.loads(l)
                except ValueError:
                    continue
                if not isinstance(e, dict) or e.get("mode") != MODE:
                    continue
                total += 1
                disc += bool(e.get("discrepancy"))
                key = "%s %s" % (e.get("decision"), e.get("reason"))
                counts[key] = counts.get(key, 0) + 1
    except FileNotFoundError:
        pass
    return {"shadow": True, "evaluaciones": total, "discrepancias": disc,
            "por_motivo": dict(sorted(counts.items()))}


def main(argv):
    cmd = argv[0] if argv else ""
    if cmd == "run" and (len(argv) == 1 or (len(argv) == 3 and argv[1] == "--delegate"
                                             and DELEGATE_RE.match(argv[2]))):
        rows = run_shadow(argv[2] if len(argv) == 3 else DEFAULT_DELEGATE)
        return 0, "\n".join(json.dumps(dict(r, shadow=True), sort_keys=True, ensure_ascii=False) for r in rows)
    if cmd == "report" and len(argv) == 1:
        return 0, json.dumps(report(), sort_keys=True, ensure_ascii=False)
    sys.stderr.write(__doc__)
    return 2, ""


def cli():
    try:
        code, out = main(sys.argv[1:])
    except SystemExit:
        raise
    except BaseException as e:  # sin pasada completa: exit 2, nunca 0
        sys.stderr.write("authority_shadow_se343: fallo: %r\n" % (e,))
        sys.exit(2)
    if out:
        print(out)
    sys.exit(code)


if __name__ == "__main__":
    cli()
