#!/usr/bin/env python3
"""tools/roster.json → core/roster.gd 를 만든다.

캐릭터 표를 두 곳(그림 생성용 JSON · 게임 코드)에 손으로 적어 두면 반드시 어긋난다.
그래서 JSON 하나만 손대고 이 도구로 GDScript 를 찍어 낸다.
그림 크기(h)도 tools/gen_art.py 의 표에서 그대로 가져오므로 그림과 게임이 항상 같은 값을 본다.

    python3 tools/gen_roster.py
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_art  # noqa: E402  — unit_h / MON_H 를 여기서만 정의한다

OUT = os.path.join(ROOT, "core", "roster.gd")

# 몬스터가 나오는 탄 구간. (여기부터, 여기까지, {단계: 비중})
# ★ 구간을 확 갈아 끼우면 그 탄에서 갑자기 육중형이 쏟아져 판이 통째로 무너진다.
#   예전에 21탄에서 mid 0.25/late 0.75 로 한 번에 넘어갔더니, 자동 플레이 24판 중
#   절반이 21~27탄에서 죽었다. 네 칸으로 나눠 천천히 섞는다.
STAGE_MIX = [
	(1, 8, {"early": 1.0}),
	(9, 18, {"early": 0.35, "mid": 0.65}),
	(19, 26, {"mid": 0.65, "late": 0.35}),
	(27, 34, {"mid": 0.25, "late": 0.75}),
	(35, 99, {"late": 1.0}),
]


def esc(s: str) -> str:
	return s.replace("\\", "\\\\").replace('"', '\\"')


def main() -> int:
	with open(os.path.join(ROOT, "tools", "roster.json"), encoding="utf-8") as f:
		r = json.load(f)

	lines: list[str] = []
	w = lines.append
	w("extends RefCounted")
	w("class_name Roster")
	w("")
	w("## 캐릭터·몬스터 표. **자동 생성 파일이다 — 손으로 고치지 마라.**")
	w("## 원본은 tools/roster.json 이고, `python3 tools/gen_roster.py` 가 이 파일을 찍어 낸다.")
	w("## h(그림 높이)는 tools/gen_art.py 가 실제로 저장하는 크기와 같은 값이다.")
	w("")
	w("## 등급별 이름. 인덱스가 Poker.Hand 값과 같다.")
	tier_ko = ", ".join('"%s"' % esc(t["ko"]) for t in r["tiers"])
	w("const TIER_KO := [%s]" % tier_ko)
	w("")

	w("## 캐릭터 %d명. tier 는 Poker.Hand 값이다." % sum(len(t["units"]) for t in r["tiers"]))
	w("##")
	w("## sc 는 **그림 크기 보정**이다. gen_art.py 는 그림을 등급마다 같은 높이로 저장하는데,")
	w("## 그 높이는 지팡이·꼬리·회오리까지 포함한 **테두리 상자**의 높이다. 그래서 소품이 큰")
	w("## 캐릭터는 사람 몸이 그만큼 작게 나온다 — 같은 등급인데 누구는 크고 누구는 작아 보인다.")
	w("## sc 가 그 몫을 되돌린다(1.0 이 보정 없음). 값은 tools/roster.json 에 손으로 적는다.")
	w("##")
	w("## elem 은 **공격 속성**이다(Balance.ELEM). 무상성(none)은 어떤 몸에도 1.0 배 —")
	w("## 활·총·대포·표창이 여기 든다. 나머지 넷은 몬스터의 몸(Balance.MBODY)에 따라")
	w("## 2배(약점)나 0.5배(저항)가 된다. 곱하는 곳은 BattleSim._hurt() 한 군데뿐이다.")
	w("const UNITS := [")
	for ti, t in enumerate(r["tiers"]):
		w("\t# --- %s ---" % t["ko"])
		for u in t["units"]:
			w('\t{"id": "%s", "ko": "%s", "tier": %d, "profile": "%s", "bullet": "%s", '
			  '"elem": "%s", "desc": "%s", "color": "%s", "h": %d, "sc": %.2f, '
			  '"art": "res://art/units/%s.png"},'
			  % (u["id"], esc(u["ko"]), ti, u["profile"], u["bullet"],
				 u.get("elem", "none"), esc(u["desc"]),
				 u["color"], gen_art.unit_h(ti), float(u.get("sc", 1.0)), u["id"]))
	w("]")
	w("")

	w("## 몬스터 %d종. body 는 **몸 속성**이다 — 무엇에 약하고 무엇을 튕겨 내는가" % len(r["monsters"]))
	w("## (Balance.MBODY). null 은 상성을 아예 안 타는 몬스터다.")
	w("const MONSTERS := [")
	for m in r["monsters"]:
		w('\t{"id": "%s", "ko": "%s", "kind": "%s", "stage": "%s", "body": "%s", '
		  '"desc": "%s", "color": "%s", "h": %d, "art": "res://art/monsters/%s.png"},'
		  % (m["id"], esc(m["ko"]), m["kind"], m["stage"], m.get("body", "null"),
			 esc(m["desc"]), m["color"], gen_art.MON_H[m["kind"]], m["id"]))
	w("]")
	w("")

	w("## 화면을 채우는 그림들.")
	w("const ART := {")
	for a in r["arts"]:
		w('\t"%s": "res://art/ui/%s.png",' % (a["id"], a["id"]))
	w("}")
	w("")
	w("""
## 그 등급의 캐릭터 중 하나를 무작위로. **같은 족보라도 매번 다른 얼굴이 나오게** 하는 것이
## 이 게임에서 카드를 뽑는 재미의 절반이다.
static func pick_unit(tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array = []
	for u in UNITS:
		if int(u["tier"]) == tier:
			pool.append(u)
	if pool.is_empty():
		return UNITS[0]
	return pool[rng.randi_range(0, pool.size() - 1)]


static func units_of_tier(tier: int) -> Array:
	var pool: Array = []
	for u in UNITS:
		if int(u["tier"]) == tier:
			pool.append(u)
	return pool


static func unit_by_id(id: String) -> Dictionary:
	for u in UNITS:
		if u["id"] == id:
			return u
	return {}


static func monster_by_id(id: String) -> Dictionary:
	for m in MONSTERS:
		if m["id"] == id:
			return m
	return {}


static func monsters_of_stage(stage: String) -> Array:
	var pool: Array = []
	for m in MONSTERS:
		if m["stage"] == stage:
			pool.append(m)
	return pool


## 씨앗 하나로 정해지는 w 탄의 편성. **같은 씨앗이면 언제 물어도 같은 답이다.**
##
## ★ 이것이 상성을 "운"이 아니라 "선택"으로 만드는 열쇠다. 예전에는 전투가 시작될 때
##   비로소 난수를 굴려 두세 종을 골랐다. 그러면 플레이어는 무엇이 올지 모른 채로
##   안뜰 여섯을 짜야 하고, 저항에 걸리는 것은 순전히 사고였다 — 자동 플레이 24판이
##   한 판도 못 깼다. 지금은 탄 번호만으로 편성이 정해지므로 **상점이 다음 탄에 나올
##   몬스터를 정확히 보여 주고**, 플레이어는 그에 맞춰 영웅을 세운다.
static func wave_kinds_seeded(w: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return wave_kinds(w, rng)


## w 탄에 **나올 수 있는** 몬스터 전부(보스 제외). 난수를 안 쓴다.
## 씨앗을 모르는 자리(검사기·미리보기)에서 "이 구간에는 이런 놈들이 있다"를 보일 때 쓴다.
static func stage_pool(w: int) -> Array:
	var mix := _mix_for(w)
	var out: Array = []
	for stage in mix:
		for m in monsters_of_stage(stage):
			if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
				continue
			if not out.has(m):
				out.append(m)
	return out


## 이번 보스가 누구인가. 앞쪽 보스탄은 용, 30탄부터는 트럼프 마왕이 나온다.
static func boss_for_wave(w: int) -> Dictionary:
	var bosses := monsters_of_stage("boss")
	if bosses.is_empty():
		return {}
	if w >= 30 and bosses.size() > 1:
		return bosses[bosses.size() - 1]
	return bosses[0]


## w 탄에 나올 몬스터 종류를 뽑는다(보스 제외). 같은 탄 안에서도 두어 종이 섞여야
## 화면이 심심하지 않다.
##
## ★ 1~3탄에는 **느린 놈(육중·주술)을 넣지 않는다.** 육중형은 길을 걷는 속도가 0.8배라
##   영웅 한둘로는 잡을 화력이 안 나오고, 첫 탄부터 크리스탈이 깨진다 —
##   게임을 켜자마자 벌을 받는 셈이다. 앞 세 탄은 무조건 막을 수 있어야 한다.
static func wave_kinds(w: int, rng: RandomNumberGenerator) -> Array:
	var mix := _mix_for(w)
	var pool: Array = []
	for stage in mix:
		var arr := monsters_of_stage(stage)
		var n: int = maxi(1, int(round(float(mix[stage]) * 10.0)))
		for i in range(n):
			for m in arr:
				if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
					continue
				pool.append(m)
	if pool.is_empty():
		pool = MONSTERS.duplicate()
	# 두세 종을 골라 그 탄의 편성으로 삼는다.
	var out: Array = []
	var want: int = 2 if w < 6 else 3
	var guard := 0
	while out.size() < want and guard < 200:
		guard += 1
		var m: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(m):
			out.append(m)
	return out
""")
	w("")
	w("static func _mix_for(w: int) -> Dictionary:")
	for lo, hi, mix in STAGE_MIX:
		body = ", ".join('"%s": %s' % (k, v) for k, v in mix.items())
		w("\tif w >= %d and w <= %d:" % (lo, hi))
		w("\t\treturn {%s}" % body)
	w('\treturn {"late": 1.0}')
	w("")

	with open(OUT, "w", encoding="utf-8") as f:
		f.write("\n".join(lines))
	print("만들었습니다: %s (%d줄)" % (OUT, len(lines)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
