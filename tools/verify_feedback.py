#!/usr/bin/env python3
"""Run checks for the dealer/UI/audio refresh with saves protected."""
import os
from pathlib import Path
import subprocess
import sys
from godot_env import GODOT, ROOT, xvfb

OUT = ROOT / 'build/feedback-verification'
SCENES = ['rules_check', 'range_check', 'flow_check', 'presentation_check', 'element_aoe_check', 'aoe_scope_check', 'all_hero_sprites_check', 'ns_check', 'audio_check']

def run(label, args, env, expected='판정: 정상'):
    result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True, timeout=240)
    output = result.stdout + result.stderr
    (OUT / (label + '.log')).write_text(output)
    passed = result.returncode == 0 and (not expected or expected in output) and not any(x in output for x in ['SCRIPT ERROR', 'ERROR:', '판정: 실패'])
    print(('PASS ' if passed else 'FAIL ') + label, flush=True)
    if not passed:
        print(output[-3000:])
    return passed

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, POCKER_NO_SAVE='1')
    good = run('audio_files', [sys.executable, 'tools/audio/check_audio.py'], env, 'PASS:')
    good = run('import', [str(GODOT), '--headless', '--path', str(ROOT), '--editor', '--import'], env, '') and good
    for scene in SCENES:
        args = [str(GODOT), '--headless', '--path', str(ROOT), f'res://tests/{scene}.tscn']
        if scene == 'ns_check':
            args += ['--', '--strict']
        scene_env = dict(env, POCKER_AUDIO_TEST='1') if scene == 'audio_check' else env
        good = run(scene, args, scene_env) and good
    for res in ['1280x800', '1000x625']:
        with xvfb(97, res) as render_env:
            good = run('input_' + res, [str(GODOT), '--path', str(ROOT), '--resolution', res, 'res://tests/feedback_check.tscn'], render_env) and good
    return 0 if good else 1

if __name__ == '__main__':
    raise SystemExit(main())
