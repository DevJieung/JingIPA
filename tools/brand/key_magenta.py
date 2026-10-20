#!/usr/bin/env python3
"""Key a painted asset off its flat magenta background (D4 brand emblem).

    python3 tools/brand/key_magenta.py in.png out.png [--lo 0.18 --hi 0.62]

alpha from m = min(R, B) - G (1 on #FF00FF, ~0 on gold, teal, white and dark ink), then the
colour is un-mixed from the measured background (C = aF + (1-a)B), small islands are dropped
and the largest component is kept. Prints coverage and the bounding box.
"""
from __future__ import annotations

import argparse
import json

import cv2
import numpy as np
from PIL import Image


def key(img: np.ndarray, lo: float, hi: float) -> np.ndarray:
    f = img.astype(np.float32) / 255.0
    border = np.concatenate([f[:8].reshape(-1, 3), f[-8:].reshape(-1, 3), f[:, :8].reshape(-1, 3), f[:, -8:].reshape(-1, 3)])
    bgc = np.median(border, 0)
    m = np.minimum(f[..., 0], f[..., 2]) - f[..., 1]
    m_bg = float(np.minimum(bgc[0], bgc[2]) - bgc[1])
    t = np.clip((m - lo * m_bg) / ((hi - lo) * m_bg), 0, 1)
    alpha = 1.0 - t * t * (3 - 2 * t)
    # keep the largest solid component (+ everything attached), drop specks
    solid = (alpha > 0.5).astype(np.uint8)
    n, lab, stats, _ = cv2.connectedComponentsWithStats(solid, 8)
    if n > 1:
        big = 1 + int(np.argmax(stats[1:, cv2.CC_STAT_AREA]))
        keep = (lab == big).astype(np.uint8)
        keep = cv2.dilate(keep, np.ones((5, 5), np.uint8), iterations=2)
        alpha *= keep
    a = alpha[..., None]
    fg = np.where(a > 0.02, (f - (1 - a) * bgc) / np.maximum(a, 1e-3), 0)
    fg = np.clip(fg, 0, 1)
    # residual magenta spill on the rim: pull G up / R,B down where the pixel is still magenta-ish
    spill = np.clip(np.minimum(fg[..., 0], fg[..., 2]) - fg[..., 1], 0, 1) * (a[..., 0] < 0.98)
    fg[..., 0] -= spill * 0.5
    fg[..., 2] -= spill * 0.5
    out = np.dstack([np.clip(fg, 0, 1), alpha])
    return (out * 255 + 0.5).astype(np.uint8), bgc


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--lo", type=float, default=0.18)
    ap.add_argument("--hi", type=float, default=0.62)
    args = ap.parse_args()
    img = np.array(Image.open(args.src).convert("RGB"))
    out, bgc = key(img, args.lo, args.hi)
    Image.fromarray(out, "RGBA").save(args.dst)
    a = out[..., 3]
    ys, xs = np.nonzero(a > 128)
    print(json.dumps({"bg": [round(float(v) * 255) for v in bgc], "coverage": round(float((a > 128).mean()), 4),
                      "bbox": [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())] if len(xs) else None}))


if __name__ == "__main__":
    main()
