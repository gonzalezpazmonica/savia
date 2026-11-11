#!/usr/bin/env python3
"""AC-4: desactiva cada paso del kernel por turnos (parche en proceso) y exige que falle su caso de R5."""
import os
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, "scripts", "lib"))
sys.path.insert(0, os.path.join(REPO, "tests", "fixtures", "se496"))
import authority_kernel as k  # noqa: E402
import battery as b  # noqa: E402


def rc_reason(case):
    try:
        rc, out = b.run_case(case, "neg", inproc=True)
    except Exception as e:  # el paso parcheado rompe el flujo: también es "falla"
        return ("EXC", type(e).__name__)
    return rc, b.reason_of(out)


def by_step_map():
    by_step = {}
    for cid, (want, step, _fn) in b.CASES.items():
        by_step.setdefault(step, cid)
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
    if got[1] == b.CASES[cid][0]:
        print("SURVIVED paso %d (%s): %s sigue dando %s" % (n, orig[i][1], cid, got[1]))
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
    by_step = {}
    for cid, (want, step, _fn) in b.CASES.items():
        by_step.setdefault(step, cid)
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
        if got[1] == b.CASES[cid][0]:
            survivors.append("paso %d (%s) desactivado y %s sigue dando %s" % (n, name, cid, got[1]))
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
    if sys.argv[1:] == ["--baseline"]:
        sys.exit(baseline())
    sys.exit(main())
