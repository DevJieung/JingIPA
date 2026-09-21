#!/usr/bin/env python3
"""Render refreshed camp, collection, formation and game-over in both languages."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/camp-refresh"
with xvfb(119, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                                 "res://tests/camp_refresh_preview.tscn", "--", "--out", str(folder)],
                                env=env, capture_output=True, text=True, timeout=240)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-6000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["title_records", "collection_water", "upgrades", "upgrades_max", "passives_owned",
                     "passives_all_3", "formation_new", "formation_selected", "formation_reserve",
                     "fusion", "fusion_selected", "over"]
            sheet = Image.new("RGB", (1500, 1360), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                path = folder / f"{locale}_{stem}.png"
                if not path.exists():
                    continue
                frame = Image.open(path).convert("RGB")
                at = ((index % 3) * 500, (index // 3) * 340)
                sheet.paste(frame.resize((500, 312)), at)
                ink.text((at[0] + 8, at[1] + 315), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
