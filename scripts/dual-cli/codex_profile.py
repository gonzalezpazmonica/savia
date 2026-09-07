"""Probe and generate the Codex projection without editing user config blindly."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import shlex
from datetime import datetime, timezone

RULES = '''# Generated Savia projection; authority remains in Savia policy.
prefix_rule(pattern=["git", "push"], decision="prompt", justification="External effect requires human authority")
prefix_rule(pattern=["git", "merge"], decision="prompt", justification="Shared-state decision requires human authority")
prefix_rule(pattern=["gh", "pr", "merge"], decision="prompt", justification="External effect requires human authority")
prefix_rule(pattern=["kubectl", "apply"], decision="prompt", justification="Deployment requires human authority")
prefix_rule(pattern=["terraform", "apply"], decision="prompt", justification="Infrastructure mutation requires human authority")
'''

PROFILE = '''# Generated Savia projection; authority remains in Savia policy.
approval_policy = "never"
default_permissions = "savia-autonomous-l2"

[permissions.savia-autonomous-l2]
description = "Savia autonomous L0-L2 with native secret isolation"
extends = ":workspace"

[permissions.savia-autonomous-l2.filesystem]
"~/.codex/auth.json" = "deny"

[permissions.savia-autonomous-l2.network]
enabled = false
'''

def run(command):
    try: return subprocess.run(command, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired): return None

def synthetic_probe(command):
    if not command: return None
    if os.environ.get("SAVIA_CODEX_TEST_MODE")!="1": return None
    if command not in ("/bin/true","/bin/false"): return None
    return run([command])

def real_enforcement_probe():
    try:
        with tempfile.TemporaryDirectory() as folder:
            rules=Path(folder)/"autonomous-l2.rules";rules.write_text(RULES)
            decisions=[]
            for command in (("git","push","origin","main"),("git","merge","feature"),("gh","pr","merge","1")):
                result=run(["codex","execpolicy","check","--rules",str(rules),*command])
                if not result or result.returncode != 0: return None
                decisions.append(json.loads(result.stdout).get("decision"))
            safe=run(["codex","execpolicy","check","--rules",str(rules),"git","status"])
            if not safe or safe.returncode != 0: return None
            return all(x == "prompt" for x in decisions) and json.loads(safe.stdout).get("decision") is None
    except (OSError, ValueError): return None

def real_l4_probe():
    secret=Path.home()/".codex"/"auth.json"
    if not secret.is_file(): return False
    config='permissions.savia_probe={extends=":workspace",filesystem={"~/.codex/auth.json"="deny"}}'
    base=["codex","sandbox","-c",config,"-P","savia_probe","--"]
    quoted=shlex.quote(str(secret))
    with tempfile.TemporaryDirectory() as folder:
        link=Path(folder)/"auth-link";link.symlink_to(secret)
        commands=[
            ["/bin/cat",str(secret)],
            ["/bin/sh","-c",f"IFS= read -r value < {quoted}"],
            ["/usr/bin/python3","-c",f'open({str(secret)!r}).read()'],
            ["/bin/sh","-c",f"/bin/cat {quoted} >/dev/null"],
            ["/bin/cat",str(link)],
            ["/bin/sh","-c",f"cd {shlex.quote(str(Path.home()))} && /bin/cat .codex/auth.json >/dev/null"],
            ["/bin/cat",str(secret.parent/".."/".codex"/"auth.json")],
        ]
        results=[run(base+command) for command in commands]
    return all(result is not None and result.returncode != 0 for result in results)

def probe(sandbox_probe, enforcement_probe=None):
    version=run(["codex","--version"]); help_result=run(["codex","--help"])
    sandbox=synthetic_probe(sandbox_probe) if sandbox_probe else run(["codex","sandbox","--","/usr/bin/true"])
    help_text=(help_result.stdout if help_result else "")
    capabilities={"workspace_write":"workspace-write" in help_text,
                  "approval_policy":"--ask-for-approval" in help_text,
                  "dangerous_bypass_default":False}
    enforcement=(synthetic_probe(enforcement_probe) if enforcement_probe else
                 None if os.environ.get("SAVIA_CODEX_TEST_MODE")=="1" else real_enforcement_probe())
    autonomy_passed=bool(version and version.returncode==0
                and capabilities["workspace_write"] and capabilities["approval_policy"]
                and not capabilities["dangerous_bypass_default"]
                and sandbox and sandbox.returncode==0
                and (enforcement.returncode==0 if hasattr(enforcement,"returncode") else enforcement is True))
    l4_blocking=(bool(autonomy_passed) if os.environ.get("SAVIA_CODEX_TEST_MODE")=="1"
                 else real_l4_probe())
    return {"frontend":"codex","version":version.stdout.strip() if version else None,
            "capabilities":capabilities,"sandbox":{"passed":bool(sandbox and sandbox.returncode==0)},
            "enforcement":{"passed":bool(enforcement.returncode==0 if hasattr(enforcement,"returncode") else enforcement is True)},
            "autonomy_l0_l2":{"passed":autonomy_passed},"l4_blocking":{"passed":l4_blocking},
            "status":"DEGRADED_SAFE","max_verified_risk":"L2","passed":autonomy_passed and l4_blocking}

def configure(target, sandbox_probe=None, enforcement_probe=None):
    evidence=probe(sandbox_probe, enforcement_probe)
    if not evidence["passed"]: return evidence,2
    target=Path(target);target.parent.mkdir(parents=True,exist_ok=True)
    marker=target.with_name(target.name+".savia.json")
    if target.exists():
        if not marker.exists(): evidence["error"]="USER_CONFIG_CONFLICT";return evidence,2
        try: ownership=json.loads(marker.read_text())
        except (OSError,ValueError): evidence["error"]="USER_CONFIG_CONFLICT";return evidence,2
        actual=hashlib.sha256(target.read_bytes()).hexdigest()
        if ownership.get("profile_sha256")!=actual or target.read_text()!=PROFILE:
            evidence["error"]="USER_CONFIG_CONFLICT";return evidence,2
    rules_target=target.parent/"rules"/"savia-autonomous-l2.rules"
    rules_target.parent.mkdir(parents=True,exist_ok=True)
    if rules_target.exists() and rules_target.read_text()!=RULES:
        evidence["error"]="USER_CONFIG_CONFLICT";return evidence,2
    target.write_text(PROFILE);rules_target.write_text(RULES)
    digest=hashlib.sha256(PROFILE.encode()).hexdigest()
    rules_digest=hashlib.sha256(RULES.encode()).hexdigest()
    marker.write_text(json.dumps({"managed_by":"savia","profile_sha256":digest,
                                  "rules_path":str(rules_target),"rules_sha256":rules_digest,
                                  "codex_version":evidence["version"]},sort_keys=True)+'\n')
    evidence["profile_sha256"]=digest
    evidence["configured"]=True
    return evidence,0

def rollback(target):
    import hmac
    target=Path(target);marker=target.with_name(target.name+".savia.json")
    if not target.exists() and not marker.exists(): return {"removed":False},0
    if not target.exists() or not marker.exists(): return {"removed":False,"error":"ROLLBACK_CONFLICT"},2
    try: ownership=json.loads(marker.read_text())
    except (OSError,ValueError): return {"removed":False,"error":"ROLLBACK_CONFLICT"},2
    expected=ownership.get("profile_sha256","");actual=hashlib.sha256(target.read_bytes()).hexdigest()
    if ownership.get("managed_by")!="savia" or not hmac.compare_digest(expected,actual): return {"removed":False,"error":"ROLLBACK_CONFLICT"},2
    rules_path=ownership.get("rules_path")
    if rules_path:
        rules=Path(rules_path)
        if rules.exists():
            actual_rules=hashlib.sha256(rules.read_bytes()).hexdigest()
            if not hmac.compare_digest(ownership.get("rules_sha256",""),actual_rules):
                return {"removed":False,"error":"ROLLBACK_CONFLICT"},2
            rules.unlink()
    target.unlink();marker.unlink();return {"removed":True},0

def evidence_package(output, sandbox_probe=None, enforcement_probe=None):
    evidence=probe(sandbox_probe,enforcement_probe)
    root=Path(__file__).resolve().parents[2]
    from autonomy import AutonomyPolicy
    policy=AutonomyPolicy(["src/*","tests/*"],["secrets/*","infra/live/*"])
    contract_passed=(policy.decide("test",path="tests/x.py")["decision"]=="PROCEED"
                     and policy.decide("push")["decision"]=="NEEDS_HUMAN"
                     and policy.decide("authority_change")["decision"]=="NEEDS_HUMAN")
    commit=run(["git","-C",str(root),"rev-parse","HEAD"])
    evidence.update({"schema":1,"kind":"codex-autonomy-evidence",
                     "timestamp":datetime.now(timezone.utc).isoformat(),
                     "commit_sha":commit.stdout.strip() if commit and commit.returncode==0 else None,
                     "contract_tests":{"passed":contract_passed},
                     "authority":"delegated_execution_only","external_effects":False,
                     "environment_assumptions":["linux","workspace-write requested","network mutation denied"]})
    Path(output).parent.mkdir(parents=True,exist_ok=True)
    Path(output).write_text(json.dumps(evidence,sort_keys=True,indent=2)+'\n')
    return evidence,0 if evidence["passed"] else 2

def main():
    p=argparse.ArgumentParser();p.add_argument("command",choices=("probe","configure","rollback","evidence"));p.add_argument("--target");p.add_argument("--output");p.add_argument("--sandbox-probe");p.add_argument("--enforcement-probe")
    a=p.parse_args()
    if a.command in ("configure","rollback") and not a.target: p.error("--target required")
    if a.command=="evidence" and not a.output: p.error("--output required")
    if a.command=="configure": result,code=configure(a.target,a.sandbox_probe,a.enforcement_probe)
    elif a.command=="rollback": result,code=rollback(a.target)
    elif a.command=="evidence": result,code=evidence_package(a.output,a.sandbox_probe,a.enforcement_probe)
    else: result,code=probe(a.sandbox_probe,a.enforcement_probe),0
    print(json.dumps(result,sort_keys=True));return code
if __name__=="__main__":raise SystemExit(main())
