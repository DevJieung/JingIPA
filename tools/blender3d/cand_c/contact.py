#!/usr/bin/env python3
"""후보 C — 대조표 한 장. `build/b3d/cand_c/contact.png`

    python3 tools/blender3d/cand_c/contact.py

줄 차례는 과제서가 정한 그대로다:
  1 원화 · 게임 도트 · 공식 마스터   (기준점)
  2 3D 원본 렌더 idle 6칸            (양자화 전)
  3 양자화·테두리 뒤 idle 6칸
  4 양자화·테두리 뒤 attack 6칸      (놓는 칸에 표시)
  5 idle 0번 칸 8방향
  6 (덤) 원화 텍스처 투영 세 축 vs 부위색 — 이 후보의 갈래 (1) 대 (2)
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import spec  # noqa: E402

OUT = spec.OUT / "cand_c"
REF = spec.OUT / "jokull" / "1_turnaround"
FONT = spec.ROOT / "core/fonts/DinoKR.ttf"
BG = (26, 26, 32, 255)
FG = (222, 228, 238, 255)
DIM = (140, 148, 164, 255)
HOT = (255, 196, 92, 255)
S = 3                      # 확대판 배율
CELL = 96


def f(sz):
    return ImageFont.truetype(str(FONT), sz)


def paste(dst, im, x, y, s=1):
    if s != 1:
        im = im.resize((im.width * s, im.height * s), Image.NEAREST)
    dst.paste(im, (x, y), im)
    return im.width, im.height


def load(p):
    return Image.open(p).convert("RGBA")


def main():
    f_t, f_l, f_s = f(26), f(17), f(14)
    rows = []           # (제목, [(라벨, 그림, 배율)], 높이)

    hi = load(REF / "jokull_hi.png")
    hi = hi.resize((CELL * S, int(hi.height * CELL * S / hi.width)), Image.LANCZOS)
    g96 = load(REF / "jokull_game96.png")
    m96 = load(REF / "jokull_master96.png")

    raw = [load(p) for p in sorted((OUT / "5_frames/idle/E").glob("*.png"))]
    ci = [load(p) for p in sorted((OUT / "6_clean/idle/E").glob("*.png"))]
    ca = [load(p) for p in sorted((OUT / "6_clean/attack/E").glob("*.png"))]
    dirs = list(spec.DIRS)
    dd = [load(OUT / f"6_clean/idle/{d}/0001.png") for d in dirs]
    tex = [(t, load(OUT / f"6_clean{t}_tex/idle/E/0001.png"))
           for t in ("", "_px", "_py")]

    W = 40 + max(8, 6) * (CELL * S + 10) + 40
    W = max(W, 40 + 3 * (CELL * S + 20) + 40)
    H = 2700
    img = Image.new("RGBA", (W, H), BG)
    dr = ImageDraw.Draw(img)
    dr.text((36, 24), "후보 C — 원화 텍스처 투영 · Blender 로우폴리 3D → 96x96 도트",
            font=f_t, fill=FG)
    dr.text((36, 58),
            "요쿨 Jokull · 얼음 · 검 · pair(101px) · EEVEE 툰 · 팔레트 15색 · "
            "후처리는 공식 tools/sprite/pixels.py 그대로",
            font=f_s, fill=DIM)

    y = 92

    def head(t, sub=""):
        nonlocal y
        dr.text((36, y), t, font=f_l, fill=HOT)
        if sub:
            dr.text((36 + dr.textlength(t, font=f_l) + 14, y + 2), sub,
                    font=f_s, fill=DIM)
        y += 26

    # ---- 1줄 기준점
    head("1  기준점", "원화 → 게임이 그리는 도트 → 공식 파이프라인 마스터")
    x, hmax = 40, 0
    for lab, im in (("원화 jokull_hi", hi), ("게임 96px", g96), ("공식 마스터 96px", m96)):
        s = 1 if im.width > CELL * 2 else S
        w, h = paste(img, im, x, y, s)
        dr.text((x, y + h + 4), lab, font=f_s, fill=DIM)
        x += w + 22
        hmax = max(hmax, h)
    y += hmax + 30

    # ---- 2줄 원본 렌더
    head("2  3D 원본 렌더 idle 6칸", "양자화 전 · 96x96 · filter_size 0 · 반투명 0")
    x = 40
    for i, im in enumerate(raw):
        w, h = paste(img, im, x, y, S)
        dr.text((x, y + h + 4), f"{i + 1}", font=f_s, fill=DIM)
        x += w + 10
    y += CELL * S + 30

    # ---- 3줄 양자화 뒤 idle
    head("3  양자화 · 1도트 테두리 뒤 idle 6칸", "3배 확대 + 1:1")
    x = 40
    for i, im in enumerate(ci):
        w, h = paste(img, im, x, y, S)
        paste(img, im, x + (w - CELL) // 2, y + h + 6)
        x += w + 10
    y += CELL * S + CELL + 26

    # ---- 4줄 attack
    hit = spec.ACTIONS["attack"]["hit"]
    head("4  양자화 · 테두리 뒤 attack 6칸", f"놓는 칸 = {hit}번(0부터) · 노란 테")
    x = 40
    for i, im in enumerate(ca):
        w, h = paste(img, im, x, y, S)
        if i == hit:
            dr.rectangle([x - 2, y - 2, x + w + 1, y + h + 1], outline=HOT, width=2)
        paste(img, im, x + (w - CELL) // 2, y + h + 6)
        x += w + 10
    y += CELL * S + CELL + 26

    # ---- 5줄 여덟 방향
    head("5  idle 0번 칸 여덟 방향",
         "게임에 나가는 것은 E 하나 — 나머지는 3D 길에만 있는 덤이다")
    x = 40
    for d, im in zip(dirs, dd):
        w, h = paste(img, im, x, y, 2)
        col = HOT if d == spec.GAME_DIR else DIM
        dr.text((x, y + h + 4), d + ("  ← 게임" if d == spec.GAME_DIR else ""),
                font=f_s, fill=col)
        x += w + 10
    y += CELL * 2 + 34

    # ---- 6줄 이 후보의 갈래 둘
    head("6  갈래 (1) 원화 텍스처 투영  대  갈래 (2) 부위별 색 추출",
         "둘 다 같은 메시·같은 리그·같은 후처리 — 다른 것은 재질뿐")
    x = 40
    items = [("투영 SE 45도", tex[0][1]), ("투영 X 옆", tex[1][1]),
             ("투영 Y 정면", tex[2][1]), ("부위색 flat ← 채택", ci[0]),
             ("공식 마스터", m96)]
    for lab, im in items:
        w, h = paste(img, im, x, y, 2)
        dr.text((x, y + h + 4), lab, font=f_s,
                fill=HOT if "채택" in lab else DIM)
        x += w + 12
    y += CELL * 2 + 34
    dr.text((40, y),
            "투영 갈래는 96px 에서 무너진다 — 원화의 1도트 테두리와 붓자국이 "
            "화면에서 잡티가 되고, 3/4 그림을 어느 축으로 눌러도 부위가 안 맞는다.",
            font=f_s, fill=DIM)
    dr.text((40, y + 20),
            "숫자로도 그렇다: 양자화 전 고유색 47(부위색) 대 1794(투영) · "
            "팔레트까지의 평균 거리 2.07 대 26.3 (RGB).", font=f_s, fill=DIM)
    y += 50

    # ---- 팔레트
    dr.text((40, y), "팔레트 15색 (spec.palette_for(\"ice\") — 공식과 같은 표)",
            font=f_s, fill=DIM)
    for i, hx in enumerate(spec.palette_for("ice")):
        dr.rectangle([40 + i * 26, y + 22, 40 + i * 26 + 22, y + 44],
                     fill=spec.hex2rgb(hx), outline=(70, 74, 84))
    y += 56

    img = img.crop((0, 0, W, min(H, y + 16)))
    img.save(OUT / "contact.png")
    print(f"{OUT / 'contact.png'} {img.size}")


if __name__ == "__main__":
    main()
