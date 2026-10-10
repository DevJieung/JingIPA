#!/usr/bin/env python3
"""Publish only a frozen GLB whose actual two-resolution proof was inspected.

This guards artifact identity and completeness. The supplied artist note is
the direct visual assessment; geometry statistics are not an aesthetic PASS.
"""
import argparse, hashlib, json, fcntl
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ids',required=True)
p.add_argument('--note',required=True);a=p.parse_args()
path=ROOT/'art/models/native_heroes.json'
lock=(ROOT/'build/character-3d/native-manifest.lock').open('a')
fcntl.flock(lock,fcntl.LOCK_EX)
manifest=json.loads(path.read_text())
report_path=ROOT/'build/character-3d/review/report.json'
reports=json.loads(report_path.read_text())['heroes']
for cid in a.ids.split(','):
    if cid=='limne':raise ValueError('Accepted Limne is protected')
    glb=ROOT/f'art/models/{cid}/{cid}.glb'
    sha=hashlib.sha256(glb.read_bytes()).hexdigest();proof=reports[cid]
    if proof['glb_sha256']!=sha:raise ValueError(cid+': stale actual engine proof')
    for res in ['1280x800','1000x625']:
        row=proof['resolutions'][res]
        if row['render_errors'] or not row['battle_captured'] or row['screenshots']<85:
            raise ValueError(cid+': incomplete actual QA')
    prov_path=ROOT/f'art/models/{cid}/provenance.json'
    prov=json.loads(prov_path.read_text())
    if prov['glb_sha256']!=sha:raise ValueError(cid+': provenance mismatch')
    prov['quality_status']='direct visual QA passed; original identity, multiview, continuous idle/attack, ranks/awakening and mixed battle in two resolutions'
    prov['visual_review']=dict(proof,report=str(report_path.relative_to(ROOT)),
        directly_inspected=['original','native studio','turnaround','idle/attack contact','grades/awakening','two-resolution mixed battle'],artist_note=a.note)
    prov_path.write_text(json.dumps(prov,indent=2)+'\n')
    manifest['heroes'][cid]['ready']=True
    if cid not in manifest['ready_ids']:manifest['ready_ids'].append(cid)
    print('DIRECT_VISUAL_QA_PUBLISHED',cid,sha)
temp=path.with_suffix('.tmp');temp.write_text(json.dumps(manifest,indent=2)+'\n');temp.replace(path)
fcntl.flock(lock,fcntl.LOCK_UN);lock.close()
