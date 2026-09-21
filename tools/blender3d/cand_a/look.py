#!/usr/bin/env python3
"""눈으로 볼 판 — 낱장을 3배로 키워 한 줄로 잇는다. (반복할 때마다 쓴다)"""
import sys, glob
from pathlib import Path
from PIL import Image

def strip(paths, zoom=3, pad=2, bg=(28, 28, 34)):
    ims = [Image.open(p).convert("RGBA") for p in paths]
    if not ims:
        return None
    w, h = ims[0].size
    W = (w * zoom + pad) * len(ims) + pad
    H = h * zoom + pad * 2
    out = Image.new("RGBA", (W, H), bg + (255,))
    for i, im in enumerate(ims):
        z = im.resize((w * zoom, h * zoom), Image.NEAREST)
        out.alpha_composite(z, (pad + i * (w * zoom + pad), pad))
    return out

if __name__ == "__main__":
    rows = []
    for pat in sys.argv[2:]:
        ps = sorted(glob.glob(pat))
        s = strip(ps)
        if s:
            rows.append(s)
    W = max(r.width for r in rows); H = sum(r.height for r in rows)
    out = Image.new("RGBA", (W, H), (28, 28, 34, 255))
    y = 0
    for r in rows:
        out.paste(r, (0, y)); y += r.height
    out.save(sys.argv[1])
    print(sys.argv[1], out.size)
