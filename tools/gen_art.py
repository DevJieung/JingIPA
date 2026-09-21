#!/usr/bin/env python3
"""올인 디펜스 — 도트 그림을 로컬 Krea 2 Turbo 로 만든다.

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
#
# ★ **화풍은 여기 한 곳에만 있다.** roster.json / concepts.json 의 prompt 는 몸통 묘사만
#   적는다. 거기에 화풍을 또 적으면 나중에 화풍을 통째로 바꿀 때 그 캐릭터만 따로 논다.
#
# ★ 앵커에 못 박은 넷. 여든 명을 한 판에 세우는 게임이라, 이것들이 없으면 같은 한 줄로
#   뽑아도 어떤 것은 데포르메로 어떤 것은 실사로 나와서 다른 게임에서 온 것처럼 보인다.
#     1. **등신 비율** — 4등신으로 압축한 어른 몸.
#     2. **광원 방향** — 왼쪽 위에서 온다. 이게 없으면 그림자가 서로 반대로 진다.
#     3. **외곽선 두께** — 한 픽셀짜리 짙은 테두리. 오려내기(cut_white)의 벽 노릇도 한다.
#     4. **얼굴** — 눈 두 점. 96px 에서 이목구비를 그리면 반드시 뭉갠다.
#   ★ 여기에 **캐릭터 고유색**은 못 박지 않는다. 색은 캐릭터마다 다르고(roster 의 color 가
#     곧 탄알 색이다), 앵커에 적으면 여든 명이 같은 옷을 입는다. 앵커가 정하는 것은
#     **속성 색 한 줄**(ELEM_LOOK)뿐이고, 그것은 캐릭터마다가 아니라 속성마다다.
# --------------------------------------------------------------------------- #
# ★★ **어두운 화풍을 버렸다** (사용자가 정한 것: 「일단 어두운 화풍 자체를 버려주고
#    지침에도 적용부탁 … 지침에도 속성컨셉이 잘 들어가게 부탁」).
#
#    예전 앵커는 `chardesign.md` 의 실측을 그대로 옮긴 것이었다 —
#      `dark muted low-key colors` · `nothing brighter than 70 percent gray` ·
#      `no white, no glow` · `desaturated cloth`
#    그리고 그 넷이 실제로 먹었다. 여든 장을 재 보면 **밝기 중앙값 0.10~0.15 ·
#    채도 중앙값 0.11~0.27** 이고, V>0.70 인 픽셀이 1% 안팎이다. 기준서가 시킨 그대로다.
#
#    문제는 그것이 **이 게임의 화면에서는 안 통한다**는 것이다. 까닭이 셋이다:
#      1. `Design.jpg` 는 79x91 도트짜리 한 화면이고 캐릭터가 16x34 도트다. 이 게임의
#         영웅은 96~141px 라 넉 배 크다. 34도트에서 「검정 3분의 1」은 실루엣이지만
#         **141px 에서는 그냥 검은 판때기**다 — 그릴 면이 넉 배 넓은데 그 면을 다 비운 것이다.
#      2. 이 게임은 **속성이 규칙의 전부**다(CLAUDE.md 2-2). 그런데 옷이 전부 탁한
#         회갈색이면 전기 영웅과 물 영웅이 화면에서 **같은 사람**이다. 속성을 아이콘으로
#         따로 적어 주고 있다는 것(10-12-2)이 곧 그림이 그 일을 못 하고 있었다는 뜻이다.
#      3. 몬스터도 같은 앵커로 뽑히므로 **투기장이 통째로 어두워진다.** 어두운 배경 위에
#         어두운 몬스터가 걷고 어두운 영웅이 쏘면, 밝은 것은 이펙트뿐이라 이펙트가
#         화면을 통째로 먹는다.
#
#    그래서 색 규칙을 **뒤집었다**. 남긴 것은 어둠이 아니라 **또렷함**이다:
#      검은 테두리(§3-1) · 재질당 3톤(§2-1) · 눈 두 점(§5) · 4등신(§1).
#    이 넷은 크기와 무관해서 96px 에도 그대로 걸리고, 「도트 그림」을 만드는 것이
#    사실 이 넷이다. 어둠은 아니었다.
#
# ★★ **다만 `no pure white` 한 줄은 화풍이 아니라 기술 규칙이라 남는다.**
#    `cut_white` 가 모서리에서 물을 부어 **밝고 채도 낮은 곳**(sat<=22 · val>=205)을
#    배경으로 지운다. 캐릭터에 순백이 있으면 그 물이 옷 안까지 새어 들어가 캐릭터를
#    통째로 지운다 — 실제로 밝은 회색 옷을 입은 거인 하나가 빈 그림이 됐고, 그래서
#    `kept < 0.05` 되돌림 길이 있는 것이다. 「흰색 바로 아래에서 멈춘다」로 적으면
#    밝기는 다 쓰면서 그 사고만 막는다.
#
# ★★ **이 모델은 negative prompt 가 안 먹는다.** turbo 는 CFG 증류라 guidance 가 0 이고,
#    krea2 가 negative_prompt 를 **조용히 버린다**(pipelines/image.py). 그래서 「밝게」도
#    부정문이 아니라 **긍정문으로만** 걸 수 있고, 그마저도 몸통 묘사를 못 이긴다
#    (CLAUDE.md 4-4). 앵커만 뒤집고 `roster.json` 을 그대로 두면 그림은 **안 바뀐다** —
#    백다섯 줄에 `dull` 77번 · `dark` 206번 · `tarnished` 33번이 박혀 있었기 때문이다.
#    그래서 앵커와 프롬프트를 **같이** 갈아엎었다.
DOT = ("16-bit pixel art sprite, retro SNES tactical japanese role playing game character "
       "sprite, crisp clean pixels, limited palette, thick black outline, "
       "strong readable silhouette, flat cel shading, no dithering on the character, "
       # ↓ 색 규칙 — 여기가 뒤집힌 자리다. 어둠이 아니라 또렷함으로 읽히게 한다.
       "rich saturated colors, bold confident lighting, "
       "strong value contrast with a clearly lit side and a deep shadow side, "
       "three tones per material, bright crisp highlights, "
       "the costume base colours sit in the mid range, "
       "deep shadow only in the creases, never a black silhouette, "
       # ↓ 기술 규칙 (화풍이 아니다) — cut_white 가 캐릭터를 지우지 않게 하는 벽
       "no pure white anywhere, the brightest highlight stops one step below white, "
       # ↓ 실루엣 — 얼굴이 눈 두 점뿐이라 머리 덩어리가 곧 이름표다
       "a large distinct hair or headgear mass reading as the silhouette, "
       "four-head-tall compressed adult proportions, narrow shoulders, short legs, "
       "tiny face with only two dark dots for eyes, no mouth, no fingers, "
       # ↓ 화풍을 통일하려고 못 박은 둘
       "single light source from the upper left with shadow falling to the lower right, "
       "uniform one pixel dark outline around every shape, "
       "no photorealism, no 3d render, no anime screenshot, no soft airbrush gradients")

# --------------------------------------------------------------------------- #
# ★★ **속성 색 — 그림이 규칙을 말하게 하는 한 줄** (사용자가 정한 것:
#    「각자 속성에 맞게 예를 들어 전기속성이면 누리끼리한 느낌으로」).
#
#    이 게임의 규칙은 상성이다(CLAUDE.md 2-2). 그런데 여든 명이 전부 탁한 회갈색 옷을
#    입고 있으면, 플레이어는 **화면을 보고는 속성을 영영 못 배운다** — 성역에 여섯이
#    서 있어도 누가 전기고 누가 물인지 그림에 없다. 그래서 아이콘을 따로 붙여야 했고
#    (10-12-2), 그 아이콘은 지름 13~22px 이다.
#
# ★ **탄알·이펙트 램프와 같은 길을 탄다.** `gen_concepts.ELEM_FX` 의 램프가 곧 이
#   색이다 — 전기는 노랑에서 보라로, 물은 청록에서 파랑으로. 옷과 이펙트가 다른 색이면
#   「저 노란 번개를 쏜 게 저 파란 옷 입은 사람인가」를 매번 다시 맞춰 봐야 한다.
# ★ **무상성(none)에는 속성 색을 주지 마라.** 놋쇠·가죽·무쇠다. 무상성은 「어떤 몸에도
#   1.0배인 안전한 줄」이라(5-2), 색까지 주면 다섯 번째 속성처럼 보인다.
# ★ **넓은 면이 아니라 두세 군데**에 준다. 열여섯이 같은 속성이라 옷을 통째로 물들이면
#   전기 열여섯이 같은 사람이 된다 — chardesign §2 의 「채도는 면적과 반비례」가
#   어둠을 버린 뒤에도 그대로 산다.
# --------------------------------------------------------------------------- #
ELEM_LOOK = {
    "elec":  ("a vivid acid-yellow sash with bright gold trim at the cuffs and hem, "
              "deep violet shadows, small amber sparks around the hands"),
    "fire":  ("a hot ember-orange sash with bright scarlet trim at the cuffs and hem, "
              "deep crimson shadows, small glowing coals around the hands"),
    "ice":   ("a pale ice-cyan sash with frost-white trim at the cuffs and hem, "
              "deep navy shadows, small crystalline glints around the hands"),
    "water": ("a bright turquoise sash with deep teal trim at the cuffs and hem, "
              "indigo shadows, small clear droplets around the hands"),
    "none":  ("a warm brass-buckled leather belt with blued steel fittings, "
              "no magical colour anywhere on the costume"),
}

# 몬스터의 **몸**은 다섯이고 공격 속성과 다른 표다(CLAUDE.md 5-0). 나무·바위가 여기만 있다.
BODY_LOOK = {
    "aqua":  "deep teal and turquoise body with bright water highlights",
    "flame": "ember orange and scarlet body with hot yellow highlights",
    "wood":  "moss green and bark brown body with fresh leaf-green highlights",
    "rock":  "warm ochre and slate body with pale sandstone highlights",
    "frost": "pale cyan and ice white body with deep navy shadows",
}

CUTOUT = (", full body from head to feet inside the frame, centered, "
          "cut out on a pure flat white background, no ground, no shadow, no scenery, "
          "no base, no stand, no text, no watermark, no grid, no border, no frame")

ONE = "a single character, only one creature in the picture, nothing else, "

# ★ **이펙트 그림은 사람 앵커를 쓰면 안 된다.** ONE 의 「only one creature」와 CUTOUT 의
#   「full body from head to feet」는 몸통 묘사를 이기는 말이라(CLAUDE.md 4-4), 불꽃 한 줄기를
#   주문하면 **불을 든 사람**이 나온다. 얼음 바닥 고리처럼 「서 있지 않은 것」은 더 나쁘다.
#   그래서 이펙트(roster.json 의 "fx": true)는 앵커 두 줄을 갈아 끼운다.
FX_ONE = "a single game effect sprite, one effect only, nothing else in the picture, "

FX_CUTOUT = (", the effect alone fills the frame, "
             "cut out on a pure flat white background, no ground, no shadow, no scenery, "
             "no character, no creature, no person, no hands, no base, no stand, "
             "no text, no watermark, no grid, no border, no frame")

# ★ **정지 그림이 곧 애니메이션의 마스터이자 0번 칸이다** (docs/ART.md 8·「세 번째 캐릭터」).
#   그래서 자세를 여기서 하나로 못 박지 않고 **캐릭터마다** 적는다(roster.json 의 pose):
#   마법사는 「한쪽 팔을 앞으로 뻗어 시전」, 활·총은 「소품을 앞으로 내밀고 겨눔」이다.
#   ★ 예전에는 여기 「자신 있게 선 3/4 정면」 한 줄이 박혀 있었다. 그러면 정지 그림과
#     애니메이션 마스터가 **다른 자세**가 되어, 그림을 두 벌 뽑아야 하고(GPU 가 두 배다)
#     전투 화면과 편성 판이 **다른 사람**으로 보인다.
UNIT_POSE = ", standing in a confident front three-quarter view"

# --------------------------------------------------------------------------- #
# ★ **자세는 무기가 정한다 — 손으로 적지 마라.**
#
#   사용자가 정한 것: 「애니메이션스프라이트를 만들때는 활/총/단일 shot마법/광역 마법
#   임을 고려하고」. 자세는 곧 애니메이션의 마스터 자세라(docs/ART.md 0-1), 무기와
#   자세가 어긋나면 클립이 통째로 어긋난다 — 활을 등에 진 채 손에서 화살이 나가는
#   그림이 실제로 아홉 장 나왔었다.
#
#   그래서 `roster.json` 에는 **`weapon` 만** 적고 자세는 여기서 뽑는다. 표가 한 곳에
#   있으면 「활 캐릭터 여섯이 저마다 다른 자세로 뽑히는」 일이 생길 수가 없다.
#
#   ★ **광역 마법(zone)은 무기와 상관없이 두 팔을 든다.** 사용자가 정한 연출이
#     「두 팔을 들어올림과 동시에 발밑에서 머리위로 이펙트가 지나가고」이기 때문이다.
#     그래서 이 갈래가 무기보다 **먼저** 걸린다.
# --------------------------------------------------------------------------- #
AIM_NOUN = {"bow": "bow", "crossbow": "crossbow", "gun": "gun",
            "cannon": "hand cannon"}

# --------------------------------------------------------------------------- #
# ★★ **자세는 「무리」와 「결」 두 층이다** (사용자가 정한 것: 「모션도 좀 너무
#    일관적인데 다양하게 나올 수 있도록」).
#
#    예전에는 자세가 **넉 줄뿐**이었다 — 여든 명이 aim 21 · cast 36 · throw 7 · raise 16
#    으로 나뉘어, 서른여섯 명이 **글자 한 자 안 다른 같은 자세**로 서 있었다. 성역에
#    여섯이 서면 그중 셋이 똑같은 팔을 뻗고 있었다.
#
#    그렇다고 자세를 통째로 자유롭게 두면 안 된다. **팔의 역학은 무리가 정한다** —
#      · `autorig.py` 가 어깨와 손끝을 찾는 신호가 그 무리에 맞춰져 있고(18-5-1),
#      · `mkanim.MOTIONS` 가 그 팔을 어떻게 돌릴지를 무리별로 갖고 있으며,
#      · `muzzle`(탄이 소품에서 나가는가 손에서 나가는가)이 무리에서 나온다.
#    무리가 흔들리면 「활을 등에 진 채 손에서 화살이 나가는」 그림이 다시 나온다.
#
#    그래서 **무리는 무기·방식이 정하고(넷), 결은 id 가 정한다(무리마다 넷)**.
#    결이 바꾸는 것은 **서 있는 품새·몸통 비틀기·시선**뿐이고 팔은 안 건드린다.
#
# ★ **앉거나 웅크리는 결은 넣지 마라.** 그림 높이는 등급마다 같게 맞추는데(unit_h)
#   그 높이는 **테두리 상자**의 높이다. 한 명만 무릎을 꿇으면 같은 상자 안에서 몸이
#   커져서, 나란히 섰을 때 혼자 거인이 된다. `sc` 로 되돌릴 수는 있지만 그것은
#   사람이 사진을 보고 정하는 값이라 여든 명에 못 쓴다.
# --------------------------------------------------------------------------- #
AIM_POSE = ", in a three-quarter side view, aiming the %s across the frame, both arms out in front"
AIM_FLAV = (
    ", standing tall with the feet planted wide and the shoulders square",
    ", weight shifted onto the front foot and the torso leaning into the shot",
    ", weight settled back on the rear leg, the head tucked down behind the weapon",
    ", the body turned side-on and narrow, the trailing arm braced hard",
    ", one knee driven forward and the shoulders rolled over the weapon",
    ", standing square to the front with the chin raised over the sight line",
)

THROW_POSE = (", in a three-quarter side view, one arm drawn back beside the head "
              "about to hurl it across the frame, the other arm out for balance")
THROW_FLAV = (
    ", the torso twisted hard away from the throw and the rear heel lifting",
    ", the front foot stamped forward and the coat swinging out behind",
    ", the shoulders coiled low and the chin dropped",
    ", rising up onto the toes with the free hand flung wide",
    ", the front knee bent deep and the shoulders squared to the throw",
    ", the body leaning back with the throwing elbow high",
)

CAST_POSE = ", standing in a three-quarter view, one arm thrust forward casting"
CAST_FLAV = (
    ", the feet planted wide and the free hand clenched at the hip",
    ", lunging onto the front foot with the robe flaring out behind",
    ", the free hand raised near the chest and the head bowed over it",
    ", the shoulders turned away and the face looking back along the outstretched arm",
    ", the rear foot dragged back and the free arm swept behind",
    ", standing tall and square with both feet together",
)

# ★ 광역 마법. **두 팔을 든다.** 손에서 탄이 안 나가므로 겨누는 자세면 안 된다.
#
# ★★ **팔을 곧게 위로 뻗게 하지 마라 — 한 번 그렇게 했다가 그림이 망가졌다.**
#   「both arms raised high straight above the head」로 뽑았더니 실제로 이렇게 나왔다:
#   팔이 틀 위로 빠져나가 **검은 막대 두 개**가 되고, 그림 높이를 등급마다 같게 맞추는
#   탓에(unit_h) 사람 몸이 통째로 쪼그라들었으며, 머리는 형체 없는 검은 덩어리가 되어
#   **얼굴이 사라졌다.** 이 화풍은 얼굴이 눈 두 점뿐이라 머리 모양이 곧 이름표인데,
#   그 이름표가 없어진 것이다.
#   그래서 **팔꿈치를 굽혀 손을 머리 옆에** 둔다. 「두 팔을 들어올림」은 그대로 읽히면서
#   머리·얼굴·몸통이 다 남고, autorig 가 찾아야 할 팔도 틀 안에 있다.
#   ★ 그러니 raise 의 결은 **팔 높이를 절대 안 건드린다** — 몸통과 옷자락만 움직인다.
RAISE_POSE = (", standing in a three-quarter front view, both forearms lifted up beside "
              "the head with the elbows bent and the palms turned upward, "
              "the head and face clearly visible between the raised hands")
RAISE_FLAV = (
    ", the feet planted wide and the cloak hanging straight",
    ", the back arched and the chin lifted, the cloak billowing out behind",
    ", one foot stepped forward and the body leaning into it",
    ", the shoulders rolled up and the head lifted between them",
    ", the feet close together and the whole body drawn tall and straight",
    ", the hips turned to one side while the face stays to the front",
)

# ★ 검 — 「컷(Cut)」. 덱을 자르는 손동작에서 나온 무기라, 벤 궤적이 그대로 날아간다.
#
# ★ **날을 머리 위로 치켜들게 하지 마라.** raise 에서 배운 것과 같은 함정이다
#   (팔이 틀 밖으로 나가고 그림 높이를 맞추느라 몸이 쪼그라든다). 그래서 날은
#   **어깨 높이에서 가슴을 가로질러** 당겨 두고, 베는 방향만 아래로 적는다.
SLASH_POSE = (", in a three-quarter side view, the blade drawn back across the chest at "
              "shoulder height and about to cut down and across the frame, "
              "the free hand open in front for balance")
SLASH_FLAV = (
    ", the feet set wide and the shoulders square over them",
    ", lunging onto the front foot with the coat flaring out behind",
    ", the torso coiled away from the cut and the chin tucked down",
    ", rising up onto the front toe with the trailing arm flung back",
    ", the rear heel lifted and the free hand thrown out to the side",
    ", settled back on the rear leg with the head turned along the blade",
)

# ★ 채찍 — 「리플 셔플(Riffle)」. 카드 수십 장이 사슬처럼 이어진 띠다.
#
# ★ **호를 낮고 넓게** 그리게 한다. 위로 크게 올리면 테두리 상자가 세로로 커지는데,
#   그림 높이는 등급마다 같게 맞추므로(unit_h) 그만큼 **사람 몸이 작아진다.**
#   가로로 넓어지는 것은 높이로 맞추는 이 파이프라인에서 아무 해가 없다.
LASH_POSE = (", in a three-quarter side view, the whip arm sweeping out low and wide "
             "across the frame with the long chain trailing behind in a flat arc, "
             "the other arm out for balance")
LASH_FLAV = (
    ", the feet planted wide and the hips turned into the swing",
    ", stepping forward onto the front foot with the hem swinging out",
    ", the shoulders dropped low and the head following the arc",
    ", the body turned side-on and the trailing hand raised near the chest",
    ", the weight rolled onto the back foot and the chin lifted",
    ", one foot crossed behind and the coat wrapping around the turn",
)

# 무리마다의 (기본 자세, 결 넷). `pose_for` 가 여기만 본다.
POSE_SETS = {
    "aim":   (AIM_POSE, AIM_FLAV),
    "slash": (SLASH_POSE, SLASH_FLAV),
    "lash":  (LASH_POSE, LASH_FLAV),
    "throw": (THROW_POSE, THROW_FLAV),
    "cast":  (CAST_POSE, CAST_FLAV),
    "raise": (RAISE_POSE, RAISE_FLAV),
}


def pose_family(weapon: str, bullet: str = "") -> str:
    """그 캐릭터가 속한 자세 **무리**. 팔의 역학이 여기서 나온다.

    ★ `gen_concepts.motion_of()` 가 이 함수와 **같은 답**을 내야 한다 — 무리가
      곧 `mkanim.MOTIONS` 의 갈래다. 두 곳이 갈리면 정지 그림과 클립이 다른 자세가 된다.
    """
    if bullet == "zone":
        return "raise"
    if weapon in AIM_NOUN:
        return "aim"
    if weapon == "sword":
        return "slash"
    if weapon == "whip":
        return "lash"
    if weapon == "thrown":
        return "throw"
    return "cast"


def pose_for(weapon: str, bullet: str = "", uid: str = "", tier: int = -1) -> str:
    """그 캐릭터가 설 자세 = 무리(무기·방식) + 결(등급 또는 id).

    ★ `uid` 를 안 주면 결이 안 붙는다. 옛 부름꼴을 그대로 살려 둔 것이라 검사기와
      도구가 안 깨지지만, **그림을 뽑을 때는 반드시 id 를 넘겨라** — 안 넘기면
      쉰 명이 다시 다섯 줄로 돌아간다.

    ★★ **결은 등급(`tier`)이 정한다 — 해시가 아니다.** 이 로스터는 무기마다 정확히
      열 명이고 그 열이 등급 0~9 에 하나씩 선다. 그러니 등급을 결의 번호로 쓰면
      결 여섯이 **고르게** 돌아 한 자세를 나눠 쓰는 사람이 최대 둘이 된다.
      id 해시로 돌렸더니 쏠려서 여섯 명이 **글자 한 자 안 다른** 같은 자세로 섰다
      (실측: 서로 다른 자세 23 / 최대 6명). 등급으로 돌리면 30 / 최대 2 다.
      ☆ 등급을 안 주면 예전처럼 id 해시로 되돌아간다 — 부르는 곳이 안 깨진다.
    """
    fam = pose_family(weapon, bullet)
    base, flav = POSE_SETS[fam]
    if fam == "aim":
        base = base % AIM_NOUN[weapon]
    if not uid:
        return base
    i = tier % len(flav) if tier >= 0 else _seed(uid + "#pose") % len(flav)
    return base + flav[i]


MON_POSE = ", front view, menacing pose"
BOSS_POSE = ", gigantic and imposing, front view, towering over the viewer"

# 테마 배경 — 위에서 내려다본 바닥과, 지평선에 두르는 먼 배경.
# ★ 바닥은 **몬스터가 걷는 길**이라 어두워야 한다. 밝으면 몬스터가 안 읽힌다.
# ★ 바닥은 **위에서 곧장 내려다본 땅 무늬**여야 한다. 투기장 원판이 그 그림이라,
#   지평선이 들어가면 원판 안에 풍경화가 붙은 꼴이 된다 — 실제로 처음 뽑았을 때
#   호수 바닥이 「먼 산과 하늘이 있는 호수 사진」으로 나왔다.
# ★ 그래서 바닥에는 배경 묘사(theme.prompt)를 쓰지 않고 **바닥 재질 묘사**
#   (theme.floor_prompt)를 따로 둔다. CLAUDE.md 4-4 와 같은 까닭이다 —
#   앵커 몇 줄은 몸통 묘사를 못 이긴다. 「호수와 먼 산」이라고 적어 두고
#   「위에서 내려다봤다」를 붙여 봐야 모델은 앞의 말을 따른다.
THEME_FLOOR = (", a flat ground surface texture seen straight down from directly overhead, "
               "top-down orthographic view, no horizon, no sky, no distant mountains, "
               "no buildings, filling the whole frame, seamless, "
               "dark and muted so that bright figures stand out on top of it")
THEME_BG = (", a wide distant horizon under a dark sky, filling the whole frame, "
            "muted shadowy tones, no foreground objects")

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

# 테마 그림 크기. 투기장 바닥(arena_floor)·배경(arena_bg)과 같은 크기여야
# battle_screen 이 그대로 갈아 끼울 수 있다.
THEME_SIZE = {"floor": (720, 720, 1024, 1024), "bg": (1280, 800, 1024, 640)}

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
    # 상태이상·크리스탈 그림. 생성 해상도의 가로세로 비를 저장 크기와 맞춘다 —
    # pixelize 가 out_w 로 늘려 버리므로 비가 다르면 그림이 눌린다.
    "crystal":     (32, 50, 640, 1024),
    "fx_fire":     (36, 48, 768, 1024),
    "fx_ice_bg":   (72, 26, 1024, 384),
    "fx_ice_fg":   (72, 34, 1024, 480),
    "fx_stun_bg":  (72, 26, 1024, 384),
    "fx_stun_fg":  (72, 34, 1024, 480),
}

# 배경으로 칠 수 있는 밝기·채도. cut_white 의 물 붓기와 trapped_white 가 **같은 값**을
# 봐야 한다 — 한쪽만 고치면 "물은 지나갔는데 갇힌 곳은 안 지워지는" 식으로 갈라진다.
BG_SAT = 22
BG_VAL = 205
# 갇힌 덩어리를 배경으로 칠 문턱. 값의 5% 분위수가 이보다 밝고 채도가 이보다 낮아야 한다.
FLAT_VAL = 240
FLAT_SAT = 4.0
# 갇힌 배경으로 칠 덩어리의 **최소 두께**(짧은 변 대비 반지름).
# ★ 이것이 없으면 칼날·옷주름의 **흰 하이라이트**가 같이 지워진다. 실제로 그랬다 —
#   스페이드왕의 검신 한가운데와 서리도제의 옷자락에 구멍이 뚫렸다. 하이라이트는 늘
#   가늘고 긴 띠이고, 갇힌 배경(활 안쪽·파도 안쪽)은 통통한 덩어리라 두께로 갈린다.
HOLE_R = 0.018

# 팔레트 색 수. 적을수록 도트 느낌이 강해지지만 너무 적으면 그라데이션이 띠가 된다.
COLORS_UNIT = 40
COLORS_SCENE = 64


def load_roster() -> dict:
    with open(ROSTER, encoding="utf-8") as f:
        return json.load(f)


def jobs(r: dict) -> list[dict]:
    """뽑을 것 전부를 한 줄씩. seed 는 id 로 정해서 다시 돌려도 같은 그림이 나온다."""
    out: list[dict] = []
    # ★ **속성 색은 몸통 묘사 바로 뒤에 붙인다 — 앵커 안에 넣지 마라.**
    #   CLAUDE.md 4-4 가 잰 것이 그대로 걸린다: 몸통 묘사가 앵커를 이긴다. 그래서
    #   「전기는 누리끼리하게」를 앵커에 적으면 옷 묘사에 밀려 안 나오고, 묘사 옆에
    #   붙이면 같은 무게로 읽힌다. 실제로 이 한 줄의 자리가 색이 붙느냐 마느냐를 갈랐다.
    for ti, t in enumerate(r["tiers"]):
        for u in t["units"]:
            look = ELEM_LOOK[u.get("elem", "none")]
            out.append(dict(
                kind="unit", id=u["id"], ko=u["ko"], dir="units",
                prompt=f"{ONE}{u['prompt']}, {look}, {DOT}"
                       f"{u.get('pose') or pose_for(u.get('weapon', ''), u.get('bullet', ''), u['id'], ti)}"
                       f"{CUTOUT}",
                w=1024, h=1024, out_h=unit_h(ti), cut=True, colors=COLORS_UNIT,
                holes=bool(u.get("holes", False)), seed=_seed(u["id"])))
    for m in r["monsters"]:
        pose = BOSS_POSE if m["kind"] == "boss" else MON_POSE
        look = BODY_LOOK[m["body"]]
        out.append(dict(
            kind="monster", id=m["id"], ko=m["ko"], dir="monsters",
            prompt=f"{ONE}{m['prompt']}, {look}, {DOT}{pose}{CUTOUT}",
            w=1024, h=1024, out_h=MON_H[m["kind"]], cut=True, colors=COLORS_UNIT,
            holes=bool(m.get("holes", False)), seed=_seed(m["id"])))
    # ★ 테마 배경은 **기본으로 안 뽑는다.** 테마가 쉰 개인데 배경이 두 장씩이면 백 장이고
    #   GPU 로 두 시간이다. 게임은 그림이 없으면 투기장 그림에 테마 색을 곱해서 쓰므로
    #   (battle_screen._tint) 없어도 쉰 곳이 서로 다르게 보인다. 진짜 그림이 필요한
    #   몇 곳만 `--kind theme --only <id>` 로 뽑는다.
    for th_ in r.get("themes", []):
        for part in ("floor", "bg"):
            tw, thh, gw, gh = THEME_SIZE[part]
            tail = THEME_FLOOR if part == "floor" else THEME_BG
            # ★ 바닥과 배경은 **다른 묘사**를 쓴다 (THEME_FLOOR 주석 참고).
            body = th_.get("floor_prompt", th_["prompt"]) if part == "floor" else th_["prompt"]
            out.append(dict(
                kind="theme", id="%s_%s" % (th_["id"], part), ko="%s %s" % (th_["ko"], part),
                dir="themes", prompt=f"{body}{tail}, {SCENE}",
                w=gw, h=gh, out_w=tw, out_h=thh, cut=False, colors=COLORS_SCENE,
                holes=False, seed=_seed(th_["id"] + part)))
    for a in r["arts"]:
        # ★ 크기는 UI_SIZE 표가 갖는다. 다만 roster.json 이 "size": [가로, 세로, 생성가로,
        #   생성세로] 로 직접 적을 수도 있다 — 패시브 문양 스물여섯 장이 전부 같은 96x96
        #   이라, 표에 스물여섯 줄을 늘리면 패시브를 하나 만들 때마다 두 곳을 고쳐야 한다.
        #   표에도 없고 size 도 없으면 KeyError 로 시끄럽게 죽는다(조용한 기본값은 두지 않는다).
        tw, th, gw, gh = tuple(a["size"]) if a.get("size") else UI_SIZE[a["id"]]
        fx = bool(a.get("fx", False))
        if fx:
            prompt = f"{FX_ONE}{a['prompt']}, {DOT}{FX_CUTOUT}"
        elif a["cut"]:
            prompt = f"{ONE}{a['prompt']}, {DOT}{CUTOUT}"
        else:
            prompt = f"{a['prompt']}, {SCENE}"
        out.append(dict(
            kind="ui", id=a["id"], ko=a["ko"], dir="ui", prompt=prompt,
            w=gw, h=gh, out_w=tw, out_h=th, cut=a["cut"], tight=fx,
            square=bool(a.get("square", False)),
            holes=bool(a.get("holes", False)),
            colors=COLORS_UNIT if a["cut"] else COLORS_SCENE, seed=_seed(a["id"])))
    return out


# ★ **화풍 세대 소금.** 시드는 id 하나에서만 나오므로, 앵커를 통째로 바꿔도 **id 가
#   같은 그림은 시드가 같다** — 그리고 같은 시드에서는 앵커 몇 줄보다 몸통 묘사가 세서
#   거의 같은 그림이 다시 나온다(CLAUDE.md 4-4 가 실제로 겪은 것이다: 서른 명을 새
#   앵커로 다시 뽑았더니 넷이 예전과 거의 같았다).
#   캐릭터 여든은 id 가 전부 새것이라 저절로 새 그림이지만, **몬스터 스물다섯은 id 를
#   그대로 두므로**(저장 파일과 테마 표가 그 id 를 가리킨다) 소금이 없으면 옛 그림이
#   그대로 나온다. 화풍을 또 갈아엎을 일이 생기면 이 숫자를 올려라.
STYLE_GEN = 3


def _seed(name: str) -> int:
    """이름에서 만든 고정 시드. --force 로 다시 돌려도 같은 그림이 나온다."""
    h = 2166136261
    for ch in ("%s#g%d" % (name, STYLE_GEN)) if STYLE_GEN else name:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h % 2000000


# --------------------------------------------------------------------------- #
# 흰 배경 오려내기 — 모서리에서 물을 부어 흰 곳만 지운다.
#   색이 있거나 어두운 곳(=그림)에는 미리 벽을 세워 두므로 물이 못 넘어온다.
#   ⚠ 흰 옷을 입은 캐릭터가 위험하지만, 화풍에 "thick black outline" 이 들어 있어서
#     외곽선이 벽 노릇을 한다. 그래도 실패를 조용히 넘기지 않게 아래에서 넓이를 잰다.
# --------------------------------------------------------------------------- #
def tight_crop(img):
    """**알파만 보고** 테두리를 바짝 자른다.

    ★ cut_white 끝의 `out.getbbox()` 는 사실상 아무 일도 안 한다 — PIL 은 RGBA 에서
      네 채널 중 하나라도 0 이 아니면 「내용」으로 치는데, 지워진 배경은 알파만 0 이고
      RGB 는 흰색(255,255,255) 이라 전부 내용으로 잡힌다. 실측: art/ui/boom.png 는
      128x128 인데 실제 그림은 60x51 뿐이고 91% 가 투명이다.
      이펙트 그림은 **화면에서 발밑·불꽃 자리에 정확히 맞춰 그려야** 하므로,
      틀 안에 빈 여백이 남으면 크기와 기준점이 통째로 어긋난다.
    """
    a = img.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    bbox = a.getbbox()
    return img.crop(bbox) if bbox else img


def cut_white(img, thresh: int = 26, feather: float = 0.6, holes: bool = False):
    from PIL import Image, ImageDraw, ImageFilter
    import numpy as np

    rgb = img.convert("RGB")
    w, h = rgb.size
    arr = np.array(rgb).astype("int16")
    sat = arr.max(axis=2) - arr.min(axis=2)
    val = arr.max(axis=2)
    protect = (sat > BG_SAT) | (val < BG_VAL)

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
    # ★ 찾기는 늘 하고, **지우는 것은 그 그림이 시켰을 때만** 한다(roster.json 의 holes).
    #   왜 자동으로 안 지우는가는 trapped_white() 의 주석에 적어 뒀다 — 흰 배경과
    #   흰 그림은 픽셀로는 똑같아서, 무엇이 배경인지는 사람만 안다.
    trapped = trapped_white(bg, sat, val)
    trapped_frac = float(trapped.sum()) / float(w * h)
    if holes:
        bg = bg | trapped
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
    return out, kept, trapped_frac


def trapped_white(bg, sat, val, min_frac: float = 0.0018):
    """**갇힌 배경**을 찾는다. 지울지 말지는 부르는 쪽이 정한다(roster.json 의 holes).

    모서리에서 부은 물은 테두리와 이어진 흰 곳만 지운다. 그래서 활시위 안쪽·파도가
    말린 안쪽처럼 **그림에 빙 둘러싸인 흰 구멍**은 그대로 남아, 화면에서 캐릭터에 흰
    판때기가 붙어 나온다 — 장궁수·짚신궁수·파도승·달빛궁수가 실제로 그랬다.

    ⚠ **자동으로 지우면 안 된다.** 흰 배경과 흰 그림은 픽셀로는 구별이 안 된다.
      포자버섯의 갓에 그려진 흰 점무늬는 활 안쪽의 배경과 밝기도 채도도 넓이도 똑같다 —
      한쪽은 배경이고 한쪽은 그림이라는 것은 **뜻**의 문제이지 픽셀의 문제가 아니다.
      실제로 자동으로 지웠더니 버섯 갓에 구멍이 뚫렸다. 그래서 `roster.json` 에
      `"holes": true` 를 적은 그림만 지운다(그 flag 가 곧 "여기 갇힌 배경이 있다"는
      사람의 판단이다). 안 적은 그림은 찾기만 하고 끝에 알려 준다.

    여기서 거르는 것은 셋이다:

      1. **거의 흰 곳**만 본다 — 모서리에서 부은 물이 지날 수 있었던 밝기·채도(BG_*).
      2. **평평해야** 한다. 갇힌 배경은 모델이 깔아 준 한 가지 색이라 249~255 안에 다
         들어오고, 그려 낸 흰 옷은 아무리 밝아도 명암이 있어 훨씬 넓게 퍼진다.
      3. **통통해야** 한다(HOLE_R). 칼날·옷주름의 하이라이트는 늘 가늘고 긴 띠라서
         이 문턱에서 걸린다 — 이게 없으면 스페이드왕의 검신 한가운데가 뚫린다.
    """
    import numpy as np

    # 모서리에서 부은 물이 지날 수 있었던 곳 중, 물이 못 닿은 곳.
    cand = (sat <= BG_SAT) & (val >= BG_VAL) & (~bg)
    if not cand.any():
        return np.zeros_like(bg)

    h, w = cand.shape
    need = max(64, int(h * w * min_frac))
    need_r = max(3, int(min(h, w) * HOLE_R))
    out = np.zeros_like(cand)
    seen = np.zeros_like(cand)
    ys, xs = np.nonzero(cand)
    for y0, x0 in zip(ys.tolist(), xs.tolist()):
        if seen[y0, x0]:
            continue
        # 덩어리 하나를 훑는다. 후보 픽셀만 도므로 그림 전체를 도는 것보다 훨씬 싸다.
        stack = [(y0, x0)]
        seen[y0, x0] = True
        blob = []
        while stack:
            y, x = stack.pop()
            blob.append((y, x))
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and cand[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(blob) < need:
            continue
        ay = np.fromiter((p[0] for p in blob), dtype=np.int32, count=len(blob))
        ax = np.fromiter((p[1] for p in blob), dtype=np.int32, count=len(blob))
        if float(np.percentile(val[ay, ax], 5)) < FLAT_VAL or float(sat[ay, ax].mean()) > FLAT_SAT:
            continue
        if not thick_enough(ay, ax, need_r):
            continue
        out[ay, ax] = True
    return out


def thick_enough(ay, ax, need_r: int) -> bool:
    """그 덩어리 안에 반지름 need_r 짜리 원이 들어가는가.

    ★ 가늘고 긴 하이라이트(칼날의 흰 줄, 옷주름)와 통통한 갇힌 배경(활 안쪽)을 가르는
      유일하게 믿을 만한 잣대다. 넓이로는 안 갈린다 — 긴 띠도 넓이는 크다.
    ★ 덩어리의 테두리 상자 안에서만 깎는다. 그림 전체(1024x1024)를 스무 번 깎으면
      한 장에 몇 초씩 걸린다.
    """
    import numpy as np

    y0, y1 = int(ay.min()), int(ay.max())
    x0, x1 = int(ax.min()), int(ax.max())
    if min(y1 - y0, x1 - x0) < need_r * 2:
        return False
    # 사방에 한 칸씩 빈 테를 두른다 — 안 두르면 상자 가장자리가 안 깎여서
    # 상자에 딱 붙은 띠가 통통한 것으로 잘못 읽힌다.
    m = np.zeros((y1 - y0 + 3, x1 - x0 + 3), dtype=bool)
    m[ay - y0 + 1, ax - x0 + 1] = True
    for _ in range(need_r):
        m = (m[1:-1, 1:-1] & m[:-2, 1:-1] & m[2:, 1:-1]
             & m[1:-1, :-2] & m[1:-1, 2:])
        if not m.any():
            return False
        m = np.pad(m, 1)
    return True


def pad_square(img):
    """바짝 자른 그림을 **투명한 정사각형** 한가운데에 놓는다.

    왜 필요한가: tight_crop 은 알파로 바짝 자르므로 가로세로 비가 그림마다 다르다.
    그런데 pixelize 는 out_w 와 out_h 를 둘 다 받으면 **늘려서** 맞추므로, 가로로 넓게
    잘린 문양은 96x96 으로 눌려 찌그러진다. 정사각으로 한 번 채워 두면 눌림 없이 줄어든다.

    ★ 패시브 문양에 이것이 필요한 까닭이 하나 더 있다: 화면은 문양을 **한 변이 2r 인
      네모** 한가운데에 그린다(Look.draw_passive_icon). 그림마다 비가 다르면 가로로 넓은
      문양이 옆 칸을 파고든다 — 전투 정보판에서 문양이 30px 간격으로 줄지어 선다.
    """
    from PIL import Image
    w, h = img.size
    n = max(w, h)
    out = Image.new("RGBA", (n, n), (255, 255, 255, 0))
    out.paste(img, ((n - w) // 2, (n - h) // 2))
    return out


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
    ap.add_argument("--kind", default="",
                    help="unit | monster | ui | theme (쉼표로 여럿: --kind unit,monster)")
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
        # ★ 쉼표로 여럿을 받는다. 캐릭터 여든과 몬스터 스물다섯을 **한 번에** 뽑기
        #   위해서다 — 따로 부르면 모델을 두 번 올리고 그것만 4분씩이다.
        kinds = [k.strip() for k in args.kind.split(",") if k.strip()]
        js = [j for j in js if j["kind"] in kinds]
    else:
        # ★ 테마 배경 백 장은 **부르지 않으면 안 뽑는다** (jobs() 주석 참고).
        js = [j for j in js if j["kind"] != "theme"]
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

    # ★ Krea2 와 MiniMax H3 는 같은 순간에 못 뜬다 — 올리기 전에 문지기를 부른다 (tools/gpu_guard.py)
    import gpu_guard
    gpu_guard.claim("krea2")
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
            img, kept, trapped = cut_white(img, holes=j["holes"])
            if j.get("tight"):
                img = tight_crop(img)
            if j.get("square"):
                img = pad_square(img)
            if j["holes"]:
                # ★ 지웠으면 **반드시 눈으로 봐라.** 흰 옷·수염을 배경으로 잘못 보면
                #   캐릭터 몸에 구멍이 뚫리는데, 그건 검사로는 절대 안 잡힌다.
                # ★ 문턱을 두지 마라. trapped_white 가 이미 넓이·평평함·두께로 걸렀으니
                #   여기까지 온 것은 무엇이든 사람이 봐야 한다. 예전에 0.4% 문턱을 두었더니
                #   그보다 작은 지우기가 **아무 말 없이** 지나갔다.
                if trapped > 0.0:
                    warn.append(f"{j['id']}: 갇힌 배경 {trapped:.1%} 를 지웠다"
                                " — 흰 옷·수염이 뚫리지 않았는지 눈으로 봐라")
            elif trapped > 0.0:
                # 지우지는 않았다. 그림에 흰 판때기가 붙어 있으면 사람이 켜 준다.
                warn.append(f"{j['id']}: 갇힌 배경으로 보이는 덩어리 {trapped:.1%} 가 있다"
                            " — 그림에 흰 판때기가 붙어 있으면 roster.json 에"
                            ' "holes": true 를 적고 --force 로 다시 뽑아라')
            # 오려내기가 실패하면(배경이 안 지워지거나 그림이 통째로 지워지면) 조용히
            # 넘어가지 않는다. 화면에 흰 네모가 붙어 나오는 것을 눈으로 찾는 건 지옥이다.
            if kept > 0.85:
                warn.append(f"{j['id']}: 배경이 거의 안 지워졌다 ({kept:.0%} 남음)")
            elif kept < 0.05:
                warn.append(f"{j['id']}: 그림이 거의 다 지워졌다 ({kept:.0%} 남음)"
                            " — python3 tools/gen_art.py --only %s --force --try 1" % j['id'])
        px = pixelize(img, j["out_h"], j["colors"], j.get("out_w", 0))
        if j["id"] == "arena_floor" or j["id"].endswith("_floor"):
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
