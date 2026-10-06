#!/usr/bin/env python3
"""Review sigil/value/fusion/support UI, all 50 terrains, and combat motion in Godot."""
import subprocess
from godot_env import ROOT, GODOT, xvfb

out = ROOT / 'build/progression-design'
out.mkdir(parents=True, exist_ok=True)
with xvfb(108, '1280x800') as env:
    for resolution in ['1280x800', '1000x625']:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), '--path', str(ROOT), '--resolution', resolution,
            'res://tests/progression_design_preview.tscn', '--', '--out', str(folder)],
            env=env, capture_output=True, text=True, timeout=360)
        log=result.stdout+result.stderr
        (out / (resolution+'.log')).write_text(log)
        print(resolution, log[-6500:],flush=True)
        if result.returncode or 'SCRIPT ERROR:' in log or '판정: 실패' in log:
            raise SystemExit(result.returncode or 1)
