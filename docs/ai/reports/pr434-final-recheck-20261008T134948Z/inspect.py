from pathlib import Path
import json,hashlib,subprocess,datetime,re
r=Path('/private/tmp/aai-pr-capability-preflight');out=r/'docs/ai/reports/pr434-final-recheck-20261008T134948Z';old=r/'docs/ai/reports/pr434-final-validation-20261008T133306Z';rec=r/'docs/ai/reports/pr434-historical-red-recovery-20261008T134500Z'
def sha(b):return hashlib.sha256(b).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(*a):return subprocess.check_output(['git','-C',str(r),*a])
def write(n,d): (out/n).write_text(json.dumps(d,indent=2)+'\n')
f=json.loads((rec/'historical-full-cat.json').read_text());m=json.loads((rec/'maker-write-and-check.json').read_text());receipt=json.loads((rec/'receipt.json').read_text())
provenance=[]
for obj in [f,m]:
 p=Path(obj['source']);raw=p.read_bytes();lines=[json.loads(l) for l in raw.splitlines()]
 for k in ['call','output']:
  item=obj[k];ordinal=item['ordinal'];assert lines[ordinal]==item,(k,ordinal)
 provenance.append({'source':str(p),'current_sha256':sha(raw),'call_id':obj['call']['payload']['call_id'],'captured_at':obj['output']['timestamp'],'exact_tool_records_match':True})
call=f['call']['payload']['input']; seq=['pr-capability-preflight-red.log','pr-capability-preflight-mutation-replay.log','pr-capability-preflight-windows.log','pr-capability-preflight-pester-update-baseline.log']; assert [call.index(x) for x in seq]==sorted(call.index(x) for x in seq)
chunks=[]
for c in f['output']['payload']['output']:
 try: chunks.append(json.loads(c['text']))
 except (ValueError,KeyError): pass
raw=next(c['output'] for c in chunks if c.get('chunk_id')=='361dc2');marker='command: node .aai/scripts/mutation-run.mjs --replay --spec ';assert raw.count(marker)==1
red=raw[:raw.index(marker)].encode('utf-8'); restored=(r/receipt['original_path']).read_bytes();assert red==restored==(rec/'original-red.log').read_bytes();assert len(red)==1740 and sha(red)==receipt['recovered_sha256'];assert red.endswith(b'\n') and red.startswith(b'RED_CLASS: product_red\n');assert re.findall(rb'^FAIL: (TEST-\d+)',red,re.M)==[f'TEST-{i:03}'.encode() for i in range(1,9)]
mc=[]
for c in m['output']['payload']['output']:
 try: mc.append(json.loads(c['text']))
 except (ValueError,KeyError):pass
assert [x['exit_code'] for x in mc]==[0,1,0] and 'ACCEPTED (product_red)' in mc[-1]['output']
assert provenance[0]['current_sha256']==receipt['source_session_sha256']
write('recovery-inspection.json',{'inspected_at_utc':now(),'historical_execution_time':m['output']['timestamp'],'historical_read_time':f['output']['timestamp'],'provenance':provenance,'artifact_order':seq,'extraction_boundary':marker,'bytes':len(red),'current_recovery_sha256':sha(red),'historical_hash_available':False,'maker_exit_codes':[x['exit_code'] for x in mc],'eight_product_failures':True,'terminal_newline':True,'baseline':(r/'docs/ai/tdd/spec-pr-capability-preflight/baseline.mjs').read_text()})
manifest=json.loads((old/'artifact-manifest.json').read_text()); checks=[]
for e in manifest['files']:
 b=(r/e['path']).read_bytes(); assert sha(b)==e['sha256'] and len(b)==e['bytes'],e['path'];checks.append(e)
write('prior-seals.json',{'inspected_at_utc':now(),'prior_report_unchanged':True,'checked_files':checks})
bound=json.loads(Path('/private/tmp/aai-pr434-final-recheck-boundary.json').read_text());checks={p:sha((r/p).read_bytes())==h for p,h in bound.items() if p!='index_raw_nul_sha256'};checks['index_raw_nul_sha256']=sha(git('ls-files','--stage','-z'))==bound['index_raw_nul_sha256'];assert all(checks.values())
paths=git('ls-files','-z').decode().split('\0')[:-1];changed=[]
for p in paths:
 if (r/p).read_bytes()!=git('show','HEAD:'+p):changed.append(p)
assert not changed
specs=list((r/'docs/specs').rglob('*.md'));opted=0;overdue=[];parent=[];deferred=[]
for p in specs:
 lines=p.read_text().splitlines()
 for i,l in enumerate(lines):
  if not l.startswith('|'):continue
  cols=[c.strip() for c in l.strip('|').split('|')]
  if not all(c in cols for c in ['Review-By','Status']):continue
  opted+=1
  for line in lines[i+2:]:
   if not line.startswith('|'):break
   cells=[c.strip() for c in line.strip('|').split('|')]
   if len(cells)!=len(cols):continue
   d=dict(zip(cols,cells))
   if d['Status'].strip('`').lower() in ['deferred','blocked']:
    item={'path':str(p.relative_to(r)),'row':d};deferred.append(item);date=d['Review-By'].strip('`')
    if re.fullmatch(r'\d{4}-\d{2}-\d{2}',date) and date<now()[:10]:overdue.append(item)
    if p.name.startswith('SPEC-0210'):parent.append(item)
assert not overdue and not parent
write('boundary-corpus.json',{'inspected_at_utc':now(),'head':git('rev-parse','HEAD').decode().strip(),'boundary':checks,'tracked_count':len(paths),'tracked_changes':changed,'spec_count':len(specs),'opted_tables':opted,'deferred':deferred,'overdue':overdue,'parent_deferred':parent})
ci=Path('/private/tmp/aai-pr434-final-ci');runs=[];logs=[]
for p in sorted(ci.glob('*.json')):
 obj=json.loads(p.read_text())
 if '-jobs' not in p.name:
  assert obj['head_sha']==git('rev-parse','HEAD').decode().strip() and obj['conclusion']=='success';runs.append({'path':str(p),'sha256':sha(p.read_bytes()),'record':obj})
 else:
  jobs=obj.get('jobs',obj) if isinstance(obj,dict) else obj
  assert all(j['conclusion'] in ['success','skipped'] for j in jobs)
for p in sorted(ci.glob('*.log')):
 text=p.read_text();assert (old/'ci'/p.name).read_bytes()==p.read_bytes()
 logs.append({'path':str(p),'sha256':sha(p.read_bytes()),'observations':[l for l in text.splitlines() if re.search(r'PASS: TEST-|Tests Passed:|\[PASS\] Passed:|\[SKIP\] Skipped:|full=success|TEST008_NATIVE_CAPTURE diagnostic',l)]})
write('ci-inspection.json',{'inspected_at_utc':now(),'meaning':'New read-back of historical exact-head CI records, not new CI execution','runs':runs,'logs':logs})
print(json.dumps({'recovery_bytes':len(red),'old_seals':len(manifest['files']),'boundary':checks,'tracked':len(paths),'specs':len(specs),'opted':opted,'overdue':len(overdue),'ci_runs':len(runs),'ci_logs':len(logs)}))
