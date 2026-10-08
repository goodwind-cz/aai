from pathlib import Path
import subprocess,json,hashlib
r=Path.cwd();e=r/'docs/ai/tdd/test008-native-20261008T000204Z';m=json.loads((e/'native-aliases.json').read_text());prior=json.loads((r/m['historical_manifest']).read_text());count=0
for row in prior['aliases']+m['aliases']:
 p=subprocess.run(['python3',str(e/'recover.py'),'--root',str(r),'--path',row['from']],capture_output=True,text=True);assert p.returncode==0,p.stderr
 got=json.loads(p.stdout);assert got['original_sha256']==row['original_sha256'] and got['bytes']==row['bytes'] and got['exact'];count+=1
 print(json.dumps(got))
for row in m['aliases']:
 old=subprocess.check_output(['git','show','bfea029b:'+row['from']]);assert hashlib.sha256(old).hexdigest()==row['original_sha256'];assert (r/row['to']).read_bytes()==old
print('LOSSLESS_TRANSITIVE_RECOVERY='+str(count)+'/24;five originals equal immutable bfea Git blobs')

# Isolated fixture: only current short leaves, original byte-bound manifests and helper.
import shutil,os
scratch=Path('/private/tmp/aai-pr434-remediation-scratch/recovery-native-fixture');assert scratch.is_absolute();shutil.rmtree(scratch,ignore_errors=True);scratch.mkdir()
def copy(rel):
 q=scratch/rel;q.parent.mkdir(parents=True,exist_ok=True);q.write_bytes((r/rel).read_bytes())
for rel in [m['historical_manifest'],str((e/'native-aliases.json').relative_to(r)),str((e/'recover.py').relative_to(r))]:copy(rel)
rows={x['from']:x for x in prior['aliases']+m['aliases']}
for x in rows.values():
 target=x['to']
 while target in rows:target=rows[target]['to']
 copy(target)
env={**os.environ,'AAI_GIT_WRITE':'1'}
def git(*args):return subprocess.run(['git','-C',str(scratch),*args],capture_output=True,env=env,check=True)
git('init','-q');git('config','user.name','Fixture');git('config','user.email','fixture@example.invalid');git('add','-A');git('commit','-qm','byte-bound current alias fixture')
identity=m['aliases'][0];leaf=scratch/identity['to'];original=leaf.read_bytes();leaf.write_bytes(original.replace(bytes([10]),bytes([13,10])))
def recover(path):return subprocess.run(['python3',str(scratch/e.relative_to(r)/'recover.py'),'--root',str(scratch),'--path',path],capture_output=True,text=True)
q=recover(identity['from']);assert q.returncode==0,q.stderr;got=json.loads(q.stdout);assert got['byte_source']=='git-blob' and got['original_sha256']==identity['original_sha256'];print('CHECKOUT_CRLF_IDENTITY=exact original Git blob after current-only alias commit')
b64=next(x for x in prior['aliases'] if x['encoding']=='base64');leaf=scratch/b64['to'];leaf.write_bytes(leaf.read_bytes().replace(bytes([10]),bytes([13,10])));q=recover(b64['from']);assert q.returncode==0,q.stderr;assert json.loads(q.stdout)['original_sha256']==b64['original_sha256'];print('CHECKOUT_CRLF_BASE64=exact original raw bytes')
q=recover('unrecorded-proof');assert q.returncode!=0;print('UNKNOWN_ALIAS_REFUSED=true')
# Neither old hyphen file nor historic objects exist in this fixture.
leaf=scratch/identity['to'];leaf.write_bytes(b'tampered');git('add',identity['to']);git('commit','-qm','tampered current blobs');q=recover(identity['from']);assert q.returncode!=0;print('WRONG_WORKTREE_INDEX_HEAD_HASH_REFUSED=true')
shutil.rmtree(scratch)
