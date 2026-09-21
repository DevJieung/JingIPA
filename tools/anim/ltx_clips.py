#!/usr/bin/env python3
"""정지 스프라이트 한 장 → **LTX2 로 동영상** → 게임이 읽는 클립 3종.

    python3 tools/anim/ltx_clips.py <id> [<id> ...]      # 고른 캐릭터만
    python3 tools/anim/ltx_clips.py --all                # 여든 명 전부
    python3 tools/anim/ltx_clips.py <id> --keep          # 중간 파일을 남긴다
    python3 tools/anim/ltx_clips.py <id> --dry           # 프롬프트만 찍어 본다

사용자가 정한 것: 「이미지 스프라이트로 하나 만들어서 LTX2 로 스프라이트가 액션을
취하는 동영상을 만들어서 거기서 애니메이션 스프라이트를 확보하는걸로 시도해봐줘」.

────────────────────────────────────────────────────────────────────────────
왜 되는가 (실제로 재 본 것)
────────────────────────────────────────────────────────────────────────────
LTX-2.3 은 실사 영상 모델이라 도트 그림을 넣으면 뭉갤 것 같은데, **안 뭉갠다.**
짚신궁수로 시험한 결과:
  · 화풍이 살아남았다 — 굵은 검은 테두리와 팔레트가 프레임마다 그대로다
  · 사람이 안 바뀐다 — 삿갓·활·화살통이 마흔아홉 칸 내내 같은 사람이다
  · **발이 같은 바닥선에 붙어 있다.** 이것이 제일 중요하다(CLAUDE.md 18-3) —
    기준점이 흔들리면 전투 화면에서 영웅이 위아래로 튄다
  · 512x512 x 49칸에 **추론이 5초**다(모델 올리는 데 3~4분). 여든 명을 한 번에
    돌리면 모델을 한 번만 올리므로 한 명당 사실상 20초 안팎이다

★ 그래서 이 파일은 **모델을 한 번만 올리고 여든 명을 이어서** 돌린다.

────────────────────────────────────────────────────────────────────────────
믿으면 안 되는 것 (실측)
────────────────────────────────────────────────────────────────────────────
★ **뒤로 갈수록 무너진다.** 마흔아홉 칸 중 **뒤 3분의 1**에서 활이 손에서 떨어지고
  사람이 녹기 시작했다. 그래서 앞 `USE_FRAC` 만 쓴다. 넉넉히 뽑고 조금만 쓰는 것이
  이 도구의 기본 태도다.
★ **틀을 자르면 안 된다.** 칸마다 알파로 바짝 자르면 기준점이 칸마다 달라져서
  영웅이 춤춘다. 그래서 512 판을 **통째로** 줄이고, 마지막에 **모든 칸의 합집합**
  테두리 상자로 **한 번만** 자른다.
★ **팔레트를 다시 잡아야 한다.** 영상 모델은 색을 조금씩 흘리므로, 칸마다 따로
  줄이면 40색이 칸마다 달라져 화면에서 깜빡인다. 그래서 **정지 그림의 팔레트로
  못 박아** 칠한다.
★ **`shot`(탄) 클립은 여기서 안 만든다.** 그것은 배우가 아니라 날아가는 탄만 담은
  작은 스트립이고, `mkanim.py` 가 속성 램프로 코드로 그린다 — 영상에서 뽑을 것이
  아니다. 이 도구는 `mkanim.py` 가 만든 `shot` 을 그대로 둔다.
  ☆ 그래서 **`build_clips.py` 를 먼저 돌려야 한다.** 이 도구는 배우 클립
    (idle·attack)만 갈아 끼운다.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tools"))

LTX_DIR = "/home/dgxmaruta/pjt/ltx2"
LTX_PY = os.path.join(LTX_DIR, ".venv", "bin", "python")
LTX_CKPT = os.path.join(LTX_DIR, "checkpoints", "ltx-2.3-22b-distilled-1.1.safetensors")
LTX_UPS = os.path.join(LTX_DIR, "checkpoints", "ltx-2.3-spatial-upscaler-x2-1.1.safetensors")
LTX_GEMMA = os.path.join(LTX_DIR, "checkpoints", "gemma-3-12b-it-qat-q4_0-unquantized")

# 판 크기. **64의 배수여야 한다** (2단계 파이프라인의 assert_resolution).
SIZE = 512
# 칸 수는 8K+1 이어야 한다. 넉넉히 뽑고 앞쪽만 쓴다.
FRAMES = 49
FPS = 24
# 실제로 쓰는 몫. 뒤 3분의 1은 그림이 무너진다(위 주석).
USE_FRAC = 0.62

# 화풍이 흔들리지 않게 못 박는 말. **정지 그림이 이미 그 화풍이므로** 여기서는
# 「그대로 두라」만 강하게 건다 — 새로 그리라고 하면 다른 사람이 나온다.
HOLD = ("16-bit pixel art game sprite animation on a flat pure white background, "
        "static locked-off camera, no camera movement, no zoom, no pan, "
        "the same sprite stays in exactly the same spot at exactly the same size, "
        "feet planted on the same ground line the whole time, "
        "crisp blocky pixels, thick black outline, dark limited palette, "
        "no motion blur, no depth of field, flat empty white background")

# 동작마다의 몸짓. `gen_concepts.motion_of()` 가 정한 motion 을 그대로 받는다.
MOTION_TEXT = {
    "draw": ("The figure holds the {weapon} drawn and aimed to the right, then releases: "
             "the string snaps forward, the shot flies off to the right, the drawing arm "
             "swings back past the shoulder, then it settles back into the aiming stance."),
    "cast": ("The figure thrusts its forward hand out to the right and casts: the {elem} "
             "gathered above the open palm flares and is flung away to the right, the arm "
             "follows through, then draws back to the ready pose."),
    # ★ 사용자가 정한 광역 연출. **탄이 안 나간다** — 팔을 들고 파동이 몸을 훑는다.
    "raise": ("The figure sinks down slightly, then slowly RAISES BOTH ARMS up beside its "
              "head with the palms turned upward, and while the arms rise a ring of {elem} "
              "sweeps upward from under its feet, up the body, and bursts out above its "
              "head. Nothing is thrown. Then the arms lower back down."),
}
ELEM_WORD = {"fire": "orange fire", "ice": "pale blue frost", "elec": "violet lightning",
             "water": "dark blue water", "none": "grey dust"}


def roster() -> dict:
    with open(os.path.join(ROOT, "tools", "roster.json"), encoding="utf-8") as f:
        r = json.load(f)
    return {u["id"]: dict(u, tier=ti)
            for ti, t in enumerate(r["tiers"]) for u in t["units"]}


def concepts() -> dict:
    p = os.path.join(HERE, "concepts.json")
    with open(p, encoding="utf-8") as f:
        return json.load(f)


def prompt_for(u: dict, motion: str) -> str:
    # ★ 결(cast_lunge…)은 무리(cast)의 글을 쓴다. 이름 그대로 찾으면 결이 전부
    #   기본값으로 떨어져서, 궁수가 마법사 글로 뽑힌다(CLAUDE.md 18-5-2).
    body = MOTION_TEXT.get(motion.split("_")[0], MOTION_TEXT["cast"]).format(
        weapon=u.get("weapon", "weapon"),
        elem=ELEM_WORD.get(u.get("elem", "none"), "grey dust"))
    return "%s %s" % (HOLD, body)


def cond_image(uid: str, out: str) -> tuple[int, int]:
    """정지 스프라이트를 **정수배로** 키워 흰 판 한가운데에 세운다.

    ★ 정수배(NEAREST)여야 도트가 안 뭉개진다. 그리고 그 배수를 그대로 돌려주어
      나중에 **같은 배수로 줄인다** — 그래야 원래 격자로 정확히 돌아온다.
    """
    from PIL import Image
    src = Image.open(os.path.join(ROOT, "art", "units", uid + ".png")).convert("RGBA")
    w, h = src.size
    k = max(1, int((SIZE * 0.78) // h))
    up = src.resize((w * k, h * k), Image.NEAREST)
    bg = Image.new("RGBA", (SIZE, SIZE), (255, 255, 255, 255))
    # 발밑을 판의 아래쪽 16% 자리에 둔다. 팔을 들면 위로 자라므로 아래에 붙인다.
    bg.alpha_composite(up, ((SIZE - up.width) // 2, int(SIZE * 0.84) - up.height))
    bg.convert("RGB").save(out)
    return k, h


def run_ltx(cond: str, prompt: str, out: str, seed: int) -> None:
    cmd = [LTX_PY, os.path.join(LTX_DIR, "run_ltx.py"),
           "--distilled-checkpoint-path", LTX_CKPT,
           "--spatial-upsampler-path", LTX_UPS,
           "--gemma-root", LTX_GEMMA,
           "--quantization", "fp8-cast",
           "--prompt", prompt,
           # CRF 0 = 무손실. 도트 그림은 압축을 먹으면 테두리가 뭉갠다.
           "--image", cond, "0", "1.0", "0",
           "--output-path", out,
           "--width", str(SIZE), "--height", str(SIZE),
           "--num-frames", str(FRAMES), "--frame-rate", str(FPS),
           "--seed", str(seed)]
    r = subprocess.run(cmd, cwd=LTX_DIR, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        tail = (r.stdout + r.stderr).strip().splitlines()
        raise RuntimeError(tail[-1][:200] if tail else "LTX 실패")


def frames_of(mp4: str, tmp: str) -> list:
    from PIL import Image
    d = os.path.join(tmp, "f")
    os.makedirs(d, exist_ok=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", mp4,
                    os.path.join(d, "%03d.png")], check=True)
    fs = sorted(os.listdir(d))
    return [Image.open(os.path.join(d, f)).convert("RGB") for f in fs]


def cut_keep_frame(im, holes: bool):
    """배경만 지우고 **틀은 그대로 둔다.**

    `gen_art.cut_white` 는 끝에서 알파로 바짝 자르는데, 칸마다 자르면 기준점이
    칸마다 달라져서 영웅이 춤춘다. 그래서 자르지 않는다.

    ★★ **모서리에서 물을 붓지 않는다 — 여기서 크게 한 번 당했다.**
      `gen_art.cut_white` 는 네 모서리와 네 변 가운데에서 `floodfill` 을 붓는다.
      그것이 되는 까닭은 Krea2 가 **정말로 평평한 흰 배경**을 내주기 때문이다.
      LTX2 의 출력은 **동영상**이라 H.264 를 거치고, 큰 흰 면에 아주 옅은 얼룩과
      비네팅이 남는다. 그래서 모서리 픽셀의 값이 `BG_VAL`(205) 밑으로 내려가는
      일이 생기는데, 그러면 그 픽셀은 **벽으로 칠해져 검게** 되고 물은 배경이 아니라
      **벽 안쪽**으로 퍼진다. 결과는 조용하다: 배경이 하나도 안 지워진 채로 통과하고
      화면에는 **하얀 판때기를 뒤집어쓴 영웅**이 선다(실제로 그렇게 나왔다 —
      칸마다 흰 픽셀이 50%였다).

      그래서 물을 붓는 대신 **덩어리를 세어** 가른다: 「배경일 수 있는 픽셀」의
      이어진 덩어리 중 **틀 가장자리에 닿은 것**만 배경이다. 어느 한 점에서
      시작하지 않으므로 그 한 점이 틀리는 사고가 아예 없다.
    """
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    import gen_art as G
    rgb = im.convert("RGB")
    arr = np.array(rgb).astype("int16")
    sat = arr.max(axis=2) - arr.min(axis=2)
    val = arr.max(axis=2)
    cand = (sat <= G.BG_SAT) & (val >= G.BG_VAL)
    lab, n = ndimage.label(cand)
    bg = np.zeros_like(cand)
    if n > 0:
        edge = set(lab[0, :].tolist()) | set(lab[-1, :].tolist()) \
            | set(lab[:, 0].tolist()) | set(lab[:, -1].tolist())
        edge.discard(0)
        if edge:
            bg = np.isin(lab, list(edge))
    if holes:
        bg = bg | G.trapped_white(bg, sat, val)
    out = im.convert("RGBA")
    out.putalpha(Image.fromarray(((~bg) * 255).astype("uint8"), "L"))
    return out


def lock_palette(im, pal):
    """정지 그림의 팔레트로 **못 박아** 칠한다.

    ★ 칸마다 따로 팔레트를 잡으면 40색이 칸마다 달라져서 화면에서 깜빡인다.
      한 벌로 못 박으면 색이 프레임 사이에서 절대 안 흔들린다.
    """
    import numpy as np
    from PIL import Image
    a = np.array(im.getchannel("A"))
    # ★★ **int32 여야 한다.** int16 으로 두었다가 크게 당했다: 색 차이는 최대 255 이고
    #   제곱하면 65025 인데 int16 의 위쪽 끝은 32767 이라 **넘쳐서 음수가 된다.**
    #   그러면 `argmin` 이 아무 색이나 고르고, 실제로 그림의 **54%가 흰색 한 칸으로**
    #   쏠렸다 — 어두운 캐릭터가 하얀 판때기가 되어 나왔다. 그리고 이 고장은
    #   **예외를 안 낸다.** 숫자로 재는 검사(위의 「흰 판때기 검사」)가 없었으면
    #   그대로 게임에 실렸을 것이다.
    rgb = np.array(im.convert("RGB")).astype("int32")
    pal = np.asarray(pal, dtype="int32")
    # 가장 가까운 팔레트 색으로. 40색 x 픽셀 수라 작은 그림에서는 넉넉히 빠르다.
    d = ((rgb[:, :, None, :] - pal[None, None, :, :]) ** 2).sum(axis=3)
    idx = d.argmin(axis=2)
    out = pal[idx].astype("uint8")
    o = Image.fromarray(out, "RGB").convert("RGBA")
    o.putalpha(Image.fromarray(a, "L"))
    return o


# --------------------------------------------------------------------------- #
# ★ **품질 관문.** 이것이 없으면 이 도구는 시험이지 도구가 아니다.
#
#   영상 모델은 뒤로 갈수록 무너진다(9-1). `USE_FRAC` 로 앞쪽만 쓰지만 그것은 **평균**에
#   맞춘 값이라, 어떤 캐릭터는 더 일찍 무너지고 어떤 캐릭터는 안 무너진다. 사람이
#   여든 개를 눈으로 다 보지 못하므로 **숫자로 걸러야** 한다.
#
#   재는 것 둘:
#     1. **넓이** — 칸마다의 알파 픽셀 수가 0번 칸 대비 얼마나 흔들리는가.
#        녹으면 줄고(소품이 사라진다) 번지면 는다.
#     2. **발밑** — 알파의 **아래쪽 가장자리**가 위아래로 얼마나 움직이는가.
#        기준점이 흔들리면 전투 화면에서 영웅이 위아래로 튄다(CLAUDE.md 18-3).
#        ★ 무게중심이 아니라 **아래 끝**을 본다. 팔을 들면 무게중심은 당연히 올라가는데
#          그것은 무너진 것이 아니라 **동작**이다.
# --------------------------------------------------------------------------- #
AREA_LO, AREA_HI = 0.70, 1.45     # 0번 칸 대비 알파 넓이의 허용 폭
FOOT_DRIFT = 0.05                  # 발밑이 움직여도 되는 몫 (칸 높이 대비)
# ★ **넓이만으로는 못 잡는다.** 실루엣이 뭉개져도 픽셀 수는 비슷할 수 있다 —
#   한 캐릭터가 「넓이는 그대로인데 사람이 덩어리가 된」 칸을 그대로 통과했다.
#
# ★★ **가로 폭으로 재면 안 된다 — 여기서 한 번 헛짚었다.** 처음에는 테두리 상자의
#   가로가 22% 넘게 변하면 무너진 것으로 쳤는데, 팔을 앞으로 뻗으면 가로는 **당연히**
#   커진다(68 → 88px). 그건 무너진 것이 아니라 **동작 그 자체**라, 이 잣대는 멀쩡한
#   클립을 두 개나 떨어뜨렸다. 가로는 자유롭게 두어야 한다.
#
# 그래서 재는 것은 셋이다 — 넓이 · 발밑 · 그리고 **부서졌는가**.
#   녹는 그림의 가장 또렷한 표는 **덩어리가 쪼개지는 것**이다. 멀쩡한 스프라이트는
#   몸 하나가 픽셀의 대부분을 차지하는데, 뭉개지기 시작하면 그 몸이 조각난다.
#   세로 높이도 같이 본다 — 사람은 키가 갑자기 변하지 않는다(팔을 들어도 그림 틀은
#   이미 그만큼 잡혀 있다).
BODY_FRAC = 0.72                   # 제일 큰 덩어리가 차지해야 할 최소 몫
TALL_DRIFT = 0.16                  # 세로 높이가 흔들려도 되는 몫 (가로는 안 본다)


def gate(frames) -> tuple[int, str]:
    """앞에서부터 **무너지기 직전까지** 몇 칸을 쓸 수 있는가."""
    import numpy as np
    from scipy import ndimage
    def mask(f):
        return np.array(f.getchannel("A")) > 128
    def stats(m):
        if not m.any():
            return 0, 0, 0, 0
        ys = np.nonzero(m.any(axis=1))[0]
        xs = np.nonzero(m.any(axis=0))[0]
        return int(m.sum()), int(ys[-1]), int(xs[-1] - xs[0] + 1), int(ys[-1] - ys[0] + 1)
    m0 = mask(frames[0])
    n0, f0, w0, h0 = stats(m0)
    if n0 <= 0:
        return 0, "0번 칸이 비었다"
    h = frames[0].size[1]
    for i, f in enumerate(frames):
        m = mask(f)
        n, fy, _bw, bh = stats(m)
        if n < n0 * AREA_LO or n > n0 * AREA_HI:
            return i, "%d번 칸에서 넓이가 %.2f배로 튀었다" % (i, n / float(n0))
        if abs(fy - f0) > h * FOOT_DRIFT:
            return i, "%d번 칸에서 발밑이 %dpx 움직였다" % (i, abs(fy - f0))
        if abs(bh - h0) > h0 * TALL_DRIFT:
            return i, "%d번 칸에서 키가 %d → %d 로 변했다" % (i, h0, bh)
        lab, k = ndimage.label(m)
        if k > 0:
            big = int(ndimage.sum(m, lab, range(1, k + 1)).max())
            if big < n * BODY_FRAC:
                return i, "%d번 칸에서 몸이 쪼개졌다 (제일 큰 덩어리가 %.0f%%)" \
                    % (i, 100.0 * big / float(max(1, n)))
    return len(frames), ""


def build(uid: str, u: dict, c: dict, tmp: str, keep: bool, seed: int) -> str:
    import numpy as np
    from PIL import Image
    motion = c.get("motion", "cast")
    cond = os.path.join(tmp, uid + "_cond.png")
    k, sh = cond_image(uid, cond)
    mp4 = os.path.join(tmp, uid + ".mp4")
    run_ltx(cond, prompt_for(u, motion), mp4, seed)
    if keep:
        # ★ **영상을 먼저 챙긴다.** 아래에서 걸러 내면(하얀 칸·녹은 칸) 예외가 나므로,
        #   끝에서 챙기면 정작 **봐야 할 때** 영상이 안 남는다.
        shutil.copy2(mp4, os.path.join(ROOT, "build", "%s_ltx.mp4" % uid))
        shutil.copy2(cond, os.path.join(ROOT, "build", "%s_cond.png" % uid))
    fr = frames_of(mp4, tmp)
    fr = fr[:max(8, int(len(fr) * USE_FRAC))]

    holes = bool(u.get("holes", False))
    cut = [cut_keep_frame(f, holes) for f in fr]
    small = [f.resize((SIZE // k, SIZE // k), Image.BOX) for f in cut]

    # 정지 그림의 팔레트를 뽑아 못 박는다.
    st = Image.open(os.path.join(ROOT, "art", "units", uid + ".png")).convert("RGBA")
    sa = np.array(st)
    pal = np.unique(sa[sa[:, :, 3] > 128][:, :3].reshape(-1, 3), axis=0).astype("int16")

    px = []
    for f in small:
        a = f.getchannel("A").point(lambda v: 255 if v > 128 else 0)
        g = f.convert("RGBA")
        g.putalpha(a)
        px.append(lock_palette(g, pal))

    # ★ **합집합 테두리 상자로 한 번만** 자른다. 칸마다 자르면 기준점이 흔들린다.
    bb = None
    for f in px:
        b = f.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
        if not b:
            continue
        bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]),
                                   max(bb[2], b[2]), max(bb[3], b[3]))
    if bb is None:
        raise RuntimeError("모든 칸이 비었다 — 배경 지우기가 그림을 통째로 먹었다")
    px = [f.crop(bb) for f in px]
    cw, ch = px[0].size

    # ★ **여기서 거른다.** 무너지기 시작한 칸부터는 버린다. 여덟 칸도 못 건지면
    #   그 캐릭터는 통째로 실패로 친다 — 리그로 만든 클립이 이미 있으므로
    #   **어설픈 것으로 덮어쓰지 않는 편이 낫다.**
    # ★★ **흰 판때기 검사.** 배경 지우기가 실패하면 그림이 통째로 하얘지는데,
    #   그것이 **조용히** 통과해서 화면에 하얀 영웅이 섰다(위 cut_keep_frame 주석).
    #   숫자로 막는다: 정지 그림이 이만큼 어두운데 클립만 밝을 수는 없다.
    def _white_frac(f):
        a = np.array(f)
        m = a[:, :, 3] > 128
        if not m.any():
            return 1.0
        c = a[:, :, :3][m].astype(int)
        return float((((c.max(1) - c.min(1)) <= 22) & (c.max(1) >= 205)).mean())
    st_w = _white_frac(np.array(st) if False else st.convert("RGBA"))
    cl_w = max(_white_frac(f) for f in px[:max(1, len(px) // 2)])
    if cl_w > max(0.18, st_w * 3.0 + 0.05):
        raise RuntimeError("칸이 하얗다 (흰 %.0f%% · 정지 그림은 %.0f%%) — 배경 지우기 실패"
                           % (cl_w * 100, st_w * 100))

    good, why = gate(px)
    if good < 8:
        raise RuntimeError("쓸 만한 칸이 %d개뿐이다 (%s)" % (good, why))
    dropped = len(px) - good
    px = px[:good]

    # ★★ **열 칸으로 솎는다 — 그대로 쓰면 안 된다.**
    #   LTX2 는 24fps 로 뽑으므로 서른 칸이면 1.25초다. 그런데 공격 클립의 길이는
    #   그대로 **뻗는 시간(wind)**이 되고(gen_roster 가 hit_ms 를 읽는다), 전투는 쏘기로
    #   정한 뒤 그만큼 **기다렸다가** 탄을 낸다(CLAUDE.md 18-9). 1초를 기다리면
    #   연사 캐릭터는 쿨다운보다 뻗는 시간이 길어져서 `Balance.windup` 이 잘라 버리고,
    #   화면은 클립을 세 배로 빨리 돌리게 된다 — 애써 뽑은 칸이 다 뭉개진다.
    #   그래서 리그 클립과 **같은 길이(0.405초)**로 맞춘다. 칸 수도 같은 열이다.
    # ★ 칸마다 시간이 다르다(CLAUDE.md 18-4). 가장 짧은 칸(20ms)이 놓는 순간이고,
    #   눈은 제일 짧은 프레임을 타격으로 읽는다. 균등하게 나누면 언제 쐈는지가 안 읽힌다.
    N_OUT = 10
    MS = [45, 45, 50, 55, 45, 25, 20, 30, 40, 50]   # mkanim 의 cast 표와 같은 값
    HIT = 6
    src = px
    px = [src[min(len(src) - 1, round(i * (len(src) - 1) / float(N_OUT - 1)))]
          for i in range(N_OUT)]
    n = N_OUT
    hit = HIT
    ms = list(MS)
    dst = os.path.join(ROOT, "art", "anim", uid)
    os.makedirs(dst, exist_ok=True)

    def strip(frames, path):
        sheet = Image.new("RGBA", (cw * len(frames), ch), (0, 0, 0, 0))
        for i, f in enumerate(frames):
            sheet.paste(f, (i * cw, 0))
        sheet.save(path)

    strip(px, os.path.join(dst, "%s_attack.png" % uid))
    # 아이들 넷 — **아직 안 움직인 앞쪽**에서 고르게 뽑는다. 뒤쪽을 쓰면 가만히 서
    # 있어야 할 때 팔을 휘두르고 있는 그림이 돈다.
    idle = [src[min(len(src) - 1, int(i * (len(src) * 0.30) / 3.0))] for i in range(4)]
    strip(idle, os.path.join(dst, "%s_idle.png" % uid))

    # ★ anim.json 은 **덮어쓰지 않고 고쳐 쓴다.** `shot` 클립과 팔레트 램프는
    #   mkanim.py 가 만든 것을 그대로 둬야 한다.
    jp = os.path.join(dst, "anim.json")
    meta = {}
    if os.path.exists(jp):
        with open(jp, encoding="utf-8") as f:
            meta = json.load(f)
    meta.setdefault("name", uid)
    meta["ko"] = u.get("ko", uid)
    meta["elem"] = u.get("elem", "none")
    meta["cell"] = {"w": cw, "h": ch}
    meta["static"] = {"w": st.size[0], "h": st.size[1]}
    # 기준점 — 가로 가운데 · 세로 발밑. 조건 이미지에서 발밑을 판의 84% 에 두었다.
    meta["anchor"] = {"x": cw // 2, "y": int(SIZE * 0.84) // k - bb[1],
                      "note": "가로 가운데 · 세로 발밑 (Art.draw_at 과 같은 규칙)"}
    total = sum(ms)
    hit_ms = sum(ms[:hit + 1])
    meta["hit_ms"] = hit_ms
    meta.setdefault("face", 1)
    meta["motion"] = motion
    meta.setdefault("muzzle", c.get("muzzle", "hand"))
    meta.setdefault("link", c.get("link", "wobble"))
    clips = meta.setdefault("clips", {})
    clips["attack"] = {"frames": n, "ms": ms, "total_ms": total, "loop": False,
                       "hit_frame": hit, "note": "LTX2 영상에서 뽑은 칸"}
    clips["idle"] = {"frames": 4, "ms": [170] * 4, "total_ms": 680, "loop": True}
    clips.setdefault("shot", {"frames": 4, "ms": [80] * 4, "total_ms": 320, "loop": True})
    with open(jp, "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    if keep:
        shutil.copy2(mp4, os.path.join(ROOT, "build", "%s_ltx.mp4" % uid))
    tail = "" if dropped == 0 else " · 뒤 %d칸 버림(%s)" % (dropped, why)
    return "%d→%d칸 %dx%d · 놓는 칸 %d (%dms)%s" % (
        len(src), n, cw, ch, hit, hit_ms, tail)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()

    R = roster()
    C = concepts()
    names = a.names or (list(R) if a.all else [])
    if not names:
        print("이름을 주거나 --all 을 써라"); return 2
    if a.dry:
        for n in names:
            if n in R:
                print("== %s (%s)\n%s\n" % (n, C.get(n, {}).get("motion", "cast"),
                                           prompt_for(R[n], C.get(n, {}).get("motion", "cast"))))
        return 0
    if not os.path.exists(LTX_PY):
        print("LTX2 가 없다: %s" % LTX_PY); return 2

    ok, bad = [], []
    tmp = tempfile.mkdtemp(prefix="ltxclip_")
    try:
        for i, n in enumerate(names, 1):
            if n not in R:
                bad.append((n, "roster 에 없다")); continue
            if not os.path.exists(os.path.join(ROOT, "art", "units", n + ".png")):
                bad.append((n, "정지 그림이 없다")); continue
            try:
                msg = build(n, R[n], C.get(n, {}), tmp, a.keep, a.seed)
                ok.append(n)
                print("  (%d/%d) %-18s ok  %s" % (i, len(names), n, msg), flush=True)
            except Exception as e:  # 한 명 때문에 나머지를 못 얹으면 안 된다
                bad.append((n, str(e)[:110]))
                print("  (%d/%d) %-18s !!  %s" % (i, len(names), n, str(e)[:110]), flush=True)
    finally:
        if not a.keep:
            shutil.rmtree(tmp, ignore_errors=True)
    print("\n클립을 얹은 캐릭터 %d명 / 실패 %d명" % (len(ok), len(bad)))
    if bad:
        for n, m in bad:
            print("  !! %-18s %s" % (n, m))
    print("★ 다 됐으면 반드시: godot --headless --path . --import  →  python3 tools/gen_roster.py")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
