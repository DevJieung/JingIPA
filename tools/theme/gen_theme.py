#!/usr/bin/env python3
"""두리의 모험 — 앱 전체의 룩앤필 자산을 로컬 Krea 2 로 생성한다.

★ 화풍 앵커는 **이미 있는 공룡 50종**이다. 그것들이 "손으로 칠한 수집용 피규어"라서,
  주인공도 배경도 같은 피규어/디오라마로 뽑는다. 그래야 한 세계가 된다 —
  귀여운 만화 캐릭터를 얹으면 공룡 피규어 옆에서 통째로 겉돈다.
  (그래서 이 파일의 STYLE 은 tools/dino/gen_dinos.py 의 STYLE 과 형제다. 같이 고쳐라.)

사용법:
    python3 tools/theme/gen_theme.py --list
    python3 tools/theme/gen_theme.py                      # 없는 것만 생성
    python3 tools/theme/gen_theme.py --only duri --force  # 특정 자산만 다시
    python3 tools/theme/gen_theme.py --only duri --tries 6 # 후보 여러 개를 골라 보기
                                                           # (build/theme_try/ 에 떨어진다)

결과: core/art/<이름>.png
"""

from __future__ import annotations

import argparse
import os
import sys
import time

KREA_ROOT = "/home/dgxmaruta/pjt/krea2"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "core", "art")
TRY = os.path.join(ROOT, "build", "theme_try")

sys.path.insert(0, KREA_ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools", "dino"))

# --------------------------------------------------------------------------- #
# 화풍 — 공룡 50종과 같은 언어로 말한다
# --------------------------------------------------------------------------- #
FIG = ("hand painted plastic model toy like a museum quality Schleich figure, "
       "matte finish, soft rounded shapes, warm friendly colors, "
       "clean studio product photograph, soft even lighting, sharp focus, no text")

CUT = (", the whole body inside the frame, centered, cut out on a pure flat white "
       "background, no base, no stand, no ground, no shadow, no scenery, "
       "no other people, no text, no logo")

## 주인공 두리 — 만 4세. 두 아이 중 누구도 "내가 아니다" 라고 느끼지 않게 성별 표시를 피한다.
## ★ 포즈가 달라도 **시드를 같이 쓴다**. 시드를 바꾸면 얼굴·비율이 미묘하게 달라져서
##   같은 아이로 안 보인다 (후보 여섯을 나란히 놓고 확인했다).
DURI = ("a single hand painted collectible toy figurine of one cheerful little child "
        "explorer about four years old, round chubby face, big warm friendly eyes, "
        "short soft black hair under a bright yellow bucket hat, blue denim overalls "
        "over a white long sleeve shirt, a small brown leather backpack, tiny sneakers")


def duri(pose: str, seed: int, note: str = "") -> dict:
    return dict(prompt=f"{DURI}{note}, {FIG}, {pose}{CUT}", seed=seed, size=1024)


# --------------------------------------------------------------------------- #
# 자산 목록
#   id     : core/art/<id>.png
#   cut    : 흰 배경을 지워 투명 PNG 로 (배경 그림은 False)
#   max_h  : 저장할 최대 높이 (없으면 원본)
# --------------------------------------------------------------------------- #
ASSETS: list[dict] = [
    # ── 주인공 두리 ─────────────────────────────────────────────────────────
    dict(id="duri", ko="두리 (기본 · 손 흔들기)", cut=True, max_h=520,
         **duri("full body standing, one hand raised waving hello, "
                "facing the camera, happy open smile", 7238)),
    dict(id="duri_cheer", ko="두리 (만세)", cut=True, max_h=520,
         **duri("full body standing, both arms raised high in the air cheering, "
                "facing the camera, eyes closed with a big happy laugh", 7238)),
    dict(id="duri_point", ko="두리 (가리키기)", cut=True, max_h=520,
         **duri("full body standing, one arm stretched out to the side pointing "
                "with the index finger, facing the camera, curious excited face", 7238)),
    dict(id="duri_torch", ko="두리 (손전등)", cut=True, max_h=520,
         **duri("full body standing, holding up a small yellow flashlight in one hand, "
                "facing the camera, curious face", 7238)),
]

# ★ 얼굴 클로즈업은 따로 만들지 않는다. 화면을 꽉 채운 얼굴은 배경 지우기가 흰 얼굴을
#   배경으로 착각해서 통째로 날려 먹는다 (한 번 그랬다). 아이콘은 기본 포즈에서
#   머리를 잘라 쓴다 — 그러면 아이콘과 게임 속 두리가 반드시 같은 얼굴이 된다.


def load_pipe():
    from krea2.pipelines.image import Krea2ImagePipeline
    t0 = time.time()
    print("[theme] 모델 올리는 중...", flush=True)
    pipe = Krea2ImagePipeline("turbo").load()
    print(f"[theme] 모델 준비 완료 ({time.time() - t0:.0f}초)", flush=True)
    return pipe


def save(img, path: str, a: dict):
    from PIL import Image
    if a.get("cut", False):
        from gen_dinos import cut_out
        img = cut_out(img)
    mh = a.get("max_h")
    if mh and img.size[1] > mh:
        w2 = max(1, int(img.size[0] * mh / img.size[1]))
        img = img.resize((w2, mh), Image.LANCZOS)
    img.save(path, optimize=True)
    return img


# --------------------------------------------------------------------------- #
# 아이콘 · 스플래시 — 두리 얼굴로
# --------------------------------------------------------------------------- #

## 앱을 여는 순간 보이는 모든 그림이 같은 얼굴이어야 한다: 런처 아이콘 · 부팅 화면.
BG_RGB = (247, 240, 228)      # Look.BG (크림)
GOLD_RGB = (255, 209, 102)    # Look.GOLD


def head_crop(src_path: str, pad: float = 0.10):
    """기본 포즈에서 머리(모자 포함)만 네모로 잘라낸다."""
    from PIL import Image
    import numpy as np
    im = Image.open(src_path).convert("RGBA")
    a = np.array(im)[:, :, 3]
    ys, xs = np.nonzero(a > 12)
    if len(ys) == 0:
        return im
    top = int(ys.min())
    # 사람 비율: 이 피규어는 머리가 큰 3등신이라 위에서 45% 가 머리+어깨다.
    bottom = top + int((int(ys.max()) - top) * 0.40)
    band = a[top:bottom]
    bxs = np.nonzero(band.max(axis=0) > 12)[0]
    left, right = int(bxs.min()), int(bxs.max())
    side = max(right - left, bottom - top)
    side = int(side * (1.0 + pad * 2.0))
    cx = (left + right) // 2
    cy = (top + bottom) // 2
    box = (cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2)
    out = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    out.alpha_composite(im.crop(box), (0, 0))
    return out


def make_icons() -> None:
    from PIL import Image, ImageDraw
    src = os.path.join(OUT, "duri.png")
    if not os.path.exists(src):
        print("!! core/art/duri.png 가 없습니다 — 먼저 생성하세요")
        return
    face = head_crop(src)

    def fit(size: int, scale: float):
        im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        k = int(size * scale)
        f = face.resize((k, k), Image.LANCZOS)
        im.alpha_composite(f, ((size - k) // 2, (size - k) // 2))
        return im

    ad = os.path.join(ROOT, "android_icons")
    os.makedirs(ad, exist_ok=True)
    # 적응형 아이콘: 전경은 안전영역(가운데 66%) 안에
    fit(432, 0.66).save(os.path.join(ad, "adaptive_fore_432.png"))
    Image.new("RGBA", (432, 432), GOLD_RGB + (255,)).save(
        os.path.join(ad, "adaptive_back_432.png"))
    legacy = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    ImageDraw.Draw(legacy).rounded_rectangle([12, 12, 419, 419], radius=86,
                                             fill=GOLD_RGB + (255,))
    legacy.alpha_composite(fit(432, 0.72))
    legacy.resize((192, 192), Image.LANCZOS).save(
        os.path.join(ad, "launcher_main_192.png"))

    # 앱스토어 마스터는 알파가 있으면 거부당한다 — 반드시 불투명하게
    store = Image.new("RGB", (1024, 1024), GOLD_RGB)
    store.paste(fit(1024, 0.78), (0, 0), fit(1024, 0.78))
    store.save(os.path.join(ROOT, "appstore_icon_1024.png"))

    # iOS 런치 스크린 (알파 있음) — 크림 바탕에 두리 전신
    body = Image.open(src).convert("RGBA")
    for name, size in [("splash@2x.png", 1024), ("splash@3x.png", 1536)]:
        sp = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        k = int(size * 0.62)
        w2 = max(1, int(body.size[0] * k / body.size[1]))
        sp.alpha_composite(body.resize((w2, k), Image.LANCZOS),
                           ((size - w2) // 2, (size - k) // 2))
        sp.save(os.path.join(ROOT, name))
    print("아이콘·스플래시 생성: android_icons/ · appstore_icon_1024.png · splash@2x/3x")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="이름에 이 문자열이 들어간 것만 (쉼표로)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--tries", type=int, default=0,
                    help="후보를 이만큼 뽑아 build/theme_try/ 에 떨어뜨린다 (고르기용)")
    ap.add_argument("--icons", action="store_true",
                    help="두리 얼굴로 런처 아이콘·스플래시를 다시 만든다 (모델 안 씀)")
    args = ap.parse_args()

    if args.icons:
        make_icons()
        return 0

    pats = [p.strip() for p in args.only.split(",") if p.strip()]
    # 이름이 정확히 맞으면 그것 하나만 (duri 는 duri_cheer 의 부분 문자열이기도 하다)
    ids = {a["id"] for a in ASSETS}
    jobs = [a for a in ASSETS
            if not pats or a["id"] in pats
            or any(p in a["id"] for p in pats if p not in ids)]
    if args.list:
        for a in jobs:
            print(f"  {a['id']:<16} {a['ko']}")
        print(f"\n총 {len(jobs)}개")
        return 0
    if not jobs:
        print("해당하는 자산이 없습니다.")
        return 1

    os.makedirs(OUT, exist_ok=True)
    if args.tries > 0:
        os.makedirs(TRY, exist_ok=True)
        pipe = load_pipe()
        for a in jobs:
            for k in range(args.tries):
                seed = int(a["seed"]) + k * 137
                t1 = time.time()
                res = pipe.generate(a["prompt"], width=a["size"], height=a["size"],
                                    seed=seed)[0]
                path = os.path.join(TRY, f"{a['id']}_{k}_{seed}.png")
                img = save(res.image, path, a)
                print(f"[theme] 후보 {a['id']} #{k} seed={seed} "
                      f"{img.size[0]}x{img.size[1]} {time.time() - t1:.0f}초", flush=True)
        print(f"[theme] 후보 완료 -> {TRY}", flush=True)
        return 0

    todo = [a for a in jobs
            if args.force or not os.path.exists(os.path.join(OUT, a["id"] + ".png"))]
    if not todo:
        print("모두 이미 있습니다. 다시 만들려면 --force")
        return 0

    pipe = load_pipe()
    t0 = time.time()
    for i, a in enumerate(todo, 1):
        t1 = time.time()
        path = os.path.join(OUT, a["id"] + ".png")
        res = pipe.generate(a["prompt"], width=a["size"], height=a["size"],
                            seed=a["seed"])[0]
        img = save(res.image, path, a)
        print(f"[theme] ({i}/{len(todo)}) {a['id']:<16} {img.size[0]}x{img.size[1]} "
              f"{os.path.getsize(path) / 1024:.0f}KB  {time.time() - t1:.0f}초", flush=True)
    print(f"[theme] 완료 — 총 {time.time() - t0:.0f}초, {OUT}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
