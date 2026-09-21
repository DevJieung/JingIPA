#!/usr/bin/env python3
"""Measure boxed copy and capture every course in both locales and review sizes."""
import json
import re
import subprocess
from collections import Counter
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / 'build/text-course'
out.mkdir(parents=True, exist_ok=True)
sites = []
for folder in ['core', 'game']:
    for path in sorted((ROOT / folder).glob('*.gd')):
        for line, source in enumerate(path.read_text().splitlines(), 1):
            if re.search(r'\b(?:Look\.)?(?:text_(?:left|right|center|center_fit|box|center_out)|wrap_text|button|reward_button|tab)\(', source):
                sites.append({'file': str(path.relative_to(ROOT)), 'line': line, 'source': source.strip()})
(out / 'source-inventory.json').write_text(json.dumps(sites, ensure_ascii=False, indent=2))
with xvfb(124, '1280x800') as env:
    for resolution in ['1280x800', '1000x625']:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), '--path', str(ROOT), '--resolution', resolution,
                                 'res://tests/text_course_preview.tscn', '--', '--out', str(folder)],
                                env=env, capture_output=True, text=True, timeout=400)
        log = result.stdout + result.stderr
        (out / f'{resolution}.log').write_text(log)
        print(resolution, log[-6000:], flush=True)
        if result.returncode or 'ERROR:' in log or '판정: 정상' not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ['ko', 'en']:
            for label, images in [('courses', sorted(folder.glob(f'{locale}_course_*.png'))),
                                  ('screens', sorted(p for p in folder.glob(f'{locale}_*.png') if '_course_' not in p.name))]:
                sheet = Image.new('RGB', (1280, ((len(images) + 3)//4)*225), '#101a22')
                ink = ImageDraw.Draw(sheet)
                for index, path in enumerate(images):
                    frame = Image.open(path).convert('RGB').resize((320, 200))
                    at = ((index % 4)*320, (index//4)*225)
                    sheet.paste(frame, at)
                    ink.text((at[0]+5, at[1]+203), path.stem, fill='#f6c445')
                sheet.save(folder / f'{locale}_{label}_contact.jpg')
