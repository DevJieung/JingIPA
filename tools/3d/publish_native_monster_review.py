#!/usr/bin/env python3
"""Publish a frozen creature only after direct two-resolution visual QA."""
import argparse,fcntl,hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ids',required=True);p.add_argument('--note',required=True);a=p.parse_args()
path=ROOT/'art/models/native_monsters.json';lock=(ROOT/'build/character-3d/monster-manifest.lock').open('a');fcntl.flock(lock,fcntl.LOCK_EX)
m=json.loads(path.read_text());rp=ROOT/'build/character-3d/monster-review/report.json';reports=json.loads(rp.read_text())['monsters']
for cid in a.ids.split(','):
 sha=hashlib.sha256((ROOT/f'art/models/monsters/{cid}/{cid}.glb').read_bytes()).hexdigest();row=reports[cid]
 if row['glb_sha256']!=sha:raise ValueError('Stale native creature proof '+cid)
 for res in ['1280x800','1000x625']:
  proof=row['resolutions'][res]
  if proof['render_errors']or proof['screenshots']<78 or not proof['battle_captured']:raise ValueError('Incomplete visual proof '+cid)
 pp=ROOT/f'art/models/monsters/{cid}/provenance.json';prov=json.loads(pp.read_text())
 if prov['glb_sha256']!=sha:raise ValueError('Stale native creature provenance '+cid)
 prov['quality_status']='direct visual QA: original identity, actual multiview/IdleLoop/MoveLoop/status/battle in two resolutions';prov['visual_review']=dict(row,report=str(rp.relative_to(ROOT)),artist_note=a.note);pp.write_text(json.dumps(prov,indent=2)+'\n')
 m['monsters'][cid]['ready']=True
 if cid not in m['ready_ids']:m['ready_ids'].append(cid)
 print('DIRECT_CREATURE_VISUAL_QA_PUBLISHED',cid,sha)
tmp=path.with_suffix('.tmp');tmp.write_text(json.dumps(m,indent=2)+'\n');tmp.replace(path);fcntl.flock(lock,fcntl.LOCK_UN);lock.close()
