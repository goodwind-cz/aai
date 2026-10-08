import subprocess, os, json, pathlib, hashlib
root=pathlib.Path('/private/tmp/aai-empty-pushurl-research')
env=os.environ.copy();env.update(GIT_CONFIG_NOSYSTEM='1',GIT_CONFIG_GLOBAL='/dev/null',AAI_ROLE='subagent',GIT_TERMINAL_PROMPT='0')
bins=['/usr/bin/git',str(root/'git-2.43.0/git'),'/Users/ales/.cache/codex-runtimes/codex-primary-runtime/dependencies/bin/fallback/git']
records=[]
def run(binary,repo,args):
 assert str(repo).startswith(str(root)+'/')
 p=subprocess.run([binary,'-C',str(repo),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
 return {'args':args,'exit':p.returncode,'stdout_hex':p.stdout.hex(),'stderr_hex':p.stderr.hex(),'stdout':p.stdout.decode(errors='replace'),'stderr':p.stderr.decode(errors='replace')}
for i,binary in enumerate(bins):
 if not pathlib.Path(binary).exists(): records.append({'binary':binary,'unknown':'not built or available'});continue
 version=subprocess.check_output([binary,'--version'],env=env).decode().strip()
 for mode in ['url','local']:
  repo=root/f'fixture-{i}-{mode}';repo.mkdir(exist_ok=True)
  assert run(binary,repo,['init','-b','main'])['exit']==0
  for key,value in [('user.name','Fixture'),('user.email','fixture@example.invalid')]:assert run(binary,repo,['config',key,value])['exit']==0
  assert run(binary,repo,['commit','--allow-empty','-m','fixture'])['exit']==0
  dest='https://github.com/Org/Repo.git'
  if mode=='local':
   bare=root/f'destination-{i}.git';bare.mkdir(exist_ok=True);assert run('/usr/bin/git',bare,['init','--bare'])['exit']==0;dest=str(bare)
  assert run(binary,repo,['remote','add','origin',dest])['exit']==0
  for name,values in [('no-pushurl',[]),('matching',[dest]),('valid-empty',[dest,'']),('empty-valid',['',dest]),('empty-only',[''])]:
   run(binary,repo,['config','--unset-all','remote.origin.pushurl'])
   for value in values:assert run(binary,repo,['config','--add','remote.origin.pushurl',value])['exit']==0
   rec={'binary':binary,'version':version,'mode':mode,'case':name,'configured_pushurls':values,'effective':run(binary,repo,['remote','get-url','--push','--all','origin'])}
   if mode=='local':
    rec['push_dry_run']=run(binary,repo,['push','--dry-run','--porcelain','origin','main'])
    rec['destination_refs_after']=run('/usr/bin/git',bare,['show-ref'])
   records.append(rec)
(root/'probe-results.json').write_text(json.dumps(records,indent=2)+'\n')
for rec in records:
 if 'effective' in rec:
  print(rec['version'],rec['mode'],rec['case'],'effective_hex='+rec['effective']['stdout_hex'],'push_exit='+str(rec.get('push_dry_run',{}).get('exit')))
