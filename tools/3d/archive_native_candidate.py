#!/usr/bin/env python3
"""Preserve a rejected/intermediate native candidate before a local rig refit."""
import argparse,hashlib,json,shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ids',required=True);a=p.parse_args()
m=json.loads((ROOT/'art/models/native_heroes.json').read_text())
for cid in a.ids.split(','):
 if cid=='limne'or cid in m['ready_ids']:raise ValueError('Reviewed native is protected: '+cid)
 glb=ROOT/f'art/models/{cid}/{cid}.glb';sha=hashlib.sha256(glb.read_bytes()).hexdigest()
 folder=ROOT/'build/character-3d/archive'/cid/sha[:16];folder.mkdir(parents=True,exist_ok=True);files={}
 for source in [glb,ROOT/f'art/models/{cid}/provenance.json',ROOT/f'build/character-3d/source/{cid}/high.blend',ROOT/f'build/character-3d/source/{cid}/game.blend',ROOT/f'build/character-3d/review/{cid}/deformation-first-pass.json']:
  if not source.exists():continue
  digest=hashlib.sha256(source.read_bytes()).hexdigest();dest=folder/source.name
  if not dest.exists():shutil.copy2(source,dest)
  if hashlib.sha256(dest.read_bytes()).hexdigest()!=digest:raise RuntimeError('Archive mismatch '+str(source))
  files[str(source.relative_to(ROOT))]={'archive':str(dest.relative_to(ROOT)),'sha256':digest}
 (folder/'manifest.json').write_text(json.dumps({'id':cid,'glb_sha256':sha,'status':'intermediate not ready; preserved before local fit','files':files},indent=2)+'\n');print('Archived candidate',cid,sha)
