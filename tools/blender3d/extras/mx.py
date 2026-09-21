#!/usr/bin/env python3
"""extras 공용 — 잣대와 그리기 도우미. 여기 말고 다른 데 쓰지 않는다."""
from __future__ import annotations

import colorsys
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent / "sprite"))
import spec  # noqa: E402

OUT = spec.OUT / "extras"
BG = (26, 26, 32)
PANEL = (34, 34, 42)
FG = (232, 234, 240)
DIM = (150, 156, 170)
HL = (255, 208, 96)
OK = (120, 216, 140)
NG = (232, 110, 110)
LINE = (210, 90, 90)
FONT = spec.ROOT / "core/fonts/DinoKR.ttf"


def font(sz: int):
    try:
        return ImageFont.truetype(str(FONT), sz)
    except Exception:
        return ImageFont.load_default()


def nn(im: Image.Image, mult: float) -> Image.Image:
    return im.resize((max(1, int(round(im.width * mult))),
                      max(1, int(round(im.height * mult)))), Image.NEAREST)


def frames_of(d: Path) -> list[Image.Image]:
    return [Image.open(p).convert("RGBA") for p in sorted(Path(d).glob("*.png"))]


def strip_frames(sheet: Path, n: int) -> list[Image.Image]:
    im = Image.open(sheet).convert("RGBA")
    cw = im.width // n
    return [im.crop((i * cw, 0, (i + 1) * cw, im.height)) for i in range(n)]


# ---------------------------------------------------------------- 잣대
def measure(im: Image.Image) -> dict:
    """낱장 하나 — 채운 넓이 · 발밑 · 몸 상자 · 고유색 · 밝기 중앙값.

    ★ 밝기 중앙값은 **알파가 있는 픽셀만** · HSV 의 V 를 쓴다. 공식 파이프라인이
      화풍을 재던 자(CLAUDE.md 4-4-0-2)와 같은 잣대여야 두 길을 견줄 수 있다.
    """
    px = im.load()
    w, h = im.size
    vs, seen, n = [], set(), 0
    x0, y0, x1, y1 = w, h, -1, -1
    sx = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if not a:
                continue
            n += 1
            sx += x
            seen.add((r, g, b))
            vs.append(max(r, g, b) / 255.0)
            x0, y0 = min(x0, x), min(y0, y)
            x1, y1 = max(x1, x), max(y1, y)
    if not n:
        return {"fill": 0, "fill_ratio": 0.0, "colors": 0, "v_median": 0.0,
                "bbox": None, "body_w": 0, "body_h": 0, "bottom": -1, "cx": -1.0}
    vs.sort()
    return {"fill": n, "fill_ratio": round(n / float(w * h), 4),
            "colors": len(seen), "v_median": round(vs[len(vs) // 2], 4),
            "bbox": [x0, y0, x1 + 1, y1 + 1],
            "body_w": x1 + 1 - x0, "body_h": y1 + 1 - y0,
            "bottom": y1 + 1, "cx": round(sx / n, 2)}


def sat_median(im: Image.Image) -> float:
    px = im.load()
    ss = []
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a:
                ss.append(colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1])
    ss.sort()
    return round(ss[len(ss) // 2], 4) if ss else 0.0


def stray(im: Image.Image, palette: list[str]) -> int:
    pal = {spec.hex2rgb(h) for h in palette}
    px = im.load()
    n = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a and (r, g, b) not in pal:
                n += 1
    return n


def agg(ms: list[dict]) -> dict:
    """여러 칸의 잣대를 하나로 — 평균과 흔들림."""
    if not ms:
        return {}
    f = lambda k: [m[k] for m in ms]
    return {
        "n": len(ms),
        "fill_ratio": round(sum(f("fill_ratio")) / len(ms), 4),
        "colors_max": max(f("colors")),
        "v_median": round(sorted(f("v_median"))[len(ms) // 2], 4),
        "body_h": [min(f("body_h")), max(f("body_h"))],
        "bottom": [min(f("bottom")), max(f("bottom"))],
        "foot_spread": max(f("bottom")) - min(f("bottom")),
    }


def load(p: Path) -> dict:
    return json.loads(Path(p).read_text())


def save(p: Path, d: dict) -> Path:
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    Path(p).write_text(json.dumps(d, ensure_ascii=False, indent=1))
    return Path(p)
