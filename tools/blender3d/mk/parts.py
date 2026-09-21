#!/usr/bin/env python3
"""최종본 · **부위별 색 추출** (후보 C 가 이긴 수 6번).

    python3 tools/blender3d/mk/parts.py

원화 한 장이 아니라 **3면도 세 장**(앞·옆·뒤)에서 부위 대표색을 뽑는다.
후보 셋은 3면도를 못 썼다 — 뒤·옆 색을 알 길이 없어서 망토와 등판을 지어냈다.

## 왜 「대표색」인가
후보 C 의 본론(원화를 텍스처로 투영)은 96px 에서 무너졌다(양자화 전 고유색 1794개 ·
팔레트까지 평균 거리 26.3). 남은 것은 갈래 2 뿐이다 — **부위마다 색 하나**를 뽑아
재질에 배정하면 양자화 전 원본이 이미 팔레트에 가깝다(평균 거리 2.07).

## 어떻게 뽑는가
부위마다 3면도 위의 네모를 손으로 찍어 두고(아래 `BOXES`), 그 안에서
**가장 많이 나온 색**을 고른다. 평균이 아니라 최빈값인 까닭: 평균은 경계의 검은
테두리와 흰 배경을 같이 먹어서 **실제로 그림에 없는 색**을 만든다.
그다음 15색 팔레트에서 가장 가까운 칸으로 접는다(가중 RGB 거리).
"""
from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import spec  # noqa: E402

REF = spec.OUT / "jokull" / "1_turnaround"

#: 부위 → [(그림, x0,y0,x1,y1), …]  (512x512 3면도 좌표. 눈으로 찍었다)
BOXES = {
    "fur_lit":    [("front", 132, 133, 190, 165), ("side", 210, 90, 300, 150)],
    "fur_mid":    [("front", 104, 168, 150, 200), ("side", 150, 180, 220, 250)],
    "fur_dark":   [("front", 300, 178, 330, 196), ("side", 130, 250, 175, 275)],
    "beard":      [("front", 268, 92, 330, 150)],
    "skin_lit":   [("front", 276, 58, 296, 72)],
    "skin_mid":   [("front", 282, 36, 302, 47)],
    "coat_lit":   [("front", 330, 190, 370, 215), ("side", 330, 200, 360, 240)],
    "coat_mid":   [("front", 207, 260, 240, 300), ("side", 300, 300, 340, 360)],
    "coat_dark":  [("front", 140, 200, 187, 247), ("side", 200, 210, 260, 300)],
    "sash":       [("front", 287, 310, 320, 400)],
    "belt":       [("front", 233, 262, 317, 276)],
    "boot":       [("front", 176, 486, 205, 508), ("side", 250, 486, 300, 508)],
    "cape_mid":   [("back", 300, 300, 380, 420), ("side", 140, 300, 190, 400)],
    "cape_dark":  [("back", 160, 340, 215, 430), ("side", 155, 385, 200, 435)],
    "cape_lit":   [("back", 380, 250, 440, 330)],
    "trim":       [("front", 180, 424, 250, 452), ("back", 300, 440, 380, 470)],
}

#: 이 부위는 **팔레트에서 이 칸 안에서만** 고른다. 없으면 15색 전부에서 고른다.
#: ★ 살결이 파랑으로 접히는 것을 막는다 — 얼굴은 이 그림에서 유일한 따뜻한 색이라
#:   가장 가까운 칸을 15색 전부에서 찾으면 채도 낮은 파랑에 먹힌다.
LIMIT = {
    "skin_lit": ["#eec49a", "#b9835a"],
    "skin_mid": ["#b9835a", "#7a5136"],
}


def dominant(im: Image.Image, box) -> tuple[int, int, int]:
    """네모 안의 최빈색. 흰 배경(밝고 채도 0)과 순검정 테두리는 뺀다."""
    c = Counter()
    px = im.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b = px[x, y][:3]
            mx, mn = max(r, g, b), min(r, g, b)
            if mx > 235 and mx - mn < 14:      # 흰 배경
                continue
            if mx < 26:                         # 검은 테두리
                continue
            c[(r, g, b)] += 1
    return c.most_common(1)[0][0] if c else (128, 128, 128)


def nearest(rgb, palette) -> str:
    """가중 RGB 거리(사람 눈에 가까운 2:4:3)로 가장 가까운 팔레트 칸."""
    best, bd = palette[0], 1e18
    for h in palette:
        pr, pg, pb = spec.hex2rgb(h)
        d = 2 * (pr - rgb[0]) ** 2 + 4 * (pg - rgb[1]) ** 2 + 3 * (pb - rgb[2]) ** 2
        if d < bd:
            best, bd = h, d
    return best


def run(elem: str = "ice") -> dict:
    ims = {n: Image.open(REF / f"view_{n}.png").convert("RGB")
           for n in ("front", "side", "back")}
    pal = spec.palette_for(elem)
    out = {}
    for part, boxes in BOXES.items():
        raws = [dominant(ims[v], b) for (v, *b) in boxes]
        # 여러 면에서 뽑았으면 **평균이 아니라 첫 면**을 쓴다 — 평균은 없는 색을 만든다.
        raw = raws[0]
        allow = LIMIT.get(part, pal)
        snap = nearest(raw, allow)
        d = sum(abs(a - b) for a, b in zip(raw, spec.hex2rgb(snap))) / 3.0
        out[part] = {"raw": "#%02x%02x%02x" % raw,
                     "raw_all": ["#%02x%02x%02x" % r for r in raws],
                     "snap": snap, "dist": round(d, 1)}
    return out


if __name__ == "__main__":
    r = run()
    print(json.dumps(r, ensure_ascii=False, indent=1))
    avg = sum(v["dist"] for v in r.values()) / len(r)
    print("부위 %d개 · 팔레트까지 평균 거리 %.2f" % (len(r), avg))
