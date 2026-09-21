#!/usr/bin/env python3
"""Render the UI refinement fixtures and interaction checks at both review sizes."""
from __future__ import annotations

from pathlib import Path
import shutil
import subprocess

from PIL import Image, ImageDraw
from godot_env import ROOT, GODOT, xvfb

OUT = ROOT / "build/visual-refinement"


def evidence(folder: Path, res: str) -> None:
    ratio = int(res.split("x")[0]) / 1280
    for stem, indexes, crop in [
        ("push", range(0, 19, 2), (80, 240, 220, 425)),
        ("stun", range(8), (55, 155, 820, 435)),
        ("area", range(9), (18, 423, 1262, 705)),
    ]:
        frames = [Image.open(folder / f"{stem}_{i:02d}.png").convert("RGB") for i in indexes]
        rect = tuple(round(n * ratio) for n in crop)
        crops = [im.crop(rect) for im in frames]
        if stem == "push":
            crops = [im.resize((im.width * 2, im.height * 2), Image.Resampling.NEAREST) for im in crops]
        cols = 5 if stem == "push" else 2
        w, h = crops[0].size
        sheet = Image.new("RGB", (w * cols, (h + 25) * ((len(crops) + cols - 1) // cols)), "#10181e")
        draw = ImageDraw.Draw(sheet)
        for i, (im, index) in enumerate(zip(crops, indexes)):
            x, y = (i % cols) * w, (i // cols) * (h + 25)
            sheet.paste(im, (x, y + 25))
            draw.text((x + 8, y + 5), f"{stem} frame {index:02d}", fill="white")
        sheet.save(folder / f"{stem}_sequence.png")
        frames[0].save(folder / f"{stem}_playback.gif", save_all=True, append_images=frames[1:],
                       duration=40 if stem == "push" else 100, loop=0)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with xvfb(95, "1280x800") as env:
        for resolution in ["1280x800", "1000x625"]:
            folder = OUT / resolution
            folder.mkdir(exist_ok=True)
            for scene in ["visual_refinement_preview", "rewards_ui_check"]:
                cmd = [str(GODOT), "--path", str(ROOT), "--resolution", resolution, f"res://tests/{scene}.tscn"]
                if scene == "visual_refinement_preview":
                    cmd += ["--", str(folder)]
                run = subprocess.run(cmd, env=env, text=True, capture_output=True, timeout=120)
                log = run.stdout + run.stderr
                (OUT / f"{scene}-{resolution}.log").write_text(log)
                print(resolution, scene, log, flush=True)
                if run.returncode or "SCRIPT ERROR:" in log or "FAIL:" in log or "\n!! " in log:
                    raise SystemExit(run.returncode or 1)
                if scene == "rewards_ui_check":
                    for source in (ROOT / "build").glob("*-rewards.png"):
                        shutil.copyfile(source, folder / source.name)
                    for name in ["fusion-selected.png", "fusion-result.png"]:
                        shutil.copyfile(ROOT / "build" / name, folder / name)
            evidence(folder, resolution)


if __name__ == "__main__":
    main()
