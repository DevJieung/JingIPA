#!/usr/bin/env python3
"""Create contact sheets for human review and verify completed image provenance."""
from pathlib import Path
import argparse
import json
from PIL import Image, ImageOps, ImageDraw
from gen_world_concepts import fingerprint_for

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art/concepts/last_refuge_v3'
ELEMENTS = ['water', 'fire', 'ice', 'elec', 'none']


def sheet(chars, path, cols=5, cell=320):
    h = cell + 36
    board = Image.new('RGB', (cols*cell, ((len(chars)+cols-1)//cols)*h), '#eee9df')
    draw = ImageDraw.Draw(board)
    for i,c in enumerate(chars):
        x, y = (i%cols)*cell, (i//cols)*h
        p = OUT / f"{c['id']}.png"
        if p.exists():
            with Image.open(p) as im:
                thumb = ImageOps.contain(im.convert('RGB'), (cell,cell))
                board.paste(thumb, (x+(cell-thumb.width)//2,y+(cell-thumb.height)//2))
        draw.text((x+12,y+cell+10),f"{c['tier']:02} | {c['id']} | {c['weapon']}", fill='#223333')
    board.save(path, quality=92)


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--complete', action='store_true')
    args=ap.parse_args()
    chars=json.loads((OUT/'characters.json').read_text())
    missing=[]
    for c in chars:
        p=OUT/f"{c['id']}.png"
        if not p.exists():
            missing.append(c['id']);continue
        with Image.open(p) as im:
            assert im.size==(1024,1024),c['id']
            embedded=json.loads(im.info['generation'])
            im.verify()
        meta=json.loads(p.with_suffix('.json').read_text())
        assert embedded==meta,c['id']
        assert meta['fingerprint']==fingerprint_for(c),c['id']
        assert meta['model']=='Krea 2 Turbo',c['id']
    if args.complete:
        assert not missing,missing
    for e in ELEMENTS:
        sheet([c for c in chars if c['element']==e],OUT/f'review_{e}.jpg')
    sheet(sorted(chars,key=lambda c:(c['tier'],ELEMENTS.index(c['element']))),OUT/'overview.jpg',cell=256)
    print(f'{len(chars)-len(missing)}/50 images verified; contact sheets refreshed.')
    if missing:print('Pending:', ', '.join(missing))


if __name__=='__main__':
    main()
