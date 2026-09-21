#!/usr/bin/env python3
"""그림 위에 격자와 좌표를 얹어 **뼈대 점을 눈으로 찍는다**.

어깨 · 손끝 · 소품 끝을 여기서 읽어 rig 파라미터에 적는다. 눈금은 마스터 픽셀 좌표다.

    python3 tools/anim/probe.py build/frost_queen/master.png            # 격자만
    python3 tools/anim/probe.py build/frost_queen/master.png 88,32 14,50  # 십자 찍기
"""
from __future__ import annotations

import os
import sys

from PIL import Image, ImageDraw

S = 6
MARKS = [(0, 255, 120), (255, 90, 90), (255, 220, 60), (160, 120, 255)]


def main() -> int:
    # ★ `--out <경로>` 로 저장 자리를 따로 줄 수 있다. 안 주면 그림 옆에 probe.png 인데,
    #   그러면 autorig.py 가 만든 probe.png 를 덮어써서 「자동이 뭘 집었는지」가 사라진다.
    argv = list(sys.argv[1:])
    out_path = ""
    if "--out" in argv:
        i = argv.index("--out")
        out_path = argv[i + 1]
        del argv[i:i + 2]
    p = argv[0]
    pts = []
    for s in argv[1:]:
        x, y = s.split(",")
        pts.append((float(x), float(y)))
    im = Image.open(p).convert("RGBA")
    big = Image.new("RGB", (im.width * S, im.height * S), (26, 20, 32))
    up = im.resize((im.width * S, im.height * S), Image.NEAREST)
    big.paste(up, (0, 0), up)
    d = ImageDraw.Draw(big)
    # 10px 마다 옅은 줄, 50px 마다 진한 줄 + 눈금 숫자
    for x in range(0, im.width, 10):
        col = (96, 84, 110) if x % 50 == 0 else (52, 44, 62)
        d.line([(x * S, 0), (x * S, big.height)], fill=col)
        if x % 50 == 0:
            d.text((x * S + 2, 2), str(x), fill=(150, 140, 165))
    for y in range(0, im.height, 10):
        col = (96, 84, 110) if y % 50 == 0 else (52, 44, 62)
        d.line([(0, y * S), (big.width, y * S)], fill=col)
        if y % 50 == 0:
            d.text((2, y * S + 2), str(y), fill=(150, 140, 165))
    for i, (x, y) in enumerate(pts):
        c = MARKS[i % len(MARKS)]
        cx, cy = int(x * S), int(y * S)
        d.line([(cx - 34, cy), (cx + 34, cy)], fill=c, width=2)
        d.line([(cx, cy - 34), (cx, cy + 34)], fill=c, width=2)
        d.text((cx + 6, cy + 6), f"{x:.0f},{y:.0f}", fill=c)
    out = out_path or os.path.join(os.path.dirname(p), "probe.png")
    big.save(out)
    print(out, im.size)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
