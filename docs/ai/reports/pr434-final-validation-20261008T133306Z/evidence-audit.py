import pathlib,hashlib,json,subprocess,base64,datetime
r=pathlib.Path('/private/tmp/aai-pr-capability-preflight');out=r/'docs/ai/reports/pr434-final-validation-20261008T133306Z'
def sha(b):return hashlib.sha256(b).hexdigest()
integration=json.loads((r/'docs/ai/tdd/pr434-integrated-remediation-20261008T115236Z/artifact-manifest.json').read_text())
checks=[{'path':e['path'],'match':sha((r/e['path']).read_bytes())==e['sha256']} for e in integration['files']]
t=json.loads((r/'docs/ai/tdd/pr-capability-preflight-final-remediation-20261007T224314Z/transport-manifest.json').read_text()); aliases=[]
for e in t['aliases']:
 p=r/e['to']
 if p.exists():
  b=p.read_bytes(); raw=base64.b64decode(b) if e['encoding']=='base64' else b
  aliases.append({'path':e['to'],'transport_matches':sha(b)==e['transport_sha256'],'original_matches':sha(raw)==e['original_sha256']})
 else: aliases.append({'path':e['to'],'missing_transitive':True})
tracked=subprocess.check_output(['git','ls-files','-z'],cwd=r).decode().split('\0')[:-1];changed=[]
for p in tracked:
 b=subprocess.check_output(['git','show','HEAD:'+p],cwd=r)
 if (r/p).read_bytes()!=b:changed.append(p)
result={'observed_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'integration_count':len(checks),'integration':checks,'historical_transport':aliases,'tracked_bytes_differ_from_HEAD':changed}
(out/'evidence-integrity.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
