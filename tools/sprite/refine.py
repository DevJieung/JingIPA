#!/usr/bin/env python3
"""Step 1-b — 후보를 눈으로 고르고, 마스터(96 도트)와 Wan 입력(512 마젠타)을 굽는다.

    python3 tools/sprite/refine.py --route sdxl --contact          # 후보 한 판에 모아 보기
    python3 tools/sprite/refine.py --route sdxl --pick glacier_lord=2 ...
    python3 tools/sprite/refine.py --route sdxl --all              # 골라 둔 것으로 굽기

★ 고르는 것은 **사람**이다. 지침 §3 Step 4 가 「Aseprite 정리 생략 금지」라고 못 박은
  것과 같은 까닭이다 — 어느 후보가 그 캐릭터로 보이는가는 픽셀로 못 잰다.
  고른 것은 `picks.json` 에 남아서 다시 돌려도 같은 그림이 나온다.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import units as U                                # noqa: E402
from make_ref import refine, to_wan_input        # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")
SDXL_REF = "/home/dgxmaruta/pjt/pixelforge/projects/pocker/00_ref"


def candidates(route: str, uid: str) -> list[str]:
    if route == "sdxl":
        # pixelforge 는 <시각>_<이름-슬러그>_s<시드>.png 로 적는다
        slug = uid.replace("_", "-")
        fs = [f for f in sorted(os.listdir(SDXL_REF))
              if f.endswith(".png") and f"_{slug}_" in f]
        return [os.path.join(SDXL_REF, f) for f in fs]
    d = os.path.join(OUT, "krea", "raw")
    fs = [f for f in sorted(os.listdir(d)) if f.startswith(uid) and f.endswith(".png")] \
        if os.path.isdir(d) else []
    return [os.path.join(d, f) for f in fs]


def contact(route: str, us: list[dict], cell: int = 256) -> str:
    """후보를 한 판에. 줄이 캐릭터, 칸이 후보다."""
    rows = [(u, candidates(route, u["id"])) for u in us]
    ncol = max((len(c) for _, c in rows), default=1)
    W, H = cell * ncol + 150, cell * len(rows)
    sheet = Image.new("RGB", (W, H), (24, 24, 28))
    dr = ImageDraw.Draw(sheet)
    for r, (u, cs) in enumerate(rows):
        dr.text((6, r * cell + 6), f"{u['id']}\n{u['elem']}\n{u['family']}", fill=(230, 230, 230))
        for c, p in enumerate(cs):
            im = Image.open(p).convert("RGBA")
            bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
            im = Image.alpha_composite(bg, im).convert("RGB").resize((cell - 8, cell - 8))
            sheet.paste(im, (150 + c * cell + 4, r * cell + 4))
            dr.text((150 + c * cell + 8, r * cell + 8), str(c), fill=(255, 40, 40))
    os.makedirs(OUT, exist_ok=True)
    dst = os.path.join(OUT, f"contact_{route}.png")
    sheet.save(dst)
    print(dst, sheet.size)
    return dst


def picks_path(route: str) -> str:
    return os.path.join(OUT, f"picks_{route}.json")


def load_picks(route: str) -> dict:
    p = picks_path(route)
    return json.load(open(p)) if os.path.exists(p) else {}


def bake(route: str, us: list[dict], picks: dict, cut: str) -> None:
    """고른 후보 → (배경 떼기) → 마스터(96) → Wan 입력(512 마젠타).

    ★ SDXL 은 「plain white background」를 자주 어긴다 — 열다섯 장 중 흰 배경이
      **한 장도 없었다**(전부 회색·풍경). 흰 배경을 전제로 한 물 붓기는 그 순간
      한 픽셀도 못 번지므로, 뜻으로 가르는 BiRefNet 을 쓴다(`cutbg.py`).
      Krea 경로는 `make_ref` 가 이미 `gen_art.cut_white` 로 떼어 놓았다.
    """
    md = os.path.join(OUT, route, "master")
    wd = os.path.join(OUT, route, "wan_in")
    cd = os.path.join(OUT, route, "cut")
    for d in (md, wd, cd):
        os.makedirs(d, exist_ok=True)

    chosen: list[tuple[dict, str]] = []
    for u in us:
        cs = candidates(route, u["id"])
        if not cs:
            print(f"  {u['id']}: 후보 없음"); continue
        i = int(picks.get(u["id"], 0))
        chosen.append((u, cs[min(i, len(cs) - 1)]))

    if cut == "birefnet":
        import cutbg
        pairs = [(src, os.path.join(cd, u["id"] + ".png")) for u, src in chosen]
        cutbg.cut(pairs)                          # 모델을 한 번만 올린다
        chosen = [(u, os.path.join(cd, u["id"] + ".png")) for u, _ in chosen]

    for u, src in chosen:
        img = Image.open(src).convert("RGBA")
        master = refine(img, u["size"], u["elem"])
        master.save(os.path.join(md, u["id"] + ".png"))
        to_wan_input(master).save(os.path.join(wd, u["id"] + ".png"))
        cols = len({p[:3] for p in master.getdata() if p[3] > 0})
        opaque = sum(1 for p in master.getdata() if p[3] > 0)
        print(f"  {u['id']:16s} {cols}색  채워진 {opaque}/{u['size']**2}px")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="sdxl", choices=("sdxl", "krea"))
    ap.add_argument("--contact", action="store_true")
    ap.add_argument("--pick", nargs="*", default=[], help="id=번호 …")
    ap.add_argument("--all", action="store_true", help="골라 둔 것으로 굽기")
    ap.add_argument("--only", default="")
    ap.add_argument("--cut", default="", choices=("", "birefnet", "none"),
                    help="배경 떼는 법 (sdxl 은 birefnet 이 기본)")
    a = ap.parse_args()

    ids = [s for s in a.only.split(",") if s] or U.PILOT
    us = U.load(ids)
    if a.contact:
        contact(a.route, us)
        return 0
    picks = load_picks(a.route)
    for kv in a.pick:
        k, v = kv.split("=")
        picks[k] = int(v)
    if a.pick:
        json.dump(picks, open(picks_path(a.route), "w"), indent=1)
    cut = a.cut or ("birefnet" if a.route == "sdxl" else "none")
    if a.all or a.pick:
        bake(a.route, us, picks, cut)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
