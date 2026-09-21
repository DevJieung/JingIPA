#!/usr/bin/env python3
"""Render bilingual direct card choice and exercise real UI -> Ads -> Run wiring."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/card-choice-restored"
with xvfb(108, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/card_choice_preview.tscn", "--", "--out", str(folder)],
            env=env, capture_output=True, text=True, timeout=150)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-5000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["free", "paid", "no_gold", "empty", "suit_0", "suit_1",
                     "suit_2", "suit_3", "selected", "retry", "royal_preview", "royal_current",
                     "notice_0", "notice_1", "notice_2", "connecting", "reward_00", "reward_05"]
            sheet = Image.new("RGB", (1500, 2040), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for i, stem in enumerate(stems):
                frame = Image.open(folder / f"{locale}_{stem}.png").convert("RGB")
                at = ((i % 3) * 500, (i // 3) * 340)
                sheet.paste(frame.resize((500, 312)), at)
                ink.text((at[0] + 8, at[1] + 315), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
            sequence = [Image.open(folder / f"{locale}_reward_{i:02}.png").convert("RGB") for i in range(6)]
            sequence[0].save(folder / f"{locale}_reward.gif", save_all=True,
                             append_images=sequence[1:], duration=90, loop=0)
