#!/usr/bin/env python3
"""Codex autonomy view for workspace-doctor; every PASS comes from a probe."""
import argparse
from codex_profile import probe

def report(sandbox_probe=None, enforcement_probe=None):
    p=probe(sandbox_probe,enforcement_probe)
    cap=p["capabilities"]
    rows=[("Codex CLI", bool(p["version"])),
          ('Authentication', p['authentication']['passed']),
          ("Sandbox", p["sandbox"]["passed"]),
          ("Workspace write", cap["workspace_write"] and p["sandbox"]["passed"]),
          ("Autonomy L0", p["autonomy_l0_l2"]["passed"]), ("Autonomy L1", p["autonomy_l0_l2"]["passed"]),
          ("Autonomy L2", p["autonomy_l0_l2"]["passed"]),
          ("Repeated approval check", p["autonomy_l0_l2"]["passed"]),
          ("L3 blocking", p["enforcement"]["passed"]),
          ("L4 blocking", p["l4_blocking"]["passed"]),
          ("Authority escalation", False)]
    return rows,p

def main():
    a=argparse.ArgumentParser();a.add_argument("--sandbox-probe");a.add_argument("--enforcement-probe");x=a.parse_args()
    rows,p=report(x.sandbox_probe,x.enforcement_probe)
    for name,ok in rows:
        state = 'BLOCKED' if name=='Authority escalation' else 'PASS' if ok else 'NOT_VERIFIED'
        if name in ('L3 blocking','L4 blocking') and ok: state='BLOCKED_OR_HUMAN_REROUTE' if name=='L3 blocking' else 'DENY'
        print(f'{name:<25} {state}')
    print(f"{'Status':<25} {p['status']}")
    print(f"{'Max verified risk':<25} {p['max_verified_risk'] or 'NOT_VERIFIED'}")
    print(f"{'Evidence type':<25} {p['evidence_type']}")
    return 0 if p['passed'] else 2
if __name__=="__main__":raise SystemExit(main())
