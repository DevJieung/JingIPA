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
# 가위바위보의 손
# --------------------------------------------------------------------------- #
## ★ 손 세 장은 **한 벌**이다. 따로따로 잘라 내면 손목 굵기가 제각각이 돼서
##   카드 세 장이 서로 다른 사람 손처럼 보인다 (아이에게는 그게 "다른 놀이"로 읽힌다).
##   그래서 **파란 소매(손목 밴드)를 자로 삼아** 세 장을 같은 틀에 다시 앉힌다
##   (fit_hand). 밴드는 자동으로 찾을 수 있는 유일하게 안정적인 기준점이다 —
##   손 모양은 셋 다 다르지만 손목은 같은 손목이기 때문이다.
##
## ★ 소매를 데님 파랑으로 두는 것은 취향이 아니다. (a) 잘린 손목이 아니라
##   "옷 입은 손"으로 보여야 이 나이대에 안 무섭고, (b) 두리가 입은 멜빵바지와
##   같은 파랑이라 이 손이 누구 손인지 글자 없이 읽히고, (c) 크림 바탕에서
##   따뜻한 살구색과 확실히 갈라져 실루엣이 산다.
HAND = ("a single hand painted plastic model toy of a small child's right hand, "
        "chubby soft rounded fingers, museum quality Schleich figure quality, "
        "matte finish, warm peach skin color, the wrist ends in a soft rolled "
        "denim blue sleeve cuff at the bottom of the frame, "
        "clean studio product photograph, soft even lighting, sharp focus")

HAND_CUT = (", the whole hand and the cuff inside the frame, centered, upright, "
            "cut out on a pure flat white background, no base, no stand, no ground, "
            "no shadow, no scenery, no arm, no person, no face, no text, no logo")

## 손 그림의 틀 — **core/look.gd 의 HAND_CUFF_W · HAND_CUFF_V 와 같은 수다.**
## 여기를 고치면 거기도 같이 고쳐라 (안 그러면 손이 화면에서 어긋난 자리에 뜬다).
HAND_BOX = (512, 512)   # 세 장 모두 이 크기
HAND_CUFF_W = 0.44      # 밴드 폭 ÷ 그림 가로
HAND_CUFF_V = 0.77      # 밴드 한가운데 ÷ 그림 세로


def hand(pose: str, seed: int) -> dict:
    return dict(prompt=f"{HAND}, {pose}{HAND_CUT}", seed=seed, size=1024)


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

    # ── 가위바위보의 손 ─────────────────────────────────────────────────────
    # ★ 두리와 달리 **시드가 손마다 다르다.** 두리는 시드를 바꾸면 얼굴이 달라져서
    #   같은 아이로 안 보이지만, 손에는 얼굴이 없다 — 화풍·살빛·소매를 붙잡는 것은
    #   시드가 아니라 위의 HAND 문장이고(후보 여덟 벌을 나란히 놓고 확인했다),
    #   손목을 맞추는 것은 fit_hand 다. 그래서 시드는 **실루엣이 제일 또렷한 쪽**으로
    #   손마다 따로 골랐다. 아이가 세 장을 한눈에 갈라 봐야 하는 것이 이 놀이의 전부다:
    #     가위 4785 — V 가 제일 곧고 넓게 벌어졌다
    #     바위 4237 — 제일 동그랗고 뭉친 주먹 (모서리가 없어야 "바위"로 읽힌다)
    #     보   4237 — 다섯 손가락이 제일 넓게 펴진 부채 (엄지가 확실히 나와 있다)
    dict(id="hand_scissors", ko="손 — 가위", cut=True, fit=True,
         **hand("a peace sign held upright, exactly two fingers extended straight up "
                "in a wide V shape, the index finger and the middle finger, the ring "
                "finger and little finger and thumb curled down tight, "
                "back of the hand facing the camera", 4785)),
    dict(id="hand_rock", ko="손 — 바위", cut=True, fit=True,
         **hand("a closed fist held upright, all fingers curled in tight, the curled "
                "knuckles at the top, the thumb resting across the front, "
                "nothing sticking out", 4237)),
    dict(id="hand_paper", ko="손 — 보", cut=True, fit=True,
         **hand("a flat open hand held upright, all five fingers straight and spread "
                "wide apart pointing up, fingers fully extended, palm flat, "
                "back of the hand facing the camera", 4237)),

    # ── 참참참의 가리키는 손 ────────────────────────────────────────────────
    # ★ 옆을 가리키는 손은 **오른쪽을 가리키는 것 한 장뿐**이다. 왼쪽은 게임이 좌우로
    #   뒤집어 쓴다 (core/look.gd 의 draw_hand flip). 두 장을 따로 뽑으면 손가락 길이도
    #   주먹 각도도 미묘하게 달라져서, 나란히 놓았을 때 아이가 "다른 손 둘"로 본다.
    #   뒤집으면 좌우가 **반드시** 대칭이고, 오른손을 뒤집은 것은 그냥 왼손이라
    #   거짓말도 아니다 (규칙 26 의 예외인 이유 — docs/cham-rules.md 6절).
    # ★ 방향이 약하면 이 놀이가 통째로 망가진다. 손가락이 **확실히 옆으로** 뻗어야 한다 —
    #   위로 살짝 든 정도로는 작게 그렸을 때 "주먹에 혹이 붙은 것"으로만 보인다.
    dict(id="hand_point", ko="손 — 가리키기 (오른쪽)", cut=True, fit=True,
         **hand("the whole hand turned on its side, the index finger extended "
                "straight out horizontally to the right and parallel to the ground, "
                "pointing far to the right, the middle ring and little fingers "
                "curled into a fist, the thumb resting on top of them, "
                "seen from the back of the hand", 4100)),
    dict(id="hand_point_up", ko="손 — 가리키기 (위)", cut=True, fit=True,
         **hand("the index finger extended straight up, pointing up, the middle "
                "finger and ring finger and little finger curled into a fist, "
                "the thumb resting across the curled fingers, "
                "back of the hand facing the camera", 4100)),
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
    if a.get("fit", False):
        img = fit_hand(img)
    mh = a.get("max_h")
    if mh and img.size[1] > mh:
        w2 = max(1, int(img.size[0] * mh / img.size[1]))
        img = img.resize((w2, mh), Image.LANCZOS)
    img.save(path, optimize=True)
    return img


# --------------------------------------------------------------------------- #
# 손 — 세 장을 같은 틀에 앉히기
# --------------------------------------------------------------------------- #

def cuff_box(im):
    """손목 밴드(데님 파랑)의 네모를 찾는다.

    파랑만 보는 이유: 살빛·손 모양은 셋 다 다르지만 **손목은 같은 손목**이라,
    자동으로 찾을 수 있는 기준점이 밴드뿐이다. 손 전체의 네모를 자로 쓰면
    보(쫙 편 손)가 바위보다 넓어서 바위만 커다랗게 앉는다.
    """
    import numpy as np
    a = np.array(im.convert("RGBA")).astype("int16")
    r, b, al = a[:, :, 0], a[:, :, 2], a[:, :, 3]
    m = (al > 100) & (b > r + 18) & (b > 70)
    ys, xs = np.nonzero(m)
    if len(ys) < im.size[0] * im.size[1] // 400:
        return None
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max()))


def fit_hand(im):
    """밴드 폭·밴드 한가운데를 HAND_CUFF_* 에 맞춰 HAND_BOX 안에 다시 앉힌다."""
    from PIL import Image
    box = cuff_box(im)
    if box is None:
        print("   !! 손목 밴드를 못 찾았습니다 — 원본 그대로 둡니다")
        return im
    x0, y0, x1, y1 = box
    bw, cx, cy = float(x1 - x0), (x0 + x1) * 0.5, (y0 + y1) * 0.5
    W, H = HAND_BOX
    k = (HAND_CUFF_W * W) / max(bw, 1.0)
    im2 = im.resize((max(1, round(im.size[0] * k)), max(1, round(im.size[1] * k))),
                    Image.LANCZOS)
    out = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ox = round(W * 0.5 - cx * k)
    oy = round(H * HAND_CUFF_V - cy * k)
    out.paste(im2, (ox, oy), im2)
    # ★ 넘치면 조용히 잘리지 않게 **말한다.** 잘린 손끝은 화면에서만 보이는데
    #   이 머신에는 화면이 없다 — 여기서 안 잡으면 아무도 안 잡는다.
    ab = im2.getbbox()
    if ab:
        l, t, rr, bb = ab[0] + ox, ab[1] + oy, ab[2] + ox, ab[3] + oy
        if l < 0 or t < 0 or rr > W or bb > H:
            print(f"   !! 틀({W}x{H})을 넘칩니다: ({l},{t})-({rr},{bb}) "
                  f"— HAND_BOX 를 키우거나 HAND_CUFF_* 를 낮추세요")
    return out


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
