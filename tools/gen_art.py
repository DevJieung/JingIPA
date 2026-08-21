#!/usr/bin/env python3
"""포커 디펜스 — 도트 그림을 로컬 Krea 2 Turbo 로 만든다.

이 컴퓨터(DGX Spark GB10)에 설치된 Krea 2 를 직접 부른다. 모델 올리는 데만 3~4분
걸리므로 한 번 올려서 전부 이어서 뽑는다 (한 장에 약 65초).

    python3 tools/gen_art.py                 # 없는 것만
    python3 tools/gen_art.py --list          # 목록만
    python3 tools/gen_art.py --only 용기사,슬라임 --force
    python3 tools/gen_art.py --kind unit     # 캐릭터만 (unit|monster|ui)

결과: art/units/<id>.png · art/monsters/<id>.png · art/ui/<id>.png

★ 화풍 앵커가 이 파일에 있다. roster.json 의 prompt 는 **몸통 묘사만** 들어 있고
  화풍·구도·배경 문구는 전부 여기서 붙인다. 그래야 나중에 화풍을 통째로 바꿀 때
  50여 줄을 고치지 않고 이 파일 한 곳만 고치면 된다.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time

KREA_ROOT = "/home/dgxmaruta/pjt/krea2"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROSTER = os.path.join(ROOT, "tools", "roster.json")
sys.path.insert(0, KREA_ROOT)

# --------------------------------------------------------------------------- #
# 화풍 앵커 — 후보 셋을 실제로 뽑아 보고 고른 것이다 (build/styletest/).
#   "16비트 SNES JRPG 스프라이트"가 (1) 96px 로 줄여도 실루엣이 살고
#   (2) 잡졸부터 용까지 같은 결로 나와서 골랐다.
# --------------------------------------------------------------------------- #
DOT = ("16-bit pixel art sprite, retro SNES japanese role playing game character sprite, "
       "crisp clean pixels, limited color palette, thick black outline, "
       "strong readable silhouette, flat cel shading with dithering")

CUTOUT = (", full body from head to feet inside the frame, centered, "
          "cut out on a pure flat white background, no ground, no shadow, no scenery, "
          "no base, no stand, no text, no watermark, no grid, no border, no frame")

ONE = "a single character, only one creature in the picture, nothing else, "

UNIT_POSE = ", standing in a confident front three-quarter view"
MON_POSE = ", front view, menacing pose"
BOSS_POSE = ", gigantic and imposing, front view, towering over the viewer"

SCENE = ("16-bit pixel art game background illustration, retro SNES style, crisp clean pixels, "
         "limited color palette, flat cel shading with dithering, no text, no watermark, "
         "no user interface, no border")

# --------------------------------------------------------------------------- #
# 저장 크기 — 화면에 1:1 로 그린다. 도트는 확대하면 뭉개지고 축소하면 이가 빠진다.
#   ★ core/roster.gd 의 h 값이 여기서 나온다 (tools/gen_roster.py 가 같은 표를 읽는다).
# --------------------------------------------------------------------------- #
def unit_h(tier_index: int) -> int:
    """등급이 오를수록 조금씩 커진다. 로열은 하이카드보다 한 뼘 크다."""
    return 96 + tier_index * 5


MON_H = {"swarm": 52, "fast": 48, "tank": 68, "caster": 58, "boss": 132}

# UI 그림은 저마다 크기가 다르다. (가로, 세로, 생성 해상도)
UI_SIZE = {
    "arena_floor": (720, 720, 1024, 1024),
    "arena_bg":    (1280, 800, 1024, 640),
    "card_back":   (118, 168, 768, 1024),
    "title_art":   (1280, 620, 1024, 512),
    "coin":        (36, 36, 768, 768),
    "heart":       (34, 34, 768, 768),
    "shop_bg":     (1280, 800, 1024, 640),
    "boom":        (128, 128, 768, 768),
}

# 팔레트 색 수. 적을수록 도트 느낌이 강해지지만 너무 적으면 그라데이션이 띠가 된다.
COLORS_UNIT = 40
COLORS_SCENE = 64


def load_roster() -> dict:
    with open(ROSTER, encoding="utf-8") as f:
        return json.load(f)


def jobs(r: dict) -> list[dict]:
    """뽑을 것 전부를 한 줄씩. seed 는 id 로 정해서 다시 돌려도 같은 그림이 나온다."""
    out: list[dict] = []
    for ti, t in enumerate(r["tiers"]):
        for u in t["units"]:
            out.append(dict(
                kind="unit", id=u["id"], ko=u["ko"], dir="units",
                prompt=f"{ONE}{u['prompt']}, {DOT}{UNIT_POSE}{CUTOUT}",
                w=1024, h=1024, out_h=unit_h(ti), cut=True, colors=COLORS_UNIT,
                seed=_seed(u["id"])))
    for m in r["monsters"]:
        pose = BOSS_POSE if m["kind"] == "boss" else MON_POSE
        out.append(dict(
            kind="monster", id=m["id"], ko=m["ko"], dir="monsters",
            prompt=f"{ONE}{m['prompt']}, {DOT}{pose}{CUTOUT}",
            w=1024, h=1024, out_h=MON_H[m["kind"]], cut=True, colors=COLORS_UNIT,
            seed=_seed(m["id"])))
    for a in r["arts"]:
        tw, th, gw, gh = UI_SIZE[a["id"]]
        if a["cut"]:
            prompt = f"{ONE}{a['prompt']}, {DOT}{CUTOUT}"
        else:
            prompt = f"{a['prompt']}, {SCENE}"
        out.append(dict(
            kind="ui", id=a["id"], ko=a["ko"], dir="ui", prompt=prompt,
            w=gw, h=gh, out_w=tw, out_h=th, cut=a["cut"],
            colors=COLORS_UNIT if a["cut"] else COLORS_SCENE, seed=_seed(a["id"])))
    return out


def _seed(name: str) -> int:
    """이름에서 만든 고정 시드. --force 로 다시 돌려도 같은 그림이 나온다."""
    h = 2166136261
    for ch in name:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h % 2000000


# --------------------------------------------------------------------------- #
# 흰 배경 오려내기 — 모서리에서 물을 부어 흰 곳만 지운다.
#   색이 있거나 어두운 곳(=그림)에는 미리 벽을 세워 두므로 물이 못 넘어온다.
#   ⚠ 흰 옷을 입은 캐릭터가 위험하지만, 화풍에 "thick black outline" 이 들어 있어서
#     외곽선이 벽 노릇을 한다. 그래도 실패를 조용히 넘기지 않게 아래에서 넓이를 잰다.
# --------------------------------------------------------------------------- #
def cut_white(img, thresh: int = 26, feather: float = 0.6):
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np

    rgb = img.convert("RGB")
    w, h = rgb.size
    arr = np.array(rgb).astype("int16")
    sat = arr.max(axis=2) - arr.min(axis=2)
    val = arr.max(axis=2)
    protect = (sat > 22) | (val < 205)

    work = np.array(rgb)
    work[protect] = 0
    wimg = Image.fromarray(work)
    key = (255, 0, 255)
    for xy in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
               (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        try:
            ImageDraw.floodfill(wimg, xy, key, thresh=thresh)
        except Exception:
            pass

    warr = np.array(wimg)
    bg = ((warr[:, :, 0] == key[0]) & (warr[:, :, 1] == key[1]) & (warr[:, :, 2] == key[2]))
    alpha = Image.fromarray(((~bg) * 255).astype("uint8"), mode="L")
    if feather > 0:
        alpha = alpha.filter(ImageFilter.GaussianBlur(feather))
        a = np.array(alpha).astype("float32")
        a = np.clip((a - 110.0) * 3.2 + 128.0, 0, 255)
        alpha = Image.fromarray(a.astype("uint8"), mode="L")

    kept = float((~bg).sum()) / float(w * h)

    # ★ 물이 그림 안까지 새어 들어가 캐릭터를 통째로 지워 버리는 일이 있다
    #   (밝은 회색 옷을 입은 거인 하나가 실제로 빈 그림이 됐다).
    #   그럴 때는 물 붓기를 포기하고 **거의 흰 픽셀만** 지운다. 배경이 조금 남을 수는
    #   있지만, 아무것도 없는 그림보다는 백 배 낫다.
    if kept < 0.05:
        near_white = (sat < 18) & (val > 234)
        alpha = Image.fromarray(((~near_white) * 255).astype("uint8"), mode="L")
        kept = float((~near_white).sum()) / float(w * h)

    out = img.convert("RGBA")
    out.putalpha(alpha)
    bbox = out.getbbox()
    if bbox:
        out = out.crop(bbox)
    return out, kept


def pixelize(img, out_h: int, colors: int, out_w: int = 0):
    """도트로 만든다: BOX 로 줄이고(평균이라 이가 안 빠진다) 팔레트를 줄인다.

    ⚠ 줄이기 **전에** 팔레트를 줄이면 색이 뭉개진 채로 평균이 나서 지저분해진다.
      반드시 줄이고 나서 줄인다.
    """
    from PIL import Image
    w, h = img.size
    tw = out_w if out_w else max(1, round(w * out_h / h))
    small = img.resize((tw, out_h), Image.BOX)
    if small.mode == "RGBA":
        a = small.getchannel("A").point(lambda v: 255 if v > 128 else 0)
        rgb = small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")
        rgb = rgb.convert("RGBA")
        rgb.putalpha(a)
        return rgb
    return small.convert("RGB").quantize(colors=colors, method=Image.MEDIANCUT).convert("RGB")


def circle_mask(img):
    """네모난 그림을 동그랗게 오려낸다.

    투기장 바닥은 원인데 PNG 는 네모라, 그대로 깔면 네 귀퉁이가 원 밖으로 튀어나온다.
    가장자리를 한 픽셀씩 부드럽게 깎아 톱니가 덜 보이게 한다.
    """
    from PIL import Image, ImageDraw
    w, h = img.size
    m = Image.new("L", (w * 4, h * 4), 0)
    ImageDraw.Draw(m).ellipse((0, 0, w * 4 - 1, h * 4 - 1), fill=255)
    m = m.resize((w, h), Image.BOX)
    out = img.convert("RGBA")
    out.putalpha(m)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="id 나 한글 이름에 이 문자열이 든 것만 (쉼표)")
    ap.add_argument("--kind", default="", help="unit | monster | ui")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--try", dest="tries", type=int, default=0, metavar="N",
                    help="시드를 N 만큼 밀어 다른 그림을 뽑는다 (--force 와 같이 쓴다)")
    args = ap.parse_args()

    r = load_roster()
    js = jobs(r)
    if args.tries:
        for j in js:
            j["seed"] = (j["seed"] + args.tries * 104729) % 2000000
    if args.kind:
        js = [j for j in js if j["kind"] == args.kind]
    pats = [p.strip() for p in args.only.split(",") if p.strip()]
    if pats:
        js = [j for j in js if any(p in j["id"] or p in j["ko"] for p in pats)]

    if args.list:
        for j in js:
            print(f"  {j['kind']:<8} {j['id']:<16} {j['ko']:<10} {j['out_h']}px")
        print(f"\n총 {len(js)}장")
        return 0

    todo = []
    for j in js:
        path = os.path.join(ROOT, "art", j["dir"], j["id"] + ".png")
        j["path"] = path
        if args.force or not os.path.exists(path):
            todo.append(j)
        os.makedirs(os.path.dirname(path), exist_ok=True)
    if not todo:
        print("모두 이미 있습니다. 다시 만들려면 --force")
        return 0

    from krea2.pipelines.image import Krea2ImagePipeline

    print(f"[art] {len(todo)}장 생성 시작 — 모델을 한 번만 올립니다", flush=True)
    t0 = time.time()
    pipe = Krea2ImagePipeline("turbo").load()
    print(f"[art] 모델 준비 완료 ({time.time() - t0:.0f}초)", flush=True)

    warn = []
    for i, j in enumerate(todo, 1):
        t1 = time.time()
        res = pipe.generate(j["prompt"], width=j["w"], height=j["h"], seed=j["seed"])[0]
        img = res.image
        if j["cut"]:
            img, kept = cut_white(img)
            # 오려내기가 실패하면(배경이 안 지워지거나 그림이 통째로 지워지면) 조용히
            # 넘어가지 않는다. 화면에 흰 네모가 붙어 나오는 것을 눈으로 찾는 건 지옥이다.
            if kept > 0.85:
                warn.append(f"{j['id']}: 배경이 거의 안 지워졌다 ({kept:.0%} 남음)")
            elif kept < 0.05:
                warn.append(f"{j['id']}: 그림이 거의 다 지워졌다 ({kept:.0%} 남음)"
                            " — python3 tools/gen_art.py --only %s --force --try 1" % j['id'])
        px = pixelize(img, j["out_h"], j["colors"], j.get("out_w", 0))
        if j["id"] == "arena_floor":
            px = circle_mask(px)
        px.save(j["path"], optimize=True)
        print(f"[art] ({i}/{len(todo)}) {j['id']:<16} {px.size[0]}x{px.size[1]} "
              f"{os.path.getsize(j['path']) / 1024:.0f}KB  {time.time() - t1:.0f}초", flush=True)

    print(f"[art] 완료 — 총 {(time.time() - t0) / 60:.1f}분", flush=True)
    if warn:
        print("\n!! 눈으로 봐야 할 것:", flush=True)
        for w in warn:
            print("   " + w, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
