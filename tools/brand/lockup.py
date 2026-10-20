#!/usr/bin/env python3
"""Finish the baked wordmark lockups (tests/brand/lockup_bake.tscn output).

The viewport renders over transparent black, so the colour it stores is premultiplied by alpha;
this divides it back out (no dark fringe when the cover draws it with normal blending), trims to
the content plus a margin, and writes art/ui/brand_lockup_<ko|en>.png with a mipmapped import.

    python3 tools/brand/lockup.py [--src build/feedback-2026-10-19/D4/lockup] [--write]
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
IMPORT = (ROOT / "art/ui/mindmorph_logo.png.import").read_text().split("[deps]")[0]


def finish(src: Path) -> Image.Image:
    a = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32)
    al = a[..., 3:4] / 255.0
    rgb = np.where(al > 0.004, a[..., :3] / np.maximum(al, 1e-4), 0)
    out = np.dstack([np.clip(rgb, 0, 255), a[..., 3:4]]).astype(np.uint8)
    ys, xs = np.nonzero(out[..., 3] > 2)
    m = 12
    box = (max(0, xs.min() - m), max(0, ys.min() - m), min(out.shape[1], xs.max() + 1 + m), min(out.shape[0], ys.max() + 1 + m))
    return Image.fromarray(out, "RGBA").crop(box)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=str(ROOT / "build/feedback-2026-10-19/D4/lockup"))
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    info = {}
    for loc in ("ko", "en"):
        im = finish(Path(args.src) / f"brand_lockup_{loc}.png")
        preview = Path(args.src) / f"brand_lockup_{loc}_final.png"
        im.save(preview)
        info[loc] = {"size": im.size}
        if args.write:
            dst = ROOT / f"art/ui/brand_lockup_{loc}.png"
            im.save(dst, optimize=True)
            imp = dst.with_suffix(".png.import")
            if not imp.exists():
                imp.write_text(IMPORT.replace('uid="uid://pgapjv2e77vy"\n', "").replace(
                    'path="res://.godot/imported/mindmorph_logo.png-ad2c9764e139c590629956c6b8bf45c5.ctex"\n', ""))
            info[loc]["sha256"] = hashlib.sha256(dst.read_bytes()).hexdigest()
    print(json.dumps(info, indent=1))


if __name__ == "__main__":
    main()
