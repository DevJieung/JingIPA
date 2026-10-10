#!/usr/bin/env python3
"""Assemble reviewed actual engine galleries, never raster target references.

Every tile pins its runtime GLB hash to actual two-resolution review evidence.
This is a presentation index, not a replacement for direct visual QA or FPS.
"""
import argparse, hashlib, json, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--output', default='build/character-3d/review/native-overview.png')
p.add_argument('--complete', action='store_true')
a = p.parse_args()
hero = json.loads((ROOT/'art/models/native_heroes.json').read_text())
monster = json.loads((ROOT/'art/models/native_monsters.json').read_text())
hr = json.loads((ROOT/'build/character-3d/review/report.json').read_text())['heroes']
mr = json.loads((ROOT/'build/character-3d/monster-review/report.json').read_text())['monsters']
lr = json.loads((ROOT/'build/limne-game-motion/game-review/report.json').read_text())
groups = [('Heroes', []), ('Monsters', [])]
groups[0][1].append(('limne', 'art/models/limne/limne.glb', lr,
                    'build/limne-game-motion/game-review/1000x625/gallery_three_quarter.png'))
for cid in hero['ready_ids']:
    groups[0][1].append((cid, hero['heroes'][cid]['path'].removeprefix('res://'),
                        hr[cid], f'build/character-3d/review/{cid}/1000x625/gallery_three_quarter.png'))
for cid in monster['ready_ids']:
    groups[1][1].append((cid, monster['monsters'][cid]['path'].removeprefix('res://'),
                        mr[cid], f'build/character-3d/monster-review/{cid}/1000x625/gallery_three_quarter.png'))
if a.complete and (len(groups[0][1]) != 50 or len(groups[1][1]) != 25):
    raise ValueError('Complete overview requires all 50 heroes and 25 reviewed monsters')
columns, cell_w, cell_h = 10, 190, 248
total = sum(len(g[1]) for g in groups)
height = 108 + sum(48+math.ceil(len(g[1])/columns)*cell_h for g in groups) + 42
sheet = Image.new('RGB', (columns*cell_w, height), '#142131')
draw = ImageDraw.Draw(sheet)
font_path = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
title = ImageFont.truetype(font_path, 26)
body = ImageFont.truetype(font_path, 15)
small = ImageFont.truetype(font_path, 11)
draw.text((24, 18), f'Actual native game models reviewed: {total}/75', font=title, fill='#f1ead7')
draw.text((24, 58), 'Actual Godot galleries / approved Limne preserved / editable skin and motion', font=body, fill='#b7cddd')
records, top = [], 108
for group, entries in groups:
    draw.text((24, top), f'{group} {len(entries)}/{50 if group == "Heroes" else 25}', font=title, fill='#f3d6a1' if group=='Heroes' else '#98dfdb')
    top += 48
    for n, (cid, source, report, capture) in enumerate(entries):
        sha = hashlib.sha256((ROOT/source).read_bytes()).hexdigest()
        if sha != report['glb_sha256']:
            raise ValueError('Stale actual model tile: '+cid)
        for res in ['1280x800', '1000x625']:
            if report['resolutions'][res]['render_errors']:
                raise ValueError('Failed actual capture: '+cid)
        image = Image.open(ROOT/capture).convert('RGBA')
        bounds = image.getchannel('A').point(lambda x: 255 if x > 8 else 0).getbbox()
        if bounds:
            image = image.crop(bounds)
        image.thumbnail((cell_w-24, cell_h-54))
        x, y = (n%columns)*cell_w, top+(n//columns)*cell_h
        draw.rounded_rectangle((x+5,y+3,x+cell_w-5,y+cell_h-5), radius=9, fill='#1c2d40')
        sheet.paste(image, (x+(cell_w-image.width)//2, y+8+(cell_h-58-image.height)//2), image)
        draw.text((x+12,y+cell_h-39), cid, font=body, fill='#edf2f6')
        draw.text((x+12,y+cell_h-18), sha[:12], font=small, fill='#8fa9bc')
        records.append({'id':cid,'group':group,'glb':source,'glb_sha256':sha,'actual_capture':capture})
    top += math.ceil(len(entries)/columns)*cell_h
draw.text((24,height-29), 'Source/render identity proof; mobile device FPS has not been measured.', font=body, fill='#a4b9cb')
output = ROOT/a.output
output.parent.mkdir(parents=True, exist_ok=True)
sheet.save(output)
output.with_suffix('.json').write_text(json.dumps({'reviewed_count':total,'expected_count':75,'complete':a.complete,'tiles':records},indent=2)+'\n')
print('Actual model overview', total, output)
