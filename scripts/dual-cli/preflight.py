from config import build_manifest
def validate(root,target,evidence,*,runtime_status,observed_versions,sandbox_passed):
 m=build_manifest(root);r=m['revision'];g=[]
 try:
  import json
  generated=json.loads((__import__('pathlib').Path(target)/'manifest.json').read_text())
  if generated.get('revision') != r: g.append('STALE_GENERATED_CONFIG')
 except Exception: g.append('STALE_GENERATED_CONFIG')
 if evidence is None:g+=['NATIVE_EVIDENCE_MISSING']
 elif evidence.get('schema')!=1 or evidence.get('revision')!=r or evidence.get('kind')!='native-e2e-observation':g+=['NATIVE_EVIDENCE_INVALID']
 if observed_versions!={'codex':'0.153.4','opencode':'1.18.21'}:g+=['CLI_VERSION_MISMATCH']
 if not evidence or any(not evidence.get('trust',{}).get(k,{}).get('verified') or evidence.get('trust',{}).get(k,{}).get('revision')!=r for k in ('codex','opencode')):g+=['NATIVE_TRUST_UNVERIFIED']
 if not sandbox_passed:g+=['SANDBOX_UNAVAILABLE']
 if runtime_status.get('revision')!=r or not runtime_status.get('certified'):g+=['RUNTIME_UNCERTIFIED']
 g+=runtime_status.get('gaps',[])
 if evidence and (evidence.get('replay',{}).get('revision')!=r or not evidence.get('replay',{}).get('passed') or evidence.get('e2e',{}).get('revision')!=r or not evidence.get('e2e',{}).get('passed') or evidence.get('capabilities',{}).get('gaps')):g+=['NATIVE_EVIDENCE_INVALID']
 g=sorted(set(g));return {'certified':not g,'revision':r,'gaps':g}
