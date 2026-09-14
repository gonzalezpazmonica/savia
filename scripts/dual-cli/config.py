from pathlib import Path
import hashlib,json
GENERATED_NAME='manifest.json'
class ConfigError(ValueError): pass
def _safe(root,rel):
 p=root/rel
 try:r=p.resolve(strict=True)
 except OSError:raise ConfigError('UNTRUSTED_SOURCE')
 # Repository-internal projections (for example .opencode/hooks) may be
 # symlinks; external targets remain untrusted and are rejected.
 if (root not in r.parents and r != root) or not r.is_file():raise ConfigError('UNTRUSTED_SOURCE')
 return p
def build_manifest(root):
 root=Path(root).resolve()
 try: reg=json.loads(_safe(root,Path('.scm/resources.json')).read_text())
 except Exception: raise ConfigError('UNTRUSTED_SOURCE')
 paths={'.scm/resources.json','.scm/INDEX.scm','.scm/categories/quality.scm','.claude/settings.json'}
 # Domain packs are an optional projection: legacy repositories remain valid.
 if (root/'config/domain-packs.json').is_file():
  paths.add('config/domain-packs.json')
  try:
   packs=json.loads(_safe(root,Path('config/domain-packs.json')).read_text())['packs']
   if not isinstance(packs,list):raise ValueError
   for pack in packs:
    for field in ('rule_refs','context_refs','test_refs'):
     refs=pack.get(field,[])
     if not isinstance(refs,list):raise ValueError
     for ref in refs:
      if not isinstance(ref,str) or Path(ref).is_absolute() or '..' in Path(ref).parts:raise ValueError
      paths.add(ref)
  except (ValueError,KeyError,TypeError,AttributeError):raise ConfigError('UNTRUSTED_SOURCE')
 for i in reg.get('resources',[]):
  if not isinstance(i,dict):raise ConfigError('UNTRUSTED_SOURCE')
  x=i.get('path')
  if not isinstance(x,str) or x.startswith('/') or '..' in Path(x).parts:raise ConfigError('UNTRUSTED_SOURCE')
  if i.get('kind') in ('script','skill','agent'):
   paths.add(x)
  if i.get('kind')=='script' and x.endswith('.sh'):
   alt='.opencode/hooks/'+Path(x).name
   if (root/alt).is_file() and not (root/alt).is_symlink(): paths.add(alt)
  if i.get('kind')=='skill':
   d=root/Path(x).parent
   if d.is_dir():paths.update(str(y.relative_to(root)) for y in d.rglob('*') if y.is_file())
 # Security and execution code is part of effective policy even when it is
 # not advertised as a public capability in .scm.  Only regular files count.
 for folder, pattern in (('scripts/dual-cli','*.py'),
                         ('scripts/opencode-plugin/savia-gates','*.ts')):
  paths.update(str(p.relative_to(root)) for p in (root/folder).rglob(pattern) if p.is_file())
 for required in ('config/model-capabilities.yaml', 'config/model-registry.json'):
  candidate = root / required
  if candidate.is_file(): paths.add(required)
 src=[]
 for x in sorted(paths):
  q=_safe(root,Path(x));src.append({'path':x,'sha256':hashlib.sha256(q.read_bytes()).hexdigest()})
 rev=hashlib.sha256(json.dumps(src,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 return {'schema':1,'revision':rev,'certified':False,'sources':src}
def generate(root,target):
 root,target=Path(root).resolve(),Path(target).resolve()
 if target==root/'.codex' or (root in target.parents and target.name=='.codex'):raise ConfigError('FORBIDDEN_TARGET')
 target.mkdir(parents=True,exist_ok=True);p=target/GENERATED_NAME;m=build_manifest(root)
 if p.exists():
  try:o=json.loads(p.read_text())
  except Exception:
   raise ConfigError('MANAGED_FILE_MODIFIED' if (p.parent/'.manifest.owner').exists() else 'FOREIGN_FILE')
  if o.get('managed_by')!='dual-cli':raise ConfigError('FOREIGN_FILE')
  if o.get('revision')!=m['revision']:raise ConfigError('MANAGED_FILE_MODIFIED')
  return o
 m['managed_by']='dual-cli';(target/'.manifest.owner').write_text('dual-cli\n');p.write_text(json.dumps(m,sort_keys=True,indent=2)+'\n');return m
def rollback(target):
 p=Path(target)/GENERATED_NAME
 if not p.exists():return {'removed':[],'conflicts':[]}
 try:o=json.loads(p.read_text())
 except Exception:o={}
 if o.get('managed_by')!='dual-cli':return {'removed':[],'conflicts':[GENERATED_NAME]}
 p.unlink();(p.parent/'.manifest.owner').unlink(missing_ok=True);return {'removed':[GENERATED_NAME],'conflicts':[]}
