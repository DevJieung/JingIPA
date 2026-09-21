#!/usr/bin/env python3
"""Render duplicate fusion cards and right-edge menus in both UI languages."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/selection-ui"
with xvfb(110, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/selection_ui_preview.tscn", "--", "--out", str(folder)],
            env=env, capture_output=True, text=True, timeout=150)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-5000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["title", "draw", "fusion_duplicates", "fusion_page_1", "fusion_selected",
                     "shop", "shop_complete", "battle", "over"]
            sheet = Image.new("RGB", (1500, 1020), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                frame = Image.open(folder / f"{locale}_{stem}.png").convert("RGB")
                at = ((index % 3) * 500, (index // 3) * 340)
                sheet.paste(frame.resize((500, 312)), at)
                ink.text((at[0] + 8, at[1] + 315), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
