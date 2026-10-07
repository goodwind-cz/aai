from pathlib import Path
import json,hashlib,subprocess,sys
root=Path(sys.argv[1]);e=root/'docs/ai/tdd/pr-capability-preflight-final-remediation-20261007T224314Z';scratch=Path('/private/tmp/aai-pr434-remediation-scratch/recovered');scratch.mkdir(exist_ok=True)
rows=json.loads((e/'transport-manifest.json').read_text())['aliases']
for i,x in enumerate(rows):
 out=scratch/str(i);p=subprocess.run([sys.executable,str(e/'recover-evidence.py'),'--root',str(root),'--path',x['from'],'--out',str(out)],capture_output=True,text=True);assert p.returncode==0,p.stderr;b=out.read_bytes();assert hashlib.sha256(b).hexdigest()==x['original_sha256'];assert len(b)==x['bytes'];print(p.stdout.strip());out.unlink()
print('LOSSLESS_RECOVERY=19/19 exact original hashes; decoded scratch outputs removed')

# A real private Git checkout with converted text proves historical blob recovery.
import os,tempfile,shutil
mini=Path(tempfile.mkdtemp(prefix='transport-',dir=scratch));env={**os.environ,'AAI_GIT_WRITE':'1'}
try:
 for x in rows:
  dst=mini/x['to'];dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes((root/x['to']).read_bytes())
 for args in [['init','-q'],['config','user.name','Fixture'],['config','user.email','fixture@example.invalid'],['add','.'],['commit','-qm','transport fixture']]:subprocess.run(['git','-C',str(mini),*args],check=True,env=env,capture_output=True)
 identity=next(x for x in rows if x['encoding']=='identity' and x['to'].endswith('.txt'));f=mini/identity['to'];f.write_bytes(f.read_bytes().replace(b'\n',b'\r\n'))
 q=subprocess.run([sys.executable,str(e/'recover-evidence.py'),'--root',str(mini),'--path',identity['from']],capture_output=True,text=True);assert q.returncode==0,q.stderr;assert json.loads(q.stdout)['byte_source']=='git-blob';print('CHECKOUT_CRLF_IDENTITY=exact historical Git blob')
 encoded=next(x for x in rows if x['encoding']=='base64');f=mini/encoded['to'];f.write_bytes(f.read_bytes().replace(b'\n',b'\r\n'))
 q=subprocess.run([sys.executable,str(e/'recover-evidence.py'),'--root',str(mini),'--path',encoded['from']],capture_output=True,text=True);assert q.returncode==0,q.stderr;assert json.loads(q.stdout)['original_sha256']==encoded['original_sha256'];print('CHECKOUT_CRLF_BASE64=exact original raw bytes')
finally:shutil.rmtree(mini)
