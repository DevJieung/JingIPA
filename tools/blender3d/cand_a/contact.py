#!/usr/bin/env python3
"""후보 A — **대조표 한 장.** 원화·게임 도트·공식 마스터와 내 결과를 한 판에 놓는다.

    python3 tools/blender3d/cand_a/contact.py

★ 이 판이 이 과제의 진짜 산출물이다. 숫자로는 「팔레트 이탈 0」이 두 길에서 똑같이
  나오지만, **96px 에서 수염 난 거인이 큰 칼을 들었다로 읽히는가**는 눈으로만 갈린다.
"""
import sys, glob, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path("/home/dgxmaruta/pjt/pocker")
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import spec  # noqa: E402

BG = (24, 24, 30)
FG = (222, 228, 238)
DIM = (140, 150, 168)
FONT = ROOT / "core/fonts/DinoKR.ttf"


def font(sz):
    try:
        return ImageFont.truetype(str(FONT), sz)
    except Exception:
        return ImageFont.load_default()


def cell(im, zoom, box=96):
    """96칸 하나를 zoom 배로. 원본이 96 이 아니면 담아 맞춘다."""
    im = im.convert("RGBA")
    if im.size != (box, box):
        s = min(box / im.width, box / im.height)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))),
                       Image.LANCZOS if s < 0.5 else Image.NEAREST)
        c = Image.new("RGBA", (box, box), (0, 0, 0, 0))
        c.alpha_composite(im, ((box - im.width) // 2, box - im.height))
        im = c
    return im.resize((box * zoom, box * zoom), Image.NEAREST)


def build(out_path, root, refs):
    f_h, f_s = font(15), font(11)
    pad, gap = 12, 6
    rows = []          # (제목, [ (라벨, PIL이미지) ], 배율)

    rows.append(("1 · 기준점 — 원화 · 게임이 지금 그리는 도트 · 공식 파이프라인 마스터",
                 [("원화 1000px", Image.open(refs["hi"])),
                  ("게임 도트 96", Image.open(refs["game"])),
                  ("공식 마스터 96", Image.open(refs["master"]))], 3))

    raw = sorted(glob.glob(f"{root}/5_frames/idle/E/*.png"))
    rows.append(("2 · 3D 원본 렌더 idle 6칸 (양자화 전 · EEVEE 툰 · filter 0)",
                 [(f"{i+1}", Image.open(p)) for i, p in enumerate(raw)], 2))

    cl = sorted(glob.glob(f"{root}/6_clean/idle/E/*.png"))
    rows.append(("3 · 양자화(얼음 15색) + 1도트 검은 테두리 — idle 6칸",
                 [(f"{i+1}", Image.open(p)) for i, p in enumerate(cl)], 2))

    ca = sorted(glob.glob(f"{root}/6_clean/attack/E/*.png"))
    hit = spec.ACTIONS["attack"]["hit"]
    rows.append(("4 · 같은 후처리 — attack 6칸 (★ 표시가 놓는 칸)",
                 [(("★" if i == hit else "") + f"{i+1}", Image.open(p))
                  for i, p in enumerate(ca)], 2))

    order = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
    dirs = []
    for d in order:
        p = Path(root) / "6_clean" / "idle" / d / "0001.png"
        if p.exists():
            dirs.append((d, Image.open(p)))
    rows.append(("5 · idle 0번 칸 8방향 — 3D 길이 공짜로 주는 것 (게임은 E 하나만 쓴다)",
                 dirs, 2))

    # ---- 판 크기 재기
    W = 0
    H = pad
    laid = []
    for title, items, z in rows:
        cw = 96 * z
        rw = pad + len(items) * (cw + gap)
        W = max(W, rw)
        rh = 22 + cw + 16
        laid.append((title, items, z, rh))
        H += rh + 10
    H += pad
    W = max(W, 860)

    img = Image.new("RGBA", (W, H), BG + (255,))
    dr = ImageDraw.Draw(img)
    y = pad
    for title, items, z, rh in laid:
        dr.text((pad, y), title, font=f_h, fill=FG)
        yy = y + 22
        x = pad
        for lab, im in items:
            c = cell(im, z)
            img.alpha_composite(c, (x, yy))
            dr.rectangle([x, yy, x + c.width - 1, yy + c.height - 1],
                         outline=(58, 60, 72))
            dr.text((x + 2, yy + c.height + 2), lab, font=f_s, fill=DIM)
            x += c.width + gap
        y += rh + 10
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    img.convert("RGB").save(out_path)
    return img.size


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else "build/b3d/cand_a"
    outp = sys.argv[2] if len(sys.argv) > 2 else f"{root}/contact.png"
    r = ROOT / "build/b3d/jokull/1_turnaround"
    print(outp, build(outp, root,
                      {"hi": r / "jokull_hi.png", "game": r / "jokull_game96.png",
                       "master": r / "jokull_master96.png"}))
