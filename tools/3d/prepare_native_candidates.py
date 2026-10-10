#!/usr/bin/env python3
"""Prepare actual raw GLBs and proof candidates; NEVER publish ready_ids.

Runs the existing finisher, posed geometry audit and actual Blender renders.
Direct artist QA and separate Godot/world QA remain required per character.
"""
import argparse,json,subprocess,time,hashlib
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--ids',required=True)
p.add_argument('--raw',default='build/character-3d/raw-v3');p.add_argument('--follow',action='store_true')
p.add_argument('--skip-build',action='store_true');a=p.parse_args()
ids=a.ids.split(',');done=set();base=ROOT/'build/character-3d/review'
def run(cid,label,script,arguments):
    out=base/cid;out.mkdir(parents=True,exist_ok=True)
    with (out/(label+'.log')).open('w')as log:
        result=subprocess.run(['bl','-b','--factory-startup','--python',str(ROOT/'tools/3d'/script),'--',*arguments],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
    text=(out/(label+'.log')).read_text()
    if result.returncode or 'Traceback (most recent call last)'in text or 'Error: Python:'in text:
        raise RuntimeError(cid+': '+label+' failed; see actual log')
while len(done)<len(ids):
    progress=False
    for cid in ids:
        if cid in done:continue
        if cid=='limne':raise ValueError('Accepted Limne is excluded')
        raw=ROOT/a.raw/cid/'model.glb'
        if not raw.exists():continue
        manifest=json.loads((ROOT/'art/models/native_heroes.json').read_text())
        if cid in manifest.get('ready_ids',[]):done.add(cid);continue
        if not a.skip_build:run(cid,'finish-first-pass','finish_native_character.py',['--id',cid,'--input',str(raw)])
        provenance=json.loads((ROOT/'art/models'/cid/'provenance.json').read_text())
        glb=ROOT/'art/models'/cid/(cid+'.glb')
        if hashlib.sha256(glb.read_bytes()).hexdigest()!=provenance['glb_sha256']:raise RuntimeError('Stale export')
        if not provenance['embedded_images'] or len(provenance['clips'])<2:raise RuntimeError('Incomplete native asset')
        blend=ROOT/'build/character-3d/source'/cid/'game.blend'
        run(cid,'deformation-first-pass','check_native_deformation.py',['--input',str(blend),'--out',str(base/cid/'deformation-first-pass.json')])
        for clip,frame,label in [('IdleLoop',0,'candidate-idle'),('Attack',30,'candidate-attack')]:
            run(cid,label,'render_native_studio.py',['--input',str(blend),'--out',str(base/cid/label),'--clip',clip,'--frame',str(frame),'--quick','--height',str(provenance['height'])])
        done.add(cid);progress=True;print('CANDIDATE_REQUIRES_ARTIST_QA',cid,provenance['glb_sha256'],flush=True)
    if not a.follow:break
    if not progress:time.sleep(5)
print('Prepared candidates',len(done),'of',len(ids),'; no ready publication',flush=True)
