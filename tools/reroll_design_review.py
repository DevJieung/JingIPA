#!/usr/bin/env python3
"""Render title repair and card quota states at both supported review sizes."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/reroll-design"
stems = ["title", "brasa_detail", "draw_basic", "shop_basic", "draw_inactive", "shop_inactive",
         "draw_active", "shop_active", "draw_max", "shop_max", "draw_mixed", "draw_paid",
         "draw_no_gold", "draw_after_click"]
with xvfb(122, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                                 "res://tests/reroll_design_preview.tscn", "--", "--out", str(folder)],
                                env=env, capture_output=True, text=True, timeout=180)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-8000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            sheet = Image.new("RGB", (1280, 430 * ((len(stems) + 1) // 2)), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                frame = Image.open(folder / f"{locale}_{stem}.png").convert("RGB")
                at = ((index % 2) * 640, (index // 2) * 430)
                sheet.paste(frame.resize((640, 400)), at)
                ink.text((at[0] + 8, at[1] + 404), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
