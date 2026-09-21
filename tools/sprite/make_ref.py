#!/usr/bin/env python3
"""Step 1 — 마스터 원화(96x96 도트) 와 Wan 입력(512 마젠타) 을 만든다.

`sprite_pipeline.md` §3 Step 1 이 시킨 것:
  「64x64 픽셀 캐릭터를 만든 뒤 **nearest 로 512 업스케일** 해서 넣는다.
    배경은 단색 마젠타. 캐릭터가 캔버스 가운데, 여백 15% 이상.」

경로가 둘이다(사용자가 「둘 다 뽑아 비교」로 정한 것):

  --route sdxl    pixelforge(SDXL + PixelArtRedmond) → 격자 스냅
                  ★ **진짜 픽셀 그리드**가 나온다. Wan 픽셀 LoRA 가 전제하는 입력 모양이다.
  --route krea    Krea2 Turbo(지금 게임의 앵커 그대로) → 여기서 격자로 눌러 앉힌다
                  ★ 지금 게임의 여든 명과 **같은 사람**으로 보인다. 대신 부드러운
                    일러스트를 억지로 도트화하는 것이라 결이 덜 깨끗하다.

두 경로가 **같은 정제 함수**(`refine`)로 들어온다 — 팔레트와 격자가 갈리면 비교가
비교가 아니게 된다.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import pixels                                    # noqa: E402
import units as U                                # noqa: E402

OUT = os.path.join(ROOT, "build", "sprite")
PIXELFORGE = "/home/dgxmaruta/pjt/pixelforge"

#: 물 붓기(`gen_art.cut_white`)가 이보다 적게 남기면 **캐릭터까지 먹은 것**으로 보고
#: BiRefNet 으로 다시 뗀다. 실측으로 멀쩡한 그림은 0.30~0.60 이 남고, 먹힌 넷은
#: 0.02~0.10 이었다. 문턱을 0.05 로 두면(옛 경고선) 0.10 짜리를 못 잡는다.
CUT_MIN = 0.18

# 자세 무리마다의 **정지 자세** 한 줄. 마스터는 언제나 「쏘기 전」이다 —
# 여기서 이미 팔을 뻗어 두면 Wan 이 그 자세에서 또 뻗어서 동작이 두 번 일어난다.
#: SDXL 용 **짧은** 자세. 77토큰 안에서 몸통과 자리를 나눠 써야 한다.
#: ★ 열쇠는 `gen_art.pose_family()` 가 내는 이름이다 — aim · slash · lash · raise
#:   (+ 안 쓰이는 cast · throw). 예전 이름 `draw` 는 units.py 가 따로 갖고 있던
#:   갈래였고, 그 갈래를 지우면서 같이 없어졌다.
SD_STANCE = {
    "aim":   "weapon held low",
    "slash": "blade held low",
    "lash":  "chain coiled at the side",
    "cast":  "one arm at the side",
    "throw": "weapon at the hip",
    "raise": "hands open at the sides",
}

STANCE = {
    "aim":   "standing side view facing right, holding the weapon low in one hand, ready stance",
    "slash": "standing side view facing right, holding the blade lowered in one hand, ready stance",
    "lash":  "standing side view facing right, the long chain coiled loosely at the side, ready stance",
    "cast":  "standing side view facing right, one arm relaxed at the side, ready stance",
    "throw": "standing side view facing right, holding the throwing weapon at the hip, ready stance",
    # ★ 광역은 손에 든 것이 「패 전체」라 지팡이를 세우게 하면 안 된다
    #   (설계서 §2 — 올인). 두 손을 비워 두고 카드가 그 자리를 채운다.
    "raise": "standing side view facing right, both hands open at the sides, ready stance",
}


def _clip_tokens(text: str) -> int:
    """CLIP BPE 로 실제 토큰 수. 넘치면 **조용히** 뒤가 잘리므로 미리 잰다."""
    from transformers import CLIPTokenizer
    global _TOK
    try:
        tok = _TOK
    except NameError:
        tok = _TOK = CLIPTokenizer.from_pretrained("openai/clip-vit-large-patch14")
    return len(tok(text)["input_ids"])


# --------------------------------------------------------------------------
# 공통 정제 — 두 경로가 여기로 모인다
# --------------------------------------------------------------------------
def refine(img: Image.Image, size: int, elem: str, gen: int = 0) -> Image.Image:
    """무엇으로 뽑았든 **96x96 도트 · 17색 · 알파 이진**으로 눌러 앉힌다.

    ★ 줄이는 일은 pixelforge 의 정제기(`pixelforge.core.pipeline.refine`)에 맡긴다.
      직접 `Image.BOX` 로 줄여 봤는데, 8배를 평균 내면 1도트 검은 테두리가 옆 색과
      섞여 **테두리가 회색 띠**가 된다 — sprite_design.md §3 이 「실루엣의 절반」이라
      부른 바로 그것이 뭉개진다. pixelforge 는 칸마다 **가장 넓은 색**을 고르고
      (dominant), 격자 위상까지 맞춰 준다. 순수 파이썬이라 GPU 도 안 쓴다.
    """
    import numpy as np
    sys.path.insert(0, PIXELFORGE)
    from pixelforge.core.palette import Palette
    from pixelforge.core.pipeline import RefineOptions, refine as pf_refine

    img = img.convert("RGBA")
    # ★★ 줄이기 **전에** 밝기를 올린다 (`pixels.LIFT_GAMMA` 머리말). 뒤로 옮기면
    #   `add_outline` 이 두른 검은 테두리까지 같이 떠서 실루엣이 회색이 된다.
    img = pixels.lift(img)
    # ★ 정사각으로 **키워** 맞춘다. 그리고 그 변은 반드시 size 의 정수배다 —
    #   정제기는 gen_size 를 target 으로 나눈 정수 배율로 칸을 세는데, 안 나누어
    #   떨어지면 target 을 88 같은 이상한 값으로 떨궈야 하고 그러면 격자 위상이
    #   틀어진다. 키우는 것은 투명한 여백이라 그림에 아무 일도 안 한다.
    side = max(gen or 0, img.width, img.height)
    gen = -(-side // size) * size
    sq = Image.new("RGBA", (gen, gen), (0, 0, 0, 0))
    sq.paste(img, ((gen - img.width) // 2, (gen - img.height) // 2))

    pal = Palette.from_hex(pixels.palette_for(elem), name="pocker-" + elem)
    opts = RefineOptions(target_w=size, target_h=size, gen_size=gen,
                         max_colors=len(pal.colors), method="dominant",
                         palette=pal, dither="none", alpha_thr=128)
    res = pf_refine(np.asarray(sq), opts)
    small = Image.fromarray(res.image if hasattr(res, "image") else res.rgba)
    # ★ 테두리는 **줄인 뒤에** 두른다 (pixels.add_outline 머리말). 줄이기 전에
    #   두르면 8배로 줄면서 그 한 겹이 평균에 섞여 다시 사라진다.
    small = pixels.add_outline(small)
    box = small.getbbox()
    if box:
        small = small.crop(box)
    return pixels.fit_bottom(small, size)


def to_wan_input(master: Image.Image, canvas: int = 512) -> Image.Image:
    """마스터를 Wan 입력으로 — **정수 배율** nearest 업스케일 + 마젠타 배경.

    ★ 배율이 정수가 아니면 픽셀 격자가 그 자리에서 깨진다. 그러면 Wan 픽셀 LoRA 가
      「픽셀아트」로 못 읽고, 정제 단계가 되살릴 격자도 없어진다.
    ★ 여백 15% 는 sprite_pipeline.md Step 1 이 못 박은 것이다. 좁으면 팔을 뻗는
      순간 캐릭터가 틀 밖으로 나가고, 그 프레임은 통째로 못 쓴다.
    """
    box = master.getbbox() or (0, 0, master.width, master.height)
    bw, bh = box[2] - box[0], box[3] - box[1]
    # ★ 배율이 정수라 「여백 15%」를 글자 그대로 지키면 한 칸 손해를 본다:
    #   90px 짜리 캐릭터에 0.70(=358px)을 주면 배율이 3배로 떨어져 화면의 53%만
    #   차고, 0.74(=379px)면 4배가 들어가 70%를 채운다(여백 14.8%). 뒤쪽이
    #   Wan 에게 **가로세로 3분의 1 더 큰** 그림을 주면서 여백은 사실상 같다.
    room = int(canvas * 0.74)
    scale = max(1, min(room // max(1, bw), room // max(1, bh)))
    art = master.crop(box).resize((bw * scale, bh * scale), Image.NEAREST)
    out = Image.new("RGBA", (canvas, canvas), pixels.CHROMA + (255,))
    out.paste(art, ((canvas - art.width) // 2, (canvas - art.height) // 2), art)
    return out.convert("RGB")


# --------------------------------------------------------------------------
# 경로 A — Krea2 (지금 게임의 앵커)
# --------------------------------------------------------------------------
def run_krea(us: list[dict], force: bool) -> None:
    import gen_art                                # 앵커·속성색·배경빼기를 그대로 쓴다
    from krea2.pipelines.image import Krea2ImagePipeline

    todo = [u for u in us
            if force or not os.path.exists(os.path.join(OUT, "krea", "raw", u["id"] + ".png"))]
    if not todo:
        print("[krea] 할 것 없음")
        return
    os.makedirs(os.path.join(OUT, "krea", "raw"), exist_ok=True)
    # ★ Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 — 올리기 전에 문지기를 부른다 (tools/gpu_guard.py)
    import gpu_guard
    gpu_guard.claim("krea2")
    print(f"[krea] 모델 올리는 중 (3~4분) — {len(todo)}장")
    pipe = Krea2ImagePipeline("turbo").load()
    for u in todo:
        body = u["prompt"].rstrip(". ")
        elem = gen_art.ELEM_LOOK[u["elem"]]
        # ★ 속성 색은 **몸통 묘사 바로 뒤**다 (CLAUDE.md 4-4-0-1). 앵커 안에 넣으면
        #   옷 묘사에 밀려서 안 나온다.
        prompt = (f"{gen_art.DOT}. {body}, {elem}. "
                  f"{STANCE[u['family']]}, full body from head to feet, "
                  f"only one creature, plain solid white background")
        seed = gen_art._seed(u["id"])
        print(f"  {u['id']:16s} seed={seed}")
        res = pipe.generate(prompt, width=1024, height=1024, seed=seed)[0]
        # ★ generate 는 PIL 이 아니라 ImageResult 를 준다 (gen_art.main 도 .image 를 쓴다)
        img, kept, trapped = gen_art.cut_white(res.image, holes=bool(u.get("holes")))
        if kept > 0.85:
            print(f"    ! 배경이 거의 안 지워졌다 (남은 {kept:.0%}) — 흰 배경이 아니다")
        if trapped > 0.0:
            print(f"    · 갇힌 배경 {trapped:.1%} — 눈으로 봐라 (CLAUDE.md 4-3)")
        # ★★ **물이 캐릭터까지 먹었으면 BiRefNet 으로 다시 뗀다.**
        #   `cut_white` 는 모서리에서 부은 물이 **밝고 채도 낮은 곳**을 지운다. 그래서
        #   흰 외투·은빛 갑주를 입은 캐릭터가 통째로 사라진다 — 실측으로 쉰 명 중
        #   넷(helga·igni·grey·protea)이 카드 몇 장만 남았다.
        #   ☆ 게임 일러스트는 멀쩡한데 스프라이트만 먹힌 것이 요점이다: 같은 시드라도
        #     자세가 다르면(여기는 「쏘기 전」 대기 자세) 다른 그림이 나오고, 밝기가
        #     문턱을 넘는 순간 물이 옷 안까지 들어간다.
        #   ☆ BiRefNet 은 **무엇이 배경인지를 뜻으로** 가르므로 밝기를 안 본다
        #     (docs/SPRITE.md 1-4). 늘 쓰지 않고 **되돌림 길**로만 두는 까닭은
        #     pixelforge 의 venv 를 따로 띄워야 해서 느리기 때문이다.
        if kept < CUT_MIN:
            print(f"    ! 그림이 거의 지워졌다 (남은 {kept:.0%}) — BiRefNet 으로 다시 뗀다")
            import cutbg
            tmp_in = os.path.join(OUT, "krea", "raw", u["id"] + "_full.png")
            tmp_out = os.path.join(OUT, "krea", "raw", u["id"] + "_cut.png")
            res.image.convert("RGB").save(tmp_in)
            try:
                cutbg.cut([(tmp_in, tmp_out)])
                img = Image.open(tmp_out).convert("RGBA")
            except Exception as e:                       # noqa: BLE001
                print(f"    ! BiRefNet 도 실패했다: {e} — 물 부은 결과를 그대로 쓴다")
            for f in (tmp_in, tmp_out):
                if os.path.exists(f):
                    os.remove(f)
        img = gen_art.tight_crop(img)
        img.save(os.path.join(OUT, "krea", "raw", u["id"] + ".png"))


# --------------------------------------------------------------------------
# 경로 B — pixelforge (SDXL + PixelArtRedmond)
# --------------------------------------------------------------------------
def run_sdxl(us: list[dict], force: bool, tries: int) -> None:
    raw = os.path.join(OUT, "sdxl", "raw")
    os.makedirs(raw, exist_ok=True)
    py = os.path.join(PIXELFORGE, ".venv", "bin", "python")
    for u in us:
        dst = os.path.join(raw, u["id"] + ".png")
        if os.path.exists(dst) and not force:
            print(f"[sdxl] {u['id']} 있음 — 건너뜀")
            continue
        # ★ --raw-prompt 로 **77토큰 전부를 이쪽이 쥔다.** pixelforge 의 기본 템플릿은
        #   구도 낱말을 뒤에 붙이는데, CLIP 이 뒤부터 자르므로 그 자리가 제일 먼저 날아간다.
        prompt = U.sd_prompt(u, SD_STANCE[u["family"]])
        n_tok = _clip_tokens(prompt)
        if n_tok > 77:
            raise SystemExit(f"{u['id']}: {n_tok}토큰 — 77 을 넘으면 뒤가 잘린다. SD_BODY 를 줄여라")
        cmd = [py, "-m", "pixelforge", "ref", "-p", "pocker",
               "--name", u["id"], "--prompt", prompt, "--raw-prompt",
               "--num", str(tries)]
        print(f"[sdxl] {u['id']:16s} {n_tok}토큰")
        subprocess.run(cmd, cwd=PIXELFORGE, check=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--route", choices=("krea", "sdxl", "both"), default="both")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--tries", type=int, default=1, help="sdxl 후보 장수")
    ap.add_argument("--only", default="", help="쉼표로 id 몇 개만")
    a = ap.parse_args()

    ids = [s for s in a.only.split(",") if s] or U.PILOT
    us = U.load(ids)
    if a.route in ("krea", "both"):
        run_krea(us, a.force)
    if a.route in ("sdxl", "both"):
        run_sdxl(us, a.force, a.tries)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
