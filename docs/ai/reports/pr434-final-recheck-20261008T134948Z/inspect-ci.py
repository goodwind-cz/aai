from pathlib import Path
import json,hashlib,subprocess,datetime,re
r=Path('/private/tmp/aai-pr-capability-preflight');out=r/'docs/ai/reports/pr434-final-recheck-20261008T134948Z';old=r/'docs/ai/reports/pr434-final-validation-20261008T133306Z';rec=r/'docs/ai/reports/pr434-historical-red-recovery-20261008T134500Z'
def sha(b):return hashlib.sha256(b).hexdigest()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def git(*a):return subprocess.check_output(['git','-C',str(r),*a])
def write(n,d): (out/n).write_text(json.dumps(d,indent=2)+'\n')
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
print("CI inspection complete: "+str(len(runs))+" runs, "+str(len(logs))+" logs")
