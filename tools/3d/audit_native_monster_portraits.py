#!/usr/bin/env python3
"""Inspect transparent bounds of the same-model creature portraits.

Alpha/margin checks are artifact checks, not a visual identity/style PASS.
"""
import argparse, hashlib, json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--ids', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
manifest = json.loads((ROOT/'art/models/native_monsters.json').read_text())
rows = []
for cid in a.ids.split(','):
    path = ROOT/'art/models/monsters'/(cid+'.png')
    im = Image.open(path).convert('RGBA')
    alpha = im.getchannel('A')
    box = alpha.getbbox()
    if box is None:
        raise ValueError('Empty portrait '+cid)
    x,y,x2,y2 = box
    edge = max(alpha.crop((0,0,im.width,3)).getextrema()[1],alpha.crop((0,im.height-3,im.width,im.height)).getextrema()[1],alpha.crop((0,0,3,im.height)).getextrema()[1],alpha.crop((im.width-3,0,im.width,im.height)).getextrema()[1])
    margin = min(x,y,im.width-x2,im.height-y2)
    rows.append({'id':cid,'path':str(path.relative_to(ROOT)),'size':im.size,'alpha_bbox':box,'minimum_margin':margin,'edge_alpha':edge,'png_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'glb_sha256':manifest['monsters'][cid]['glb_sha256'],'failure':edge>0 or margin<4})
out = Path(a.output)
out.parent.mkdir(parents=True,exist_ok=True)
report = {'purpose':'same-model portrait alpha/margin artifact check; direct visual QA remains separate','portraits':rows,'failures':sum(r['failure'] for r in rows)}
out.write_text(json.dumps(report,indent=2)+'\n')
print('Creature portrait alpha audit',len(rows),'failures',report['failures'])
if report['failures']:
    raise SystemExit(1)
