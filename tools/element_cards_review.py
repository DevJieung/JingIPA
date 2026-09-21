#!/usr/bin/env python3
"""Render element card palettes, protection, roster, detail and result screens."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/element-cards"
with xvfb(112, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/element_cards_preview.tscn", "--", "--out", str(folder)],
            env=env, capture_output=True, text=True, timeout=150)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-5000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["palette", "formation", "roster", "fusion_locked", "fusion_selected",
                     "detail_thalassa", "detail_morrigan", "detail_sigrid", "detail_lugh",
                     "summon_thalassa", "summon_brasa", "summon_blank",
                     "fusion_result_thalassa", "fusion_result_sigrid", "fusion_result_lugh"]
            stems = [stem for stem in stems if (folder / f"{locale}_{stem}.png").exists()]
            sheet = Image.new("RGB", (1500, ((len(stems) + 2) // 3) * 340), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                with Image.open(folder / f"{locale}_{stem}.png") as frame:
                    at = ((index % 3) * 500, (index // 3) * 340)
                    sheet.paste(frame.resize((500, 312)).convert("RGB"), at)
                    ink.text((at[0] + 8, at[1] + 315), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
