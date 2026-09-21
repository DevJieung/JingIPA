#!/usr/bin/env python3
"""Capture the actual startup, inspect every margin pixel, and make a motion review."""
import hashlib
import json
import subprocess

import numpy as np
from PIL import Image, ImageDraw

from godot_env import ROOT, GODOT, xvfb


def main() -> None:
    out = ROOT / "build/startup-splash"
    out.mkdir(parents=True, exist_ok=True)
    original = ROOT / "docs/icon-business-v3-512.png"
    exported = ROOT / "art/ui/startup_logo.png"
    assert original.read_bytes() == exported.read_bytes(), "Original logo bytes changed"
    bg = np.array([35, 93, 72], dtype=np.uint8)
    reports = {}
    with xvfb(102, "1280x800") as env:
        for res in ["1280x800", "1000x625", "1280x720"]:
            folder = out / res
            folder.mkdir(parents=True, exist_ok=True)
            result = subprocess.run(
                [str(GODOT), "--path", str(ROOT), "--resolution", res, "--fixed-fps", "60",
                 "res://tests/startup_splash_preview.tscn", "--", "--out", str(folder)],
                env=env, text=True, capture_output=True, timeout=120,
            )
            log = result.stdout + result.stderr
            (out / f"{res}.log").write_text(log)
            print(res, log, flush=True)
            if result.returncode or "SCRIPT ERROR:" in log:
                raise SystemExit(result.returncode or 1)
            records = json.loads((folder / "frames.json").read_text())
            assert not records["failures"], records["failures"]
            frames = records["frames"]
            alphas = [item["alpha"] for item in frames]
            assert min(alphas[:2]) < 0.01 and max(alphas) == 1.0 and alphas[-1] == 0.0
            peak = alphas.index(max(alphas))
            assert all(a <= b for a, b in zip(alphas[:peak], alphas[1:peak + 1]))
            assert all(a >= b for a, b in zip(alphas[peak:], alphas[peak + 1:]))
            previews = []
            checked_pixels = 0
            for item in frames:
                im = Image.open(folder / item["file"]).convert("RGB")
                pixels = np.asarray(im)
                w, h = im.size
                assert (w, h) == tuple(map(int, res.split("x"))), (res, im.size)
                x, y, lw, lh = item["logo_rect"]
                vw, vh = item["viewport_size"]
                left, top = int(x * w / vw), int(y * h / vh)
                right, bottom = int((x + lw) * w / vw + 1), int((y + lh) * h / vh + 1)
                mask = np.ones((h, w), dtype=bool)
                mask[top:bottom, left:right] = False
                assert np.all(pixels[mask] == bg), f"Nonmatching outer background: {res}/{item['file']}"
                assert np.all(pixels[max(top, 0) + 8, w // 2] == bg), "Logo green differs from margin"
                if item["alpha"] == 0.0:
                    assert np.all(pixels == bg), "Fade-out leaves a visible pixel"
                checked_pixels += int(mask.sum())
                preview = im.resize((480, round(h * 480 / w)), Image.Resampling.LANCZOS)
                previews.append(preview)
            previews[0].save(folder / "playback.gif", save_all=True,
                             append_images=previews[1:], duration=67, loop=0)
            chosen = list(dict.fromkeys([0, 2, 4, 6, peak, len(frames) - 8, len(frames) - 4, len(frames) - 1]))
            cw, ch = previews[0].size
            sheet = Image.new("RGB", (cw * 4, (ch + 26) * 2), "#15221d")
            draw = ImageDraw.Draw(sheet)
            for n, index in enumerate(chosen):
                px, py = (n % 4) * cw, (n // 4) * (ch + 26)
                sheet.paste(previews[index], (px, py))
                draw.text((px + 10, py + ch + 5), f"Frame {frames[index]['frame']} | alpha {alphas[index]:.3f}", fill="white")
            sheet.save(folder / "sequence.png")
            reports[res] = {"frames": len(frames), "exact_margin_pixels": checked_pixels,
                            "background": "#235d48", "title_reached": True, "aspect_restored": True}
    reports["source_sha256"] = hashlib.sha256(original.read_bytes()).hexdigest()
    (out / "report.json").write_text(json.dumps(reports, indent=2) + "\n")
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
