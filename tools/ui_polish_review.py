#!/usr/bin/env python3
"""Actual Godot rendering of bilingual poker, rewards and camp hero details."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb
out = ROOT / 'build/ui-polish'
with xvfb(97, '1280x800') as env:
    for resolution in ['1280x800', '1000x625']:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), '--path', str(ROOT), '--resolution', resolution, 'res://tests/ui_polish_preview.tscn', '--', '--out', str(folder)], env=env, text=True, capture_output=True, timeout=180)
        log = result.stdout + result.stderr
        (out / f'{resolution}.log').write_text(log)
        print(resolution, log[-4000:], flush=True)
        if result.returncode or 'SCRIPT ERROR:' in log or '판정: 실패' in log:
            raise SystemExit(result.returncode or 1)
        for locale in ['ko', 'en']:
            files = [folder / f'{locale}_{stem}.png' for stem in ['title', 'poker', 'poker_no_gold', 'hero_pip', 'hero_thalassa', 'camp_deployment', 'camp_roster', 'camp_info', 'reward_notice', 'fusion_result', 'camp_u', 'camp_p', 'menu_menu', 'menu_rules', 'menu_hands', 'menu_elements', 'battle', 'battle_result', 'over']]
            sheet = Image.new('RGB', (1500, 2380), '#101a22')
            ink = ImageDraw.Draw(sheet)
            for i, path in enumerate(files):
                img = Image.open(path).convert('RGB').resize((500, 312))
                at = ((i % 3) * 500, (i // 3) * 340)
                sheet.paste(img, at)
                ink.text((at[0] + 8, at[1] + 315), path.stem, fill='#f6c445')
            sheet.save(folder / f'{locale}_contact.jpg')
