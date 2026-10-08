import os,json,pathlib,subprocess
r=pathlib.Path('/private/tmp/aai-empty-pushurl-research');records=[]
for n,binary in [(0,'/usr/bin/git'),(1,str(r/'git-2.43.0/git'))]:
 repo=r/f'fixture-{n}-url';env=os.environ.copy();env.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1',AAI_ROLE='subagent',PATH=str(pathlib.Path(binary).parent)+':'+env['PATH'])
 for label,values in [('valid-empty',['https://github.com/Org/Repo.git','']),('empty-valid',['','https://github.com/Org/Repo.git'])]:
  subprocess.run([binary,'-C',str(repo),'config','--unset-all','remote.origin.pushurl'],env=env,check=False)
  for v in values:subprocess.run([binary,'-C',str(repo),'config','--add','remote.origin.pushurl',v],env=env,check=True)
  inp=r/f'input-{n}.json';inp.write_text(json.dumps(dict(schema_version=1,repo_root=str(repo),remote_name='origin',source_branch='main',target_branch='other',repository='Org/Repo')))
  # Old Git must refuse before provider; newer success attempts unavailable provider, so only invoke old version here.
  if n==1:
   p=subprocess.run(['node',str(r/'.aai/scripts/pr-preflight.mjs'),'--input',str(inp),'--json'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20)
   records.append(dict(version='2.43.0',case=label,exit=p.returncode,stdout=p.stdout.decode(),stderr=p.stderr.decode()))
(r/'targeted-preflight.json').write_text(json.dumps(records,indent=2)+'\n');print(json.dumps(records,indent=2))
