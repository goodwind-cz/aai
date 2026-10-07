#!/usr/bin/env python3
"""Recover a historical named proof through the immutable transport manifest."""
import argparse,base64,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--path',required=True);p.add_argument('--out');a=p.parse_args()
r=Path(a.root).resolve();m=json.loads(Path(__file__).with_name('transport-manifest.json').read_text());rows={x['from']:x for x in m['aliases']}
x=rows.get(a.path)
if x is None:raise SystemExit('path is not a recorded transport alias')
target=r/x['to'];source='worktree'
def decode(b):return base64.decodebytes(b) if x['encoding']=='base64' else b
def exact(b):return len(b)==x['bytes'] and hashlib.sha256(b).hexdigest()==x['original_sha256']
try:b=decode(target.read_bytes())
except Exception:b=b''
if not exact(b):
 # Git blobs preserve historical bytes even when checkout autocrlf changes a text alias.
 for revision in [':'+x['to'],'HEAD:'+x['to']]:
  q=subprocess.run(['git','-C',str(r),'show',revision],capture_output=True)
  if q.returncode!=0:continue
  try:candidate=decode(q.stdout)
  except Exception:continue
  if exact(candidate):b=candidate;source='git-blob';break
assert exact(b),'historical proof mismatch'
if a.out:Path(a.out).write_bytes(b)
print(json.dumps({'original_path':a.path,'resolved_path':x['to'],'byte_source':source,'bytes':len(b),'original_sha256':hashlib.sha256(b).hexdigest(),'exact':True}))
