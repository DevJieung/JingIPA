#!/usr/bin/env python3
"""쉰 명 — `tools/roster.json` 을 그대로 읽는다.

설계서 `pokerdefense_world_characters_v2.md` 의 50캐릭(5속성 x 10등급)이 그대로
게임의 로스터라, 이 파이프라인이 도는 대상도 그 쉰 명 전부다.

★ 이 표는 `tools/roster.json` 을 **안 베낀다** — id 로 그때그때 읽는다.
  베끼면 로스터를 고친 날 둘이 조용히 갈라진다.
★★ **자세 무리도 안 베낀다** — `gen_art.pose_family()` 를 **직접 부른다.**
  예전에는 여기에 같은 갈래가 한 벌 더 있었고(이름까지 달라서 `aim` 이 `draw` 였다),
  무기를 하나 늘릴 때마다 두 곳을 고쳐야 했다. 한 곳을 빠뜨리는 날 정지 그림과
  클립이 **다른 자세**가 된다 (CLAUDE.md 4-1-1 이 gen_concepts 에서 배운 것과 같다).
"""

from __future__ import annotations

import json
import os

import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROSTER = os.path.join(ROOT, "tools", "roster.json")
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_art  # noqa: E402  — 자세 무리는 저기 한 곳에서만 정한다


def all_ids() -> list[str]:
    """로스터에 있는 쉰 명 전부. 차례는 등급 낮은 것 → 높은 것."""
    data = json.load(open(ROSTER, encoding="utf-8"))
    return [u["id"] for t in data["tiers"] for u in t["units"]]


#: 기본으로 도는 대상 = **쉰 명 전부**. 몇 명만 볼 때는 도구마다 `--only` 를 준다.
#: ★ 예전에는 여기 시범 다섯이 박혀 있었다. 그 다섯은 지금 로스터에 없다 —
#:   설계서 rev.2 로 캐릭터를 통째로 갈아 끼웠기 때문이다.
PILOT = all_ids()

#: 이 시범에서 뽑을 클립. 영웅은 성역에 서서 쏘기만 하므로 걷지도 죽지도 않는다
#: (walk·hit·death 는 몬스터용 규격이다 — sprite_pipeline.md §1 은 그 둘을 안 가른다).
ANIMS = ["idle", "attack"]


def pose_family(weapon: str, bullet: str) -> str:
    """CLAUDE.md 4-1-1 과 **같은 갈래** — 지어내지 않고 `gen_art` 에 물어본다.

    지금 도는 갈래는 넷이다: `aim`(활·총) · `slash`(검) · `lash`(채찍) · `raise`(광역).
    `cast`·`throw` 는 로스터에 그 무기가 없어서 안 걸리지만 표에는 남겨 둔다 —
    지우면 무기를 하나 되살리는 날 KeyError 로 멈춘다.
    """
    return gen_art.pose_family(weapon, bullet)


#: 무리마다의 공격 동작 한 줄. Wan 에게 "무엇을 하는 중인가"를 말한다.
#: ★ 무리를 흔들면 「활을 등에 진 채 손에서 화살이 나가는」 그림이 다시 나온다
#:   (CLAUDE.md 4-1-1). 그래서 이 표는 자세 무리에만 매여 있고 캐릭터를 안 본다.
ATTACK_ACTION = {
    "aim":   "drawing the weapon up to aim then firing, arms extending forward",
    "slash": "swinging the blade down and across in one clean cut, "
             "weight driving onto the front foot",
    "lash":  "whipping the long chain out low and wide across the frame, "
             "the torso turning with the swing",
    "cast":  "thrusting one arm forward in a casting strike, weight shifting onto the front foot",
    "throw": "pulling one arm back then whipping it forward to throw, torso twisting",
    "raise": "lifting both arms up beside the head, body sinking down first then rising",
}

#: ★★ 픽셀 공격 LoRA(`pix_attack`)의 세기 — **무리마다 다르다.**
#:
#: docs/SPRITE.md 4-3 이 「손잡이가 셋 있다. 아직 안 재 봤다」로 남겨 둔 자리를
#: 실제로 재 본 값이다. 세 팔(1.0 · 0.5 · 0)을 다섯 명에게 다 돌려 나란히 놓고 봤다:
#:
#:   1.0  다섯이 **전부** 흰 초승달 궤적으로 칼을 휘둘렀다. 건틀릿 무사가 언월도를
#:        쥐었고 오브를 든 대해제왕도 칼을 휘둘렀다. LoRA 가 무리를 통째로 덮는다.
#:   0.5  draw·cast·throw 는 **제 동작이 살아났다** — 활잡이가 활을 세워 당기고,
#:        건틀릿 무사가 주먹을 지르며 손등에 타격 섬광이 튀고, 대해제왕은 오브
#:        둘레에 소용돌이가 돈다. 칼과 초승달은 사라졌고 「타격이 있다」는 남았다.
#:   0    동작은 안 틀리는데 **밋밋하다.** 팔만 움직이고 이펙트가 한 톨도 없다.
#:
#: ★★ 그런데 `raise` 만 결이 반대다. 0.5 에서 빙하대공은 지팡이를 **창처럼 내려친다** —
#:   LoRA 가 「손에 든 긴 것」을 무기로 읽기 때문이고, 세기를 반으로 줄여도 그 읽기는
#:   안 없어진다. 0 에서야 지팡이를 세운 채 **두 팔을 올린다.**
#:   그리고 그것이 이 게임에서 맞는 그림이다 — CLAUDE.md 4-1-1 이 `raise` 를
#:   「팔 높이를 절대 안 건드린다. 몸통과 옷자락만 움직인다」로 못 박았고,
#:   발밑에서 머리 위로 지나가는 파동은 클립이 아니라 게임이 그린다(`Fx.rise`,
#:   18-5-2). 장판은 저 멀리 깔리므로 캐릭터가 무엇을 **때리면 안 된다.**
PIX_W = {
    "aim":   0.5,
    # ★★ **검만 1.0 이다 — 여기서는 LoRA 가 틀린 게 아니라 맞다.**
    #   `pix_attack` 은 「melee attack」으로 학습돼 있어 세기를 올리면 **흰 초승달
    #   궤적의 칼질**이 나온다. 활잡이에게는 그것이 거짓말이라 0.5 로 눌렀지만
    #   (아래 표), 검 캐릭터 열 명에게는 그것이 정확히 주문한 그림이다.
    #   설계서 §2 의 「컷(Cut) — 위에서 아래로 베면 벤 궤적이 그대로 날아감」이
    #   곧 그 초승달이다.
    "slash": 1.0,
    # ★ 채찍은 0.5. 1.0 에서 옛 시범(flame_juggler)이 **검은 채찍 궤적**을 냈으니
    #   결이 맞기는 하는데, 같은 세기에서 다른 넷이 칼을 쥐었다 — 채찍 열 명이
    #   전부 칼로 넘어갈 위험이 그만큼 크다. 눈으로 보고 올릴 값이다.
    "lash":  0.5,
    "cast":  0.5,
    "throw": 0.5,
    "raise": 0.0,
}

#: ★★ 손으로 고른 **클립 씨앗**. 여기 없으면 기본값(`wan_i2v --seed`)을 쓴다.
#:
#: 까닭: `PIX_W` 가 칼을 크게 줄이지만 **0 으로 만들지는 못한다.** 같은 세기·같은
#: 프롬프트라도 씨앗이 바뀌면 결과가 바뀐다 — 실측으로 `thunder_fist` 는 씨앗 7 에서
#: 주먹 대신 **보라색 칼날**을 뻗었고, 11 에서는 검은 낫을 휘둘렀고, 23·41 에서야
#: 깨끗한 주먹에 타격 섬광이 났다.
#: 그래서 클립도 정지 그림과 **같은 대우**를 받는다 — 후보를 몇 장 뽑아 눈으로 고른다
#: (`tools/reroll_art.py` 가 정지 그림에 하는 일 · CLAUDE.md 4-4).
#:
#: ★★ **고른 값은 반드시 여기 적어라.** `build/` 는 gitignore 라 클립이 저장소에 안
#:   남는다 — 안 적어 두면 다시 돌리는 순간 기본 씨앗으로 되돌아가서 그 캐릭터가
#:   조용히 칼을 다시 쥔다. (CLAUDE.md 18-5-1 이 리그 점에서 배운 것과 같은 규칙이다)
#: ★ 지금은 비어 있다 — 옛 시범 다섯(thunder_fist …)은 로스터를 갈아 끼우면서
#:   사라진 id 라 그 씨앗도 같이 지웠다. 쉰 명을 굽고 **눈으로 보다가 칼을 쥔
#:   캐릭터가 나오면 그 id 를 여기 적는다.**
SEED: dict[str, int] = {}

IDLE_ACTION = {
    "aim":   "standing at ready with the weapon lowered, chest rising and falling",
    "slash": "standing at ready with the blade lowered, chest rising and falling",
    "lash":  "standing ready with the chain coiled at the side, chest rising and falling",
    "cast":  "standing ready, chest rising and falling, cloth shifting",
    "throw": "standing ready, chest rising and falling, cloth shifting",
    "raise": "standing ready, chest rising and falling, robes shifting",
}


# --------------------------------------------------------------------------
# ★★ SDXL 용 **압축** 몸통 묘사 — CLIP 은 77토큰에서 통째로 자른다.
#
# roster.json 의 prompt 는 Krea2(T5, 긴 문맥)를 보고 쓴 것이라 60토큰이 넘는다.
# 그것을 그대로 SDXL 에 넣었더니 뒤가 다 잘려서 **시점·배경·자세가 통째로 사라졌고**,
# 빙하대공이 얼음 동굴을 배경으로 정면을 보고 섰다(실측: 158토큰 중 81토큰이 잘림).
# 그래서 몸통을 스물몇 낱말로 줄이고, **구도 낱말을 앞에 둔다** — 잘리는 것은 언제나
# 뒤쪽이므로 앞자리가 곧 우선순위다.
#
# ★ 줄일 때 남기는 것은 **실루엣을 정하는 것**뿐이다(sprite_design.md §1 —
#   얼굴이 눈 두 점뿐이라 머리 덩어리와 소품이 이름표다).
# --------------------------------------------------------------------------
SD_BODY: dict[str, str] = {}   # ★ 비었다 — 위 sd_prompt 가 로스터에서 잘라 쓴다

#: 구도 낱말은 **앞**, 화풍 낱말은 뒤. 둘 사이에 몸통이 낀다.
#: ★ 첫 판에서 셋이 틀렸다(실측): 배경이 흰색이 아니라 회색이고, 정면을 보고,
#:   후보 열다섯 중 넷에 **인물이 둘** 섞였다. 배경은 BiRefNet 이 떼므로 말로
#:   싸우지 않고, 프롬프트로는 「인물 하나」와 등신만 잡는다.
#: ★ 「side view」는 뺐다 — PixelArtRedmond 는 정면 RPG 스프라이트로 학습돼 있어
#:   시점을 못 이긴다. 그리고 sprite_design.md §6 이 「캐릭터는 거의 정면 입면」이라
#:   지금 게임의 여든 명과도 그쪽이 맞는다. 좌우 뒤집기는 엔진이 한다.
SD_HEAD = "pixel art sprite, one single character alone, full body, four heads tall, plain white background"
SD_TAIL = "thick black outline, flat shading, two dot eyes, nothing else in frame"


def sd_prompt(u: dict, stance: str) -> str:
    """SDXL 에 넣을 한 줄. 77토큰 안에 들어가는지 부르는 쪽이 잰다.

    ★ `SD_BODY` 에 없으면 로스터의 몸통 묘사를 **앞에서 스물다섯 낱말만** 잘라 쓴다.
      SDXL 경로는 원화 대결에서 졌으므로(docs/SPRITE.md 4-2) 쉰 명분을 손으로 줄여
      둘 값이 없다. 그래도 KeyError 로 멈추면 안 된다 — 비교 팔을 다시 돌려 볼 때
      쓰는 길이기 때문이다.
    """
    body = SD_BODY.get(u["id"])
    if body is None:
        body = " ".join(u["prompt"].replace(",", " ").split()[:25])
    return f"{SD_HEAD}, {body}, {stance}, {SD_TAIL}"


def load(ids: list[str] | None = None) -> list[dict]:
    """roster.json 에서 그 id 들을 읽어 자세 무리와 등급을 붙여 돌려준다."""
    ids = ids or PILOT
    data = json.load(open(ROSTER, encoding="utf-8"))
    by_id: dict[str, dict] = {}
    for ti, t in enumerate(data["tiers"]):
        for u in t["units"]:
            u = dict(u)
            u["tier"] = t["tier"]
            u["tier_ko"] = t["ko"]
            u["tier_i"] = ti
            by_id[u["id"]] = u
    out = []
    for i in ids:
        if i not in by_id:
            raise SystemExit(f"로스터에 없는 id: {i}")
        u = by_id[i]
        u["family"] = pose_family(u["weapon"], u["bullet"])
        u["size"] = 96              # 영웅은 전부 96x96 (sprite_pipeline.md §1)
        out.append(u)
    return out


if __name__ == "__main__":
    for u in load():
        print("%-16s %-14s %-6s %-6s %-9s %-8s %s"
              % (u["id"], u["en"], u["elem"], u["family"], u["weapon"],
                 u["tier"], u["ko"]))
