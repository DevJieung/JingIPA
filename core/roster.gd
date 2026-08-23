extends RefCounted
class_name Roster

## 캐릭터·몬스터 표. **자동 생성 파일이다 — 손으로 고치지 마라.**
## 원본은 tools/roster.json 이고, `python3 tools/gen_roster.py` 가 이 파일을 찍어 낸다.
## h(그림 높이)는 tools/gen_art.py 가 실제로 저장하는 크기와 같은 값이다.

## 등급별 이름. 인덱스가 Poker.Hand 값과 같다.
const TIER_KO := ["하이카드", "원페어", "투페어", "트리플", "스트레이트", "플러시", "풀하우스", "포카드", "스트레이트플러시", "로열플러시"]

## 캐릭터 31명. tier 는 Poker.Hand 값이다.
##
## sc 는 **그림 크기 보정**이다. gen_art.py 는 그림을 등급마다 같은 높이로 저장하는데,
## 그 높이는 지팡이·꼬리·회오리까지 포함한 **테두리 상자**의 높이다. 그래서 소품이 큰
## 캐릭터는 사람 몸이 그만큼 작게 나온다 — 같은 등급인데 누구는 크고 누구는 작아 보인다.
## sc 가 그 몫을 되돌린다(1.0 이 보정 없음). 값은 tools/roster.json 에 손으로 적는다.
##
## elem 은 **공격 속성**이다(Balance.ELEM). 무상성(none)은 어떤 몸에도 1.0 배 —
## 활·총·대포·표창이 여기 든다. 나머지 넷은 몬스터의 몸(Balance.MBODY)에 따라
## 2배(약점)나 0.5배(저항)가 된다. 곱하는 곳은 BattleSim._hurt() 한 군데뿐이다.
const UNITS := [
	# --- 하이카드 ---
	{"id": "straw_archer", "ko": "짚신궁수", "tier": 0, "profile": "rapid", "bullet": "shot", "elem": "none", "desc": "낡은 활을 쉼 없이 쏜다", "color": "#CFC06B", "h": 96, "sc": 1.00, "art": "res://art/units/straw_archer.png"},
	{"id": "ember_apprentice", "ko": "불씨견습", "tier": 0, "profile": "balance", "bullet": "burn", "elem": "fire", "desc": "손끝 불씨로 태운다", "color": "#FFB24A", "h": 96, "sc": 1.00, "art": "res://art/units/ember_apprentice.png"},
	{"id": "puddle_boy", "ko": "물장난꾼", "tier": 0, "profile": "rapid", "bullet": "slow", "elem": "water", "desc": "물을 뿌려 미끄러뜨린다", "color": "#2EB9FF", "h": 96, "sc": 1.00, "art": "res://art/units/puddle_boy.png"},
	# --- 원페어 ---
	{"id": "bolt_scout", "ko": "쇠뇌정찰병", "tier": 1, "profile": "rapid", "bullet": "pierce", "elem": "none", "desc": "작은 쇠뇌를 연사한다", "color": "#9ACC62", "h": 101, "sc": 1.00, "art": "res://art/units/bolt_scout.png"},
	{"id": "frost_novice", "ko": "서리도제", "tier": 1, "profile": "balance", "bullet": "slow", "elem": "ice", "desc": "얼려서 몬스터를 느리게", "color": "#6FD0F5", "h": 101, "sc": 0.98, "art": "res://art/units/frost_novice.png"},
	{"id": "match_gunner", "ko": "화승총병", "tier": 1, "profile": "heavy", "bullet": "shot", "elem": "none", "desc": "화승총 한 방이 무겁다", "color": "#DBAB7B", "h": 101, "sc": 1.06, "art": "res://art/units/match_gunner.png"},
	# --- 투페어 ---
	{"id": "shuriken_ninja", "ko": "표창닌자", "tier": 2, "profile": "rapid", "bullet": "pierce", "elem": "none", "desc": "표창을 뿌리듯 던진다", "color": "#6FBEC7", "h": 106, "sc": 1.00, "art": "res://art/units/shuriken_ninja.png"},
	{"id": "spark_mage", "ko": "전격술사", "tier": 2, "profile": "balance", "bullet": "chain", "elem": "elec", "desc": "번개 구슬이 튕겨 다닌다", "color": "#96FA00", "h": 106, "sc": 1.10, "art": "res://art/units/spark_mage.png"},
	{"id": "field_mortar", "ko": "야전박격포병", "tier": 2, "profile": "heavy", "bullet": "splash", "elem": "none", "desc": "박격포로 넓게 터뜨린다", "color": "#E67ECF", "h": 106, "sc": 1.06, "art": "res://art/units/field_mortar.png"},
	# --- 트리플 ---
	{"id": "longbow_ranger", "ko": "장궁수", "tier": 3, "profile": "sniper", "bullet": "pierce", "elem": "none", "desc": "키만 한 활로 꿰뚫는다", "color": "#23B82F", "h": 111, "sc": 1.12, "art": "res://art/units/longbow_ranger.png"},
	{"id": "flame_mage", "ko": "화염술사", "tier": 3, "profile": "rapid", "bullet": "burn", "elem": "fire", "desc": "불덩이를 던져 태운다", "color": "#F57520", "h": 111, "sc": 1.08, "art": "res://art/units/flame_mage.png"},
	{"id": "tide_monk", "ko": "파도승", "tier": 3, "profile": "balance", "bullet": "splash", "elem": "water", "desc": "물벼락을 불러 터뜨린다", "color": "#0F35D6", "h": 111, "sc": 1.10, "art": "res://art/units/tide_monk.png"},
	# --- 스트레이트 ---
	{"id": "rifle_marksman", "ko": "장총저격수", "tier": 4, "profile": "sniper", "bullet": "shot", "elem": "none", "desc": "긴 화승총으로 한 발씩", "color": "#AD8CDB", "h": 116, "sc": 1.02, "art": "res://art/units/rifle_marksman.png"},
	{"id": "frost_witch", "ko": "서리마녀", "tier": 4, "profile": "heavy", "bullet": "slow", "elem": "ice", "desc": "얼음 창을 무겁게 박는다", "color": "#0C5FCC", "h": 116, "sc": 1.14, "art": "res://art/units/frost_witch.png"},
	{"id": "blast_ninja", "ko": "폭탄닌자", "tier": 4, "profile": "rapid", "bullet": "splash", "elem": "fire", "desc": "불붙은 수리검을 흩뿌린다", "color": "#F0433A", "h": 116, "sc": 1.04, "art": "res://art/units/blast_ninja.png"},
	# --- 플러시 ---
	{"id": "storm_shaman", "ko": "폭풍주술사", "tier": 5, "profile": "balance", "bullet": "chain", "elem": "elec", "desc": "먹구름에서 번개가 튄다", "color": "#F0E91D", "h": 121, "sc": 1.12, "art": "res://art/units/storm_shaman.png"},
	{"id": "siege_cannon", "ko": "공성포병", "tier": 5, "profile": "heavy", "bullet": "splash", "elem": "none", "desc": "대포로 여럿을 터뜨린다", "color": "#879CC7", "h": 121, "sc": 1.04, "art": "res://art/units/siege_cannon.png"},
	{"id": "hail_shaman", "ko": "우박주술사", "tier": 5, "profile": "rapid", "bullet": "aura", "elem": "ice", "desc": "우박을 뿌려 얼린다", "color": "#94C2FF", "h": 121, "sc": 1.08, "art": "res://art/units/hail_shaman.png"},
	{"id": "volt_sniper", "ko": "뇌격저격수", "tier": 5, "profile": "sniper", "bullet": "beam", "elem": "elec", "desc": "번개를 재워 멀리 쏜다", "color": "#DBA8F0", "h": 121, "sc": 1.10, "art": "res://art/units/volt_sniper.png"},
	# --- 풀하우스 ---
	{"id": "steel_tank", "ko": "강철전차", "tier": 6, "profile": "heavy", "bullet": "splash", "elem": "none", "desc": "포탑을 돌려 포격한다", "color": "#E0687E", "h": 126, "sc": 0.88, "art": "res://art/units/steel_tank.png"},
	{"id": "inferno_mage", "ko": "지옥불술사", "tier": 6, "profile": "balance", "bullet": "burn", "elem": "fire", "desc": "불바다를 만들어 태운다", "color": "#CC2176", "h": 126, "sc": 1.12, "art": "res://art/units/inferno_mage.png"},
	{"id": "rain_shaman", "ko": "비구름주술사", "tier": 6, "profile": "rapid", "bullet": "aura", "elem": "water", "desc": "비구름으로 물장판을 깐다", "color": "#457AE6", "h": 126, "sc": 1.12, "art": "res://art/units/rain_shaman.png"},
	{"id": "mist_ninja", "ko": "물안개닌자", "tier": 6, "profile": "sniper", "bullet": "pierce", "elem": "water", "desc": "물안개 속 표창을 던진다", "color": "#11D1A4", "h": 126, "sc": 1.00, "art": "res://art/units/mist_ninja.png"},
	# --- 포카드 ---
	{"id": "railgun_ranger", "ko": "전자포수", "tier": 7, "profile": "sniper", "bullet": "beam", "elem": "elec", "desc": "번개 광선으로 멀리 저격", "color": "#EAF0B6", "h": 131, "sc": 1.06, "art": "res://art/units/railgun_ranger.png"},
	{"id": "glacier_shaman", "ko": "빙하주술사", "tier": 7, "profile": "heavy", "bullet": "splash", "elem": "ice", "desc": "빙하를 떨궈 터뜨린다", "color": "#049AD1", "h": 131, "sc": 1.16, "art": "res://art/units/glacier_shaman.png"},
	{"id": "magma_gunner", "ko": "용암포병", "tier": 7, "profile": "balance", "bullet": "burn", "elem": "fire", "desc": "용암탄으로 불태운다", "color": "#D64F0B", "h": 131, "sc": 1.00, "art": "res://art/units/magma_gunner.png"},
	# --- 스트레이트플러시 ---
	{"id": "tempest_shaman", "ko": "태풍주술사", "tier": 8, "profile": "balance", "bullet": "aura", "elem": "elec", "desc": "태풍 장판으로 감전시킨다", "color": "#D2FA8E", "h": 136, "sc": 1.16, "art": "res://art/units/tempest_shaman.png"},
	{"id": "siege_walker", "ko": "공성보행포", "tier": 8, "profile": "heavy", "bullet": "splash", "elem": "none", "desc": "일제 포격으로 쓸어버린다", "color": "#23917A", "h": 136, "sc": 0.92, "art": "res://art/units/siege_walker.png"},
	{"id": "moon_archer", "ko": "달빛궁수", "tier": 8, "profile": "sniper", "bullet": "beam", "elem": "ice", "desc": "달빛 화살로 얼려 뚫는다", "color": "#D3C9F5", "h": 136, "sc": 1.12, "art": "res://art/units/moon_archer.png"},
	# --- 로열플러시 ---
	{"id": "spade_monarch", "ko": "스페이드왕", "tier": 9, "profile": "heavy", "bullet": "aura", "elem": "none", "desc": "빛 폭풍으로 주변을 쓸어버린다", "color": "#FFC630", "h": 141, "sc": 0.92, "art": "res://art/units/spade_monarch.png"},
	{"id": "prism_empress", "ko": "다이아 여왕", "tier": 9, "profile": "sniper", "bullet": "beam", "elem": "ice", "desc": "얼음 광선으로 멀리 저격", "color": "#8FE9FF", "h": 141, "sc": 0.98, "art": "res://art/units/prism_empress.png"},
]

## 몬스터 14종. body 는 **몸 속성**이다 — 무엇에 약하고 무엇을 튕겨 내는가
## (Balance.MBODY). null 은 상성을 아예 안 타는 몬스터다.
const MONSTERS := [
	{"id": "slime_blob", "ko": "초록슬라임", "kind": "swarm", "stage": "early", "body": "aqua", "desc": "느릿느릿 굴러오는 잡몹", "color": "#57E04A", "h": 52, "art": "res://art/monsters/slime_blob.png"},
	{"id": "cave_bat", "ko": "동굴박쥐", "kind": "fast", "stage": "early", "body": "beast", "desc": "파닥이며 빠르게 달려든다", "color": "#9B7BE8", "h": 48, "art": "res://art/monsters/cave_bat.png"},
	{"id": "spore_cap", "ko": "포자버섯", "kind": "caster", "stage": "early", "body": "plant", "desc": "멀리서 포자를 뿜는다", "color": "#FF5C7A", "h": 58, "art": "res://art/monsters/spore_cap.png"},
	{"id": "shell_bug", "ko": "딱정벌레", "kind": "tank", "stage": "early", "body": "stone", "desc": "껍질이 단단해 안 죽는다", "color": "#35B9C4", "h": 68, "art": "res://art/monsters/shell_bug.png"},
	{"id": "goblin", "ko": "고블린", "kind": "swarm", "stage": "mid", "body": "null", "desc": "단검 들고 떼로 몰려온다", "color": "#B9D93C", "h": 52, "art": "res://art/monsters/goblin.png"},
	{"id": "bone_soldier", "ko": "해골병사", "kind": "tank", "stage": "mid", "body": "undead", "desc": "녹슨 칼을 든 뼈다귀", "color": "#EDE6CE", "h": 68, "art": "res://art/monsters/bone_soldier.png"},
	{"id": "dire_wolf", "ko": "사나운늑대", "kind": "fast", "stage": "mid", "body": "beast", "desc": "엄청 빠르게 파고든다", "color": "#7FA8E8", "h": 48, "art": "res://art/monsters/dire_wolf.png"},
	{"id": "kobold_bow", "ko": "코볼트궁수", "kind": "caster", "stage": "mid", "body": "flame", "desc": "멀리서 불화살을 쏜다", "color": "#F2A03D", "h": 58, "art": "res://art/monsters/kobold_bow.png"},
	{"id": "orc_brute", "ko": "오크전사", "kind": "tank", "stage": "late", "body": "beast", "desc": "도끼를 휘두르는 덩치", "color": "#C0452F", "h": 68, "art": "res://art/monsters/orc_brute.png"},
	{"id": "stone_golem", "ko": "돌골렘", "kind": "tank", "stage": "late", "body": "stone", "desc": "느리지만 아주 튼튼하다", "color": "#C89B5A", "h": 68, "art": "res://art/monsters/stone_golem.png"},
	{"id": "hex_witch", "ko": "마녀", "kind": "caster", "stage": "late", "body": "arcane", "desc": "저주 구슬을 날린다", "color": "#C64BE8", "h": 58, "art": "res://art/monsters/hex_witch.png"},
	{"id": "wraith", "ko": "망령", "kind": "fast", "stage": "late", "body": "undead", "desc": "스르륵 빠르게 스쳐간다", "color": "#5FEFC6", "h": 48, "art": "res://art/monsters/wraith.png"},
	{"id": "flame_dragon", "ko": "화염용", "kind": "boss", "stage": "boss", "body": "dragon", "desc": "불을 뿜는 거대한 용", "color": "#FF5A16", "h": 132, "art": "res://art/monsters/flame_dragon.png"},
	{"id": "demon_king", "ko": "트럼프마왕", "kind": "boss", "stage": "boss", "body": "null", "desc": "카드 세계의 최종보스", "color": "#FF2D55", "h": 132, "art": "res://art/monsters/demon_king.png"},
]

## 화면을 채우는 그림들.
const ART := {
	"arena_floor": "res://art/ui/arena_floor.png",
	"arena_bg": "res://art/ui/arena_bg.png",
	"card_back": "res://art/ui/card_back.png",
	"title_art": "res://art/ui/title_art.png",
	"coin": "res://art/ui/coin.png",
	"heart": "res://art/ui/heart.png",
	"shop_bg": "res://art/ui/shop_bg.png",
	"boom": "res://art/ui/boom.png",
}


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


static func _mix_for(w: int) -> Dictionary:
	if w >= 1 and w <= 8:
		return {"early": 1.0}
	if w >= 9 and w <= 18:
		return {"early": 0.35, "mid": 0.65}
	if w >= 19 and w <= 26:
		return {"mid": 0.65, "late": 0.35}
	if w >= 27 and w <= 34:
		return {"mid": 0.25, "late": 0.75}
	if w >= 35 and w <= 99:
		return {"late": 1.0}
	return {"late": 1.0}
