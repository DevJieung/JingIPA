#!/usr/bin/env python3
"""마스터 후보를 뽑는다 — ART.md 1번.

★ `tools/gen_art.py` 를 **import 해서** 화풍 앵커(DOT/CUTOUT/ONE)와 후처리
  (cut_white · pixelize)를 그대로 쓴다. 복사하면 나중에 화풍을 바꿀 때 여기만 안
  바뀌어서 새 캐릭터만 따로 논다.

★ 1024x1024 원본(`*_raw.png`)을 **반드시 남긴다.** 등급(=저장 높이)은 후처리에서만
  쓰이므로, 등급을 나중에 바꿔도 GPU 를 다시 돌릴 필요가 없다 — `--repost` 로
  원본에서 다시 줄이면 된다. 한 장에 70초, 모델 올리는 데 4분이라 이 차이가 크다.

    python3 tools/anim/gen_master.py frost_queen --seeds 3
    python3 tools/anim/gen_master.py frost_queen --repost --tier 8
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, "/home/dgxmaruta/pjt/krea2")

import gen_art as GA   # noqa: E402  — 화풍 앵커는 여기 한 곳에만 있다

HERE = os.path.dirname(os.path.abspath(__file__))
CONCEPTS = os.path.join(HERE, "concepts.json")


def load(name: str) -> dict:
    with open(CONCEPTS, encoding="utf-8") as f:
        all_ = json.load(f)
    if name not in all_:
        raise SystemExit(f"concepts.json 에 {name} 이 없다. 있는 것: {list(all_)}")
    return all_[name]


def jobs(name: str, c: dict, seeds: int, only: str = "") -> list[dict]:
    """컨셉 x 시드. `poses` 에 적힌 갈래는 그 갈래만의 자세를 쓴다.

    ★ 자세를 갈래마다 따로 둘 수 있어야 하는 이유 — 같은 캐릭터를 **다른 자세로** 다시
      뽑아 볼 때 앞서 뽑은 갈래까지 새 자세로 다시 돌게 하면 안 된다. 궁수에서 실제로
      겪었다: 활을 든 아홉 장이 전부 활을 **몸 뒤에** 들고 있어 겨누는 자세로 다시
      뽑아야 했는데, `pose` 하나만 있으면 멀쩡한 아홉 장을 GPU 14분 들여 다시 돌려야 한다.
    """
    keys = [k.strip() for k in only.split(",") if k.strip()] if only else None
    out = []
    for key, body in c["bodies"].items():
        if keys and key not in keys:
            continue
        pose = c.get("poses", {}).get(key, c["pose"])
        for s in range(seeds):
            out.append(dict(
                tag=f"{key}{s}",
                prompt=f"{GA.ONE}{body}, {GA.DOT}{pose}{GA.CUTOUT}",
                seed=(GA._seed(f"{name}_{key}") + s * 104729) % 2000000))
    return out


def post(raw_path: str, out_path: str, out_h: int, holes: bool = False) -> tuple[int, int, float, float]:
    """원본 → 오려내기 → 도트. 순서를 바꾸지 마라(gen_art.pixelize 주석)."""
    from PIL import Image
    img = Image.open(raw_path)
    # holes 는 기본으로 끈다. 갇힌 배경을 지울지는 **사람이** 고른 뒤에 정한다 (CLAUDE.md 4-3).
    # ★ 활을 든 캐릭터는 예외다 — **시위 안쪽에 갇힌 배경이 반드시 생긴다.** 옷 하이라이트와
    #   달리 그건 눈으로 볼 것도 없이 배경이고, 안 지우면 활에 흰 판때기가 붙어 나온다
    #   (장궁수·짚신궁수·달빛궁수가 실제로 그랬다 — CLAUDE.md 4-3). `--holes` 로 켠다.
    #   GPU 를 다시 안 돌려도 된다: `--repost --holes` 로 원본에서 다시 줄이면 된다.
    cut, kept, trapped = GA.cut_white(img, holes=holes)
    px = GA.pixelize(cut, out_h, GA.COLORS_UNIT)
    px.save(out_path, optimize=True)
    return px.size[0], px.size[1], kept, trapped


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("name")
    ap.add_argument("--seeds", type=int, default=3, help="컨셉마다 시드 몇 개")
    ap.add_argument("--tier", type=int, default=-1, help="등급(높이). 안 주면 concepts.json")
    ap.add_argument("--only", default="", help="이 갈래만 (예: d,e,f)")
    ap.add_argument("--holes", action="store_true",
                    help="갇힌 배경을 지운다. ★ **활을 든 캐릭터는 켜라** — 시위 안쪽은 "
                         "언제나 배경이다. concepts.json 의 holes 로도 켤 수 있다")
    ap.add_argument("--repost", action="store_true",
                    help="GPU 없이 남겨 둔 *_raw.png 에서 후처리만 다시 한다")
    a = ap.parse_args()

    c = load(a.name)
    tier = a.tier if a.tier >= 0 else int(c["tier"])
    out_h = GA.unit_h(tier)
    holes = a.holes or bool(c.get("holes", False))
    out_dir = os.path.join(ROOT, "build", a.name, "cand")
    os.makedirs(out_dir, exist_ok=True)
    js = jobs(a.name, c, a.seeds, a.only)
    print(f"[{a.name}] 등급 {tier} → 높이 {out_h}px · 후보 {len(js)}장", flush=True)

    if a.repost:
        for j in js:
            raw = os.path.join(out_dir, f"{j['tag']}_raw.png")
            if not os.path.exists(raw):
                continue
            w, h, kept, trapped = post(raw, os.path.join(out_dir, f"{j['tag']}.png"),
                                       out_h, holes)
            print(f"  {j['tag']}  {w}x{h}  남은넓이 {kept:.0%}  갇힌흰색 {trapped:.2%}", flush=True)
        return 0

    # ★ Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 — 올리기 전에 문지기를 부른다 (tools/gpu_guard.py)
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    import gpu_guard
    gpu_guard.claim("krea2")
    from krea2.pipelines.image import Krea2ImagePipeline
    t0 = time.time()
    print("[gen] 모델 올리는 중 (3~4분)", flush=True)
    pipe = Krea2ImagePipeline("turbo").load()
    print(f"[gen] 모델 준비 완료 ({time.time()-t0:.0f}초)", flush=True)

    for i, j in enumerate(js, 1):
        t1 = time.time()
        img = pipe.generate(j["prompt"], width=1024, height=1024, seed=j["seed"])[0].image
        raw = os.path.join(out_dir, f"{j['tag']}_raw.png")
        img.save(raw)
        w, h, kept, trapped = post(raw, os.path.join(out_dir, f"{j['tag']}.png"),
                                   out_h, holes)
        print(f"[gen] ({i}/{len(js)}) {j['tag']}  {w}x{h}  남은넓이 {kept:.0%}  "
              f"갇힌흰색 {trapped:.2%}  {time.time()-t1:.0f}초", flush=True)

    print(f"[gen] 완료 {(time.time()-t0)/60:.1f}분 → {out_dir}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
