from config import build_manifest
from contracts import ProtocolError, verify_observation

def _required_adapters(evidence, observed_versions):
 # Legacy evidence retains the two historical adapters. v2 is explicit so a
 # newly registered adapter does not require a parser or policy edit.
 if evidence and evidence.get('schema') == 2:
  adapters=evidence.get('adapters')
  if not isinstance(adapters,list) or not adapters: return None
  if any(not isinstance(item,dict) or set(item) != {'id','version'} or not isinstance(item['id'],str) or not isinstance(item['version'],str) for item in adapters): return None
  ids=[item['id'] for item in adapters]
  if len(ids) != len(set(ids)): return None
  return {item['id']:item for item in adapters}
 return {name:{'version':version} for name,version in observed_versions.items()} if observed_versions else None

def validate(root,target,evidence,*,runtime_status,observed_versions,sandbox_passed):
 m=build_manifest(root);r=m['revision'];g=[]
 try:
  import json
  generated=json.loads((__import__('pathlib').Path(target)/'manifest.json').read_text())
  if generated.get('revision') != r: g.append('STALE_GENERATED_CONFIG')
 except Exception: g.append('STALE_GENERATED_CONFIG')
 if evidence is None:g+=['NATIVE_EVIDENCE_MISSING']
 elif evidence.get('schema') not in (1,2) or evidence.get('revision')!=r or evidence.get('kind')!='native-e2e-observation':g+=['NATIVE_EVIDENCE_INVALID']
 required=_required_adapters(evidence,observed_versions)
 # v1 deliberately retains its frozen certification fixture. v2 makes the
 # adapter list evidence-driven, allowing an explicit third adapter.
 if evidence and evidence.get('schema') == 1 and observed_versions != {'codex':'0.153.4','opencode':'1.18.21'}:g+=['CLI_VERSION_MISMATCH']
 elif not required or set(required) != set(observed_versions or {}):g+=['CLI_VERSION_MISMATCH']
 elif any(required[name].get('version') != version for name,version in observed_versions.items()):g+=['CLI_VERSION_MISMATCH']
 if not evidence or not required or any(type(evidence.get('trust',{}).get(k,{}).get('verified')) is not bool or not evidence.get('trust',{}).get(k,{}).get('verified') or evidence.get('trust',{}).get(k,{}).get('revision')!=r for k in required):g+=['NATIVE_TRUST_UNVERIFIED']
 if not sandbox_passed:g+=['SANDBOX_UNAVAILABLE']
 if runtime_status.get('revision')!=r or runtime_status.get('certified') is not True:g+=['RUNTIME_UNCERTIFIED']
 g+=runtime_status.get('gaps',[])
 if evidence and (evidence.get('replay',{}).get('revision')!=r or not evidence.get('replay',{}).get('passed') or evidence.get('e2e',{}).get('revision')!=r or not evidence.get('e2e',{}).get('passed') or evidence.get('capabilities',{}).get('gaps')):g+=['NATIVE_EVIDENCE_INVALID']
 if evidence and evidence.get('schema') == 2:
  observations=evidence.get('observations', [])
  if not isinstance(observations,list):
   g+=['NATIVE_EVIDENCE_INVALID']
  else:
   evidence_refs=evidence.get('evidence_refs', {})
   for observation in observations:
    try: verify_observation(observation, evidence_refs)
    except ProtocolError: g+=['NATIVE_TRUST_UNVERIFIED']; break
 g=sorted(set(g));return {'certified':not g,'revision':r,'gaps':g}
