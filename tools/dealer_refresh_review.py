#!/usr/bin/env python3
"""Render the actual dealer, summon, fusion and camp UI at both review sizes."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb
out = ROOT / 'build/dealer-refresh'
with xvfb(96, '1280x800') as env:
    for resolution in ['1280x800', '1000x625']:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        for scene in ['dealer_refresh_preview', 'visual_refinement_preview']:
            destination = folder if scene == 'dealer_refresh_preview' else folder / 'aoe'
            destination.mkdir(exist_ok=True)
            p = subprocess.run([str(GODOT), '--path', str(ROOT), '--resolution', resolution, f'res://tests/{scene}.tscn', '--', str(destination)], env=env, text=True, capture_output=True, timeout=180)
            log = p.stdout + p.stderr
            (out / f'{scene}-{resolution}.log').write_text(log)
            print(resolution, scene, log[-2400:], flush=True)
            if p.returncode or 'SCRIPT ERROR:' in log or 'FAIL:' in log:
                raise SystemExit(p.returncode or 1)
        for stem in ['summon', 'fusion']:
            frames = [Image.open(folder / f'{stem}_{i:02d}.png').convert('RGB') for i in range(18)]
            frames[0].save(folder / f'{stem}_playback.gif', save_all=True, append_images=frames[1:], duration=150 if stem == 'summon' else 120, loop=0)
            chosen = [frames[i].resize((640,400)) for i in [0,3,6,9,12,17]]
            sheet=Image.new('RGB',(1920,800))
            for i,frame in enumerate(chosen): sheet.paste(frame,((i%3)*640,(i//3)*400))
            sheet.save(folder / f'{stem}_sequence.png')
