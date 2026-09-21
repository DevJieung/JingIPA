#!/usr/bin/env python3
"""`h3-game-sprites` 스킬의 길을 **이 머신의 모델로** 걸어 본다.

    python3 tools/anim/h3_sprites.py <id> [<id> ...]        # 고른 캐릭터
    python3 tools/anim/h3_sprites.py <id> --frames 12        # 뽑을 칸 수
    python3 tools/anim/h3_sprites.py <id> --loop             # 순환 구간을 찾는다
    python3 tools/anim/h3_sprites.py <id> --dry              # 프롬프트만 찍어 본다
    python3 tools/anim/h3_sprites.py --atlas a,b,c           # 이미 뽑은 것으로 아틀라스만

원본 스킬: https://github.com/gary149/h3-game-sprites (MIT).
모탈컴뱃이 배우를 찍어 스프라이트로 만든 그 길을, 배우 자리에 영상 모델을 세워
다시 걷는 것이다. 스킬은 **셋**을 시킨다:

  1. **마젠타 판 위의 정지 그림** — 옆모습·발을 판에 붙이고·판은 완전히 평평하게.
  2. **아이들 핀(idle pin)** — 한 동작 클립의 **첫 칸과 마지막 칸을 같은 정지
     그림으로 못 박는다.** 그러면 (ㄱ) 사람이 안 변하고 (ㄴ) 동작이 반드시 중립으로
     돌아와서 이어 붙고 (ㄷ) 상태 기계에서 동작끼리 이어진다.
  3. **호 길이(arc-length)로 칸 고르기** — 균등하게 나누면 뭉개지고, 움직임이 쌓인
     양을 등분하면 칸이 **자세의 극점**에 앉는다.

────────────────────────────────────────────────────────────────────────────
바꾼 것 둘 — 그리고 왜
────────────────────────────────────────────────────────────────────────────
★ **배우가 H3 가 아니라 LTX2 다.** 스킬은 MiniMax H3 를 API 로 부르는데
  (`OPENROUTER_API_KEY`, 클립 한 편에 0.64달러), 이 머신에는 그 열쇠가 없고
  대신 `tools/anim/ltx_clips.py` 가 이미 **LTX2 로 되는 것을 확인해 두었다.**
  ★★ 그리고 LTX2 의 `--image` 는 **여러 번 줄 수 있다**(`PATH FRAME STRENGTH [CRF]`,
    argparse 가 append 한다). 그래서 **아이들 핀이 그대로 된다** —
    `--image still 0 1.0 0 --image still 48 1.0 0`.
    이것이 `ltx_clips.py` 와 다른 점이다. 거기는 0번 칸만 못 박아서 뒤 3분의 1이
    무너졌고(그 파일 주석), 그래서 앞 62%만 썼다. 양쪽을 못 박으면 **끝까지 산다.**
★ **정지 그림을 새로 안 뽑는다.** 스킬은 Nano Banana 로 그리라는데, 이 저장소에는
  이미 캐릭터 여든 장이 있다. 그것을 **마젠타 판 위에 세우면** 그대로 스킬이 말하는
  정지 그림이다 — 게다가 화풍이 이미 게임의 것이라 「다른 사람이 나오는」 사고가 없다.

────────────────────────────────────────────────────────────────────────────
믿으면 안 되는 것
────────────────────────────────────────────────────────────────────────────
★ **마젠타가 캐릭터를 파먹을 수 있다.** 키 판정이 `r + b - 2g > 120` 이라 보라색
  번개를 두른 캐릭터가 걸린다 — 실측으로 여든 명 중 둘이다(`arc_signal` 4.6% ·
  `thunder_wing` 2.8%). 그래서 세우기 전에 **세어 보고 막는다**(`_key_risk`).
  걸리면 `--key green` 으로 돌려라.
★ **원본 픽셀 격자로 안 돌아온다.** 이 도구는 스킬대로 **크로마 키 + 호 길이**로
  자르는 데까지만 간다. 게임이 읽는 클립(`art/anim/<id>/`)은 안 건드린다 —
  그것은 `ltx_clips.py` 와 `build_clips.py` 의 몫이고, 팔레트를 못 박고 정수배로
  줄이는 절차가 따로 있다. 여기 결과는 **샘플**이다.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SKILL = os.path.expanduser("~/.claude/skills/h3-game-sprites/scripts")

LTX_DIR = "/home/dgxmaruta/pjt/ltx2"
LTX_PY = os.path.join(LTX_DIR, ".venv", "bin", "python")
LTX_CKPT = os.path.join(LTX_DIR, "checkpoints", "ltx-2.3-22b-distilled-1.1.safetensors")
LTX_UPS = os.path.join(LTX_DIR, "checkpoints", "ltx-2.3-spatial-upscaler-x2-1.1.safetensors")
LTX_GEMMA = os.path.join(LTX_DIR, "checkpoints", "gemma-3-12b-it-qat-q4_0-unquantized")

OUT = os.path.join(ROOT, "build", "h3")

# 판 크기는 64의 배수, 칸 수는 8K+1 이어야 한다 (LTX 파이프라인의 assert).
SIZE = 512
FRAMES = 49
FPS = 24

KEY_RGB = {"magenta": (255, 0, 255), "green": (0, 255, 0)}

# ─────────────────────────────────────────────────────────────────────────── #
# 프롬프트 — 스킬의 「가드」를 그대로 옮기고 도트 화풍만 덧댄다
#
# ★ 스킬이 못 박으라는 다섯 줄은 전부 **겪고 나서 생긴 것**이라고 적혀 있다:
#   주먹이 부풀고 · 카메라가 움직이고 · 배경에 그림자가 지고 · 사람이 화면을
#   가로질러 걸어가고 · 음악이 깔린다.
# ─────────────────────────────────────────────────────────────────────────── #
GUARD = (
    "The character's hands and feet stay their normal size at all times - NO "
    "ballooning, NO growing fists; limbs may stretch but hands and feet keep "
    "constant scale. "
    "Camera locked on a tripod, no zoom, no pan, no cut. "
    "The background stays a perfectly flat uniform solid {key} at all times - no "
    "gradient, no cast shadow, no ground line, nothing else enters the frame. "
    "The character stays centered on the same ground level and does not travel "
    "across the frame; everything not described stays static. "
    "Audio: SFX only. NEVER generate music, melody, score or musical tones."
)

# 화풍을 붙드는 말. 정지 그림이 이미 그 화풍이므로 「그대로 두라」만 강하게 건다.
HOLD = ("16-bit pixel art game sprite animation, single character, "
        "crisp blocky pixels, thick black outline, flat bold colors, "
        "no motion blur, no depth of field, no film grain, no vignette, "
        "the sprite stays in exactly the same spot at exactly the same size, "
        "feet planted on the same ground line the whole time. ")

# 동작. `concepts.json` 의 motion 무리(draw · cast · raise)를 그대로 받는다.
MOTION_TEXT = {
    # ★ 무는 동작(`{nock}`)이 무기마다 다르다. 총에 「시위가 튕긴다」를 붙이면 모델이
    #   손에 활을 쥐여 준다 — CLAUDE.md 4-1-1 의 「무리는 못 바꾼다」와 같은 함정이다.
    "draw": ("The figure holds the {weapon} raised and aimed to the right, then releases: "
             "{nock}, the shot flies off to the right, the {weapon} kicks back and the "
             "arms absorb the recoil, then it settles back into the aiming stance."),
    "cast": ("The figure thrusts its forward hand out to the right and casts: the {elem} "
             "gathered above the open palm flares and is flung away to the right, the arm "
             "follows through, then draws back to the ready pose."),
    # ★★ **속성 파동을 여기에 시키지 마라 — 한 번 시켰다가 캐릭터가 사라졌다.**
    #   「얼음 고리가 발밑에서 머리 위로 훑는다」로 뽑았더니 모델이 그것을 **화면을
    #   덮는 폭발**로 그려서, 열두 칸 중 여섯 칸이 흰 구름 한 덩어리였다. 게다가 구름의
    #   알파가 발밑 아래로 뻗어서 **발밑 흔들림이 82px** 로 찍혔다 — 그 값이 곧
    #   전투 화면에서 영웅이 위아래로 튄다는 뜻이다(CLAUDE.md 18-3).
    #   그리고 애초에 그 파동은 **클립에 넣으면 안 되는 것**이다(CLAUDE.md 18-5-2):
    #   속성 색을 타야 하는데 클립은 팔레트가 구워져 있고, 크기가 그려지는 키에 맞아야
    #   하는데 클립은 크기가 고정이다. 게임이 `Fx.rise` 로 따로 그린다.
    #   그래서 여기서는 **몸짓만** 시키고 이펙트는 한 자도 안 적는다.
    "raise": ("The figure sinks down slightly, then RAISES BOTH ARMS up beside its "
              "head with the palms turned upward and the elbows bent, holds them up, "
              "then lowers the arms back down to the resting pose. "
              "Nothing is thrown and NO magic effect, NO glow, NO aura, NO particles, "
              "NO smoke and NO burst appears anywhere - only the body moves."),
}
ELEM_WORD = {"fire": "orange fire", "ice": "pale blue frost", "elec": "violet lightning",
             "water": "deep blue water", "none": "grey dust"}
# 「놓는 순간」이 무기마다 다르다. 없는 무기는 활로 떨어진다.
NOCK = {"bow": "the bowstring snaps forward", "crossbow": "the string snaps forward",
        "gun": "the muzzle flashes with a puff of smoke",
        "cannon": "the barrel belches a burst of smoke"}


def roster() -> dict:
    with open(os.path.join(ROOT, "tools", "roster.json"), encoding="utf-8") as f:
        r = json.load(f)
    return {u["id"]: dict(u, tier=ti)
            for ti, t in enumerate(r["tiers"]) for u in t["units"]}


def concepts() -> dict:
    with open(os.path.join(HERE, "concepts.json"), encoding="utf-8") as f:
        c = json.load(f)
    items = c["units"] if isinstance(c, dict) and "units" in c else c
    if isinstance(items, dict):
        items = [dict(v, id=k) for k, v in items.items()]
    return {it["id"]: it for it in items}


def prompt_for(u: dict, motion: str, key: str) -> str:
    # ★ 결(cast_lunge…)은 무리(cast)의 글을 쓴다. 이름 그대로 찾으면 결이 전부
    #   기본값으로 떨어져서 궁수가 마법사 글로 뽑힌다(CLAUDE.md 18-5-2).
    body = MOTION_TEXT.get(motion.split("_")[0], MOTION_TEXT["cast"]).format(
        weapon=u.get("weapon", "weapon"),
        nock=NOCK.get(u.get("weapon", ""), "the bowstring snaps forward"),
        elem=ELEM_WORD.get(u.get("elem", "none"), "grey dust"))
    return HOLD + body + " " + GUARD.format(key=key)


# ─────────────────────────────────────────────────────────────────────────── #
# 1. 마젠타 판 위의 정지 그림
# ─────────────────────────────────────────────────────────────────────────── #
def _key_risk(rgba, key: str) -> float:
    """캐릭터 픽셀 중 **키 색으로 오해받을** 몫. 스킬의 판정식 그대로 잰다."""
    import numpy as np
    a = np.asarray(rgba).astype(int)
    m = a[..., 3] > 128
    if not m.any():
        return 1.0
    c = a[..., :3][m]
    r, g, b = c[:, 0], c[:, 1], c[:, 2]
    if key == "magenta":
        hit = ((r + b - 2 * g) > 120) & (r > 90) & (b > 90)
    else:
        hit = ((2 * g - r - b) > 120) & (g > 90)
    return float(hit.mean())


def still(uid: str, out: str, key: str) -> int:
    """정지 스프라이트를 **정수배로** 키워 키 색 판 한가운데에 세운다.

    ★ 정수배(NEAREST)여야 도트가 안 뭉개진다.
    ★ 발밑을 판의 아래쪽 16% 자리에 둔다 — 팔을 들면 그림이 위로 자라기 때문이다.
    """
    from PIL import Image
    src = Image.open(os.path.join(ROOT, "art", "units", uid + ".png")).convert("RGBA")
    risk = _key_risk(src, key)
    if risk > 0.01:
        raise RuntimeError(
            "%s 는 %s 키에 %.1f%% 가 먹힌다 — 캐릭터에 구멍이 난다. --key 를 바꿔라"
            % (uid, key, risk * 100))
    w, h = src.size
    k = max(1, int((SIZE * 0.78) // h))
    up = src.resize((w * k, h * k), Image.NEAREST)
    bg = Image.new("RGBA", (SIZE, SIZE), KEY_RGB[key] + (255,))
    bg.alpha_composite(up, ((SIZE - up.width) // 2, int(SIZE * 0.84) - up.height))
    # ★ CRF 0(무손실)으로 넘길 것이므로 PNG 로 둔다. JPEG 로 두면 마젠타 가장자리에
    #   링잉이 생겨서 키가 캐릭터 테두리를 갉아먹는다.
    bg.convert("RGB").save(out)
    return k


# ─────────────────────────────────────────────────────────────────────────── #
# 2. LTX2 로 영상 — **아이들 핀**
# ─────────────────────────────────────────────────────────────────────────── #
def run_ltx(cond: str, prompt: str, out: str, seed: int, pin: bool = True) -> None:
    """★ 핵심은 `--image` 를 **두 번** 주는 것이다.

    첫 칸과 마지막 칸을 같은 정지 그림으로 못 박으면, 영상 모델은 그 사이를
    메우는 일만 한다 — 사람이 안 변하고, 끝이 처음으로 돌아와서 클립이 이어 붙는다.
    """
    cmd = [LTX_PY, os.path.join(LTX_DIR, "run_ltx.py"),
           "--distilled-checkpoint-path", LTX_CKPT,
           "--spatial-upsampler-path", LTX_UPS,
           "--gemma-root", LTX_GEMMA,
           "--quantization", "fp8-cast",
           "--prompt", prompt,
           # CRF 0 = 무손실. 도트 그림은 압축을 먹으면 테두리가 뭉갠다.
           "--image", cond, "0", "1.0", "0"]
    if pin:
        cmd += ["--image", cond, str(FRAMES - 1), "1.0", "0"]
    cmd += ["--output-path", out,
            "--width", str(SIZE), "--height", str(SIZE),
            "--num-frames", str(FRAMES), "--frame-rate", str(FPS),
            "--seed", str(seed)]
    r = subprocess.run(cmd, cwd=LTX_DIR, capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(out):
        tail = (r.stdout + r.stderr).strip().splitlines()
        raise RuntimeError("\n".join(tail[-12:]) if tail else "LTX 실패")


# ─────────────────────────────────────────────────────────────────────────── #
# 3. 게이트 — **무너지기 시작한 칸부터 버린다**
#
# `ltx_clips.py` 의 `gate()` 를 그대로 옮기고 **다섯째 잣대를 더한 것**이다.
# 넷만으로는 「총이 손에서 사라지는」 무너짐을 **하나도 못 잡는다**(실측):
#   scorch_tyrant 의 19~43번 칸에서 총이 통째로 없어졌는데 넓이비 0.81~1.03 ·
#   발밑 0~2px · 세로 -2 · 덩어리 100% 로 넉 잣대가 전부 통과했다.
#   움직인 값은 **가로 하나뿐**이었다 (1.43 → 0.68).
#
# ★★ **그런데 `ltx_clips.py` 는 가로를 일부러 뺐다** — 그 파일 주석에 까닭이 적혀
#   있다: 「팔을 앞으로 뻗으면 가로는 **당연히** 커진다(68 → 88px). 그건 무너진 것이
#   아니라 **동작 그 자체**라, 이 잣대는 멀쩡한 클립을 두 개나 떨어뜨렸다.」
#   맞는 말이고, 그래서 **그 판단을 되돌리지 않는다.** 그때 문제는 **넓어지는 것**이고
#   지금 문제는 **좁아지는 것**이라, 방향이 반대다. 가로는 **커지는 쪽으로는 여전히
#   자유롭다** — 주저앉는 쪽만 본다.
#
# ★ 그리고 **주저앉는 것만 봐도 아직 모자란다.** 셋을 다 만족해야 자른다:
#     1. **밑값 아래**(0.85)   — 이것만 보면 안 된다
#     2. **벼랑**(한 칸에 18% 이상)  ← `alpine_horn` 을 살린다. 두 팔을 모으면 가로가
#        1.00 → 0.76 으로 **매끄럽게** 줄어드는데(18칸에 걸쳐), 그건 동작이다.
#     3. **버틴다**(여섯 칸 내리)     ← `volt_augur` 를 살린다. 번개가 화면 밖으로
#        날아가는 순간 가로가 1.00 → 0.69 로 **벼랑처럼** 떨어지지만 두 칸 만에
#        돌아온다. 소품이 사라진 것이 아니라 이펙트가 지나간 것이다.
#   실측: scorch_tyrant 16/49 로 잘리고, 나머지 둘은 49/49 로 전부 산다.
#
# ★ 재는 것은 **가장 큰 덩어리의 가로**다 — 알파 전체가 아니다. 번개·연기처럼 몸에서
#   **떨어진** 조각은 빼고 재야, 「손에 쥔 것이 없어졌는가」만 남는다.
# ─────────────────────────────────────────────────────────────────────────── #
AREA_LO, AREA_HI = 0.70, 1.45      # 0번 칸 대비 알파 넓이의 허용 폭
FOOT_DRIFT = 0.05                  # 발밑이 움직여도 되는 몫 (판 높이 대비)
BODY_FRAC = 0.72                   # 제일 큰 덩어리가 차지해야 할 최소 몫
TALL_DRIFT = 0.16                  # 세로 높이가 흔들려도 되는 몫
WIDE_FLOOR = 0.85                  # 몸 가로가 이 밑으로 내려가야 의심한다
WIDE_DROP = 0.18                   # 한 칸에 이만큼 주저앉아야 「벼랑」이다
WIDE_HOLD = 6                      # 이만큼 내리 안 돌아와야 「사라진 것」이다
# ★ 여덟 칸도 못 건지면 그 클립은 통째로 실패로 친다 — `ltx_clips.py` 와 같은 잣대다.
#   어설픈 것으로 덮어쓰느니 안 만드는 편이 낫다.
MIN_FRAMES = 8


def _shape(m):
    """(알파 전체 넓이, **몸** 넓이, 몸 발밑, 몸 세로, 몸 가로).

    ★★ **넓이·발밑·세로도 「몸」으로 잰다 — 알파 전체로 재면 이펙트에 속는다.**
      `ltx_clips.py` 는 알파 전체로 쟀는데, 여기서 그대로 쓰니 `volt_augur` 가
      14번 칸에서 **잘못 잘렸다**: 「키가 362 → 422 로 변했다」. 사람이 무너진 것이
      아니라 **번개가 머리 위로 뻗어서** 테두리 상자가 커진 것이다.
      그 파일에서 안 터진 까닭은 거기 게이트가 **정지 그림 팔레트로 못 박고 정수배로
      줄인 뒤**에 도는 데다, 애초에 앞 62%만 보기 때문이다.
      잣대가 재려는 것은 전부 **몸이 온전한가**이므로, 몸에서 떨어져 나온 조각
      (번개·연기·총구 불꽃·파편)은 어느 잣대에도 안 들어가야 한다.
    ★ 「쪼개졌는가」만 둘 다 쓴다 — 몸이 전체에서 차지하는 몫이 곧 그 잣대다.
    """
    import numpy as np
    from scipy import ndimage
    if not m.any():
        return 0, 0, 0, 0, 0
    lab, k = ndimage.label(m)
    if k == 0:
        return 0, 0, 0, 0, 0
    sizes = ndimage.sum(m, lab, range(1, k + 1))
    big = lab == (int(np.argmax(sizes)) + 1)
    ys = np.nonzero(big.any(axis=1))[0]
    xs = np.nonzero(big.any(axis=0))[0]
    return (int(m.sum()), int(sizes.max()), int(ys[-1]),
            int(ys[-1] - ys[0] + 1), int(xs[-1] - xs[0] + 1))


def gate(masks) -> tuple:
    """앞에서부터 **무너지기 직전까지** 몇 칸을 쓸 수 있는가."""
    sh = [_shape(m) for m in masks]
    _a0, n0, f0, h0, w0 = sh[0]
    if n0 <= 0:
        return 0, "0번 칸이 비었다"
    H = masks[0].shape[0]
    wr = [(s[4] / float(w0)) if w0 else 0.0 for s in sh]
    for i, (n_all, n, fy, bh, _w) in enumerate(sh):
        if n < n0 * AREA_LO or n > n0 * AREA_HI:
            return i, "%d번 칸에서 몸 넓이가 %.2f배로 튀었다" % (i, n / float(n0))
        if abs(fy - f0) > H * FOOT_DRIFT:
            return i, "%d번 칸에서 발밑이 %dpx 움직였다" % (i, abs(fy - f0))
        if abs(bh - h0) > h0 * TALL_DRIFT:
            return i, "%d번 칸에서 키가 %d → %d 로 변했다" % (i, h0, bh)
        if n < n_all * BODY_FRAC:
            return i, "%d번 칸에서 몸이 쪼개졌다 (제일 큰 덩어리가 %.0f%%)" \
                % (i, 100.0 * n / float(max(1, n_all)))
        # ★ 다섯째 — 손에 쥔 것이 사라졌는가
        if i >= 1 and wr[i] <= WIDE_FLOOR and wr[i] <= wr[i - 1] * (1 - WIDE_DROP):
            run = wr[i:i + WIDE_HOLD]
            if len(run) >= WIDE_HOLD and max(run) <= WIDE_FLOOR:
                return i, ("%d번 칸에서 몸 가로가 %.2f → %.2f 로 주저앉아 %d칸을 "
                           "안 돌아왔다 (손에 쥔 것이 사라졌다)"
                           % (i, wr[i - 1], wr[i], WIDE_HOLD))
    return len(masks), ""


def _skill_mod():
    """키 판정식을 **스킬 파일에서 그대로 가져온다.** 여기에 베껴 적으면 언젠가
    스킬과 게이트가 서로 다른 배경을 보게 된다."""
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "h3_sprite_cut", os.path.join(SKILL, "sprite_cut.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def gate_clip(mp4: str, tmp: str, key: str) -> tuple:
    """클립을 재서 **살아남은 칸까지만** 잘라 낸 새 클립 경로를 돌려준다.

    ★ 자를 때 **무손실(ffv1)** 이어야 한다. 다시 압축하면 마젠타 가장자리에 링잉이
      생겨서, 애써 1.000 이던 키 순도가 조용히 내려간다.
    """
    import numpy as np
    from PIL import Image
    sc = _skill_mod()
    raw = os.path.join(tmp, "gate_raw")
    names = sc.extract(mp4, raw)
    masks = []
    for n in names:
        rgba, _bg = sc.key_frame(Image.open(os.path.join(raw, n)), key)
        masks.append(np.asarray(rgba)[..., 3] > 128)
    good, why = gate(masks)
    shutil.rmtree(raw, ignore_errors=True)
    if good >= len(names):
        return mp4, len(names), len(names), ""
    out = os.path.splitext(mp4)[0] + "_gated.mkv"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-i", mp4,
                    "-frames:v", str(good), "-c:v", "ffv1", "-an", out], check=True)
    return out, good, len(names), why


# ─────────────────────────────────────────────────────────────────────────── #
# 4. 스킬의 자르는 도구를 그대로 부른다
# ─────────────────────────────────────────────────────────────────────────── #
def sprite_cut(mp4: str, outdir: str, frames: int, key: str, loop: bool) -> dict:
    # ★★ **먼저 비운다 — 스킬의 `extract()` 는 디렉터리를 안 비운다.**
    #   그 함수는 `ffmpeg … f%04d.png` 로 뽑고 나서 `os.listdir` 로 **거기 있는 것을
    #   전부** 훑는다. 그래서 49칸을 뽑았던 자리에 게이트로 자른 16칸을 다시 뽑으면
    #   앞 판의 17~49번이 그대로 남아, **잘라 낸 무너진 칸이 도로 살아 들어온다.**
    #   실제로 그랬다 — 게이트가 「16/49 칸만 쓴다」고 찍고도 보고서는 49칸이었다.
    #   스킬 파일은 안 고친다(그대로 두는 것이 이 도구의 값이다). 여기서 비운다.
    for sub in ("raw", "keyed"):
        shutil.rmtree(os.path.join(outdir, sub), ignore_errors=True)
    cmd = [sys.executable, os.path.join(SKILL, "sprite_cut.py"), mp4, outdir,
           "--frames", str(frames), "--key", key]
    if loop:
        cmd.append("--loop")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stdout + r.stderr).strip()[-800:])
    with open(os.path.join(outdir, "report.json"), encoding="utf-8") as f:
        return json.load(f)["summary"]


def build_atlas(ids: list, ref: str, height: int) -> str:
    """★ 스킬의 아틀라스는 **동작**마다 한 칸인데, 여기서는 캐릭터마다 한 동작뿐이라
    「캐릭터 = 동작」으로 넣는다. 잣대(scale)가 하나뿐인 것이 핵심이라 뜻은 그대로다."""
    out = os.path.join(OUT, "atlas.json")
    cmd = [sys.executable, os.path.join(SKILL, "build_atlas.py"), OUT, out,
           "--moves", ",".join(ids), "--ref", ref, "--height", str(height)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError((r.stdout + r.stderr).strip()[-800:])
    print(r.stdout.strip())
    return out


# ─────────────────────────────────────────────────────────────────────────── #
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--frames", type=int, default=12)
    ap.add_argument("--key", default="magenta", choices=["magenta", "green"])
    ap.add_argument("--loop", action="store_true")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--dry", action="store_true", help="프롬프트만 찍는다")
    ap.add_argument("--atlas", default="", help="이미 뽑은 것으로 아틀라스만 짠다")
    ap.add_argument("--height", type=int, default=340)
    ap.add_argument("--recut", action="store_true",
                    help="이미 뽑아 둔 clip.mp4 를 다시 자르기만 한다 (영상은 안 뽑는다)")
    ap.add_argument("--no-gate", action="store_true",
                    help="게이트를 끄고 무너진 칸까지 전부 쓴다 (무엇이 잘렸나 볼 때)")
    args = ap.parse_args()

    if args.atlas:
        ids = [x.strip() for x in args.atlas.split(",") if x.strip()]
        build_atlas(ids, ids[0], args.height)
        return 0

    R, C = roster(), concepts()
    os.makedirs(OUT, exist_ok=True)
    ok, bad = [], []

    for uid in args.ids:
        u = R.get(uid)
        if u is None:
            print("  ! 없는 id: %s" % uid)
            bad.append(uid)
            continue
        motion = C.get(uid, {}).get("motion", "cast")
        pr = prompt_for(u, motion, args.key)
        if args.dry:
            print("── %s (%s · %s · %s)\n%s\n" % (uid, u.get("en"), motion, u.get("elem"), pr))
            continue

        d = os.path.join(OUT, uid)
        os.makedirs(d, exist_ok=True)
        st = os.path.join(d, "still.png")
        mp4 = os.path.join(d, "clip.mp4")
        try:
            if args.recut:
                if not os.path.exists(mp4):
                    raise RuntimeError("다시 자를 영상이 없다: %s" % mp4)
                print("[%s] %s · %s — 있는 영상을 다시 자른다"
                      % (uid, u.get("en"), motion), flush=True)
            else:
                still(uid, st, args.key)
                print("[%s] %s · %s — 영상 뽑는 중 (아이들 핀 0 ↔ %d)"
                      % (uid, u.get("en"), motion, FRAMES - 1), flush=True)
                run_ltx(st, pr, mp4, args.seed + abs(hash(uid)) % 1000)
            src = mp4
            if not args.no_gate:
                src, good, tot, why = gate_clip(mp4, d, args.key)
                if good < MIN_FRAMES:
                    raise RuntimeError("쓸 만한 칸이 %d개뿐이다 (%s)" % (good, why))
                if why:
                    print("   게이트: %d/%d 칸만 쓴다 — %s" % (good, tot, why), flush=True)
                else:
                    print("   게이트: %d칸 전부 산다" % tot, flush=True)
            s = sprite_cut(src, d, args.frames, args.key, args.loop)
            print("   칸 %d 중 %d 골랐다 | 키 순도 %.3f | 되돌아옴 %.2f | 발밑 흔들림 %dpx"
                  % (s["frames"], len(s["picked"]), s["worst_bg_purity"],
                     s["loop_diff"], s["baseline_drift_px"]), flush=True)
            ok.append(uid)
        except Exception as e:                                  # noqa: BLE001
            print("   ✗ %s: %s" % (uid, e), flush=True)
            bad.append(uid)

    if len(ok) >= 2:
        print()
        build_atlas(ok, ok[0], args.height)
    print("\n됐다: %s   실패: %s" % (", ".join(ok) or "-", ", ".join(bad) or "-"))
    print("결과: %s" % OUT)
    return 0 if (ok or args.dry) else 1


if __name__ == "__main__":
    raise SystemExit(main())
