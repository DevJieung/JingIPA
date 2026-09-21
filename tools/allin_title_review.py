#!/usr/bin/env python3
"""Check the All-in title, explicit language choices and cleaned upgrade rows."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/allin-title"
with xvfb(120, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                                 "res://tests/allin_title_preview.tscn", "--", "--out", str(folder)],
                                env=env, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-6000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["title_new", "title_continue", "upgrades_middle", "upgrades_max", "battle", "fusion", "menu", "collection"]
            sheet = Image.new("RGB", (1280, 1720), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                frame = Image.open(folder / f"{locale}_{stem}.png").convert("RGB")
                at = ((index % 2) * 640, (index // 2) * 430)
                sheet.paste(frame.resize((640, 400)), at)
                ink.text((at[0] + 8, at[1] + 404), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
