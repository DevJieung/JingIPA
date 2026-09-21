#!/usr/bin/env python3
"""Step 3 — Wan 프레임 → 게임용 스프라이트 시트.

`sprite_pipeline.md` §3 Step 3 의 `sprite_post.py` 를 이 저장소에 맞게 옮긴 것.
바뀐 것이 넷이다:

  1. **입력이 mp4 가 아니라 PNG 폴더**다. H.264 는 하드 엣지를 갈아 뭉개고 색을
     4:2:0 으로 반씩 버려서, 테두리 한 도트와 마젠타 크로마키를 동시에 망친다
     (`wan_i2v.py` 머리말).
  2. **팔레트·크로마키·공통 크롭이 `pixels.py` 한 곳**에 있다. 원화(Step 1)와
     시트(Step 3)가 다른 팔레트를 쓰면 그 어긋남은 눈으로만 잡힌다.
  3. **루프 잇는 자리를 찾는다.** 지침 §5 는 「루프의 첫/끝이 자연스럽게 이어진다」를
     체크리스트로만 두는데, I2V 출력은 그냥 자르면 절대로 안 이어진다 — 33프레임을
     끝까지 쓰면 마지막이 처음으로 안 돌아온다. 0번과 가장 닮은 프레임을 찾아
     **그 앞까지**를 한 바퀴로 친다.
  4. **임팩트 프레임을 5번 자리에 맞춘다**(지침 §1 「임팩트 프레임을 5~6번째에」).
     움직임이 가장 큰 칸이 곧 놓는 칸이다 — CLAUDE.md 18-4 와 같은 규칙이다.

    python3 tools/sprite/sprite_post.py --route sdxl
"""

from __future__ import annotations

import argparse
import json
import os
import sys

from PIL import Image, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import pixels                                    # noqa: E402
import units as U                                # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")


# --------------------------------------------------------------------------
# 프레임 고르기
# --------------------------------------------------------------------------
def _load_dir(d: str) -> list[Image.Image]:
    fs = sorted(f for f in os.listdir(d) if f.endswith(".png"))
    if not fs:
        raise SystemExit(f"프레임이 없다: {d}")
    return [Image.open(os.path.join(d, f)).convert("RGBA") for f in fs]


def _diff(a: Image.Image, b: Image.Image) -> float:
    """두 프레임이 얼마나 다른가 (0=같음). 알파를 지운 RGB 로만 잰다."""
    ga, gb = a.convert("L"), b.convert("L")
    h = ImageChops.difference(ga, gb).histogram()
    tot = sum(h)
    return sum(i * v for i, v in enumerate(h)) / max(1, tot) / 255.0


def loop_end(fr: list[Image.Image], lo: int = 8) -> int:
    """0번으로 되돌아오는 자리 중 **가장 늦은** 것. 루프 한 바퀴의 끝이다.

    ★ 그냥 「제일 닮은 칸」을 고르면 **반 주기**에서 끊긴다. 숨쉬기는 올라갔다
      내려오므로 한 바퀴 가운데에서도 자세가 처음과 같아지는데, 거기서 자르면
      캐릭터가 계속 올라가기만 하는 애니메이션이 된다(실측: 24칸 주기를 12칸으로
      끊었다). 그래서 **가장 닮은 값에 가까운 것들 중 제일 늦은 칸**을 고른다.
    """
    ds = [(i, _diff(fr[0], fr[i])) for i in range(lo, len(fr))]
    if not ds:
        return len(fr) - 1
    m = min(d for _, d in ds)
    near = [i for i, d in ds if d <= m * 1.35 + 0.004]
    return max(near)


class KeyedAway(Exception):
    """크로마키가 캐릭터까지 지웠다. 그 한 명만 건너뛰라는 뜻이다."""


def _arm_top(im: Image.Image) -> int:
    """알파가 있는 **맨 윗줄**. 작을수록 팔이 높다."""
    b = im.getbbox()
    return b[1] if b else im.height


def impact_i(fr: list[Image.Image], family: str = "") -> int:
    """**쉬는 자세에서 가장 멀리 간 칸** = 놓는 칸.

    ★ 칸과 칸 사이의 차이(속도)로 잡으면 안 된다 — 그것이 제일 큰 곳은 팔이
      **지나가는** 중간이고, 놓는 순간은 오히려 잠깐 멎는다. 실측으로 12번에
      정점을 둔 가짜 클립에서 속도 기준은 9번을 골랐다.
      0번(쉬는 자세)에서 가장 먼 칸이 곧 가장 뻗은 칸이다.

    ★★ **`raise`(광역)만 자가 다르다 — 팔이 제일 높은 칸이다.**
      이 무리의 동작은 「먼저 가라앉았다가 두 팔을 올린다」라, 가라앉는 앞쪽 칸이
      0번에서 **픽셀로는** 팔을 든 뒤쪽 칸만큼 멀다. 실측으로 림네에서 그 자가
      33칸 중 9번(아직 서 있다)을 골랐고, 팔은 20번이 넘어서야 올라갔다.
      그러면 장판이 **팔을 들기 전에** 깔린다 — 사용자가 정한 연출이
      「두 팔을 들어올림과 **동시에**」이므로 그 순간 규칙이 화면에서 거짓말을 한다.
      팔 높이(알파의 맨 윗줄)로 재면 그 무리에서만 정직하다.
    """
    lo, hi = 1, len(fr) - 2
    if family == "raise":
        # ★ 제일 높은 칸이 아니라 **제일 높은 자리에 처음 닿는 칸**이다.
        #   팔은 한 번 올라가면 끝까지 올라가 있으므로 「제일 높은 칸」은 늘 뒤쪽
        #   어딘가가 되고, 그러면 시트를 다시 잴 때마다 답이 흔들린다 — 실측으로
        #   `pick` 은 5칸을 겨눴는데 `to_game` 이 같은 시트에서 9칸을 골랐고,
        #   `ns_check` 의 총구 대조가 그 어긋남을 잡았다.
        #   **닿는 순간**이 곧 시전이 끝나는 순간이라 뜻으로도 그쪽이 맞다.
        tops = [_arm_top(fr[i]) for i in range(lo, hi)]
        peak = min(tops)
        for k, t in enumerate(tops):
            if t <= peak + 2:
                return lo + k
        return lo
    return max(range(lo, hi), key=lambda i: _diff(fr[0], fr[i]))


def pick(fr: list[Image.Image], n: int, *, loop: bool, hit_at: int = 5,
         family: str = "") -> list[int]:
    """n 칸을 고른다. 루프면 **앞뒤로 왕복**시키고, 아니면 임팩트를 hit_at 에 맞춘다."""
    if loop:
        return _pingpong(fr, n)
    # 논루프(attack): 1번부터 임팩트까지 hit_at 칸, 임팩트 뒤로 나머지
    hit = impact_i(fr, family)
    lo, hi = 1, len(fr) - 2
    tail_n = n - hit_at
    # ★ 임팩트가 너무 뒤면 뒤쪽 칸이 **중복**된다(실측: 27번에서 28,28,29,30,30,31).
    #   뒤에 남길 칸 수만큼은 반드시 비워 둔다.
    hit = min(max(hit, lo + 1), hi - max(1, tail_n - 1))
    head = [round(lo + i * (hit - lo) / hit_at) for i in range(hit_at)]
    tail = [round(hit + i * (hi - hit) / max(1, tail_n - 1)) for i in range(tail_n)]
    idx = head + tail
    return [min(max(i, 0), len(fr) - 1) for i in idx]


def _pingpong(fr: list[Image.Image], n: int) -> list[int]:
    """★★ 숨쉬기는 **왕복**으로 만든다 — Wan 의 idle 은 한 바퀴를 안 돈다.

    실측: 다섯 명의 idle 다섯 개 모두 0번으로 돌아오는 자리가 없었다
    (첫/끝 차이 0.060~0.086). Wan I2V 는 2초짜리 **한 방향** 움직임을 주지
    사이클을 주지 않는다 — 그대로 자르면 마지막 칸에서 첫 칸으로 툭 튄다.

    ★ 앞으로 가는 절반을 고르고 **거울로 되돌린다**. 숨쉬기는 실제로도 들이쉬고
      내쉬는 왕복이라 뜻이 맞고, 이음매가 산수로 없다 — 마지막 칸의 다음이
      첫 칸이 아니라 **첫 칸 자신**이기 때문이다.
    ★ 되돌아오는 쪽에서 양 끝(0번과 정점)은 **빼야** 한다. 안 빼면 그 두 칸이
      두 번씩 나와서 숨이 그 자리에서 잠깐 멎는다.
    """
    half = n // 2 + 1                     # 시작 … 정점 (n=8 이면 다섯 칸)
    end = loop_end(fr)
    # ★★ **0번을 쓰지 마라.** Wan I2V 의 0번은 넣어 준 입력 그대로이고 1번부터가
    #    모델이 다시 그린 것이라, 그 사이에 결이 한 번 튄다 — 빙하대공에서
    #    이음매가 0.072 인데 다른 걸음이 0.004 였다(열여덟 배). 지침 §3 이
    #    「첫/끝 프레임은 흔들리므로 안쪽에서 균등 샘플링」이라 한 그 자리다.
    lo = 1
    fwd = arc_pick(fr, lo, end, half)
    back = list(reversed(fwd[1:-1]))      # 양 끝은 빼고 거울
    idx = (fwd + back)[:n]
    while len(idx) < n:                   # 홀수 n 이면 정점을 한 칸 더 쓴다
        idx.append(fwd[-1])
    return idx


def arc_pick(fr: list[Image.Image], lo: int, hi: int, k: int) -> list[int]:
    """[lo, hi] 를 **움직인 양**으로 k 등분해 고른다.

    ★★ 프레임 번호로 등분하면 안 된다. Wan I2V 의 움직임은 **앞쪽에 몰려 있다** —
       빙하대공의 숨쉬기는 앞 여덟 칸에서 다 움직이고 나머지 스물넷은 거의 멎어
       있었다(걸음 0.064 대 0.004, 열여섯 배). 번호로 등분하면 그 한 걸음만
       크게 남아서, 왕복 루프의 이음매가 그 자리에서 툭 튄다.
    ★ 움직인 양으로 등분하면 **모든 걸음이 같은 크기**가 되고, 이음매도 그중
      한 걸음일 뿐이라 산수로 안 튄다.
    """
    cum = [0.0]
    for i in range(lo, hi):
        cum.append(cum[-1] + _diff(fr[i], fr[i + 1]))
    total = cum[-1]
    if total <= 1e-6:                     # 아예 안 움직이면 번호로 등분
        return [round(lo + i * (hi - lo) / max(1, k - 1)) for i in range(k)]
    out, j = [], 0
    for i in range(k):
        want = total * i / (k - 1)
        while j + 1 < len(cum) and cum[j + 1] < want:
            j += 1
        out.append(lo + j)
    return out


# --------------------------------------------------------------------------
# 한 애니메이션 처리
# --------------------------------------------------------------------------
def select(frames_dir: str, *, n: int, loop: bool,
           family: str = "") -> tuple[list[Image.Image], list[int], tuple]:
    """프레임을 떼어 내고 n칸을 고른 뒤, 그 칸들의 **공통 크롭 상자**까지 준다.

    ★ 굽는 일(`render`)과 나눠 놓은 까닭은 하나다 — **한 캐릭터의 클립 둘이 같은
      상자를 써야** 하기 때문이다. 아래 `render` 머리말을 봐라.
    """
    raw = _load_dir(frames_dir)
    keyed = [pixels.dekey_hard(pixels.dekey(im.copy())) for im in raw]
    # ★ 크로마키가 캐릭터까지 지웠으면 여기서 멈춘다. 그냥 두면 빈 프레임이
    #   공통 크롭을 통과해 **한 픽셀짜리 시트**가 조용히 만들어진다.
    gone = max(pixels.keyed_ratio(a, b) for a, b in zip(raw, keyed))
    if gone > 0.985:
        # ★ **멈추지 말고 그 한 명만 건너뛴다.** 쉰 명을 한 번에 도는 길에서
        #   `SystemExit` 를 던지면 뒤에 남은 마흔몇이 통째로 안 구워진다 —
        #   한 명이 실패해도 나머지는 얹는다는 규칙(CLAUDE.md 18-1)과 정반대다.
        raise KeyedAway(f"{frames_dir}: 크로마키가 {gone:.1%} 를 지웠다 — 캐릭터까지 먹었다")
    idx = pick(keyed, n, loop=loop, family=family)
    sel = [keyed[i] for i in idx]
    # ★ 공통 크롭 — 프레임마다 따로 자르면 발이 프레임마다 튄다 (지침 §3)
    return sel, idx, pixels.union_bbox(sel)


def shrink(im: Image.Image, box: tuple, size: int) -> Image.Image:
    """상자로 잘라 정사각 칸에 **하단 정렬**로 앉히고 size 로 줄인다 (팔레트 전).

    ★ `render` 와 `foot_lines` 가 **같은 기하**를 쓰게 하려고 떼어 놓은 것이다.
      발 줄을 재는 자와 굽는 자가 다르면, 재서 맞춰 놓은 것이 구울 때 도로 어긋난다.
    """
    im = pixels.binarize_alpha(im.crop(box))
    side = max(im.width, im.height)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - im.width) // 2, side - im.height))
    # 줄일 때는 BOX. NEAREST 로 줄이면 1도트 검은 테두리가 통째로 사라진다.
    return pixels.binarize_alpha(canvas.resize((size, size), Image.BOX), 110)


def bake(im: Image.Image, box: tuple, size: int, elem: str) -> Image.Image:
    """한 칸을 **끝까지** 굽는다 — 자르고 · 줄이고 · 팔레트에 앉히고 · 테두리를 두른다.

    ★ 시트에 저장되는 것과 **한 픽셀도 다르지 않아야** 한다. 발 줄을 재는 `foot_lines`
      가 이 함수를 그대로 부르기 때문이다 — 재는 그림과 나가는 그림이 다르면, 재서
      맞춰 놓은 것이 구울 때 도로 어긋난다. 실제로 그랬다: 처음에는 테두리를 두르기
      **전**에 쟀는데, 그러면 `add_outline` 이 떨어져 있던 조각을 몸에 이어 붙이면서
      「가장 큰 덩어리」가 달라져 세 명(리아넌·모리안·블랭크)이 1px 씩 다르게 읽혔다.
      그 셋은 최종 시트에서 흔들림이 0 인데도 밀려서 시트가 바뀌었다.
    """
    small = pixels.quantize(shrink(im, box, size), pixels.palette_for(elem))
    # ★ 마스터와 **같은 자리에서** 테두리를 다시 두른다. Wan 을 지나온 가장자리는
    #   흐려져 있어서, 마스터에 그려 둔 한 겹이 그대로 살아 돌아오지 않는다.
    return pixels.add_outline(small)


def render(sel: list[Image.Image], idx: list[int], box: tuple, *,
           size: int, elem: str, loop: bool, n_src: int) -> tuple[Image.Image, dict]:
    """고른 칸들을 그 상자로 잘라 96x96 시트로 굽는다.

    ★★ **`box` 는 그 캐릭터의 클립 **전부**를 아우른 상자여야 한다.**
      클립마다 제 상자로 자르면 idle 과 attack 의 배율이 달라진다 — 팔을 뻗는
      attack 쪽 상자가 더 넓으므로 같은 96칸에 눌러 담으면서 **사람이 작아진다.**
      화면에서는 영웅이 쏠 때마다 쪼그라들었다 커지는 것으로 보인다.
      CLAUDE.md 18-3 이 「기준점이 어긋나면 영웅이 위아래로 튄다」로 적은 것과
      같은 자리이고, 여기서는 **크기**가 튄다.
    """
    out = [bake(im, box, size, elem) for im in sel]

    meta = {"picked": idx, "src_frames": n_src, "union_box": box, "loop": loop}
    return pixels.pack_sheet(out, size), meta


# --------------------------------------------------------------------------
# ★★ 발 맞추기 — 「칸마다 발이 같은 줄에 선다」
#
# 게임은 **아이들 0번 칸의 발밑** 하나를 기준점으로 삼아 모든 칸을 그린다
# (`to_game.one` 의 `anchor`). 그래서 칸마다 발 높이가 다르면 그 캐릭터는 전투
# 화면에서 **위아래로 흔들린다** — CLAUDE.md 18-3 이 금지한 바로 그것이다.
# 이 게임에는 점프가 없으므로 발은 언제나 같은 줄에 있어야 맞다.
#
# 실측(출고된 쉰 명): 시그리드의 공격 6~9번 칸이 통째로 **5px 가라앉아** 있었고
# (512칸 기준 25px · 몸 전체가 내려간다), 루그는 3px 흔들렸다. 나머지 48명은 0 이다.
# 공식 `qc()` 는 시그리드를 「발 높이가 5px 흔들림」으로 **이미 지적하고 있었는데**
# 그 지적이 아무것도 막지 않아서 그대로 게임에 들어갔다.
#
# ★★ **재는 자는 알파 아래끝이 아니라 `pixels.feet_line`(가장 큰 덩어리가 **발자리를 덮는**
#   맨 아랫줄)이다.** 루그의 3px 중 1px 은 발이 아니라 왼쪽 아래에 떠 있는 **부스러기**였다.
#   아래끝으로 맞추면 부스러기에 몸을 맞추게 된다 (`body_bottom` 머리말).
#   ★ 그리고 덩어리의 맨 아랫줄(`body_bottom`)로도 모자랐다 — H3 클립에서 스노리의 채찍이
#     후려칠 때 발 밑으로 내려갔고, 그 칸의 **몸을 71px 밀어 올렸다**(채찍 끝을 발로 읽었다).
#     발자리는 **아이들 0번 칸**(마스터 · 모든 칸의 기준점)이 정하고, 발 밑으로 내려간 소품은
#     그 자리를 안 덮는다 — `feet_line(ref)` 가 그 잣대다(`pixels` 머리말).
#     출고된 쉰 명 백 장에서 두 자는 같다(`pixels.py --feet`).
# ★ **재는 곳은 다 구워 놓은 최종 96칸**이다(`bake`). 원본 512칸에서 재면 여덟 명이
#   걸리는데 줄이고 나면 그중 여섯은 1px 도 안 흔들리고, 테두리를 두르기 **전**에 재면
#   또 세 명이 1px 씩 다르게 읽힌다. 게임이 보는 것은 다 구운 96칸이므로 거기서 재는
#   것이 맞고, 그래야 이미 멀쩡한 48명의 시트가 **한 바이트도 안 바뀐다.**
# ★ **미는 것은 원본 512칸**이다. 96칸에서 밀면 칸 밖으로 나간 몫이 잘리는데,
#   원본에서 밀고 상자를 다시 잡으면 상자가 따라 넓어져서 아무것도 안 잘린다.
# --------------------------------------------------------------------------
def foot_lines(sel: list[Image.Image], box: tuple, size: int, elem: str,
               ref: list[tuple[int, int]] | None = None) -> list[int]:
    """**끝까지 구운** 칸에서 잰 발 줄(96칸 기준). 재는 그림 = 나가는 그림이다.
    `ref` 는 아이들 0번 칸의 발자리(`pixels.feet_runs`) — 같은 상자로 구운 것이어야 한다."""
    return [pixels.feet_line(bake(im, box, size, elem), ref) for im in sel]


def foot_ref(picked: dict, box: tuple, size: int, elem: str) -> list[tuple[int, int]]:
    """발자리의 기준 — 아이들 0번 칸(없으면 첫 클립의 0번 칸)을 그 상자로 구워서 잰다."""
    anim = "idle" if "idle" in picked else next(iter(picked))
    return pixels.feet_runs(bake(picked[anim][0][0], box, size, elem))


def foot_shift(feet: dict[str, list[int]], box: tuple, size: int) -> dict[str, list[int]]:
    """발 줄을 **가운뎃값**에 맞추는 세로 이동량(원본 픽셀 · 아래가 양수).

    ★ 가운뎃값을 기준으로 삼는 까닭: 대부분의 칸은 제자리에 있고 몇 칸만 튄다.
      가장 낮은 칸에 맞추면 멀쩡한 열여섯 칸이 통째로 가라앉는다(시그리드에서 실제로
      그렇게 된다 — 튄 칸은 넷뿐인데 나머지 열여섯이 5px 씩 내려간다).
    ★ 칸이 다 같으면 이동량이 전부 0 이다 — 48명에게 이 함수는 **아무 일도 안 한다.**
    """
    # ★ 빈 칸(-1)은 셈에서 빼고 **안 민다.** 안 그러면 빈 칸 하나가 기준을 끌어내리고,
    #   그 큰 이동량이 `pad` 가 되어 쉰 명의 틀을 통째로 부풀린다. 빈 칸 자체는
    #   `select` 가 먼저 막고 `qc` 가 따로 지적한다.
    flat = sorted(v for vs in feet.values() for v in vs if v >= 0)
    if not flat:
        return {a: [0] * len(vs) for a, vs in feet.items()}
    ref = flat[len(flat) // 2]
    k = max(box[2] - box[0], box[3] - box[1]) / float(size)   # 96칸 한 도트 = 원본 몇 도트
    return {a: [(int(round((ref - v) * k)) if v >= 0 else 0) for v in vs]
            for a, vs in feet.items()}


def shift_frames(sel: list[Image.Image], dys: list[int], pad: int) -> list[Image.Image]:
    """칸을 세로로 민다. **틀을 위아래로 pad 만큼 넓혀** 밀린 몫이 안 잘리게 한다.

    ★ pad 는 그 캐릭터의 **클립 전부**에서 하나로 잡아야 한다. 클립마다 다르게 넓히면
      좌표계가 갈라져서, 클립 둘이 나눠 쓰는 공통 상자(`render` 머리말)가 뜻을 잃는다.
    """
    out = []
    for im, dy in zip(sel, dys):
        c = Image.new("RGBA", (im.width, im.height + 2 * pad), (0, 0, 0, 0))
        c.paste(im, (0, pad + dy))
        out.append(c)
    return out


# --------------------------------------------------------------------------
# 품질 검사 — 지침 §5 체크리스트를 잴 수 있는 것만 코드로
# --------------------------------------------------------------------------
def qc(sheet: Image.Image, size: int, n: int, elem: str, loop: bool) -> list[str]:
    bad: list[str] = []
    fr = [sheet.crop((i * size, 0, (i + 1) * size, size)) for i in range(n)]

    cols = {p[:3] for f in fr for p in f.getdata() if p[3] > 0}
    if len(cols) > 20:
        bad.append(f"색 {len(cols)}개 — 20색 넘음")
    allowed = {pixels.hex2rgb(c) for c in pixels.palette_for(elem)}
    stray = cols - allowed
    if stray:
        bad.append(f"팔레트 이탈 {len(stray)}색")

    if any(0 < p[3] < 255 for f in fr for p in f.getdata()):
        bad.append("반투명 픽셀이 남음")
    if any(p[0] > 150 and p[2] > 150 and p[1] < 90 for f in fr for p in f.getdata() if p[3]):
        bad.append("마젠타 잔여물")

    # 발 위치: 알파가 있는 맨 아랫줄이 프레임마다 같아야 한다
    feet = []
    for f in fr:
        b = f.getbbox()
        feet.append(b[3] if b else 0)
    if max(feet) - min(feet) > 2:
        bad.append(f"발 높이가 {max(feet) - min(feet)}px 흔들림")

    # 캐릭터가 틀 밖으로 나가지 않았는가 (카메라가 움직이면 여기 걸린다)
    empt = [i for i, f in enumerate(fr) if not f.getbbox()]
    if empt:
        bad.append(f"빈 프레임 {empt}")

    ratio = min(pixels.outline_ratio(f) for f in fr)
    if ratio < 0.60:
        bad.append(f"검은 테두리가 가장자리의 {ratio:.0%} 뿐 (sprite_design.md §3)")

    if loop:
        # ★★ 「첫 칸과 끝 칸이 닮았는가」로 재면 안 된다 — **왕복 루프**에서는
        #    끝 칸이 첫 칸의 한 칸 옆이라 닮을 리가 없다(그게 정상이다).
        #    루프가 이어진다는 것은 **이음매 걸음이 다른 걸음보다 안 튄다**는 뜻이다.
        steps = [_diff(fr[i], fr[i + 1]) for i in range(len(fr) - 1)]
        wrap = _diff(fr[-1], fr[0])
        mid = sorted(steps)[len(steps) // 2]
        if wrap > mid * 2.2 + 0.012:
            bad.append(f"루프 이음매가 튄다 (이음매 {wrap:.3f} · 보통 걸음 {mid:.3f})")
    return bad


def _union(boxes) -> tuple:
    """상자 여럿을 하나로 — 클립 둘이 **같은 상자**를 나눠 쓴다(`render` 머리말)."""
    bs = list(boxes)
    return (min(b[0] for b in bs), min(b[1] for b in bs),
            max(b[2] for b in bs), max(b[3] for b in bs))


def _cross_feet(sheets: dict, size: int) -> str:
    """클립 **사이**의 발 높이 차. 어긋나면 지적 한 줄, 아니면 빈 문자열.

    ★ `qc()` 의 「발 높이」는 시트 **하나 안에서만** 잰다. 클립마다 프레임을 따로
      고르므로(`select`) idle 과 attack 의 발이 통째로 어긋날 수 있는데, 게임은
      **아이들 0번 칸의 발밑** 하나를 기준점으로 두 클립을 다 그린다 —
      어긋난 만큼 공격할 때 영웅이 가라앉았다 올라온다(CLAUDE.md 18-3).
    """
    per = {}
    ref_sh = sheets.get("idle") or next(iter(sheets.values()))
    ref = pixels.feet_runs(ref_sh.crop((0, 0, size, size)))
    for anim, sh in sheets.items():
        fr = [sh.crop((i * size, 0, (i + 1) * size, size))
              for i in range(sh.width // size)]
        bots = [pixels.feet_line(f, ref) for f in fr]
        per[anim] = (min(bots), max(bots))
    if len(per) < 2:
        return ""
    spread = max(v[1] for v in per.values()) - min(v[0] for v in per.values())
    if spread <= 2:
        return ""
    return ("클립 사이 발 높이가 %dpx 흔들림 (%s)"
            % (spread, " · ".join("%s %d~%d" % (k, v[0], v[1]) for k, v in per.items())))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", default="sdxl")
    ap.add_argument("--only", default="")
    ap.add_argument("--anim", default="")
    #: ★ `wan_i2v.py --tag` 와 **같은 꼬리표**를 준다. 클립도 시트도 같이 갈려야
    #   두 팔을 나란히 놓고 볼 수 있다.
    ap.add_argument("--tag", default="")
    a = ap.parse_args()

    ids = [s for s in a.only.split(",") if s] or U.PILOT
    anims = [s for s in a.anim.split(",") if s] or U.ANIMS
    dst = os.path.join(OUT, a.route, "sheets" + a.tag)
    os.makedirs(dst, exist_ok=True)
    report = []
    for u in U.load(ids):
        # ── 1단계. 그 캐릭터의 클립을 **다 골라 놓고** 상자를 하나로 합친다.
        #    (render 머리말 — 클립마다 제 상자로 자르면 쏠 때마다 사람이 쪼그라든다)
        picked: dict[str, tuple] = {}
        for anim in anims:
            d = os.path.join(OUT, a.route, "clips" + a.tag, f"{u['id']}_{anim}")
            if not os.path.isdir(d):
                print(f"  {u['id']}_{anim}: 클립 없음 — 건너뜀")
                continue
            n = pixels.FRAMES[anim]
            try:
                sel, idx, box = select(d, n=n, loop=anim in pixels.LOOPING,
                                       family=u["family"])
            except KeyedAway as e:
                print(f"!! {u['id']}_{anim}: {e}")
                report.append({"unit": u["id"], "anim": anim, "file": "",
                               "picked": [], "issues": [str(e)]})
                continue
            picked[anim] = (sel, idx, box, n)
        if not picked:
            continue
        shared = _union(v[2] for v in picked.values())

        # ── 1.5단계. **발을 한 줄에 세운다** (foot_shift 머리말).
        #    칸마다 발 높이가 같으면 이동량이 전부 0 이라 여기서 아무 일도 안 일어난다.
        ref = foot_ref(picked, shared, u["size"], u["elem"])
        feet = {an: foot_lines(v[0], shared, u["size"], u["elem"], ref)
                for an, v in picked.items()}
        dys = foot_shift(feet, shared, u["size"])
        pad = max((abs(d) for ds in dys.values() for d in ds), default=0)
        if pad:
            print("  %s 발 맞춤: %s → 원본 %s px 밀었다"
                  % (u["id"],
                     " · ".join("%s %s" % (a, feet[a]) for a in feet),
                     " · ".join("%s %s" % (a, dys[a]) for a in dys)))
            for anim, (sel, idx, _own, n) in picked.items():
                sel = shift_frames(sel, dys[anim], pad)
                picked[anim] = (sel, idx, pixels.union_bbox(sel), n)
            shared = _union(v[2] for v in picked.values())

        # ── 2단계. 같은 상자로 굽는다.
        sheets: dict[str, Image.Image] = {}
        entries: dict[str, dict] = {}
        for anim, (sel, idx, _own, n) in picked.items():
            loop = anim in pixels.LOOPING
            sheet, meta = render(sel, idx, shared, size=u["size"], elem=u["elem"],
                                 loop=loop, n_src=len(sel))
            name = pixels.sheet_name(u["id"], anim, u["size"], n)
            sheet.save(os.path.join(dst, name))
            bad = qc(sheet, u["size"], n, u["elem"], loop)
            sheets[anim] = sheet
            e = {"unit": u["id"], "anim": anim, "file": name,
                 "picked": meta["picked"], "issues": bad}
            entries[anim] = e
            report.append(e)

        # ── 3단계. **클립 사이**의 발 높이도 잰다 (공식 qc 는 시트 하나 안에서만 잰다).
        #    idle 의 발과 attack 의 발이 어긋나면 쏠 때마다 영웅이 가라앉았다 올라온다.
        cross = _cross_feet(sheets, u["size"])
        for anim, e in entries.items():
            if cross:
                e["issues"] = list(e["issues"]) + [cross]
            mark = "OK " if not e["issues"] else "!! "
            print(f"{mark}{e['file']}  칸={e['picked']}")
            for b in e["issues"]:
                print(f"     - {b}")
    json.dump(report, open(os.path.join(dst, "qc.json"), "w"),
              ensure_ascii=False, indent=1)
    nbad = sum(1 for r in report if r["issues"])
    print(f"\n{len(report)}장 중 {nbad}장에 지적 사항")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
