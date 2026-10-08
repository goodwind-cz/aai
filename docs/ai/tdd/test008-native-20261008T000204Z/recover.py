#!/usr/bin/env python3
"""Resolve historical portable aliases transitively with original-byte verification."""
import argparse,base64,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--path',required=True);p.add_argument('--out');a=p.parse_args();r=Path(a.root).resolve()
m=json.loads(Path(__file__).with_name('native-aliases.json').read_text());prior=json.loads((r/m['historical_manifest']).read_text())
rows={x['from']:x for x in prior['aliases']+m['aliases']};x=rows.get(a.path)
if x is None:raise SystemExit('path is not a recorded transport alias')
target=x['to'];chain=[a.path];seen={a.path}
while target in rows:
 if target in seen:raise SystemExit('alias cycle')
 seen.add(target);chain.append(target);next=rows[target]
 if next['encoding']!='identity' or next['original_sha256']!=x['original_sha256']:raise SystemExit('alias byte identity mismatch')
 target=next['to']
chain.append(target)
def decode(b):return base64.decodebytes(b) if x['encoding']=='base64' else b
def exact(b):return len(b)==x['bytes'] and hashlib.sha256(b).hexdigest()==x['original_sha256']
try:b=decode((r/target).read_bytes());source='worktree'
except Exception:b=b'';source='missing'
if not exact(b):
 for revision in [':'+target,'HEAD:'+target]:
  q=subprocess.run(['git','-C',str(r),'show',revision],capture_output=True)
  if q.returncode:continue
  try:v=decode(q.stdout)
  except Exception:continue
  if exact(v):b=v;source='git-blob';break
assert exact(b),'historical proof mismatch'
if a.out:Path(a.out).write_bytes(b)
print(json.dumps({'original_path':a.path,'resolved_path':target,'alias_chain':chain,'byte_source':source,'bytes':len(b),'original_sha256':hashlib.sha256(b).hexdigest(),'exact':True}))
