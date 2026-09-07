"""Canonical Savia autonomy policy shared by frontend projections."""
from fnmatch import fnmatch
import hashlib
import json
from pathlib import Path
import sys

class PolicyError(ValueError): pass

AUTONOMOUS = {"read": "L0", "inspect": "L0", "plan": "L0",
              "edit": "L1", "create": "L1", "refactor": "L1", "worktree": "L1",
              "test": "L2", "build": "L2", "lint": "L2", "format": "L2",
              "repo_script": "L2", "verify": "L2", "evaluate": "L2"}
GATES = {"push": "EXTERNAL_EFFECT", "merge": "EXTERNAL_EFFECT",
         "deploy": "EXTERNAL_EFFECT", "remote_write": "EXTERNAL_EFFECT",
         "secret_access": "RISK_ESCALATION", "secret_change": "RISK_ESCALATION",
         "architectural_choice": "DECISION_AUTHORITY",
         "product_choice": "DECISION_AUTHORITY", "authority_change": "RISK_ESCALATION",
         "sandbox_disable": "RISK_ESCALATION"}

class AutonomyPolicy:
    def __init__(self, allowed, forbidden, max_risk="L2"):
        if max_risk != "L2": raise PolicyError("AUTHORITY_ESCALATION")
        self.allowed, self.forbidden, self.max_risk = tuple(allowed), tuple(forbidden), max_risk

    def decide(self, action, *, path=None, prompt=None):
        del prompt  # Prompt text is never authority evidence.
        if action in GATES:
            return self._result("NEEDS_HUMAN", GATES[action], action, external=action in {"push","merge","deploy","remote_write"})
        if action not in AUTONOMOUS:
            return self._result("NEEDS_HUMAN", "UNKNOWN", action)
        if path is not None:
            if any(fnmatch(path, rule) for rule in self.forbidden):
                return self._result("NEEDS_HUMAN", "SCOPE_EXPANSION", action)
            if self.allowed and not any(fnmatch(path, rule) for rule in self.allowed):
                return self._result("NEEDS_HUMAN", "SCOPE_EXPANSION", action)
        return self._result("PROCEED", "EXECUTION_PERMISSION", action)

    def _result(self, decision, reason, action, external=False):
        return {"decision": decision, "reason": reason, "risk": AUTONOMOUS.get(action, "L3"),
                "authority": "delegated_execution_only", "human_gate": decision != "PROCEED",
                "external_effects": external, "profile": "autonomous-l2"}

def scope_hash(allowed, forbidden):
    data=json.dumps({"allowed":sorted(allowed),"forbidden":sorted(forbidden)},separators=(',',':'))
    return hashlib.sha256(data.encode()).hexdigest()

def write_receipt(path, decision, scope_digest, revision, actions):
    receipt={"schema":1,"frontend":"codex","profile":"autonomous-l2",
             "risk":decision["risk"],"authority":"delegated_execution_only",
             "scope_hash":scope_digest,"policy_revision":revision,
             "actions":list(actions),"external_effects":decision["external_effects"],
             "human_gate":decision["human_gate"],"result":"PASS" if decision["decision"]=="PROCEED" else "NEEDS_HUMAN",
             "reason":decision["reason"]}
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(receipt,sort_keys=True,indent=2)+'\n')
    return receipt

def agents_contract():
    return """## Savia autonomy contract

For the `autonomous-l2` profile, proceed without an extra human gate for
repository reads, local analysis, workspace edits, tests, builds, linters,
deterministic repository scripts, reversible fixes, worktrees and verification
inside the approved scope. The number of commands does not create authority.

Require human authority for external effects, publication, push, merge, deploy,
secrets, scope expansion, unresolved product or architecture choices, irreversible
effects and risk above L2. Unknown operations fail safe. Execution may be
delegated; decision authority remains human. Never raise this profile or disable
the sandbox to finish a task.
"""

if __name__ == "__main__" and sys.argv[1:] == ["contract"]:
    print(agents_contract(), end="")
