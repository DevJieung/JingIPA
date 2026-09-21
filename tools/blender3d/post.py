#!/usr/bin/env python3
"""6단계 — 후처리. 렌더 낱장을 **팔레트에 앉히고** 1도트 테두리를 두른다.

    python3 tools/blender3d/post.py --unit estoque --elem fire

★★ **공식 파이프라인의 `tools/sprite/pixels.py` 를 그대로 빌려 쓴다.** 고치지 않는다.
   까닭: 두 길을 견주는 것이 이 테스트의 전부인데, 후처리 코드가 서로 다르면 차이가
   「3D 냐 영상이냐」에서 온 것인지 「양자화 코드가 다른가」에서 온 것인지 갈리지 않는다.
   같은 `quantize` · 같은 `add_outline` · 같은 `pack_sheet` 를 쓰면 남는 차이는
   **원본 프레임의 차이뿐**이다.

★ 팔레트만 다르다 — 공식은 15색(램프 7 + 공용 8)이고 여기는 **24색**이다(spec.py 머리말).
  3D 툰은 면마다 명/암이 갈려서 중간 톤을 더 쓴다.

★ `lift`(밝기 감마)는 **기본으로 끈다.** 공식 길이 그것을 켜는 까닭은 1024px 일러스트를
  96px 로 **줄이면서** 어두운 쪽으로 밀리는 몫을 미리 갚기 위해서다(pixels.LIFT_GAMMA
  머리말). 3D 길은 애초에 96px 로 렌더하므로 줄이는 일이 없고, 재질 색이 이미 팔레트
  그 자체라 갚을 몫이 없다. 켜면 오히려 의도한 칸보다 한 톤 위로 접힌다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "sprite"))
import spec        # noqa: E402
import pixels      # noqa: E402  ← 공식 파이프라인의 규격. 읽기만 한다.


def clean_one(src: Path, palette: list[str], outline: bool = True,
              lift_gamma: float = 1.0, lift_sat: float = 1.0) -> Image.Image:
    """낱장 하나를 팔레트에 앉힌다."""
    im = Image.open(src).convert("RGBA")
    # 1) 반투명을 없앤다. 도트 그림에 반투명 가장자리는 없다.
    #    ★ filter_size=0 으로 렌더하면 거의 안 생기지만, 인버티드 헐의 뒷면이나
    #      알파 블렌딩 재질이 섞이면 한두 줄이 남는다. 그것이 남은 채로 양자화하면
    #      가장자리가 회색으로 갈려서 검은 테두리가 뭉갠다.
    im = pixels.binarize_alpha(im)
    # 2) (기본 꺼짐) 줄이면서 잃는 몫 갚기 — 3D 길에는 줄이는 일이 없다
    if lift_gamma != 1.0 or lift_sat != 1.0:
        im = pixels.lift(im, gamma=lift_gamma, sat=lift_sat)
    # 3) 팔레트에 앉힌다 (디더 없음)
    im = pixels.quantize(im, palette)
    # 4) 1도트 검은 테두리
    if outline:
        im = pixels.add_outline(im, spec.OUTLINE)
    return im


def run(uid: str, elem: str, outline: bool = True, lift: bool = False) -> dict:
    p = spec.paths(uid)
    frames, clean = p["frames"], p["clean"]
    if not frames.exists():
        raise SystemExit(f"렌더 낱장이 없습니다: {frames} — 5단계를 먼저 돌리세요")
    palette = spec.palette_for(elem)
    lg = pixels.LIFT_GAMMA if lift else 1.0
    ls = pixels.LIFT_SAT if lift else 1.0

    rep: dict = {"unit": uid, "elem": elem, "palette_n": len(palette),
                 "outline_drawn": outline, "lift": lift, "clips": {}}
    for act_dir in sorted(d for d in frames.iterdir() if d.is_dir()):
        act = act_dir.name
        rep["clips"][act] = {}
        for dir_dir in sorted(d for d in act_dir.iterdir() if d.is_dir()):
            dname = dir_dir.name
            outd = clean / act / dname
            outd.mkdir(parents=True, exist_ok=True)
            srcs = sorted(dir_dir.glob("*.png"))
            metrics = []
            for s in srcs:
                im = clean_one(s, palette, outline=outline,
                               lift_gamma=lg, lift_sat=ls)
                im.save(outd / s.name)
                metrics.append(_measure(im))
            rep["clips"][act][dname] = {
                "n": len(srcs),
                "frames": metrics,
                # ★ 발이 튀는가 — 3D 는 카메라가 고정이라 원리상 0 이어야 한다.
                #   0 이 아니면 5단계에서 캐릭터가 격자에서 벗어나 도는 것이다.
                "foot_y_spread": (max(m["bottom"] for m in metrics)
                                  - min(m["bottom"] for m in metrics)) if metrics else 0,
                "cx_spread": (max(m["cx"] for m in metrics)
                              - min(m["cx"] for m in metrics)) if metrics else 0,
            }
    (p["root"] / "post_report.json").write_text(
        json.dumps(rep, ensure_ascii=False, indent=1))
    return rep


def _measure(im: Image.Image) -> dict:
    """낱장 하나의 잣대 — 발밑 y · 가로 가운데 · 채운 넓이 · 고유 색 수."""
    a = im.split()[3]
    bb = a.getbbox()
    if bb is None:
        return {"bottom": -1, "cx": -1, "fill": 0, "colors": 0, "bbox": None}
    x0, y0, x1, y1 = bb
    px = im.load()
    n = 0
    seen = set()
    sx = 0
    for y in range(y0, y1):
        for x in range(x0, x1):
            r, g, b, al = px[x, y]
            if al:
                n += 1
                sx += x
                seen.add((r, g, b))
    return {"bottom": y1, "cx": round(sx / max(1, n), 2), "fill": n,
            "colors": len(seen), "bbox": [x0, y0, x1, y1]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", default="estoque")
    ap.add_argument("--elem", default="fire")
    ap.add_argument("--no-outline", action="store_true",
                    help="렌더 단계에서 인버티드 헐로 이미 그렸을 때")
    ap.add_argument("--lift", action="store_true", help="밝기 감마를 켠다 (기본 꺼짐)")
    a = ap.parse_args()
    r = run(a.unit, a.elem, outline=not a.no_outline, lift=a.lift)
    for act, dirs in r["clips"].items():
        for d, v in dirs.items():
            print(f"  {act:7s} {d:3s} {v['n']}칸 · 발밑 흔들림 {v['foot_y_spread']}px · "
                  f"가운데 흔들림 {v['cx_spread']:.2f}px · "
                  f"색 {max((m['colors'] for m in v['frames']), default=0)}")
