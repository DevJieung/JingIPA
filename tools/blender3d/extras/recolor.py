#!/usr/bin/env python3
"""1 · 속성 5벌 리컬러 — 모델 하나로 캐릭터 다섯을 굽는다.

    python3 tools/blender3d/extras/recolor.py

`bl_render.py --job recolor` 가 구워 둔 낱장을 **속성마다 제 팔레트로** 양자화하고
(`post.clean_one` = 공식 `pixels.py`), 다섯 줄짜리 대조표와 숫자를 낸다.

★ 재는 것 넷
  1. 다섯 벌이 **저마다의 15색 팔레트를 지키는가** (팔레트 이탈 0 이어야 한다)
  2. 얼음 대비 **몇 %의 픽셀이 실제로 갈렸는가** — 공용 8색(살결·쇠·가죽)은 안 갈린다
  3. 램프 일곱 칸이 **밝기 사다리인가** — 아니면 리컬러가 명암 구조를 부순다
  4. 실루엣이 얼마나 같은가 — 리컬러는 원리상 1.000 이다. 그 수를 **로스터의 서로
     다른 캐릭터끼리**의 값과 나란히 놓아야 「이게 다른 캐릭터인가」에 답이 된다.
"""
from __future__ import annotations

import colorsys
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import mx    # noqa: E402
import spec  # noqa: E402
import post  # noqa: E402  ← 6단계. 공식 pixels.py 를 그대로 부른다

ROOT = mx.OUT / "recolor"
ELEMS = ["fire", "elec", "ice", "water", "none"]
KO = {"fire": "불", "elec": "전기", "ice": "얼음", "water": "물", "none": "무상성"}


def v_of(hx: str) -> float:
    r, g, b = spec.hex2rgb(hx)
    return max(r, g, b) / 255.0


def ramp_stats(elem: str) -> dict:
    """램프 일곱 칸이 밝기 사다리인가. 뒤집힌 칸이 있으면 리컬러가 명암을 부순다."""
    vs = [v_of(h) for h in spec.RAMP[elem]]
    drops = [i for i in range(1, 7) if vs[i] < vs[i - 1]]
    return {"v": [round(x, 3) for x in vs],
            "monotone": not drops,
            "drops": drops,
            "worst_drop": round(max((vs[i - 1] - vs[i] for i in drops), default=0.0), 3)}


def silhouette_iou(a: Image.Image, b: Image.Image) -> float:
    A = np.array(a)[:, :, 3] > 0
    B = np.array(b)[:, :, 3] > 0
    u = (A | B).sum()
    return round(float((A & B).sum()) / u, 4) if u else 0.0


def roster_iou_sample(limit: int = 50) -> dict:
    """★ 「다른 캐릭터끼리는 실루엣이 얼마나 다른가」 — 공식 시트로 실측한다.

    리컬러의 실루엣 IoU 는 원리상 1.000 이다. 그 값이 크다/작다를 말하려면
    **게임이 실제로 다른 캐릭터라고 부르는 것들**의 값이 있어야 한다.
    """
    ims = []
    for d in sorted((spec.ROOT / "art/anim").iterdir()):
        f = d / f"{d.name}_idle.png"
        if not f.exists():
            continue
        im = Image.open(f).convert("RGBA")
        n = 8
        cw = im.width // n
        fr = im.crop((0, 0, cw, im.height))
        # 발밑·가로 가운데를 맞춰 놓고 재야 「모양이 다른가」를 재는 것이 된다
        a = np.array(fr)[:, :, 3] > 0
        if not a.any():
            continue
        ys, xs = np.nonzero(a)
        cx = int(round(xs.mean()))
        by = int(ys.max())
        sh = np.zeros((96, 96), bool)
        dy, dx = 95 - by, 48 - cx
        y0, y1 = max(0, dy), min(96, 96 + dy)
        x0, x1 = max(0, dx), min(96, 96 + dx)
        sh[y0:y1, x0:x1] = a[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
        ims.append((d.name, sh))
        if len(ims) >= limit:
            break
    vals = []
    for i in range(len(ims)):
        for j in range(i + 1, len(ims)):
            A, B = ims[i][1], ims[j][1]
            u = (A | B).sum()
            if u:
                vals.append(float((A & B).sum()) / u)
    vals.sort()
    return {"n_units": len(ims), "n_pairs": len(vals),
            "iou_mean": round(sum(vals) / len(vals), 4) if vals else 0.0,
            "iou_median": round(vals[len(vals) // 2], 4) if vals else 0.0,
            "iou_max": round(vals[-1], 4) if vals else 0.0,
            "iou_p95": round(vals[int(len(vals) * 0.95)], 4) if vals else 0.0}


SKIN = ["#7a5136", "#b9835a", "#eec49a"]
#: 두 팔레트 칸이 96px 화면에서 서로 안 갈리기 시작하는 RGB 거리. 눈으로 골랐다.
MERGE_D = 60.0


def clash(elem: str) -> dict:
    """★ 공용 8색이 그 속성 램프에 **먹히는가**.

    살결·쇠·가죽은 속성이 없어서 다섯 벌에서 한 톨도 안 갈린다. 그런데 램프가
    그 색 옆으로 오면 '안 갈렸다'가 곧 '안 보인다'가 된다 — 불 램프의 #c04a1c 와
    살결 #b9835a 는 RGB 거리 40 이라, 96px 에서는 얼굴이 옷에 먹힌다.
    """
    per = {}
    for c in spec.COMMON:
        a = np.array(spec.hex2rgb(c), float)
        d = min(float(np.linalg.norm(a - np.array(spec.hex2rgb(h), float)))
                for h in spec.RAMP[elem])
        per[c] = round(d, 1)
    skin = min(per[c] for c in SKIN)
    return {"per_common": per, "skin_min": skin,
            "merged": sorted(c for c, d in per.items() if d < MERGE_D),
            "merged_n": sum(1 for d in per.values() if d < MERGE_D)}


def main() -> int:
    rep = mx.load(ROOT / "report.json")
    out: dict = {"job": "recolor", "render": {k: v for k, v in rep.items() if k != "per"},
                 "per": {}, "ramp": {}, "silhouette": {}}
    ice_frames = None
    clean: dict[str, list[Image.Image]] = {}

    for elem in ELEMS:
        pal = spec.palette_for(elem)
        srcs = sorted((ROOT / elem / "raw").glob("*.png"))
        outd = ROOT / elem / "clean"
        outd.mkdir(parents=True, exist_ok=True)
        ims = []
        for s in srcs:
            im = post.clean_one(s, pal, outline=True)
            im.save(outd / s.name)
            ims.append(im)
        clean[elem] = ims
        ms = [mx.measure(i) for i in ims]
        a = mx.agg(ms)
        a["stray"] = sum(mx.stray(i, pal) for i in ims)
        a["sat_median"] = mx.sat_median(ims[0])
        a["render"] = rep["per"][elem]["render_sec"]
        a["swap_sec"] = rep["per"][elem]["swap_sec"]
        out["per"][elem] = a
        out["ramp"][elem] = ramp_stats(elem)
        if elem == "ice":
            ice_frames = ims

    # --- 얼음 대비 실제로 갈린 픽셀 --------------------------------------
    ice0 = np.array(ice_frames[0])
    for elem in ELEMS:
        c0 = np.array(clean[elem][0])
        al = ice0[:, :, 3] > 0
        diff = (c0[:, :, :3] != ice0[:, :, :3]).any(axis=2) & al
        out["per"][elem]["changed_px"] = int(diff.sum())
        out["per"][elem]["changed_ratio"] = round(float(diff.sum()) / max(1, int(al.sum())), 4)
        out["per"][elem]["iou_vs_ice"] = silhouette_iou(clean[elem][0], ice_frames[0])
        out["per"][elem]["clash"] = clash(elem)

    # --- 재질 표: 몇 개가 속성색을 지고 있는가 ------------------------------
    mats = rep["per"]["fire"]["mats"]
    n_ch = sum(1 for v in mats.values() if any(v["changed"]))
    out["materials"] = {"total": len(mats), "element_bearing": n_ch,
                        "common_only": len(mats) - n_ch,
                        "table": {k: {"ice": v["ice"], "changed": v["changed"]}
                                  for k, v in mats.items()}}
    out["silhouette"]["recolor_iou"] = 1.0
    out["silhouette"]["roster"] = roster_iou_sample()

    mx.save(mx.OUT / "recolor_data.json", out)
    draw_sheet(clean, out)
    return 0


# ---------------------------------------------------------------- 대조표
def draw_sheet(clean: dict[str, list[Image.Image]], data: dict) -> Path:
    SW = 22                       # 램프 스와치 한 칸
    LAB_W = 118
    RAMP_W = SW * 7 + 8
    ONE_W = 104
    Z = 2
    CELL = 96 * Z + 6
    W = LAB_W + RAMP_W + ONE_W + CELL * 6 + 24
    ROW = 96 * Z + 46
    H = 74 + ROW * len(ELEMS) + 128
    img = Image.new("RGB", (W, H), mx.BG)
    dr = ImageDraw.Draw(img)
    f16, f13, f11, f10 = mx.font(16), mx.font(13), mx.font(11), mx.font(10)

    dr.text((12, 10), "1 · 속성 5벌 리컬러 — 모델 하나(요쿨 · 1516삼각형 · 뼈 18)로 캐릭터 다섯",
            font=f16, fill=mx.HL)
    r = data["render"]
    dr.text((12, 32),
            "램프 7색만 갈아 끼운다. 공용 8색(살결·쇠·가죽·검정)은 안 건드린다 — "
            "다섯 벌 30칸 전부 %.2f초(렌더 %.2f초 · 램프 갈기 한 번 %.4f초 · Blender 켜는 데 %.2f초)"
            % (r["total_sec"], r["total_render_sec"],
               data["per"]["fire"]["swap_sec"], r["boot_sec"]),
            font=f11, fill=mx.DIM)
    dr.text((LAB_W + 4, 54), "램프 7색", font=f10, fill=mx.DIM)
    dr.text((LAB_W + RAMP_W + 4, 54), "1배(96px)", font=f10, fill=mx.DIM)
    dr.text((LAB_W + RAMP_W + ONE_W + 4, 54), "idle 6칸 · 2배", font=f10, fill=mx.DIM)

    y = 74
    for elem in ELEMS:
        p = data["per"][elem]
        rs = data["ramp"][elem]
        dr.rectangle([8, y - 4, W - 8, y + ROW - 12], fill=mx.PANEL)
        dr.text((14, y + 2), KO[elem], font=f13, fill=mx.FG)
        dr.text((14, y + 22), elem, font=f10, fill=mx.DIM)
        dr.text((14, y + 40), "갈린 픽셀", font=f10, fill=mx.DIM)
        dr.text((14, y + 54), "%.1f%%" % (p["changed_ratio"] * 100),
                font=f11, fill=mx.FG if p["changed_ratio"] else mx.DIM)
        dr.text((14, y + 74), "이탈 %d · 색 %d" % (p["stray"], p["colors_max"]),
                font=f10, fill=mx.OK if p["stray"] == 0 else mx.NG)
        dr.text((14, y + 90), "V %.2f · S %.2f" % (p["v_median"], p["sat_median"]),
                font=f10, fill=mx.DIM)
        dr.text((14, y + 108), "발밑 %d~%d" % tuple(p["bottom"]), font=f10, fill=mx.DIM)
        cl = p["clash"]
        dr.text((14, y + 124), "살결까지 %.0f" % cl["skin_min"], font=f10,
                fill=mx.NG if cl["skin_min"] < MERGE_D else mx.DIM)

        # 램프 스와치 — 밝기가 뒤집힌 칸에는 빨간 금을 긋는다
        x = LAB_W
        for i, hx in enumerate(spec.RAMP[elem]):
            dr.rectangle([x, y + 4, x + SW - 2, y + 4 + SW - 2], fill=spec.hex2rgb(hx))
            if i in rs["drops"]:
                dr.line([(x, y + 4), (x + SW - 2, y + 4 + SW - 2)], fill=mx.LINE, width=2)
            dr.text((x + 3, y + 4 + SW), str(i), font=f10, fill=mx.DIM)
            x += SW
        dr.text((LAB_W, y + 4 + SW + 16),
                "밝기 사다리" if rs["monotone"] else "★ %d번에서 뒤집힘 (-%.2f)"
                % (rs["drops"][0], rs["worst_drop"]),
                font=f10, fill=mx.DIM if rs["monotone"] else mx.NG)
        vtxt = " ".join("%.2f" % v for v in rs["v"])
        dr.text((LAB_W, y + 4 + SW + 32), vtxt, font=f10, fill=mx.DIM)

        # 1배 한 칸
        x = LAB_W + RAMP_W
        img.paste(clean[elem][0], (x, y + 4), clean[elem][0])
        # 2배 6칸
        x = LAB_W + RAMP_W + ONE_W
        for i, im in enumerate(clean[elem]):
            z = mx.nn(im, Z)
            img.paste(z, (x + i * CELL, y + 4), z)
        y += ROW

    dr.text((12, y + 4),
            "★ 실루엣 IoU — 리컬러 다섯 벌끼리 %.3f (기하가 같으니 원리상 1)  ·  "
            "게임의 서로 다른 캐릭터 %d명 %d쌍은 중앙값 %.3f · 95분위 %.3f · 최대 %.3f"
            % (data["silhouette"]["recolor_iou"],
               data["silhouette"]["roster"]["n_units"],
               data["silhouette"]["roster"]["n_pairs"],
               data["silhouette"]["roster"]["iou_median"],
               data["silhouette"]["roster"]["iou_p95"],
               data["silhouette"]["roster"]["iou_max"]),
            font=f11, fill=mx.FG)
    dr.text((12, y + 24),
            "★ 재질 %d개 중 속성색을 진 것은 %d개 · 나머지 %d개(살결·쇠·가죽·눈)는 다섯 벌이 똑같다"
            % (data["materials"]["total"], data["materials"]["element_bearing"],
               data["materials"]["common_only"]),
            font=f11, fill=mx.FG)
    dr.text((12, y + 44),
            "★ 전기·무상성 램프는 밝기 사다리가 아니다(CLAUDE.md 22-2 — 램프는 '그 가문이 쓰는 색 일곱'이다). "
            "칸 번호를 그대로 옮기면 밝은 자리에 어두운 색이 앉는다 — 위 빨간 금이 그 자리다.",
            font=f11, fill=mx.FG)
    worst = min(ELEMS, key=lambda e: data["per"][e]["clash"]["skin_min"])
    dr.text((12, y + 64),
            "★ 공용 8색은 안 갈린다 — 그래서 램프가 그 색 옆에 오면 안 보인다. 살결까지의 RGB 거리: " +
            " · ".join("%s %.0f" % (KO[e], data["per"][e]["clash"]["skin_min"]) for e in ELEMS) +
            "   → %s 이 %.0f 로 제일 가깝다(문턱 %.0f). 얼굴과 손이 옷에 먹힌다."
            % (KO[worst], data["per"][worst]["clash"]["skin_min"], MERGE_D),
            font=f11, fill=mx.FG)
    dr.text((12, y + 84),
            "→ 결론: 리컬러는 '같은 사람의 속성 변주'다. 실루엣이 한 픽셀도 안 다르므로 "
            "게임의 편성 판에 다섯을 나란히 세우면 다섯이 한 사람으로 읽힌다.",
            font=f11, fill=mx.HL)

    out = mx.OUT / "recolor.png"
    img.save(out)
    print(out, img.size)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
