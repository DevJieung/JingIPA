#!/usr/bin/env python3
"""시트를 눈으로 보는 도구 — 프레임 띠(PNG)와 움직이는 GIF.

    python3 tools/sprite/preview.py --route sdxl

★ 띠를 **3배 nearest 확대**해서 그린다. 96px 짜리를 그대로 보면 무엇이 잘못됐는지가
  안 보인다 — 발이 2px 떠 있는 것도, 테두리가 끊긴 것도 원본 크기에서는 못 잡는다.
★ 바탕은 격자다. 투명이 흰색이면 「흰 옷」과 「구멍」이 화면에서 같은 것이 된다
  (CLAUDE.md 4-3 이 그림에서 배운 것과 같은 함정이다).
"""

from __future__ import annotations

import argparse
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import units as U                                # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")


def checker(w: int, h: int, cell: int = 8) -> Image.Image:
    im = Image.new("RGB", (w, h), (58, 58, 64))
    dr = ImageDraw.Draw(im)
    for y in range(0, h, cell):
        for x in range(0, w, cell):
            if (x // cell + y // cell) % 2:
                dr.rectangle([x, y, x + cell - 1, y + cell - 1], fill=(46, 46, 52))
    return im


def frames_of(path: str, size: int) -> list[Image.Image]:
    sh = Image.open(path).convert("RGBA")
    n = sh.width // size
    return [sh.crop((i * size, 0, (i + 1) * size, size)) for i in range(n)]


def strip(fr: list[Image.Image], size: int, zoom: int = 3) -> Image.Image:
    w, h = size * zoom, size * zoom
    out = checker(w * len(fr) + 2 * (len(fr) + 1), h + 4).convert("RGBA")
    for i, f in enumerate(fr):
        big = f.resize((w, h), Image.NEAREST)
        out.alpha_composite(big, (2 + i * (w + 2), 2))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="sdxl")
    ap.add_argument("--zoom", type=int, default=3)
    ap.add_argument("--tag", default="", help="sprite_post 와 같은 꼬리표")
    ap.add_argument("--anim", default="")
    a = ap.parse_args()

    src = os.path.join(OUT, a.route, "sheets" + a.tag)
    dst = os.path.join(OUT, a.route, "preview" + a.tag)
    os.makedirs(dst, exist_ok=True)
    rows = []
    anims = [s for s in a.anim.split(",") if s] or U.ANIMS
    for u in U.load():
        for anim in anims:
            n = pixels.FRAMES[anim]
            p = os.path.join(src, pixels.sheet_name(u["id"], anim, u["size"], n))
            if not os.path.exists(p):
                continue
            fr = frames_of(p, u["size"])
            st = strip(fr, u["size"], a.zoom)
            st.convert("RGB").save(os.path.join(dst, f"{u['id']}_{anim}_strip.png"))
            # GIF — 12fps 그대로 (지침 §1)
            gif = [Image.alpha_composite(
                Image.new("RGBA", f.size, (46, 46, 52, 255)), f).convert("P",
                palette=Image.ADAPTIVE) for f in fr]
            gif[0].save(os.path.join(dst, f"{u['id']}_{anim}.gif"), save_all=True,
                        append_images=gif[1:], duration=int(1000 / pixels.FPS), loop=0)
            rows.append((u, anim, st))
            print(f"  {u['id']}_{anim}: {len(fr)}칸")

    if rows:
        W = max(r[2].width for r in rows) + 180
        H = sum(r[2].height + 8 for r in rows) + 8
        board = checker(W, H).convert("RGBA")
        dr = ImageDraw.Draw(board)
        y = 8
        for u, anim, st in rows:
            dr.text((6, y + 10), f"{u['id']}\n{anim}\n{u['elem']}", fill=(235, 235, 235))
            board.alpha_composite(st, (180, y))
            y += st.height + 8
        board.convert("RGB").save(os.path.join(OUT, f"board_{a.route}{a.tag}.png"))
        print(os.path.join(OUT, f"board_{a.route}{a.tag}.png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
