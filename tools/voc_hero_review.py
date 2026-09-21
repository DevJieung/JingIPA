#!/usr/bin/env python3
"""Render VOC hero cards, formation, blank slots and continue reward in both languages."""
import subprocess
from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

out = ROOT / "build/voc-hero"
with xvfb(132, "1280x800") as env:
    for resolution in ["1280x800", "1000x625"]:
        folder = out / resolution
        folder.mkdir(parents=True, exist_ok=True)
        result = subprocess.run([str(GODOT), "--path", str(ROOT), "--resolution", resolution,
                                 "res://tests/voc_hero_preview.tscn", "--", "--out", str(folder)],
                                env=env, capture_output=True, text=True, timeout=240)
        log = result.stdout + result.stderr
        (out / f"{resolution}.log").write_text(log)
        print(resolution, log[-6000:], flush=True)
        if result.returncode or "ERROR:" in log or "판정: 정상" not in log:
            raise SystemExit(result.returncode or 1)
        for locale in ["ko", "en"]:
            stems = ["formation", "formation_selected", "hero_cards", "hero_detail", "empty_slots", "fusion",
                     "summon", "reward_brian", "reward_nerea", "reward_brasa", "reward_isa", "reward_zero"]
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
            frames = [Image.open(p).convert("RGB").resize((800, 500))
                      for p in sorted(folder.glob(f"{locale}_reward_motion_*.png"))]
            if frames:
                motion = Image.new("RGB", (1500, 1014), "#101a22")
                motion_ink = ImageDraw.Draw(motion)
                for index, frame in enumerate(frames):
                    at = ((index % 3) * 500, (index // 3) * 338)
                    motion.paste(frame.resize((500, 312)), at)
                    motion_ink.text((at[0] + 8, at[1] + 315), f"{locale}_reward_motion_{index:02d}", fill="#f6c445")
                motion.save(folder / f"{locale}_reward_motion_contact.jpg")
                frames[0].save(folder / f"{locale}_reward_motion.gif", save_all=True,
                               append_images=frames[1:], duration=[160, 180, 160, 250, 350, 400, 700, 1800, 800], loop=0)
