#!/usr/bin/env python3
"""Extract preserved active-sprite source cells for native character inference.

This is lossless source preprocessing, not a new bitmap character design.
The active sheet name is resolved from anim.json and its larger source cell is
preferred when present. Limne is excluded so its accepted native asset remains.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/hero-native'
p = argparse.ArgumentParser()
p.add_argument('--ids', default='echo,brasa,pip')
p.add_argument('--all', action='store_true')
p.add_argument('--manifest', type=Path, default=ROOT/'tools/3d/character_sources.json')
args = p.parse_args()
profiles = json.loads((ROOT/'art/models/manifest.json').read_text())['heroes']
ids = [i for i in profiles if i != 'limne'] if args.all else args.ids.split(',')
existing = {x['id']:x for x in json.loads(args.manifest.read_text())} if args.manifest.exists() else {}
rows=[]
inputs=OUT/'inputs';inputs.mkdir(parents=True,exist_ok=True)
for cid in ids:
    if cid=='limne': raise ValueError('Limne is accepted and must not be regenerated')
    meta_path=ROOT/f'art/anim/{cid}/anim.json'
    meta=json.loads(meta_path.read_text())
    active=ROOT/f'art/anim/{cid}/{meta["name"]}_idle.png'
    read=meta.get('readability',{})
    source=ROOT/read.get('source','__missing__')
    rects=read.get('source_cells',[])
    if source.is_file() and rects:
        rect=tuple(rects[0]);cell=Image.open(source).convert('RGBA').crop(rect)
    else:
        source=active;sheet=Image.open(active).convert('RGBA')
        rect=(0,0,sheet.width//meta['clips']['idle']['frames'],sheet.height)
        cell=sheet.crop(rect)
    alpha=cell.getchannel('A');box=alpha.getbbox()
    if box is None: raise ValueError(f'{cid}: empty source alpha')
    cell=cell.crop(box);pad=18
    image=Image.new('RGBA',(cell.width+pad*2,cell.height+pad*2))
    image.alpha_composite(cell,(pad,pad))
    dest=inputs/f'{cid}.png';image.save(dest)
    row=existing.get(cid,{'id':cid,'workflow_overrides':{}}).copy()
    row.update(image=str(dest),source=str(source.relative_to(ROOT)),source_rect=rect,
        active_idle=str(active.relative_to(ROOT)),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
        image_sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),preprocess='exact source cell; alpha crop; 18px transparent margin')
    rows.append(row)
args.manifest.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',20)
for page,start in enumerate(range(0,len(rows),18)):
    group=rows[start:start+18];canvas=Image.new('RGB',(6*240,3*320),(19,31,44));d=ImageDraw.Draw(canvas)
    for n,row in enumerate(group):
        im=Image.open(row['image']).convert('RGBA');im.thumbnail((220,275))
        x=(n%6)*240+(240-im.width)//2;y=(n//6)*320+35
        canvas.paste(im,(x,y),im);d.text(((n%6)*240+10,(n//6)*320+5),row['id'],font=font,fill=(236,242,247))
    canvas.save(OUT/f'source-contact-{page+1}.jpg')
print(f'{len(rows)} source inputs, manifest {args.manifest}')
