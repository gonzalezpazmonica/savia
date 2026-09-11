"""Canonical Savia autonomy policy shared by frontend projections."""
from fnmatch import fnmatch
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
from contracts import receipt as validate_receipt
from protocol import ProtocolError, canonical

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

def write_receipt(path, decision, scope_digest, revision, actions, *, frontend="unknown", execution=None,
                  request_id=None, event_id=None, decision_id=None, observation_refs=(), context=None):
    # schema 2 distinguishes a policy decision from an observed execution.
    # Keep schema 1 shape for callers that do not supply execution correlation.
    if execution is not None or request_id or event_id or decision_id or context is not None:
        if context is None or not all((request_id, event_id, decision_id)):
            raise ProtocolError('INCOMPLETE_RECEIPT')
        if context.get('frontend_id') != frontend or context.get('policy_revision') != revision:
            raise ProtocolError('INCONSISTENT_RECEIPT')
        if type(decision.get('human_gate')) is not bool or decision.get('decision') not in ('PROCEED', 'NEEDS_HUMAN', 'DENY'):
            raise ProtocolError('INCONSISTENT_RECEIPT')
        receipt={"schema":2,"context":context,"request_id":request_id,
            "event_id":event_id,"decision_id":decision_id,
            "decision":{"PROCEED":"proceed", "NEEDS_HUMAN":"needs_human", "DENY":"deny"}[decision['decision']],
            "execution":execution,"observation_refs":list(observation_refs),
            "human_gate_count":int(decision["human_gate"]),"delegated_execution":True,
            "decision_authority":"human"}
        validate_receipt(receipt)
    else:
        receipt={"schema":1,"frontend":frontend,"profile":"autonomous-l2",
             "risk":decision["risk"],"authority":"delegated_execution_only",
             "scope_hash":scope_digest,"policy_revision":revision,
             "actions":list(actions),"external_effects":decision["external_effects"],
             "human_gate":decision["human_gate"],"result":decision["decision"],
             "reason":decision["reason"]}
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    content = canonical(receipt) + '\n'
    # Publish a complete inode atomically; no reader sees a partial receipt.
    fd, temporary = tempfile.mkstemp(prefix='.receipt-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        try:
            os.link(temporary, path)
        except FileExistsError:
            try:
                existing = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
                with os.fdopen(existing) as stream:
                    if stream.read(len(content) + 1) != content:
                        raise ProtocolError('RECEIPT_CONFLICT')
            except OSError:
                raise ProtocolError('RECEIPT_CONFLICT') from None
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        os.unlink(temporary)
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
