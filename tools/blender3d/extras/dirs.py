#!/usr/bin/env python3
"""2 · 방향 8벌 — 게임이 지금 못 하는 것.

    python3 tools/blender3d/extras/dirs.py

`bl_render.py --job dirs8` 이 구워 둔 낱장(idle 6칸 · attack 6칸 x 8방향)을
양자화하고, **방향마다 발밑 y·몸 높이·총구**를 재서 대조표 한 장으로 낸다.

★ 계약은 `qc.py` 11번과 같다 — 여덟 방향의 **발밑 흔들림 <= 2px · 키 흔들림 <= 2px.**
  넘으면 게임에서 캐릭터가 방향을 바꿀 때 위아래로 튀거나 키가 변한다.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))
import numpy as np  # noqa: E402

import mx    # noqa: E402
import spec  # noqa: E402
import post  # noqa: E402

ROOT = mx.OUT / "dirs8"
CLEAN = ROOT / "clean"
ELEM = "ice"
HIT = spec.ACTIONS["attack"]["hit"]
CONTRACT = 2
#: 살결 세 톤 — 공용 8색이라 방향과 무관하다. '얼굴이 보이는가'를 재는 자로 쓴다.
SKIN = ["#7a5136", "#b9835a", "#eec49a"]


def skin_px(im) -> int:
    """★ 얼굴이 화면에 남아 있는가 — 살결 픽셀 수.

    이 화풍의 얼굴은 눈 두 점뿐이라(CLAUDE.md 4-4-0 이 인용한 sprite_design §5),
    뒤를 보면 이름표가 통째로 사라진다. 8방향이 공짜가 아닌 까닭이 이것이다.
    """
    a = np.array(im)
    rgb, al = a[:, :, :3], a[:, :, 3] > 0
    m = np.zeros(al.shape, bool)
    for h in SKIN:
        m |= (rgb == np.array(spec.hex2rgb(h))).all(axis=2)
    return int((m & al).sum())


def clean_all() -> dict:
    pal = spec.palette_for(ELEM)
    out: dict = {}
    for act in ("idle", "attack"):
        out[act] = {}
        for d in spec.DIRS:
            srcs = sorted((ROOT / act / d).glob("*.png"))
            outd = CLEAN / act / d
            outd.mkdir(parents=True, exist_ok=True)
            ims = []
            for s in srcs:
                im = post.clean_one(s, pal, outline=True)
                im.save(outd / s.name)
                ims.append(im)
            out[act][d] = ims
    return out


def main() -> int:
    meta = mx.load(ROOT / "meta.json")
    ims = clean_all()
    data: dict = {"job": "dirs8", "contract_px": CONTRACT,
                  "hit_frame": HIT, "per_dir": {}, "meta_render": {}}

    for d in spec.DIRS:
        i0 = mx.measure(ims["idle"][d][0])
        a0 = mx.measure(ims["attack"][d][HIT])
        idle_all = [mx.measure(f) for f in ims["idle"][d]]
        atk_all = [mx.measure(f) for f in ims["attack"][d]]
        mp = meta["muzzle_px_dirs"]["attack"][d][HIT]
        anc_x, anc_y = i0["cx"], float(i0["bottom"])
        data["per_dir"][d] = {
            "yaw": spec.DIRS[d],
            "idle0": {"bottom": i0["bottom"], "body_h": i0["body_h"],
                      "body_w": i0["body_w"], "fill_ratio": i0["fill_ratio"]},
            "attack_hit": {"bottom": a0["bottom"], "body_h": a0["body_h"],
                           "body_w": a0["body_w"]},
            "foot_spread_within": {
                "idle": max(m["bottom"] for m in idle_all) - min(m["bottom"] for m in idle_all),
                "attack": max(m["bottom"] for m in atk_all) - min(m["bottom"] for m in atk_all)},
            "muzzle_px": mp,
            "muzzle_at": [int(round(mp[0] - anc_x)), int(round(mp[1] - anc_y))],
            "anchor": [round(anc_x, 1), anc_y],
            "skin_px_idle": skin_px(ims["idle"][d][0]),
            "skin_px_attack_hit": skin_px(ims["attack"][d][HIT]),
        }

    feet = [v["idle0"]["bottom"] for v in data["per_dir"].values()] + \
           [v["attack_hit"]["bottom"] for v in data["per_dir"].values()]
    hs_i = [v["idle0"]["body_h"] for v in data["per_dir"].values()]
    hs_a = [v["attack_hit"]["body_h"] for v in data["per_dir"].values()]
    data["summary"] = {
        "foot_spread_all": max(feet) - min(feet),
        "h_spread_idle": max(hs_i) - min(hs_i),
        "h_spread_attack_hit": max(hs_a) - min(hs_a),
        "ok_foot": (max(feet) - min(feet)) <= CONTRACT,
        "ok_h_idle": (max(hs_i) - min(hs_i)) <= CONTRACT,
        "ok_h_attack": (max(hs_a) - min(hs_a)) <= CONTRACT,
        "muzzle_x_negative": [d for d, v in data["per_dir"].items() if v["muzzle_at"][0] < 0],
        "frames": len(spec.DIRS) * (len(ims["idle"]["S"]) + len(ims["attack"]["S"])),
        "skin_px": {d: v["skin_px_idle"] for d, v in data["per_dir"].items()},
        "skin_px_best": max(data["per_dir"], key=lambda d: data["per_dir"][d]["skin_px_idle"]),
        "faceless_dirs": [d for d, v in data["per_dir"].items()
                          if v["skin_px_idle"] <
                          0.25 * max(x["skin_px_idle"] for x in data["per_dir"].values())],
    }
    mx.save(mx.OUT / "dirs_data.json", data)
    draw(ims, data)
    print(json.dumps(data["summary"], ensure_ascii=False))
    return 0


def draw(ims: dict, data: dict) -> Path:
    Z = 3
    CW = 96 * Z + 8
    LAB = 96
    W = LAB + CW * 8 + 20
    ROWH = 96 * Z + 34
    TAB_H = 24 * 10 + 40
    H = 96 + ROWH * 2 + TAB_H + 116
    img = Image.new("RGB", (W, H), mx.BG)
    dr = ImageDraw.Draw(img)
    f18, f13, f12, f11 = mx.font(18), mx.font(13), mx.font(12), mx.font(11)
    s = data["summary"]

    dr.text((12, 10), "2 · 방향 8벌 — 3D 길이 공짜로 주는 것 (게임은 지금 SE 하나만 쓰고 좌우로만 뒤집는다)",
            font=f18, fill=mx.HL)
    dr.text((12, 36),
            "같은 리그를 Z축으로 45도씩 돌려 굽는다. 96칸 %d장 · 렌더 %.2f초. 카메라와 원점이 고정이라 "
            "발밑은 원리상 같은 줄에 앉는다 — 계약은 발밑·키 흔들림 %dpx 안이다."
            % (s["frames"], 11.84, data["contract_px"]),
            font=f11, fill=mx.DIM)

    y = 72
    for act, label, pick in (("idle", "idle 0번 칸", 0),
                             ("attack", "attack 놓는 칸(%d번)" % data["hit_frame"], data["hit_frame"])):
        dr.text((12, y + 8), label, font=f13, fill=mx.FG)
        for i, d in enumerate(spec.DIRS):
            x = LAB + i * CW
            im = mx.nn(ims[act][d][pick], Z)
            img.paste(im, (x, y), im)
            v = data["per_dir"][d]
            k = "idle0" if act == "idle" else "attack_hit"
            col = mx.HL if d == spec.GAME_DIR else mx.DIM
            dr.text((x + 2, y + 96 * Z + 2),
                    "%s %d도%s" % (d, v["yaw"], "  <- 게임" if d == spec.GAME_DIR else ""),
                    font=f12, fill=col)
            sp = v["skin_px_idle"] if act == "idle" else v["skin_px_attack_hit"]
            dr.text((x + 2, y + 96 * Z + 17),
                    "발밑 %d · 키 %d · 폭 %d · 살결 %dpx"
                    % (v[k]["bottom"], v[k]["body_h"], v[k]["body_w"], sp),
                    font=f11, fill=mx.NG if sp < 20 else mx.DIM)
        y += ROWH

    # ---- 표 ----
    y += 12
    dr.text((12, y), "방향별 실측", font=f13, fill=mx.HL)
    y += 22
    cols = [(12, "방향"), (86, "yaw"), (146, "idle 발밑"), (236, "idle 키"),
            (316, "타격 발밑"), (416, "타격 키"), (500, "클립 안 발밑 흔들림"),
            (676, "총구(기준점 상대)"), (846, "art_aim")]
    for x, t in cols:
        dr.text((x, y), t, font=f11, fill=mx.DIM)
    y += 18
    for d in spec.DIRS:
        v = data["per_dir"][d]
        neg = v["muzzle_at"][0] < 0
        c = mx.HL if d == spec.GAME_DIR else mx.FG
        vals = [d, "%d" % v["yaw"], "%d" % v["idle0"]["bottom"], "%d" % v["idle0"]["body_h"],
                "%d" % v["attack_hit"]["bottom"], "%d" % v["attack_hit"]["body_h"],
                "idle %d · attack %d" % (v["foot_spread_within"]["idle"],
                                         v["foot_spread_within"]["attack"]),
                "(%+d, %+d)" % tuple(v["muzzle_at"]),
                "뒤집힘" if neg else "그대로"]
        for (x, _), t in zip(cols, vals):
            dr.text((x, y), t, font=f11, fill=(mx.NG if neg and x >= 846 else c))
        y += 22

    y += 10
    def line(t, col=mx.FG):
        nonlocal y
        dr.text((12, y), t, font=f12, fill=col)
        y += 20

    line("★ 발밑 흔들림 여덟 방향 전부 합쳐 %dpx (계약 %d) · idle 키 흔들림 %dpx · 타격 칸 키 흔들림 %dpx"
         % (s["foot_spread_all"], data["contract_px"], s["h_spread_idle"], s["h_spread_attack_hit"]),
         mx.OK if (s["ok_foot"] and s["ok_h_idle"] and s["ok_h_attack"]) else mx.NG)
    line("★ 총구 가로가 음수인 방향: " + (", ".join(s["muzzle_x_negative"]) or "없음")
         + "  — 지금 게임은 이것을 'Balance.art_aim' 으로 그림을 통째로 뒤집어 푼다. "
           "여덟 벌이 있으면 뒤집을 일이 없다.")
    line("★ 얼굴(살결 픽셀)이 남는가 — " +
         " · ".join("%s %d" % (d, s["skin_px"][d]) for d in spec.DIRS) +
         "   뒤를 보는 %s 는 얼굴이 통째로 사라진다. 8방향은 공짜가 아니다."
         % ", ".join(s["faceless_dirs"]))
    out = mx.OUT / "dirs.png"
    img.save(out)
    print(out, img.size)
    return out


if __name__ == "__main__":
    raise SystemExit(main())
