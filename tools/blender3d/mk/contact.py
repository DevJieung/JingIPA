#!/usr/bin/env python3
"""최종 대조표 한 장 — `build/b3d/jokull/final_contact.png`.

    python3 tools/blender3d/mk/contact.py

일곱 줄이다:
  1 원화 · 3면도 · 게임 도트 · 공식 마스터
  2 3D 원본 렌더 idle 6칸 (양자화 **전**)
  3 양자화 + 1도트 테두리 뒤 idle 6칸 (1배와 3배)
  4 attack 6칸 (★ 가 놓는 칸)
  5 walk 8칸
  6 8방향
  7 ★ 공식 시트와 나란히 — **게임이 그리는 키**로 맞춰 위아래로 놓는다
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import spec  # noqa: E402

BG = (26, 26, 32)
FG = (232, 234, 240)
DIM = (150, 156, 170)
HL = (255, 208, 96)
LINE = (210, 90, 90)
FONT = spec.ROOT / "core/fonts/DinoKR.ttf"


def font(sz):
    try:
        return ImageFont.truetype(str(FONT), sz)
    except Exception:
        return ImageFont.load_default()


def nn(im, mult):
    return im.resize((max(1, int(round(im.width * mult))),
                      max(1, int(round(im.height * mult)))), Image.NEAREST)


def main():
    p = spec.paths("jokull")
    ref, raw, clean, sheet = p["ref"], p["root"] / "5_raw", p["clean"], p["sheet"]
    aj = json.loads((sheet / "anim.json").read_text())
    gd = spec.GAME_DIR
    W = 1660
    img = Image.new("RGB", (W, 3000), BG)
    dr = ImageDraw.Draw(img)
    f13, f11, f16 = font(13), font(11), font(16)
    y = 8

    def head(t, yy):
        dr.text((10, yy), t, font=f13, fill=HL)
        return yy + 18

    def cap(t, x, yy, col=DIM):
        dr.text((x, yy), t, font=f11, fill=col)

    # ---------------------------------------------------------------- 1줄
    y = head("1 · 기준점 — 원화 · Krea2 3면도(앞·옆·뒤) · 게임이 지금 그리는 도트 · 공식 파이프라인 마스터", y)
    x = 10
    hi = Image.open(ref / "jokull_hi.png").convert("RGBA")
    hi.thumbnail((190, 190))
    img.paste(hi, (x, y), hi)
    cap("원화 1000px", x, y + 196)
    x += 200
    for nm in ("front", "side", "back"):
        v = Image.open(ref / f"view_{nm}.png").convert("RGB").resize((190, 190), Image.NEAREST)
        img.paste(v, (x, y))
        cap("3면도 " + nm, x, y + 196)
        x += 200
    for nm, lbl in (("jokull_game96.png", "게임 도트 96"), ("jokull_master96.png", "공식 마스터 96")):
        v = Image.open(ref / nm).convert("RGBA")
        v = nn(v, 190 / v.width)
        img.paste(v, (x, y), v)
        cap(lbl, x, y + 196)
        x += 200
    y += 216

    # ---------------------------------------------------------------- 2·3줄
    def strip(d, n, mult, yy, mark=None, xs=10):
        ims = sorted(Path(d).glob("*.png"))[:n]
        for i, f in enumerate(ims):
            im = Image.open(f).convert("RGBA")
            z = nn(im, mult)
            img.paste(z, (xs + i * (z.width + 4), yy), z)
            lbl = ("★%d" % i) if (mark is not None and i == mark) else str(i)
            cap(lbl, xs + i * (z.width + 4) + 2, yy + z.height + 1,
                HL if (mark is not None and i == mark) else DIM)
        return yy + (96 * mult) + 16

    y = head("2 · 3D 원본 렌더 idle 6칸 — 양자화 전 (EEVEE 툰 3톤 · filter 0 · 내부 선 없음)", y)
    y = strip(raw / "idle" / gd, 6, 2, y)
    y = head("3 · 양자화(얼음 15색) + 1도트 테두리 + ★내부 선화 — idle 6칸 (2배 · 오른쪽은 1배)", y)
    yy = strip(clean / "idle" / gd, 6, 2, y)
    for i, f in enumerate(sorted((clean / "idle" / gd).glob("*.png"))):
        im = Image.open(f).convert("RGBA")
        img.paste(im, (1290 + i * 60, y), im)
    cap("1배", 1290, y + 100)
    y = yy

    # ---------------------------------------------------------------- 4·5줄
    y = head("4 · attack 6칸 — ★ 가 놓는 칸(hit_frame %d · hit_ms %d)"
             % (aj["clips"]["attack"]["hit_frame"], aj["hit_ms"]), y)
    y = strip(clean / "attack" / gd, 6, 2, y, mark=aj["clips"]["attack"]["hit_frame"])
    y = head("5 · walk 8칸 — ★ 발목 뼈 + 픽셀 정렬 → 발밑 흔들림 0px · 보폭 13.7px "
             "(정렬을 꺼도 0px · 발목을 빼면 1px · 후보 A 는 3px 이라 계약을 못 지켰다)", y)
    y = strip(clean / "walk" / gd, 8, 2, y)

    # ---------------------------------------------------------------- 6줄
    y = head("6 · 8방향 idle 0번 칸 — 3D 길이 공짜로 주는 것 (게임은 SE 하나만 쓴다)", y)
    x = 10
    for d in spec.DIRS:
        f = clean / "idle" / d / "0001.png"
        if not f.exists():
            continue
        im = nn(Image.open(f).convert("RGBA"), 2)
        img.paste(im, (x, y), im)
        cap(d + ("  ← 게임" if d == gd else ""), x + 2, y + im.height + 1,
            HL if d == gd else DIM)
        x += im.width + 4
    y += 96 * 2 + 16

    # ---------------------------------------------------------------- 7줄
    y = head("7 · ★ 공식 시트와 나란히 — **게임이 그리는 키**로 맞췄다 "
             "(공식 배율 1.2785 · 3D 배율 %.4f · 둘 다 몸높이 101px)" % aj["scale"], y)
    ROW_H, GROUND = 268, 236
    off_aj = json.loads((spec.ROOT / "art/anim/jokull/anim.json").read_text())
    rows = [("공식 (Wan 2.2 I2V · 12칸 · 시트에서 칼이 76px 잘려 있다)",
             spec.ROOT / "art/anim/jokull/jokull_attack.png",
             off_aj["clips"]["attack"]["frames"], off_aj,
             off_aj["clips"]["attack"]["hit_frame"], 136),
            ("3D  (Blender 툰 · 6칸 · 칸 밖으로 나간 픽셀 0)", sheet / "jokull_attack.png",
             aj["clips"]["attack"]["frames"], aj,
             aj["clips"]["attack"]["hit_frame"], 264)]
    for ri, (lbl, path, n, meta, hit, pitch) in enumerate(rows):
        top = y + ri * ROW_H
        gy = top + GROUND
        cap(lbl, 10, top, FG)
        shp = Image.open(path).convert("RGBA")
        cw = shp.width // n
        m = meta["scale"] * 1.9
        for i in range(n):
            fr = shp.crop((i * cw, 0, (i + 1) * cw, shp.height))
            z = nn(fr, m)
            ax, ay = meta["anchor"]["x"] * m, meta["anchor"]["y"] * m
            px = int(14 + i * pitch + pitch * 0.5 - ax)
            py = int(gy - ay)
            img.paste(z, (px, py), z)
            if i == hit:
                dr.text((int(14 + i * pitch + pitch * 0.5 - 5), gy + 3), "★",
                        font=f16, fill=HL)
        dr.line([(6, gy), (W - 6, gy)], fill=LINE)
        cap("게임 배율 %.4f · 몸높이 %dpx → 그리는 키 %dpx"
            % (meta["scale"], meta["static"]["h"],
               round(meta["scale"] * meta["static"]["h"])), 10, top + 14)
    y = y + ROW_H * 2 + 14

    img = img.crop((0, 0, W, y))
    out = p["root"] / "final_contact.png"
    img.save(out)
    print(out, img.size)


if __name__ == "__main__":
    main()
