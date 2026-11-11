#!/usr/bin/env python3
"""AC-4: desactiva cada paso del kernel por turnos (parche en proceso) y exige que falle su caso de R5.

KILLED solo si el kernel mutado termina sin excepcion y da otra decision o motivo. Si revienta
(CRASHED), el control no queda demostrado: cuenta como superviviente."""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
sys.path.insert(0, os.path.join(REPO, "tests", "fixtures", "se496"))
import authority_kernel as k  # noqa: E402
import denegaciones as b  # noqa: E402


def rc_reason(case):
    try:
        rc, out = b.run_case(case, "neg", inproc=True)
    except Exception as e:  # el paso parcheado rompe el flujo: NO demuestra que el control importe
        return ("EXC", type(e).__name__)
    return rc, b.reason_of(out)


def verdict(cid, got):
    """KILLED | SURVIVED | CRASHED."""
    if got[0] == "EXC":
        return "CRASHED"
    return "SURVIVED" if got[1] == b.CASES[cid][0] else "KILLED"


# Paso 12 (lectores): su caso de R5 es D13 (gh ausente -> UNKNOWN_STATE). Con el 12 apagado, el
# guard fail-closed del 13 ("precondicion sin hecho leido") da el mismo UNKNOWN_STATE: es redundancia
# deliberada, no prueba del 12. Se mide con D12, cuyo motivo (PRECONDITION_FAILED) exige que el 12 lea.
MUTATION_CASE = {12: "D12"}


# Controles que viven dentro de un paso junto a otros: desactivar el paso entero los mata a la vez y no
# demuestra cuál importa. Se desactiva solo la función y se exige que falle su regresión de review_fixes.
FN_MUTATIONS = {"bind_params": "params-scope", "check_lifetime": "contract-invariants",
                "check_single_use": "contract-invariants"}


def run_fix(name):
    """-> lista de fallos de la regresión, o ("EXC", tipo) si revienta."""
    import review_fixes as rf
    rf.INPROC = True
    try:
        return rf.FIXES[name]()
    except Exception as e:
        return ("EXC", type(e).__name__)
    finally:
        rf.INPROC = False


def one_fn(fn):
    """Desactiva solo la función fn: exit 0 si su regresión falla sin excepción (KILLED), 1 si no, 2 si no existe."""
    fix = FN_MUTATIONS.get(fn)
    if fix is None or not callable(getattr(k, fn, None)):
        print("funcion %s inexistente" % fn)
        return 2
    base = run_fix(fix)
    if base != []:
        print("BASE-FAIL %s: %s" % (fix, base))
        return 1
    orig = getattr(k, fn)
    setattr(k, fn, lambda *a, **kw: None)
    try:
        got = run_fix(fix)
    finally:
        setattr(k, fn, orig)
    if isinstance(got, tuple):
        print("CRASHED funcion %s: %s -> %s" % (fn, fix, got))
        return 1
    if not got:
        print("SURVIVED funcion %s: %s sigue en verde" % (fn, fix))
        return 1
    print("KILLED funcion %s por %s (%d fallos)" % (fn, fix, len(got)))
    return 0


def by_step_map():
    by_step = {}
    for cid, (want, step, _fn) in b.CASES.items():
        by_step.setdefault(step, cid)
    by_step.update(MUTATION_CASE)
    return by_step


def one_step(n):
    """Desactiva solo el paso n: exit 0 si su caso de R5 falla (KILLED), 1 si sobrevive, 2 si n no existe."""
    orig = list(k.STEPS)
    idx = [i for i, st in enumerate(orig) if st[0] == n]
    cid = by_step_map().get(n)
    if not idx or cid is None:
        print("paso %s inexistente" % n)
        return 2
    i = idx[0]
    k.STEPS[i] = (n, orig[i][1], lambda ctx: None)
    try:
        got = rc_reason(cid)
    finally:
        k.STEPS[i] = orig[i]
    v = verdict(cid, got)
    if v != "KILLED":
        print("%s paso %d (%s): %s -> %s" % (v, n, orig[i][1], cid, got))
        return 1
    print("KILLED paso %d (%s) por %s -> %s" % (n, orig[i][1], cid, got))
    return 0


def baseline():
    for cid in by_step_map().values():
        got = rc_reason(cid)
        if got[1] != b.CASES[cid][0]:
            print("BASE-FAIL %s: %s" % (cid, got))
            return 1
    print("BASE-OK")
    return 0


def main():
    by_step = by_step_map()
    for cid in by_step.values():  # sin parche, los casos dan lo esperado (el test puede fallar de verdad)
        got = rc_reason(cid)
        if got[1] != b.CASES[cid][0]:
            print("BASE-FAIL %s: %s" % (cid, got))
            return 1
    survivors = []
    orig = list(k.STEPS)
    for i, (n, name, fn) in enumerate(orig):
        cid = by_step.get(n)
        if cid is None:
            survivors.append("paso %d (%s) sin caso asignado" % (n, name))
            continue
        k.STEPS[i] = (n, name, lambda ctx: None)
        try:
            got = rc_reason(cid)
        finally:
            k.STEPS[i] = (n, name, fn)
        v = verdict(cid, got)
        if v != "KILLED":
            survivors.append("paso %d (%s) desactivado y %s da %s (%s)" % (n, name, cid, got, v))
        else:
            print("KILLED paso %d (%s) por %s -> %s" % (n, name, cid, got))
    if survivors:
        print("\n".join("SURVIVED " + s for s in survivors))
        return 1
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--step":
        try:
            sys.exit(one_step(int(sys.argv[2])))
        except ValueError:
            print("paso no numerico")
            sys.exit(2)
    if len(sys.argv) == 3 and sys.argv[1] == "--fn":
        sys.exit(one_fn(sys.argv[2]))
    if sys.argv[1:] == ["--baseline"]:
        sys.exit(baseline())
    sys.exit(main())
