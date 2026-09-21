#!/usr/bin/env python3
"""tools/roster.json → core/roster.gd 를 만든다.

캐릭터 표를 두 곳(그림 생성용 JSON · 게임 코드)에 손으로 적어 두면 반드시 어긋난다.
그래서 JSON 하나만 손대고 이 도구로 GDScript 를 찍어 낸다.
그림 크기(h)도 tools/gen_art.py 의 표에서 그대로 가져오므로 그림과 게임이 항상 같은 값을 본다.

    python3 tools/gen_roster.py

★ 테마 표(THEMES)도 여기서 찍는다. 테마는 배경 그림·색·몸 분포를 같이 들고 있어서
  게임 코드와 그림 도구가 **같은 한 줄**을 봐야 한다 — 두 곳에 적으면 "화면은 호수인데
  나오는 건 바위 몬스터"가 된다.
"""
from __future__ import annotations

import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_art  # noqa: E402  — unit_h / MON_H 를 여기서만 정의한다

OUT = os.path.join(ROOT, "core", "roster.gd")


def esc(s: str) -> str:
	return s.replace("\\", "\\\\").replace('"', '\\"')


# 클립이 아직 없는 캐릭터의 총구·뻗는 시간. 마법사의 평균쯤에 맞춰 둔 어림수다.
# ★ 어림수라도 **발밑(0,0)보다는 언제나 낫다.** 클립이 없다고 탄이 발바닥에서 나가면
#   그 캐릭터만 다른 게임에서 온 것처럼 보인다.
MUZ_FALLBACK = (0.34, -0.80)
WIND_FALLBACK = 0.24


def muzzle_of(u: dict, art_h: int) -> tuple[float, float, float]:
	"""그 캐릭터의 총구 자리(그림 높이의 배수)와 팔을 뻗는 시간(초).

	★ **원본은 클립이다** — `art/anim/<id>/anim.json` 의 `muzzle_at`(기준점에서 잰 칸
	  좌표)과 `hit_ms`(놓는 칸까지 걸린 시간)를 그대로 읽어 그림 높이로 나눈다.
	  손으로 roster.json 에 또 적지 않는 이유는 뻔하다: 클립을 다시 짜면 총구가 옮겨
	  가는데 손으로 적은 숫자는 안 따라온다. 그러면 총구 불꽃만 팔끝에 있고 탄은
	  옛 자리에서 나가는, 아무도 못 잡는 어긋남이 된다.
	★ 클립이 없으면 어림수를 준다(위). 클립은 GPU 로 몇 시간이라 늘 다 있지는 않다.
	"""
	p = os.path.join(ROOT, "art", "anim", u["id"], "anim.json")
	if not (u.get("anim", False) and os.path.exists(p)):
		return MUZ_FALLBACK[0], MUZ_FALLBACK[1], WIND_FALLBACK
	with open(p, encoding="utf-8") as f:
		meta = json.load(f)
	mz = meta.get("muzzle_at")
	if not mz:
		return MUZ_FALLBACK[0], MUZ_FALLBACK[1], WIND_FALLBACK
	# ★ 나누는 것은 **그림 높이**다. 게임이 그림을 그릴 때 곱하는 배수가 딱 그것이라
	#   (Art.unit_h = h * sc * 화면배수), 높이로 나눠 두면 어느 화면에서 그리든 맞는다.
	h = float(meta.get("static", {}).get("h", art_h) or art_h)
	wind = float(meta.get("hit_ms", WIND_FALLBACK * 1000.0)) / 1000.0
	return float(mz["x"]) / h, float(mz["y"]) / h, wind


HELPERS = '''
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


## 그 몸을 가진 몬스터 전부. 보스는 빼고 준다 — 보스는 boss_of_body() 가 따로 낸다.
static func monsters_of_body(body: String) -> Array:
	var pool: Array = []
	for m in MONSTERS:
		if m["body"] == body and m["kind"] != "boss":
			pool.append(m)
	return pool


## 그 몸의 보스. 테마가 보스를 정한다 — 화산이면 불 보스, 설산이면 얼음 보스다.
static func boss_of_body(body: String) -> Dictionary:
	for m in MONSTERS:
		if m["kind"] == "boss" and m["body"] == body:
			return m
	# 표에 없으면 아무 보스나. 판이 멈추는 것보다 낫다.
	for m2 in MONSTERS:
		if m2["kind"] == "boss":
			return m2
	return {}


static func theme_by_id(id: String) -> Dictionary:
	for t in THEMES:
		if t["id"] == id:
			return t
	return {}


## 몸 분포(weights)에서 몸 하나를 뽑는다.
static func _pick_body(wt: Dictionary, rng: RandomNumberGenerator, skip: Array = []) -> String:
	var total := 0.0
	for b in Balance.MBODY_ORDER:
		if skip.has(b):
			continue
		total += float(wt.get(b, 0.0))
	if total <= 0.0:
		# 분포가 비었거나 전부 걸러졌다. 아무 몸이나 — 판이 멈추는 것보다 낫다.
		for b2 in Balance.MBODY_ORDER:
			if not skip.has(b2):
				return String(b2)
		return String(Balance.MBODY_ORDER[0])
	var r := rng.randf() * total
	for b3 in Balance.MBODY_ORDER:
		if skip.has(b3):
			continue
		r -= float(wt.get(b3, 0.0))
		if r <= 0.0:
			return String(b3)
	return String(Balance.MBODY_ORDER[Balance.MBODY_ORDER.size() - 1])


## 그 테마에서 w 탄에 나올 몬스터 종류(보스 제외). **같은 씨앗이면 언제 물어도 같은 답이다.**
##
## ★ 이것이 상성을 "운"이 아니라 "선택"으로 만드는 열쇠다. 씨앗과 탄 번호만으로 정해지므로
##   **상점이 다음 탄에 나올 몬스터를 정확히 보여 주고**, 플레이어는 그에 맞춰 성역을 짠다.
##   전투가 시작될 때 굴리면 상성은 피할 수 없는 사고가 된다.
##
## 주 속성은 반드시 포함하고 다른 속성도 최소 하나 섞는다.
## 실제 개체 수는 theme_spawns가 주 속성 70~80%로 배분한다.
##
## ★ 1~3탄에는 **느린 놈(육중·주술)을 넣지 않는다.** 육중형은 걷는 속도가 0.8배라 영웅
##   한둘로는 잡을 화력이 안 나오고, 첫 탄부터 크리스탈이 깨진다 — 게임을 켜자마자 벌을
##   받는 셈이다. 앞 세 탄은 무조건 막을 수 있어야 한다.
static func theme_kinds(w: int, theme: Dictionary, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var wt: Dictionary = theme.get("weights", {})
	# 한 탄에 몇 종을 섞을까. ★ 탄 번호를 못 박지 마라 — 40탄에서 100탄이 되면
	#   「후반」의 뜻이 통째로 달라진다. 비율로 적는다.
	var want: int = 2 if w < 6 else (3 if w < Balance.LAST_WAVE * 0.4 else 4)
	var out: Array = []
	var bodies: Array = []
	var main_body := String(theme.get("main_body", ""))
	var main_pool := _kind_pool(main_body, w)
	# 초반 면역 보호로 주 속성을 쓸 수 없는 옛 저장은 허용된 몸으로 진행한다.
	var main_want := mini(main_pool.size(), 1 if want == 2 else 2)
	for i in range(main_want):
		var pick := rng.randi_range(0, main_pool.size() - 1)
		out.append(main_pool.pop_at(pick))
	if not out.is_empty():
		bodies.append(main_body)
	var guard := 0
	while out.size() < want and guard < 400:
		guard += 1
		# 마지막 한 자리인데 아직 몸이 한 가지뿐이면 **다른 몸에서** 뽑는다.
		var skip: Array = []
		if out.size() == want - 1 and bodies.size() == 1:
			skip = bodies
		var body := _pick_body(wt, rng, skip)
		var pool := _kind_pool(body, w)
		if pool.is_empty():
			continue
		var m: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if out.has(m):
			continue
		out.append(m)
		if not bodies.has(body):
			bodies.append(body)
	if out.is_empty():
		out = wave_kinds_seeded(w, seed_value)
	return out


## 미리보기와 전투가 함께 쓰는 일반 몬스터 목록. 종류 수로 비율이 희석되지 않는다.
static func theme_spawns(w: int, theme: Dictionary, seed_value: int) -> Array:
	var kinds := theme_kinds(w, theme, seed_value)
	var main_body := String(theme.get("main_body", ""))
	var wt: Dictionary = theme.get("weights", {})
	var by_body: Dictionary = {}
	for monster in kinds:
		var body := String(monster["body"])
		if not by_body.has(body):
			by_body[body] = []
		by_body[body].append(monster)
	var count := Balance.wave_count(w)
	var main_count := 0
	if by_body.has(main_body):
		main_count = roundi(count * float(wt.get(main_body, 0.75)))
		if by_body.size() == 1:
			main_count = count
	var out: Array = []
	for i in range(main_count):
		out.append(by_body[main_body][i % by_body[main_body].size()])
	var side_bodies: Array = []
	var side_total := 0.0
	for body in by_body:
		if body != main_body:
			side_bodies.append(body)
			side_total += float(wt.get(body, 0.0))
	var remaining := count - main_count
	var amounts: Array[int] = []
	var fractions: Array[float] = []
	var assigned := 0
	for body in side_bodies:
		var share := float(wt.get(body, 0.0)) / side_total if side_total > 0.0 else 1.0 / side_bodies.size()
		var exact := remaining * share
		amounts.append(floori(exact))
		fractions.append(exact - floor(exact))
		assigned += floori(exact)
	for i in range(remaining - assigned):
		var best := 0
		for j in range(1, fractions.size()):
			if fractions[j] > fractions[best]:
				best = j
		amounts[best] += 1
		fractions[best] = -1.0
	for i in range(side_bodies.size()):
		var pool: Array = by_body[side_bodies[i]]
		for j in range(amounts[i]):
			out.append(pool[j % pool.size()])
	return out


## 그 몸에서 w 탄에 쓸 수 있는 몬스터.
##
## ★ 앞 **다섯** 탄에는 **면역을 가진 몸을 안 넣는다**(바위). 1탄에는 영웅이 **하나뿐**이라
##   그 하나가 전기면 바위에게 한 톨도 못 넣는다 — 피할 길이 없다. 편성을 미리 보여
##   줘도 소용없다. 바꿀 영웅이 없기 때문이다. 자동 플레이에서 실제로 1탄 평균
##   크리스탈 -0.58 로 나왔다(원래 1~6탄은 하나도 안 잃어야 한다).
## ★★ **셋에서 다섯으로 늘린 것은 캐릭터가 늘면서다.** 등급에 셋뿐이던 시절에는 앞
##   탄에 **같은 캐릭터를 두 번 뽑는 일이 흔했고**(1/3) 겹치면 화력이 곧 두 배였다.
##   여든이던 시절에는 그 확률이 1/8 까지 떨어져 **앞 탄의 겹침이 사실상 사라졌고**,
##   4탄에서 크리스탈이 깨지는 판이 열둘 중 하나씩 나왔다(`verify.sh` 7단계가 잡았다).
##   ☆ 지금은 등급마다 **다섯**이라 겹칠 확률이 1/5 로 되돌아왔다 — 그만큼 앞 탄이
##     다시 두꺼워졌으므로, 이 다섯 탄을 줄일 여지가 생기면 여기부터 재 봐라.
##   ☆ 몬스터를 더 얇게 하는 것으로는 안 풀린다. 전기 영웅에게 바위는 **0배**라,
##     얼마나 얇든 곱하면 0 이기 때문이다. 막을 수 있는 것은 「안 나오게」뿐이다.
## ★ 앞 세 탄에는 **느린 놈(육중·주술)도 안 넣는다.** 육중형은 걷는 속도가 0.8배라
##   영웅 한둘로는 잡을 화력이 안 나오고, 첫 탄부터 크리스탈이 깨진다 — 게임을
##   켜자마자 벌을 받는 셈이다. 앞 세 탄은 무조건 막을 수 있어야 한다.
static func _kind_pool(body: String, w: int) -> Array:
	if w <= 5 and not Balance.body_immune(body).is_empty():
		return []
	var pool: Array = []
	for m in monsters_of_body(body):
		if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
			continue
		# ★ 첫 두 탄은 **떼거리만** 나온다. 쾌속형은 걷는 속도가 1.7배라 열일곱 초면
		#   크리스탈에 닿는데, 그때 플레이어는 영웅이 **하나**다. 그 하나가 하필
		#   저항에 걸리는 속성이면(불 영웅 x 물·얼음 몸이면 둘 다 반) 화력이 절반이 되어
		#   막을 수가 없다 — 자동 플레이 24판에서 1탄 평균 크리스탈 -0.12 로 나왔다.
		#   첫 두 탄은 게임을 켠 사람이 처음 보는 장면이다. 거기서 벌을 주면 안 된다.
		if w <= 2 and m["kind"] != "swarm":
			continue
		pool.append(m)
	return pool


## 테마를 모르는 자리(가짜 Run 을 쓰는 검사기)가 쓰는 되돌림 길. 몸을 안 가리고 뽑는다.
static func wave_kinds_seeded(w: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return wave_kinds(w, rng)


static func wave_kinds(w: int, rng: RandomNumberGenerator) -> Array:
	var pool: Array = []
	for m in MONSTERS:
		if m["kind"] == "boss":
			continue
		if w <= 3 and (m["kind"] == "tank" or m["kind"] == "caster"):
			continue
		# 앞 세 탄에는 면역을 가진 몸을 안 넣는다 (_kind_pool 주석 참고).
		if w <= 3 and not Balance.body_immune(String(m["body"])).is_empty():
			continue
		pool.append(m)
	if pool.is_empty():
		pool = MONSTERS.duplicate()
	var out: Array = []
	var want: int = 2 if w < 6 else 3
	var guard := 0
	while out.size() < want and guard < 200:
		guard += 1
		var m2: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.has(m2):
			out.append(m2)
	return out


## 그 테마에 **나올 수 있는** 몬스터 전부(보스 제외). 난수를 안 쓴다.
## 씨앗을 모르는 자리(검사기·미리보기)에서 "이 테마에는 이런 놈들이 있다"를 보일 때 쓴다.
static func theme_pool(theme: Dictionary, w: int = 99) -> Array:
	var wt: Dictionary = theme.get("weights", {})
	var out: Array = []
	for b in Balance.MBODY_ORDER:
		if float(wt.get(b, 0.0)) <= 0.0:
			continue
		for m in _kind_pool(String(b), w):
			if not out.has(m):
				out.append(m)
	return out
'''


def main() -> int:
	with open(os.path.join(ROOT, "tools", "roster.json"), encoding="utf-8") as f:
		r = json.load(f)

	lines: list[str] = []
	w = lines.append
	w("extends RefCounted")
	w("class_name Roster")
	w("")
	w("## 캐릭터·몬스터·테마 표. **자동 생성 파일이다 — 손으로 고치지 마라.**")
	w("## 원본은 tools/roster.json 이고, `python3 tools/gen_roster.py` 가 이 파일을 찍어 낸다.")
	w("## h(그림 높이)는 tools/gen_art.py 가 실제로 저장하는 크기와 같은 값이다.")
	w("")
	w("## 등급별 이름. 인덱스가 Poker.Hand 값과 같다.")
	tier_ko = ", ".join('"%s"' % esc(t["ko"]) for t in r["tiers"])
	w("const TIER_KO := [%s]" % tier_ko)
	w("")

	n_units = sum(len(t["units"]) for t in r["tiers"])
	per = sorted({len(t["units"]) for t in r["tiers"]})
	w("## 캐릭터 %d명(등급마다 %s). tier 는 Poker.Hand 값이다."
	  % (n_units, "여덟" if per == [8] else "·".join(str(x) for x in per)))
	w("##")
	w("## sc 는 **그림 크기 보정**이다. gen_art.py 는 그림을 등급마다 같은 높이로 저장하는데,")
	w("## 그 높이는 지팡이·꼬리·회오리까지 포함한 **테두리 상자**의 높이다. 그래서 소품이 큰")
	w("## 캐릭터는 사람 몸이 그만큼 작게 나온다 — 같은 등급인데 누구는 크고 누구는 작아 보인다.")
	w("## sc 가 그 몫을 되돌린다(1.0 이 보정 없음). 값은 tools/roster.json 에 손으로 적는다.")
	w("##")
	w("## role 은 **역할** 넷 중 하나다(Balance.ROLE) — 사용자가 정한 축이다:")
	w("##   single 일격 · ricochet 도탄 · rider 특효 · area 광역.")
	w("##   ★ 방식(bullet)과 **다른 축**이다. 방식은 「어떻게 닿는가」이고 역할은 「무엇으로")
	w("##   값을 하는가」다 — 같은 shot 이라도 일격은 한 대가 무겁고(x1.26) 특효는 가벼운")
	w("##   대신(x0.74) 상태이상이 2.2배다. **역할은 무기가 정한다** — 검·총=일격 · 활=도탄 · 채찍=특효 · 광역=광역.")
	w("##")
	w("## weapon 은 손에 든 것이다. ★ **자세가 여기서 나온다** — gen_art.pose_for() 가")
	w("##   활·석궁·총·대포는 겨누는 3/4 옆면으로, 던지는 것은 뒤로 당긴 자세로, 나머지는")
	w("##   한 팔을 앞으로 뻗은 시전 자세로 뽑는다. **광역(zone)만은 무기와 상관없이")
	w("##   두 팔을 머리 위로 든다**(사용자가 정한 연출).")
	w("##")
	w("## elem 은 **공격 속성**이다(Balance.ELEM). 무상성(none)은 어떤 몸에도 1.0 배 —")
	w("## 활·총·대포·표창이 여기 든다. 나머지 넷은 몬스터의 몸(Balance.MBODY)에 따라")
	w("## 2배(약점)·0.5배(저항)·0배(면역)가 된다. 곱하는 곳은 BattleSim._hurt() 한 군데뿐이다.")
	w("## ★ **속성이 상태이상도 정한다** — 얼음은 늦추고, 불은 태우고, 전기는 확률로 마비시킨다.")
	w("##")
	w("## en 은 **화면에 뜨는 이름**이다(영문). ko 는 설명 팝업에만 부제로 남는다 —")
	w("## 이름이 두 곳에 있으면 반드시 한 곳만 고치게 되므로, 화면은 en 하나만 본다.")
	w("## lore 는 설명 팝업에 뜨는 한 줄 소개다.")
	w("##")
	w("## anim 은 Idle/Attack/Shot 클립 묶음이 있는 곳이다. 없으면 빈 문자열이고,")
	w("## 그때는 정지 그림(art) 한 장만 쓴다 — 그림이 아직 안 나온 캐릭터도 게임은 돈다.")
	w("##")
	w("## muz 는 **탄이 나가는 자리**다 — 발밑 가운데에서 잰 [가로, 세로]이고 단위는 그림")
	w("## 높이(h)의 배수다. 세로는 위가 음수다. **가로의 부호가 곧 그림이 바라보는 쪽**이라")
	w("## 음수면 왼쪽을 겨눈 그림이고, 화면이 그런 그림만 좌우로 뒤집어 목표를 보게 한다.")
	w("## ★ 손으로 적은 값이 아니라 클립의 **놓는 칸**에서 그대로 잰 값이다")
	w("##   (art/anim/<id>/anim.json 의 muzzle_at). 그래서 총구 불꽃과 탄이 늘 같은 자리다.")
	w("## wind 는 팔을 뻗는 데 걸리는 시간(초) — 그 클립이 놓는 칸에 닿는 데 걸리는 시간이다.")
	w("## 전투는 쏘기로 정한 뒤 이만큼 **기다렸다가** 탄을 내보낸다. 안 그러면 팔을 뻗기도")
	w("## 전에 탄이 나가서 몸짓과 사건이 따로 논다.")
	w("const UNITS := [")
	for ti, t in enumerate(r["tiers"]):
		w("\t# --- %s ---" % t["ko"])
		for u in t["units"]:
			anim = 'res://art/anim/%s/' % u["id"] if u.get("anim", False) else ""
			mx, my, wind = muzzle_of(u, gen_art.unit_h(ti))
			w('\t{"id": "%s", "ko": "%s", "en": "%s", "tier": %d, "role": "%s", '
			  '"profile": "%s", "bullet": "%s", "weapon": "%s", '
			  '"elem": "%s", "desc": "%s", "lore": "%s", "color": "%s", "h": %d, "sc": %.2f, '
			  '"muz": [%.4f, %.4f], "wind": %.3f, '
			  '"art": "res://art/units/%s.png", "anim": "%s"},'
			  % (u["id"], esc(u["ko"]), esc(u.get("en", u["ko"])), ti,
				 u.get("role", "single"), u["profile"], u["bullet"],
				 u.get("weapon", ""),
				 u.get("elem", "none"), esc(u["desc"]), esc(u.get("lore", u["desc"])),
				 u["color"], gen_art.unit_h(ti), float(u.get("sc", 1.0)),
				 mx, my, wind, u["id"], anim))
	w("]")
	w("")

	w("## 몬스터 %d종. body 는 **몸 속성** 다섯 가지 중 하나다(Balance.MBODY) —" % len(r["monsters"]))
	w("## aqua 물 · flame 불 · wood 나무 · rock 바위 · frost 얼음.")
	w("## ★ 몸 다섯 × 형 넷 = 스무 종에 보스 다섯이다. 형(kind)이 체력·속도를 정하고")
	w("##   몸(body)이 상성을 정한다 — 둘은 서로 아무 상관이 없는 축이다.")
	w("const MONSTERS := [")
	for m in r["monsters"]:
		w('\t{"id": "%s", "ko": "%s", "kind": "%s", "body": "%s", '
		  '"desc": "%s", "color": "%s", "h": %d, "art": "res://art/monsters/%s.png", '
		  '"anim": "res://art/anim/monsters/%s/"},'
		  % (m["id"], esc(m["ko"]), m["kind"], m["body"],
			 esc(m["desc"]), m["color"], gen_art.MON_H[m["kind"]], m["id"], m["id"]))
	w("]")
	w("")

	themes = r.get("themes", [])
	w("## 테마 %d개. **열 탄이 한 테마**이고 그 열 번째 탄이 보스맵이다." % len(themes))
	w("##")
	w("## weights 는 다섯 몸의 등장 확률이고 합이 1.0 이다. 「호수면 물 몬스터가 많이 나온다」가")
	w("## 주 속성은 70~80%, 나머지는 테마의 보조 속성 비율이다. 보스는 항상 주 속성이다.")
	w("## theme_spawns가 실제 개체 수로 배분하며, 첫 테마는 초반 면역 보호와 맞춰 선택한다.")
	w("##")
	w("## rank(1~5)는 그곳이 얼마나 험한가다. 체력에 곱해지고(Balance.theme_hp), 뒤 블록일수록")
	w("## 높은 rank 가 걸린다(Run.roll_themes). 사용자가 정한 「뒤로 갈수록 세진다」가 이것이다.")
	w("const THEMES := [")
	for th in themes:
		wt = th["weights"]
		assert th["boss_body"] == th["main_body"], f'{th["id"]}: boss must match theme'
		w('\t{"id": "%s", "ko": "%s", "main_body": "%s", "boss_body": "%s", "rank": %d, '
		  '"weights": {"aqua": %.2f, "flame": %.2f, "wood": %.2f, "rock": %.2f, "frost": %.2f}, '
		  '"bg": "%s", "floor": "%s", '
		  '"art_bg": "res://art/themes/%s_bg.png", "art_floor": "res://art/themes/%s_floor.png"},'
		  % (th["id"], esc(th["ko"]), th["main_body"], th["boss_body"], int(th["rank"]),
			 wt["aqua"], wt["flame"], wt["wood"], wt["rock"], wt["frost"],
			 th["bg"], th["floor"], th["id"], th["id"]))
	w("]")
	w("")

	w("## 화면을 채우는 그림들.")
	w("const ART := {")
	for a in r["arts"]:
		w('\t"%s": "%s",' % (a["id"], esc(a.get("art", "res://art/ui/%s.png" % a["id"]))))
	w("}")
	w("")
	w(HELPERS)
	w("")

	content = "\n".join(lines).rstrip() + "\n"
	if "--check" in sys.argv:
		with open(OUT, encoding="utf-8") as f:
			current = f.read()
		if current != content:
			print("로스터가 낡았습니다. python3 tools/gen_roster.py를 실행하세요.")
			return 1
		print("로스터 일치")
		return 0
	with open(OUT, "w", encoding="utf-8") as f:
		f.write(content)
	print("만들었습니다: %s (%d줄, 캐릭터 %d · 몬스터 %d · 테마 %d)"
		  % (OUT, len(lines), n_units, len(r["monsters"]), len(themes)))
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
