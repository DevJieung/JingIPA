#!/usr/bin/env python3
"""Create a portable review/delivery archive after all 50 exports pass checks."""
import json
import zipfile
from pathlib import Path
from world_h3 import ROOT,OUT
from world_h3_audit import audit
from world_h3_post import gallery
import world_fx

def main():
    chars=json.loads((ROOT/'art/concepts/last_refuge_v3/characters.json').read_text())
    for c in chars:world_fx.build(c,OUT/c['id'])
    result=audit()
    if result['artifact_pass']!=50:
        raise SystemExit('Bundle withheld: all 50 characters must pass the artifact checks.')
    if result['visual_approved']!=50:
        raise SystemExit('Bundle withheld: visual review must be completed for all 50 characters.')
    gallery(chars)
    target=OUT.parent/'last_refuge_v3_pixel_h3.zip'
    roots=['README.md','index.html','effects.html','overview.png','effects_overview.png','review_peak.png','progress.json','audit.json']
    roots += [f'review_{e}.png' for e in ['water','fire','ice','elec','none']]
    files=[OUT/f for f in roots]
    for c in chars:
        p=OUT/c['id']
        files += [f for f in p.iterdir() if f.is_file() and f.suffix in ('.png','.webp','.mp4','.json','.txt') and f.name not in ('resume_prompt.json','post_error.json')]
        for anim in ['idle','attack','shot','effect']:
            files += sorted((p/anim).glob('*.png'))
    with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for f in files:z.write(f,str(f.relative_to(OUT)))
    print(target,round(target.stat().st_size/1048576,1),'MiB',len(files),'files')

if __name__=='__main__':main()
