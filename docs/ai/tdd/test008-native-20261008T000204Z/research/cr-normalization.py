import subprocess,pathlib,json,os
root=pathlib.Path('/private/tmp/aai-empty-pushurl-research');env=os.environ.copy();env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL='/dev/null',AAI_ROLE='subagent');out=[]
for i,binary in [(0,'/usr/bin/git'),(1,str(root/'git-2.43.0/git'))]:
 for mode in ['url','local']:
  repo=root/f'cr-{i}-{mode}';repo.mkdir(exist_ok=True)
  def run(args):
   p=subprocess.run([binary,'-C',str(repo),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
   return dict(args=args,exit=p.returncode,stdout_hex=p.stdout.hex(),stderr_hex=p.stderr.hex(),stdout=p.stdout.decode(errors='replace'),stderr=p.stderr.decode(errors='replace'))
  assert run(['init','-b','main'])['exit']==0
  for k,v in [('user.name','Fixture'),('user.email','fixture@example.invalid')]:assert run(['config',k,v])['exit']==0
  assert run(['commit','--allow-empty','-m','fixture'])['exit']==0
  dest='https://github.com/Org/Repo.git' if mode=='url' else str(root/f'destination-{i}.git')
  assert run(['remote','add','origin',dest])['exit']==0
  for endpoint in ['url','pushurl']:
   for label,value in [('leading-CR','\r'+dest),('trailing-CR',dest+'\r')]:
    run(['config','--unset-all','remote.origin.pushurl']);run(['config','remote.origin.url',dest]);assert run(['config','remote.origin.'+endpoint,value])['exit']==0
    rec=dict(binary=binary,version=subprocess.check_output([binary,'--version'],env=env).decode().strip(),mode=mode,endpoint=endpoint,case=label,supplied_hex=value.encode().hex(),config_file_hex=(repo/'.git/config').read_bytes().hex(),config_get=run(['config','--null','--get-all','remote.origin.'+endpoint]),fetch=run(['remote','get-url','--all','origin']),push=run(['remote','get-url','--push','--all','origin']))
    if mode=='local':rec['push_dry_run']=run(['push','--dry-run','--porcelain','origin','main'])
    out.append(rec)
(root/'cr-normalization.json').write_text(json.dumps(out,indent=2)+'\n')
for r in out:print(r['version'],r['mode'],r['endpoint'],r['case'],'configured='+r['config_get']['stdout_hex'],'effective='+r['push']['stdout_hex'],'push_exit='+str(r.get('push_dry_run',{}).get('exit')))
