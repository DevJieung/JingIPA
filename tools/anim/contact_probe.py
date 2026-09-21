#!/usr/bin/env python3
"""probe.png 여러 장을 한 판에 이어 붙인다 — 리그 점을 **한 번에** 눈으로 보려고.

    python3 tools/anim/contact_probe.py            # build/*/probe.png 전부
    python3 tools/anim/contact_probe.py a b c      # 고른 것만

★ 서른 명을 한 장씩 열어 보면 서른 번 봐야 한다. 여섯씩 묶으면 다섯 번이면 된다.
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    repo = os.path.dirname(root)
    names = sys.argv[1:]
    if not names:
        names = sorted(d for d in os.listdir(os.path.join(repo, "build"))
                       if os.path.exists(os.path.join(repo, "build", d, "probe.png")))
    imgs = []
    for n in names:
        p = os.path.join(repo, "build", n, "probe.png")
        if os.path.exists(p):
            imgs.append((n, Image.open(p).convert("RGBA")))
    if not imgs:
        print("probe.png 가 없다")
        return 1
    pad, lab = 10, 16
    H = max(im.height for _, im in imgs) + pad * 2 + lab
    W = sum(im.width + pad for _, im in imgs) + pad
    sheet = Image.new("RGBA", (W, H), (24, 26, 34, 255))
    d = ImageDraw.Draw(sheet)
    x = pad
    for n, im in imgs:
        sheet.paste(im, (x, pad), im)
        d.text((x, H - lab), n[:18], fill=(200, 205, 215, 255))
        x += im.width + pad
    out = os.path.join(repo, "build", "contact_probe.png")
    sheet.save(out)
    print("만들었습니다: %s (%d명)" % (out, len(imgs)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
