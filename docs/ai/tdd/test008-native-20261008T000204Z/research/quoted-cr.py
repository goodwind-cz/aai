import pathlib,subprocess,json,os
r=pathlib.Path('/private/tmp/aai-empty-pushurl-research');b=str(r/'git-2.43.0/git');env=os.environ.copy();env.update(GIT_CONFIG_GLOBAL='/dev/null',GIT_CONFIG_NOSYSTEM='1',AAI_ROLE='subagent');rows=[]
for endpoint in ['url','pushurl']:
 for loc in ['leading','trailing']:
  repo=r/'cr-1-local';config=repo/'.git/config';dest=str(r/'destination-1.git');value=('\r'+dest) if loc=='leading' else (dest+'\r')
  data='[core]\n\trepositoryformatversion = 0\n\tbare = false\n[remote "origin"]\n\turl = "'+(value if endpoint=='url' else dest)+'"\n'
  if endpoint=='pushurl':data+='\tpushurl = "'+value+'"\n'
  config.write_bytes(data.encode())
  rec=dict(endpoint=endpoint,case=loc,supplied_hex=value.encode().hex(),config_file_hex=config.read_bytes().hex())
  for name,args in [('config_get',['config','--null','--get-all','remote.origin.'+endpoint]),('effective',['remote','get-url','--push','--all','origin']),('dry_run',['push','--dry-run','--porcelain','origin','main'])]:
   p=subprocess.run([b,'-C',str(repo),*args],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=20);rec[name]=dict(exit=p.returncode,stdout_hex=p.stdout.hex(),stderr_hex=p.stderr.hex())
  rows.append(rec)
(r/'quoted-cr.json').write_text(json.dumps(rows,indent=2)+'\n');print(json.dumps(rows,indent=2))
