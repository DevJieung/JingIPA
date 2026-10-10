#!/usr/bin/env python3
"""Prepare retained native creature surfaces; never publish a visual PASS.

Independent per-ID source processing, authored anatomy/loop diagnostics and
actual studio renders. A designer must still inspect those and engine motion.
"""
import argparse, json, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--ids', required=True)
p.add_argument('--follow', action='store_true')
p.add_argument('--raw', default='build/character-3d/monster-raw')
a = p.parse_args()
done = set()
ids = a.ids.split(',')

def run(cid, label, script, arguments):
    folder = ROOT/'build/character-3d/monster-review'/cid
    folder.mkdir(parents=True, exist_ok=True)
    log = folder/(label+'.log')
    with log.open('w') as handle:
        result = subprocess.run(['bl','-b','--factory-startup','--python',str(ROOT/'tools/3d'/script),'--',*arguments], stdout=handle, stderr=subprocess.STDOUT, cwd=ROOT)
    text = log.read_text()
    if result.returncode or 'Traceback (most recent call last)' in text or 'Error: Python:' in text:
        raise RuntimeError(str(log))

while len(done) < len(ids):
    progress = False
    for cid in ids:
        if cid in done:
            continue
        manifest = json.loads((ROOT/'art/models/native_monsters.json').read_text())
        if cid in manifest['ready_ids']:
            done.add(cid)
            continue
        raw = ROOT/a.raw/cid/'model.glb'
        if not raw.exists():
            continue
        run(cid,'candidate-finish','finish_native_monster.py',['--id',cid,'--input',str(raw)])
        source = ROOT/'build/character-3d/monster-source'/cid/'game.blend'
        folder = ROOT/'build/character-3d/monster-review'/cid
        prov = json.loads((ROOT/'art/models/monsters'/cid/'provenance.json').read_text())
        run(cid,'deformation','check_native_monster_deformation.py',['--input',str(source),'--output',str(folder/'deformation.json')])
        for clip,frame,label in [('IdleLoop',0,'candidate-idle'),('MoveLoop',8,'candidate-move')]:
            run(cid,label,'render_native_studio.py',['--input',str(source),'--out',str(folder/label),'--clip',clip,'--frame',str(frame),'--height',str(prov['height']),'--quick'])
        done.add(cid)
        progress = True
        print('CREATURE_CANDIDATE_REQUIRES_ACTUAL_QA',cid,prov['glb_sha256'],flush=True)
    if not a.follow:
        break
    if not progress:
        time.sleep(5)
print('Prepared creature candidates',len(done),'of',len(ids),'; not a ready publication')
