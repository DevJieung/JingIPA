#!/usr/bin/env python3
"""Inspect genuine free placements and the lightweight 3D lighting at both sizes."""
import argparse
import json
import subprocess
import sys
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from godot_env import ROOT, GODOT, ensure_xvfb, xvfb

parser = argparse.ArgumentParser()
parser.add_argument('--res', action='append')
args = parser.parse_args()
ensure_xvfb()
report = {'renderer': 'gl_compatibility', 'resolutions': {}, 'device_fps_measured': False}
for index, res in enumerate(args.res or ['1280x800', '1000x625']):
    out = ROOT / 'build/free-placement-render' / res
    out.mkdir(parents=True, exist_ok=True)
    with xvfb(101 + index, res) as env:
        result = subprocess.run([str(GODOT), '--path', str(ROOT), '--resolution', res,
            'res://tests/3d/free_placement_visual_preview.tscn', '--', '--out', str(out)],
            env=env, capture_output=True, text=True, timeout=600)
    log = result.stdout + '\n' + result.stderr
    (out / 'render.log').write_text(log)
    if result.returncode or 'ERROR:' in log or '!! ' in log:
        print(log)
        sys.exit(1)
    for locale in ['ko', 'en']:
        files = [out / f'{locale}_{state}.png' for state in
            ['formation', 'selected', 'valid', 'invalid', 'battle', 'battle_selected', 'battle_orbit']]
        contact = Image.new('RGB', (1280, 800), (12, 22, 32))
        for n, path in enumerate(files):
            shot = Image.open(path).convert('RGB')
            shot.thumbnail((426, 267))
            contact.paste(shot, (n % 3 * 426, n // 3 * 267))
        contact.save(out / f'{locale}_contact.jpg', quality=93)
        frames = [Image.open(out / f'{locale}_motion_{n:02d}.png').convert('RGB') for n in range(8)]
        frames[0].save(out / f'{locale}_battle_motion.gif', save_all=True,
            append_images=frames[1:], duration=100, loop=0)
        motion = Image.new('RGB', (426*4, 267*2), (12, 22, 32))
        for n, shot in enumerate(frames):
            shot.thumbnail((426, 267))
            motion.paste(shot, (n % 4 * 426, n // 4 * 267))
        motion.save(out / f'{locale}_motion_contact.jpg', quality=93)
    report['resolutions'][res] = {'screenshots': len(list(out.glob('*.png'))),
        'geometry': json.loads((out / 'geometry.json').read_text()), 'render_errors': 0}
    print(res, 'free-position and actual rendering captures passed')
(ROOT / 'build/free-placement-render/report.json').write_text(json.dumps(report, indent=2) + '\n')
