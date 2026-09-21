#!/usr/bin/env python3
"""tools/roster.json → tools/anim/concepts.json 을 만든다.

캐릭터가 서른이라 컨셉을 손으로 적으면 반드시 어긋난다 — roster.json 의 속성을 고쳤는데
concepts.json 의 램프는 그대로여서 「불 영웅인데 얼음 이펙트를 쓰는」 클립이 나오는 식이다.
그래서 **몸통 묘사(prompt)와 속성(elem)은 roster.json 하나만 보고**, 애니메이션에만 필요한
것(무기·동작·램프)은 여기 표에서 붙인다.

    python3 tools/gen_concepts.py            # 전부 다시 찍는다
    python3 tools/gen_concepts.py --keep     # 이미 있는 항목은 손대지 않는다 (손으로 다듬은 것 보호)

★ 손으로 다듬은 항목을 지키려면 `--keep` 을 써라. 화염마도사·서리여왕·뇌전궁수 셋은
  실제로 만들어 보며 좌표까지 맞춰 둔 것이라 덮어쓰면 안 된다.
"""
from __future__ import annotations

import argparse
import json
import os

import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_art  # noqa: E402  (자세 표를 **한 곳에서만** 갖기 위해서다)

ROSTER = os.path.join(ROOT, "tools", "roster.json")
OUT = os.path.join(ROOT, "tools", "anim", "concepts.json")

# --------------------------------------------------------------------------- #
# 속성마다의 이펙트 — 램프(안쪽→바깥쪽)와 심의 모양(facets)
#
# ★ **심지를 (255,255,255) 로 두지 마라.** gen_art.cut_white 의 배경 띠
#   (sat<=22 & val>=205)와 픽셀로 구별이 안 되어 이펙트에 구멍이 뚫린다.
# ★ 램프끼리 **길이 겹치면 안 된다.** 서른 명이 나란히 서는 게임이라, 두 속성이 같은
#   색길을 타면 화면에서 같은 이펙트로 보인다. 실제로 그래서 전기 램프가 노랑에서
#   주황을 건너뛰고 **보라로** 간다 — 주황을 거치면 불 램프와 같은 길이 된다.
# ★ 물과 얼음이 제일 위험하다. 둘 다 파랑이라 그냥 두면 구별이 안 된다. 그래서
#   **얼음은 창백한 하늘빛에서 남색으로, 물은 청록(민트)에서 파랑으로** 간다.
#   모양도 갈린다 — 얼음은 육각 결정(facets=6), 물은 둥근 심(facets=0).
# --------------------------------------------------------------------------- #
ELEM_FX = {
	"fire": dict(facets=0,
		ramp=[[255, 247, 219], [255, 221, 112], [255, 170, 60], [240, 106, 26], [196, 48, 10]],
		edge=[78, 16, 6],
		note="불 — 둥근 심 + 흔들리는 혓바닥. 게임의 불 속성색 #FF6A2A 에서 이어 뽑았다."),
	"ice": dict(facets=6,
		ramp=[[226, 250, 255], [160, 233, 255], [96, 200, 246], [46, 140, 219], [24, 78, 166]],
		edge=[10, 30, 74],
		note="얼음 — 육각 결정 + 곧고 뾰족한 가시(안 흔들린다). 흔들림을 넣어 봤더니 그냥 **녹는 것**으로 보였다. 게임의 얼음 속성색 #7BDCFF 에서 뽑았다."),
	"elec": dict(facets=-1,
		ramp=[[255, 246, 176], [255, 216, 77], [222, 170, 242], [140, 92, 226], [64, 34, 140]],
		edge=[22, 12, 54],
		note="전기 — 작고 사나운 심 + 꺾이고 갈라지는 지그재그 가지. ★ 노랑에서 **주황을 건너뛰고 보라로** 간다. 주황을 거치면 불 램프와 같은 길이 되어 나란히 놓았을 때 같은 이펙트로 보인다."),
	"water": dict(facets=0,
		ramp=[[186, 255, 246], [92, 236, 220], [40, 168, 246], [22, 92, 200], [8, 36, 112]],
		edge=[4, 18, 58],
		note="물 — 둥근 심 + 흔들리는 물갈기. ★ 심을 **청록(민트)**에서 시작한다. 얼음처럼 창백한 하늘빛으로 시작하면 얼음과 픽셀로 구별이 안 된다 — 둘 다 파랑이라 램프가 갈라지지 않으면 화면에서 같은 이펙트가 된다."),
	"none": dict(facets=0,
		ramp=[[255, 244, 206], [246, 214, 140], [206, 160, 88], [140, 96, 44], [72, 44, 18]],
		edge=[30, 18, 8],
		note="무상성 — 놋쇠빛 불똥. 마법이 아니라 **쇠붙이가 부딪힌 자국**이다. 활·총·대포·표창이 여기 든다. 속성 이펙트를 주면 「무상성인데 무언가를 두르고 있는」 그림이 되어 안전한 줄이라는 뜻이 흐려진다."),
}

# 소품에서 탄이 나가는 무기. 자세와 holes 가 다르다 (docs/ART.md 0).
PROP_WEAPONS = {"bow", "crossbow", "gun", "cannon"}
AIM_WORD = {"bow": "bow", "crossbow": "crossbow", "gun": "musket", "cannon": "cannon"}

CAST_POSE = ", standing in a three-quarter view, one arm thrust forward casting"


# --------------------------------------------------------------------------- #
# ★ **동작은 무기와 방식에서 뽑는다 — 손으로 적지 마라.**
#
#   예전에는 `tools/anim/anim_fields.json` 에 서른 명의 motion/muzzle/link 를 손으로
#   적어 두었다. 캐릭터가 여든이 되면서 그 표는 통째로 뜻을 잃었고(id 가 전부 새것이다),
#   무엇보다 **무기와 동작이 두 곳에 적혀 있으면 반드시 어긋난다** — 활을 든 캐릭터가
#   마법사 동작으로 도는 클립이 나온다.
#
#   ★★ **무리는 `gen_art.pose_family()` 하나가 정한다.** 예전에는 여기에 같은 갈래가
#     한 벌 더 적혀 있었다 — 정지 그림의 자세와 클립의 동작이 **다른 함수 둘**에서
#     나온 것이다. 무기 하나만 늘려도 두 곳을 고쳐야 하고, 한 곳을 빠뜨리는 날
#     「활을 겨눈 정지 그림 + 지팡이를 휘두르는 클립」이 나온다.
#
#   draw   활·쇠뇌·총·대포 — 소품을 겨누고 있다가 놓는다. 탄은 **소품에서** 나가고
#          손과 소품을 잇는 것은 뻣뻣한 살(shaft)이다.
#   raise  광역 마법(zone) — **두 팔을 든다.** 캐릭터에서 탄이 안 나간다.
#   cast   나머지 — 한 팔을 앞으로 뻗어 손에서 던진다.
#
# --------------------------------------------------------------------------- #
# ★★ **결(variant) — 같은 무리 안에서 셋으로 갈린다** (사용자가 정한 것: 「모션도
#    좀 너무 일관적인데 다양하게 나올 수 있도록」). 표는 `mkanim.MOTIONS` 에 있다.
#
# ★ **결은 `profile` 이 먼저 정한다.** 그래야 동작이 **뜻을 갖는다** — 상점과 설명
#   팝업에 적히는 그 성격(heavy 한 대가 무겁다 · rapid 연사)이 화면에서도 보인다.
#   무작위로 뿌리면 다양해지기만 하고 아무것도 안 가르친다.
#     heavy  → 크게 파고들고 크게 밀린다 (cast_lunge · draw_heavy · raise_slam)
#     rapid  → 짧고 잦다             (cast_sweep · draw_snap · raise_wide)
#     sniper · balance → id 로 셋 중 하나. 이 둘은 몸짓으로 갈릴 성격이 아니라서,
#       여기서까지 뜻을 붙이면 없는 규칙을 지어내는 것이 된다. 대신 **골고루 퍼뜨린다.**
# ★ **대포는 언제나 `draw_heavy`** 다. 한 명뿐이라 id 로 굴리면 절반의 확률로
#   속사 대포가 나오는데, 그것은 성격이 아니라 그냥 틀린 그림이다.
# --------------------------------------------------------------------------- #
# 자세 무리(gen_art) → 동작 무리(mkanim). 이름이 다른 까닭은 자세는 **그림의 말**이고
# 동작은 **클립의 말**이기 때문이다 — 「겨눔(aim)」의 클립 이름이 「놓는다(draw)」이고,
# 「던짐(throw)」은 손에서 나가므로 마법사와 같은 `cast` 를 탄다.
# ★ `slash`(검)·`lash`(채찍)는 **손에서 나가는** 동작이라 마법사와 같은 `cast` 를 탄다 —
#   옛 길(tools/anim)의 동작 표에는 그 둘이 없다. 게임은 이제 옛 길을 안 쓰지만,
#   여기가 KeyError 로 멈추면 `gen_concepts.py` 를 돌리는 순간 사고가 난다.
FAM_MOTION = {"aim": "draw", "throw": "cast", "cast": "cast", "raise": "raise",
              "slash": "cast", "lash": "cast"}

VARIANTS = {
    "cast":  ("cast", "cast_lunge", "cast_sweep"),
    "draw":  ("draw", "draw_heavy", "draw_snap"),
    "raise": ("raise", "raise_slam", "raise_wide"),
}
PROFILE_PICK = {"heavy": 1, "rapid": 2}


def _spread(uid: str, n: int) -> int:
    h = 2166136261
    for ch in uid + "#motion":
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h % n


def motion_of(weapon: str, bullet: str, uid: str = "", profile: str = "") -> dict:
    fam = FAM_MOTION[gen_art.pose_family(weapon, bullet)]
    vs = VARIANTS[fam]
    if fam == "draw" and weapon == "cannon":
        motion = "draw_heavy"
    elif profile in PROFILE_PICK:
        motion = vs[PROFILE_PICK[profile]]
    elif uid:
        motion = vs[_spread(uid, len(vs))]
    else:
        motion = vs[0]
    if fam == "raise":
        return dict(motion=motion, muzzle="hand", link="wobble", shot_kind="bolt")
    if fam == "draw":
        return dict(motion=motion, muzzle="prop", link="shaft", shot_kind="arrow")
    return dict(motion=motion, muzzle="hand", link="wobble", shot_kind="bolt")


def load_roster() -> dict:
	with open(ROSTER, encoding="utf-8") as f:
		return json.load(f)


def build(r: dict, anim_fields: dict) -> dict:
	units = []
	for ti, t in enumerate(r["tiers"]):
		for u in t["units"]:
			units.append((ti, u))

	by_elem: dict[str, list[str]] = {}
	for _, u in units:
		by_elem.setdefault(u.get("elem", "none"), []).append(u["id"])

	out: dict = {}
	for ti, u in units:
		uid = u["id"]
		# ★ roster.json 이 원본이다. anim_fields.json 은 **옛 서른 명의 흔적**이라
		#   roster 에 없는 값을 채울 때만 본다 — 두 곳이 어긋나면 roster 가 이긴다.
		a = dict(anim_fields.get(uid, {}))
		elem = u.get("elem", "none")
		fx = ELEM_FX[elem]
		weapon = u.get("weapon") or a.get("weapon", "staff")
		a.update(motion_of(weapon, u.get("bullet", "shot"), uid, u.get("profile", "")))
		prop = weapon in PROP_WEAPONS
		# 자세는 roster.json 이 들고 있다 — 정지 그림도 같은 자세를 써야 한다
		# (정지 그림이 곧 마스터이자 0번 칸이다, docs/ART.md 8).
		# ★ **자세는 gen_art.pose_for() 하나만 쓴다.** 여기서 따로 지어내면 정지 그림과
		#   애니메이션 마스터가 다른 자세가 되어 전투 화면과 편성 판이 다른 사람으로 보인다
		#   (docs/ART.md 0-1).
		pose = u.get("pose") or gen_art.pose_for(weapon, u.get("bullet", ""), uid, ti)
		e: dict = {
			"ko": u["ko"],
			"elem": elem,
			"tier": ti,
			# 1:1 로 나란히 놓고 볼 이웃 = **같은 속성** 캐릭터들.
			# ★ 혼자 놓고 보면 늘 괜찮아 보인다 (docs/ART.md 2-3).
			"neighbors": [x for x in by_elem[elem] if x != uid],
			"pose": pose,
			# 몸통 묘사는 roster.json 하나만 본다 — 두 곳에 적으면 반드시 어긋난다.
			"bodies": {"a": u["prompt"]},
			"_note_ramp": fx["note"],
			"ramp": fx["ramp"],
			"edge": fx["edge"],
			"facets": fx["facets"],
		}
		# ★ 결이 생긴 뒤로는 **언제나 적는다.** 예전에는 "cast 면 생략"이었는데,
		#   지금은 cast·cast_lunge·cast_sweep 셋이라 생략하면 build_clips 가 결을 잃고
		#   셋 다 기본 cast 로 돈다 — 다양하게 만들어 놓고 화면에서는 하나만 보인다.
		e["motion"] = a["motion"]
		if a.get("muzzle", "hand") != "hand":
			e["muzzle"] = a["muzzle"]
		if a.get("link", "wobble") != "wobble":
			e["link"] = a["link"]
		if a.get("shot_kind", "bolt") != "bolt":
			e["shot"] = a["shot_kind"]
		if u.get("holes"):
			e["holes"] = True
			e["_note_holes"] = ("★ 활·쇠뇌·총·대포는 holes 를 켠다. 시위 안쪽·방아쇠울 안쪽은"
								" 그림에 빙 둘러싸인 흰 구멍이라 모서리에서 부은 물이 못 들어간다 —"
								" 안 켜면 흰 판때기가 붙어 나온다 (CLAUDE.md 4-3). 켜는 것은"
								" **사람의 판단**이고, 활은 그 판단이 늘 같은 몇 안 되는 경우다.")
		# ★ **무리로 비교한다 — 동작 이름으로 비교하지 마라.** 결이 생기면서
		#   `== "draw"` 가 조용히 거짓이 된다(CLAUDE.md 18-5-2). 그러면 속사·중포
		#   궁수 열여덟 명이 stretch 를 못 받아 팔이 길이로만 움직인다.
		if a.get("motion", "").split("_")[0] == "draw":
			# 만작이라 어깨~손이 짧다. 길이가 아니라 **각도**가 움직임을 낸다.
			e["stretch"] = "0.85,1.35"
		out[uid] = e
	return out


# 이 도구가 만들어 내는 키 전부. 여기 없는 키는 **사람이 손으로 더한 것**이라 --keep 이 지킨다.
GEN_KEYS = {"ko", "elem", "tier", "neighbors", "pose", "bodies", "_note_ramp", "ramp",
			"edge", "facets", "motion", "muzzle", "link", "shot", "holes", "_note_holes",
			"stretch"}
# 그중 **사람이 덮어써도 되는** 키. 옆에 `_note_<키>` 가 있으면 그것이 "사람이 정한 값"이라는
# 표시이고, --keep 이 덮어쓰지 않는다. (기우사제의 stretch 가 그렇게 맞춰 둔 값이다)
MANUAL_KEYS = ("stretch",)


def merge(old: dict, new: dict) -> dict:
	"""--keep 의 합치기 — **로스터에서 나오는 것은 새로 덮고, 손으로 더한 것은 남긴다.**

	★ 예전의 --keep 은 있는 항목을 통째로 건너뛰었다. 그러면 `roster.json` 의 몸통 묘사를
	  고쳐도 concepts.json 에는 영영 안 닿는다 — 이 파일 맨 위가 경고하는 바로 그 어긋남
	  ("속성은 불로 고쳤는데 램프는 얼음인" 클립)을 --keep 이 도로 만들고 있었다.
	  실제로 네 명의 몸통 묘사를 고쳤을 때 걸렸다.
	"""
	out = dict(new)
	for k, v in old.items():
		if k not in new and (k not in GEN_KEYS
							 or (k in MANUAL_KEYS and ("_note_%s" % k) in old)):
			out[k] = v
	return out


def main() -> int:
	ap = argparse.ArgumentParser()
	ap.add_argument("--keep", action="store_true",
					help="손으로 더한 값은 남기고 로스터에서 나오는 것만 새로 덮는다")
	args = ap.parse_args()

	anim_path = os.path.join(ROOT, "tools", "anim", "anim_fields.json")
	if not os.path.exists(anim_path):
		raise SystemExit("tools/anim/anim_fields.json 이 없다 — 무기·동작 표가 있어야 한다")
	with open(anim_path, encoding="utf-8") as f:
		anim_fields = json.load(f)

	built = build(load_roster(), anim_fields)
	old: dict = {}
	if args.keep and os.path.exists(OUT):
		with open(OUT, encoding="utf-8") as f:
			old = json.load(f)
	for k, v in built.items():
		if args.keep and k in old:
			old[k] = merge(old[k], v)
		else:
			old[k] = v
	# 로스터에서 빠진 캐릭터는 지운다 — 안 지우면 없는 캐릭터의 클립을 계속 만들게 된다.
	for k in [k for k in old if k not in built]:
		del old[k]

	with open(OUT, "w", encoding="utf-8") as f:
		json.dump(old, f, ensure_ascii=False, indent=1)
	print("만들었습니다: %s (캐릭터 %d명)" % (OUT, len(old)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
