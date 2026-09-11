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
    # Exercise protected *test data*, never read authentication credentials.
    with tempfile.TemporaryDirectory(prefix='.savia-boundary-', dir=Path.cwd()) as folder:
        root=Path(folder); secret=root/'protected.txt'; allowed=root/'allowed.txt'
        secret.write_text('protected-test-fixture\n');allowed.write_text('public-control\n')
        config='permissions.savia_probe={extends=":workspace",filesystem={'+json.dumps(str(secret))+ '="deny"},network={enabled=false}}'
        base=['codex','sandbox','--include-managed-config','-C',str(root),'-c',config,'-P','savia_probe','--']
        def commands(target):
            quoted=shlex.quote(str(target))
            link=root/(target.stem+'-link');link.symlink_to(target)
            return [
                ['/bin/cat',str(target)],
                ['/bin/sh','-c',f'IFS= read -r value < {quoted}'],
                [sys.executable,'-c',f'open({str(target)!r}).read()'],
                [sys.executable,'-c',f'import subprocess,sys; sys.exit(subprocess.run(["/bin/cat",{str(target)!r}]).returncode)'],
                ['/bin/cat',str(link)],
                ['/bin/sh','-c',f'cd {shlex.quote(str(root))} && /bin/cat {target.name}'],
                ['/bin/cat',str(root/'..'/root.name/target.name)],
            ]
        for positive, negative in zip(commands(allowed),commands(secret)):
            control=run(base+positive)
            if control is None or control.returncode != 0:return False
            denied=run(base+negative)
            if denied is None or denied.returncode == 0:return False
            if not any(message in denied.stderr.lower() for message in ('permission denied','operation not permitted')):return False
    return True

def real_workspace_probe():
    with tempfile.TemporaryDirectory(prefix='.savia-write-', dir=Path.cwd()) as folder:
        target=Path(folder)/'control.txt'
        command=['codex','sandbox','--include-managed-config','-c','permissions.savia_probe={extends=":workspace",network={enabled=false}}','-P','savia_probe','-C',folder,'--',sys.executable,
                 '-c',f'from pathlib import Path; Path({str(target)!r}).write_text("workspace-control")']
        result=run(command)
        return bool(result and result.returncode==0 and target.is_file() and target.read_text()=='workspace-control')

def probe(sandbox_probe, enforcement_probe=None):
    if os.environ.get('SAVIA_CODEX_TEST_MODE')=='1' or sandbox_probe or enforcement_probe:
        return {'frontend':'codex','version':None,'evidence_type':'SYNTHETIC',
                'capabilities':{'workspace_write':False,'approval_policy':False,'dangerous_bypass_default':False},
                'authentication':{'passed':False},'sandbox':{'passed':False},'enforcement':{'passed':False},
                'autonomy_l0_l2':{'passed':False},'l4_blocking':{'passed':False},
                'status':'DEGRADED_SAFE','max_verified_risk':None,'passed':False,'configuration_ready':False,
                'gaps':['SYNTHETIC_NOT_OPERATIONAL','REAL_SESSION_CANARIES_MISSING']}
    version=run(["codex","--version"]); help_result=run(["codex","--help"])
    sandbox=run(["codex","sandbox","--include-managed-config",'-c','permissions.savia_probe={extends=":workspace",network={enabled=false}}','-P','savia_probe',"--","/usr/bin/true"])
    authentication=run(['codex','login','status'])
    help_text=(help_result.stdout if help_result else "")
    capabilities={"workspace_write":real_workspace_probe() if sandbox and sandbox.returncode==0 else False,
                  "approval_policy":"--ask-for-approval" in help_text,
                  "dangerous_bypass_default":False}
    enforcement=real_enforcement_probe()
    autonomy_passed=bool(version and version.returncode==0
                and capabilities["workspace_write"] and capabilities["approval_policy"]
                and not capabilities["dangerous_bypass_default"]
                and sandbox and sandbox.returncode==0
                and (enforcement.returncode==0 if hasattr(enforcement,"returncode") else enforcement is True))
    l4_blocking=real_l4_probe() if sandbox and sandbox.returncode==0 else False
    configuration_ready=bool(autonomy_passed and l4_blocking and authentication and authentication.returncode==0)
    gaps=['REAL_SESSION_CANARIES_MISSING']
    if not sandbox or sandbox.returncode!=0:gaps.append('SANDBOX_UNAVAILABLE')
    if not capabilities['workspace_write']:gaps.append('WORKSPACE_WRITE_UNVERIFIED')
    if not l4_blocking:gaps.append('SECRET_BOUNDARY_UNVERIFIED')
    return {"frontend":"codex","version":version.stdout.strip() if version and version.returncode==0 else None,
            'evidence_type':'OPERATIONAL_PROBE','authentication':{'passed':bool(authentication and authentication.returncode==0)},
            "capabilities":capabilities,"sandbox":{"passed":bool(sandbox and sandbox.returncode==0)},
            "enforcement":{"passed":bool(enforcement.returncode==0 if hasattr(enforcement,"returncode") else enforcement is True)},
            "autonomy_l0_l2":{"passed":False},"l4_blocking":{"passed":l4_blocking},
            'configuration_ready':configuration_ready,'gaps':gaps,
            "status":"DEGRADED_SAFE","max_verified_risk":None,"passed":False}

def configure(target, sandbox_probe=None, enforcement_probe=None):
    evidence=probe(sandbox_probe, enforcement_probe)
    if evidence.get('configuration_ready') is not True or evidence.get('evidence_type') != 'OPERATIONAL_PROBE': return evidence,2
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
    else:
        result=probe(a.sandbox_probe,a.enforcement_probe)
        code=0 if result['passed'] else 2
    print(json.dumps(result,sort_keys=True));return code
if __name__=="__main__":raise SystemExit(main())
