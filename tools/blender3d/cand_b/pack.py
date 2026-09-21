#!/usr/bin/env python3
"""후보 B — 6단계(후처리) + 시트 + 잣대 + 대조표.

    python3 tools/blender3d/cand_b/pack.py

★ 후처리는 **손대지 않은 `tools/blender3d/post.py`** 를 그대로 부른다. 그것이 다시
  공식 파이프라인의 `tools/sprite/pixels.py` 를 부르므로, 세 후보 사이에 남는 차이는
  「원본 프레임의 차이」뿐이다.
"""
from __future__ import annotations
import json, sys, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent.parent / "sprite"))
import spec      # noqa: E402
import post      # noqa: E402  ← 6단계. 고치지 않는다
import pixels    # noqa: E402  ← 공식 규격. 읽기만 한다

UNIT = "jokull"
ELEM = "ice"
OUT = spec.ROOT / "build" / "b3d" / "cand_b"
FRAMES = OUT / "5_frames"
CLEAN = OUT / "6_clean"
REF = spec.ROOT / "build" / "b3d" / UNIT / "1_turnaround"
FONT = spec.ROOT / "core/fonts/DinoKR.ttf"


def font(sz):
    try:
        return ImageFont.truetype(str(FONT), sz)
    except Exception:
        return ImageFont.load_default()


def clean_all(palette):
    """5_frames 를 통째로 6_clean 으로. post.clean_one 만 쓴다."""
    made = {}
    for act_dir in sorted(d for d in FRAMES.iterdir() if d.is_dir()):
        for dir_dir in sorted(d for d in act_dir.iterdir() if d.is_dir()):
            outd = CLEAN / act_dir.name / dir_dir.name
            outd.mkdir(parents=True, exist_ok=True)
            ims = []
            for src in sorted(dir_dir.glob("*.png")):
                im = post.clean_one(src, palette, outline=True)
                im.save(outd / src.name)
                ims.append(im)
            made[(act_dir.name, dir_dir.name)] = ims
    return made


def alpha_bbox(im):
    return im.split()[3].getbbox()


def foot_center_x(im):
    """발의 가로 가운데 — 알파 상자 **맨 아래 네 줄**의 무게중심.
    ★ 그림 전체의 가운데를 쓰면 대검이 오른쪽으로 뻗은 만큼 기준점이 끌려간다."""
    bb = alpha_bbox(im)
    if bb is None:
        return im.width / 2
    px = im.load()
    xs, n = 0, 0
    for y in range(max(bb[1], bb[3] - 4), bb[3]):
        for x in range(bb[0], bb[2]):
            if px[x, y][3]:
                xs += x
                n += 1
    return xs / max(1, n)


def measure(im, palette_rgb):
    bb = alpha_bbox(im)
    px = im.load()
    cols, semi, out_of_pal, fill, magenta = set(), 0, 0, 0, 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if 0 < a < 255:
                semi += 1
            if a:
                fill += 1
                cols.add((r, g, b))
                if (r, g, b) not in palette_rgb:
                    out_of_pal += 1
                if abs(r - 255) < 40 and g < 60 and abs(b - 255) < 40:
                    magenta += 1
    return {"bbox": bb, "colors": len(cols), "semi": semi, "outliers": out_of_pal,
            "fill": fill, "magenta": magenta,
            "outline_ratio": round(pixels.outline_ratio(im), 4),
            "cols": cols}


def main():
    palette = spec.palette_for(ELEM)                 # game15 — 공식과 같은 15색
    pal_rgb = {pixels.hex2rgb(h) for h in palette}
    made = clean_all(palette)

    gd = spec.GAME_DIR
    idle = made[("idle", gd)]
    atk = made[("attack", gd)]
    dirs = {d: made[("idle", d)][0] for d in spec.DIRS if ("idle", d) in made}

    ms = {"idle": [measure(i, pal_rgb) for i in idle],
          "attack": [measure(i, pal_rgb) for i in atk],
          "dirs": {d: measure(im, pal_rgb) for d, im in dirs.items()}}

    # --- 시트 (가로 1행 · 간격 0)
    sh_i = pixels.pack_sheet(idle, spec.CELL[0])
    sh_a = pixels.pack_sheet(atk, spec.CELL[0])
    sh_i.save(OUT / f"{UNIT}_idle.png")
    sh_a.save(OUT / f"{UNIT}_attack.png")

    # --- 기준점 · 배율 · 총구
    b0 = ms["idle"][0]["bbox"]
    body_h = b0[3] - b0[1]
    anchor = (round(foot_center_x(idle[0]), 1), float(b0[3]))
    scale = round(spec.unit_h(spec.roster_unit(UNIT)["tier_i"]) / body_h, 4)
    rr = json.loads((OUT / "render_report.json").read_text())
    hit_i = spec.ACTIONS["attack"]["hit"]                  # 0-based
    tip = rr["sword"]["attack"][hit_i]["tip_px"]
    muzzle = {"x": int(round(tip[0] - anchor[0])), "y": int(round(tip[1] - anchor[1]))}

    frames_e = ms["idle"] + ms["attack"]
    bots = [m["bbox"][3] for m in frames_e]
    metrics = {
        "unique_colors": max(m["colors"] for m in frames_e),
        "palette_outliers": sum(m["outliers"] for m in frames_e),
        "semi_alpha_px": sum(m["semi"] for m in frames_e),
        "magenta_px": sum(m["magenta"] for m in frames_e),
        "foot_y_spread": max(bots) - min(bots),
        "foot_y_spread_8dir": (max(m["bbox"][3] for m in ms["dirs"].values())
                               - min(m["bbox"][3] for m in ms["dirs"].values())),
        "body_h_px": body_h,
        "body_w_px": b0[2] - b0[0],
        "scale": scale,
        "outline_ratio_min": round(min(m["outline_ratio"] for m in frames_e), 4),
        "fill_ratio": round(sum(m["fill"] for m in frames_e) / (len(frames_e) * 96 * 96), 4),
        "fill_ratio_idle0": round(ms["idle"][0]["fill"] / (96 * 96), 4),
        "empty_frames": sum(1 for m in frames_e if m["fill"] == 0),
        "anchor": {"x": anchor[0], "y": anchor[1]},
        "muzzle_at": muzzle,
        "colors_used": sorted('#%02x%02x%02x' % c
                              for c in set().union(*(m["cols"] for m in frames_e))),
    }
    # 루프 이음매 — idle 마지막 칸과 0번 칸이 얼마나 다른가(픽셀 %)
    a0, an = idle[0], idle[-1]
    diff = sum(1 for p, q in zip(a0.getdata(), an.getdata()) if p != q)
    metrics["idle_loop_seam_pct"] = round(100.0 * diff / (96 * 96), 2)

    aj = {
        "name": UNIT, "elem": ELEM, "source": "tools/blender3d/cand_b (Blender 3D 스킨드)",
        "cell": {"w": spec.CELL[0], "h": spec.CELL[1]},
        "static": {"w": metrics["body_w_px"], "h": body_h},
        "anchor": {"x": anchor[0], "y": anchor[1]},
        "scale": scale, "muzzle_at": muzzle,
        "hit_ms": int(round(1000.0 * hit_i / spec.FPS)),
        "face": 1, "family": "slash",
        "clips": {
            "idle": {"frames": len(idle), "ms": [int(1000 / spec.FPS)] * len(idle),
                     "total_ms": int(1000 * len(idle) / spec.FPS), "loop": True},
            "attack": {"frames": len(atk), "ms": [int(1000 / spec.FPS)] * len(atk),
                       "total_ms": int(1000 * len(atk) / spec.FPS), "loop": False,
                       "hit_frame": hit_i},
        },
    }
    (OUT / "anim.json").write_text(json.dumps(aj, ensure_ascii=False, indent=1))
    metrics_out = {k: v for k, v in metrics.items()}
    (OUT / "metrics.json").write_text(json.dumps(metrics_out, ensure_ascii=False, indent=1))

    contact(idle, atk, dirs)
    print("PACK_JSON " + json.dumps(metrics_out, ensure_ascii=False))


# ---------------------------------------------------------------- 대조표
def row(imgs, z, gap):
    w = spec.CELL[0] * z
    return [(im.resize((w, w), Image.NEAREST)) for im in imgs], w


def contact(idle, atk, dirs):
    Z = 3
    GAP = 6
    PAD = 10
    LBL = 20
    BG = (26, 26, 32)
    cell = spec.CELL[0] * Z
    ncol = max(6, len(dirs), 3)
    W = PAD * 2 + ncol * cell + (ncol - 1) * GAP
    rows = 5
    H = PAD + rows * (cell + GAP + LBL) + PAD
    out = Image.new("RGB", (W, H), BG)
    dr = ImageDraw.Draw(out)
    f = font(15)
    fs = font(12)

    def put(y, label, imgs, tags=None):
        dr.text((PAD, y), label, font=f, fill=(235, 235, 245))
        y += LBL
        for i, im in enumerate(imgs):
            x = PAD + i * (cell + GAP)
            box = Image.new("RGB", (cell, cell), (40, 40, 48))
            r = im.convert("RGBA").resize((cell, cell), Image.NEAREST)
            box.paste(r, (0, 0), r)
            out.paste(box, (x, y))
            if tags:
                dr.text((x + 3, y + cell - 15), tags[i], font=fs, fill=(200, 210, 230))
        return y + cell + GAP

    y = PAD
    hi = Image.open(REF / "jokull_hi.png").convert("RGBA")
    hi.thumbnail((96, 96), Image.LANCZOS)
    pad_hi = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
    pad_hi.paste(hi, ((96 - hi.width) // 2, 96 - hi.height))
    y = put(y, "1  원화(축소) · 게임이 쓰는 96px 도트 · 공식 파이프라인 마스터96   |   3배 확대",
            [pad_hi,
             Image.open(REF / "jokull_game96.png").convert("RGBA"),
             Image.open(REF / "jokull_master96.png").convert("RGBA")],
            ["hi", "game", "master"])
    y = put(y, "2  후보 B · 3D 원본 렌더 idle 6칸 (양자화 전 · EEVEE 툰 · 96x96)",
            [Image.open(FRAMES / "idle" / spec.GAME_DIR / f"{i:04d}.png").convert("RGBA")
             for i in range(1, 7)], [str(i) for i in range(6)])
    y = put(y, "3  후보 B · 팔레트 15색 + 1도트 테두리 뒤 idle 6칸",
            idle, [str(i) for i in range(6)])
    y = put(y, "4  후보 B · attack 6칸 (3번 칸이 놓는 칸)",
            atk, ["0", "1", "2", "3 HIT", "4", "5"])
    order = ["S", "SE", "E", "NE", "N", "NW", "W", "SW"]
    y = put(y, "5  idle 0번 칸 · 여덟 방향 (E 만 게임에 쓴다)",
            [dirs[d] for d in order if d in dirs],
            [d for d in order if d in dirs])
    out.save(OUT / "contact.png")


if __name__ == "__main__":
    main()
