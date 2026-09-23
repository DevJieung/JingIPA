#!/usr/bin/env python3
"""Render actual rewarded fusion restoration and gold revival in Korean and English."""
import subprocess

from PIL import Image, ImageDraw

from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/revive-fusion"
with xvfb(139, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run(
            [str(GODOT), "--path", str(ROOT), "--resolution", resolution,
             "res://tests/revive_fusion_preview.tscn", "--", "--out", str(folder)],
            env=env, capture_output=True, text=True, timeout=240)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-7000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["fusion_average", "fusion_four", "fusion_result", "fusion_restored",
                     "camp_fusion_restored", "normal_over", "normal_gold_reward",
                     "all_owned_gold_reward", "normal_camp_upgrades", "normal_camp_formation",
                     "normal_camp_empty", "camp_fusion_average"]
            sheet = Image.new("RGB", (1500, 1360), "#101a22")
            ink = ImageDraw.Draw(sheet)
            for index, stem in enumerate(stems):
                frame = Image.open(folder / f"{locale}_{stem}.png").convert("RGB")
                at = ((index % 3) * 500, (index // 3) * 340)
                sheet.paste(frame.resize((500, 312)), at)
                ink.text((at[0] + 8, at[1] + 315), stem, fill="#f6c445")
            sheet.save(folder / f"{locale}_contact.jpg")
            for animation in ["restore", "gold"]:
                frames = [Image.open(p).convert("RGB") for p in sorted(folder.glob(f"{locale}_{animation}_motion_*.png"))]
                contact = Image.new("RGB", (1500, 1014), "#101a22")
                for index, frame in enumerate(frames):
                    contact.paste(frame.resize((500, 312)), ((index % 3) * 500, (index // 3) * 338))
                contact.save(folder / f"{locale}_{animation}_motion_contact.jpg")
                resized = [frame.resize((800, 500)) for frame in frames]
                resized[0].save(folder / f"{locale}_{animation}_motion.gif", save_all=True,
                                append_images=resized[1:], duration=[160, 180, 160, 250, 250, 350, 450, 700, 800], loop=0)
