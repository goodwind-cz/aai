import pathlib,subprocess,json,hashlib,datetime,re
r=pathlib.Path('/private/tmp/aai-pr-capability-preflight'); out=r/'docs/ai/reports/pr434-final-validation-20261008T133306Z'
def sha(b): return hashlib.sha256(b).hexdigest()
def git(*args): return subprocess.check_output(['git','-C',str(r),*args])
bound=json.load(open('/private/tmp/aai-pr434-final-boundary.json')); checks={p:sha((r/p).read_bytes())==h for p,h in bound.items() if p!='index_raw_nul_sha256'}
checks['index_raw_nul_sha256']=sha(git('ls-files','--stage','-z'))==bound['index_raw_nul_sha256']
a=json.load(open(r/'docs/ai/reports/pr434-native-path-aliases-20261008T1230Z/alias-map.json'))
alias=[]
for e in a['entries']:
 original=git('show',e['source_commit']+':'+e['original_path']); current=(r/e['portable_path']).read_bytes()
 alias.append({'original':e['original_path'],'portable':e['portable_path'],'byte_equal':original==current,'sha256':sha(current),'expected_hash_matches':sha(current)==e['sha256'],'blob_matches':git('rev-parse',e['source_commit']+':'+e['original_path']).decode().strip()==e['source_blob']})
paths=git('ls-files','-z').decode().split('\0')[:-1]; invalid=[]; lower={}; collisions=[]
for p in paths:
 for part in p.split('/'):
  if re.search(r'[<>:"\\|?*\x00-\x1f]',part) or part.endswith((' ','.')) or re.match(r'(?i)^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)',part): invalid.append(p)
 if p.casefold() in lower: collisions.append([lower[p.casefold()],p])
 lower[p.casefold()]=p
# Preserve all files already in the shipping index, plus four append-only base prefixes.
ledger={}
for p in ['docs/ai/EVENTS.jsonl','docs/ai/METRICS.jsonl','docs/ai/decisions.jsonl','docs/ai/tests/test-runs.jsonl']:
 ledger[p]=(r/p).read_bytes().startswith(git('show','bdeb425c040ada918dd97e5b878b71e420bad83a:'+p))
specs=list((r/'docs/specs').rglob('*.md')); opted=0; deferred=[]; violations=[]
for p in specs:
 lines=p.read_text().splitlines()
 for i,l in enumerate(lines):
  if l.startswith('|') and 'Review-By' in l and 'Status' in l:
   cols=[c.strip() for c in l.strip('|').split('|')]
   if 'Status' not in cols or 'Review-By' not in cols: continue
   opted+=1
   for row in lines[i+2:]:
    if not row.startswith('|'): break
    cells=[c.strip() for c in row.strip('|').split('|')]
    if len(cells)!=len(cols): continue
    d=dict(zip(cols,cells)); status=d['Status'].strip('`').lower()
    if status in ['deferred','blocked']:
     item={'path':str(p.relative_to(r)),'row':d};deferred.append(item)
     date=d['Review-By'].strip('`')
     if re.fullmatch(r'\d{4}-\d{2}-\d{2}',date) and date<'2026-10-08': violations.append(item)
report={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'head':git('rev-parse','HEAD').decode().strip(),'boundary':checks,'aliases':alias,'tracked_count':len(paths),'invalid_paths':invalid,'case_collisions':collisions,'longest_path':max(paths,key=len),'base_ledger_prefixes':ledger,'spec_count':len(specs),'opted_tables':opted,'deferred_blocked':deferred,'overdue':violations}
(out/'boundary-corpus.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
