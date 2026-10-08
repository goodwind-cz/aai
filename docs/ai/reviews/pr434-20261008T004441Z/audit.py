import subprocess,json,hashlib,base64,re
from pathlib import Path
r=Path.cwd();out=r/'docs/ai/reviews/pr434-20261008T004441Z';base='bdeb425c040ada918dd97e5b878b71e420bad83a';head='ebbd0eaeaebfa9015f550193df6f0b54afc338c3'
def sha(b):return hashlib.sha256(b).hexdigest()
m=json.loads((r/'docs/ai/tdd/test008-native-20261008T000204Z/final-manifest.json').read_text());errors=[]
for x in m['files']:
 p=r/x['path']
 if x['action']=='delete':
  if p.exists():errors.append('deleted path exists:'+x['path'])
 else:
  b=p.read_bytes()
  if len(b)!=x['bytes'] or sha(b)!=x['sha256']:errors.append('manifest mismatch:'+x['path'])
names=subprocess.check_output(['git','diff','--name-only',base+'...'+head]).decode().splitlines();inventory=[]
for n in names:
 b=subprocess.check_output(['git','show',head+':'+n]);inventory.append({'path':n,'bytes':len(b),'sha256':sha(b),'nul_count':b.count(bytes([0]))})
ledgers=[]
for n in ['docs/ai/EVENTS.jsonl','docs/ai/METRICS.jsonl','docs/ai/decisions.jsonl','docs/ai/tests/test-runs.jsonl']:
 b=subprocess.check_output(['git','show',base+':'+n]);same=(r/n).read_bytes().startswith(b);ledgers.append({'path':n,'base_bytes':len(b),'exact_prefix':same});assert same,n
aliases=json.loads((r/'docs/ai/tdd/test008-native-20261008T000204Z/native-aliases.json').read_text());prior=json.loads((r/aliases['historical_manifest']).read_text());rows={x['from']:x for x in prior['aliases']+aliases['aliases']};recovery=[]
for x in rows.values():
 target=x['to'];seen=set()
 while target in rows:
  assert target not in seen;seen.add(target);target=rows[target]['to']
 b=(r/target).read_bytes();b=base64.decodebytes(b) if x['encoding']=='base64' else b
 assert len(b)==x['bytes'] and sha(b)==x['original_sha256'],x['from']
 recovery.append({'from':x['from'],'leaf':target,'bytes':len(b),'sha256':sha(b),'exact':True})
records=[]
for p in sorted((r/'docs/ai/tdd/spec-pr-capability-preflight').glob('mutation-TEST-???.txt')):
 t=p.read_text();fields=dict(line.split(': ',1) for line in t.split('---')[0].splitlines() if ': ' in line);live=sha((r/fields['target']).read_bytes());assert live==fields['target_sha256'];records.append({'test':fields['test_id'],'target':fields['target'],'sha256':live,'matched':True})
assert subprocess.check_output(['git','rev-parse','HEAD']).decode().strip()==head
j={'base':base,'head':head,'diff_sha256':sha(subprocess.check_output(['git','diff',base+'...'+head])),'scope_paths':len(names),'maker_manifest_entries':len(m['files']),'errors':errors,'ledgers':ledgers,'aliases':recovery,'mutation_targets':records,'scope_inventory':inventory}
(out/'audit.json').write_text(json.dumps(j,indent=2)+'\n');print(json.dumps({'scope_paths':len(names),'maker_manifest_entries':len(m['files']),'errors':errors,'nul_files':[x['path'] for x in inventory if x['nul_count']],'ledgers_exact':len(ledgers),'aliases_exact':len(recovery),'mutation_targets_current':len(records)},indent=2));assert not errors
