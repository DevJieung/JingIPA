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
STAGE_MIX = [
	(1, 8, {"early": 1.0}),
	(9, 20, {"early": 0.30, "mid": 0.70}),
	(21, 34, {"mid": 0.25, "late": 0.75}),
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
	w("const UNITS := [")
	for ti, t in enumerate(r["tiers"]):
		w("\t# --- %s ---" % t["ko"])
		for u in t["units"]:
			w('\t{"id": "%s", "ko": "%s", "tier": %d, "profile": "%s", "bullet": "%s", '
			  '"desc": "%s", "color": "%s", "h": %d, "art": "res://art/units/%s.png"},'
			  % (u["id"], esc(u["ko"]), ti, u["profile"], u["bullet"], esc(u["desc"]),
				 u["color"], gen_art.unit_h(ti), u["id"]))
	w("]")
	w("")

	w("## 몬스터 %d종." % len(r["monsters"]))
	w("const MONSTERS := [")
	for m in r["monsters"]:
		w('\t{"id": "%s", "ko": "%s", "kind": "%s", "stage": "%s", "desc": "%s", '
		  '"color": "%s", "h": %d, "art": "res://art/monsters/%s.png"},'
		  % (m["id"], esc(m["ko"]), m["kind"], m["stage"], esc(m["desc"]),
			 m["color"], gen_art.MON_H[m["kind"]], m["id"]))
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
static func wave_kinds(w: int, rng: RandomNumberGenerator) -> Array:
	var mix := _mix_for(w)
	var pool: Array = []
	for stage in mix:
		var arr := monsters_of_stage(stage)
		var n: int = maxi(1, int(round(float(mix[stage]) * 10.0)))
		for i in range(n):
			for m in arr:
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
