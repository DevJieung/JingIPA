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
const UNITS := [
	# --- 하이카드 ---
	{"id": "broom_maid", "ko": "빗자루꾼", "tier": 0, "profile": "rapid", "bullet": "shot", "desc": "빗자루로 먼지를 쏜다", "color": "#7CE04F", "h": 96, "sc": 1.14, "art": "res://art/units/broom_maid.png"},
	{"id": "bubble_boy", "ko": "비누꼬마", "tier": 0, "profile": "rapid", "bullet": "slow", "desc": "비눗물로 미끄러뜨린다", "color": "#45D2F2", "h": 96, "sc": 1.06, "art": "res://art/units/bubble_boy.png"},
	{"id": "taffy_gran", "ko": "엿할멈", "tier": 0, "profile": "balance", "bullet": "slow", "desc": "끈적한 엿으로 묶는다", "color": "#C77DFF", "h": 96, "sc": 1.10, "art": "res://art/units/taffy_gran.png"},
	# --- 원페어 ---
	{"id": "briar_hunter", "ko": "덤불사냥꾼", "tier": 1, "profile": "rapid", "bullet": "pierce", "desc": "쇠뇌로 빠르게 연사한다", "color": "#3FA65C", "h": 101, "sc": 1.00, "art": "res://art/units/briar_hunter.png"},
	{"id": "frost_novice", "ko": "서리도제", "tier": 1, "profile": "balance", "bullet": "slow", "desc": "얼려서 몬스터를 느리게", "color": "#74DFFF", "h": 101, "sc": 0.98, "art": "res://art/units/frost_novice.png"},
	{"id": "ember_smith", "ko": "불씨대장", "tier": 1, "profile": "heavy", "bullet": "shot", "desc": "큰 망치로 한 방에 부순다", "color": "#FF7A33", "h": 101, "sc": 1.02, "art": "res://art/units/ember_smith.png"},
	# --- 투페어 ---
	{"id": "steel_lancer", "ko": "강철창병", "tier": 2, "profile": "heavy", "bullet": "pierce", "desc": "긴 창으로 꿰뚫는다", "color": "#9AD7FF", "h": 106, "sc": 1.00, "art": "res://art/units/steel_lancer.png"},
	{"id": "bolt_ranger", "ko": "석궁사수", "tier": 2, "profile": "sniper", "bullet": "shot", "desc": "멀리서 화살을 쏜다", "color": "#5FE08C", "h": 106, "sc": 1.00, "art": "res://art/units/bolt_ranger.png"},
	{"id": "ward_shaman", "ko": "부적술사", "tier": 2, "profile": "rapid", "bullet": "slow", "desc": "부적으로 발을 묶는다", "color": "#B98CFF", "h": 106, "sc": 1.14, "art": "res://art/units/ward_shaman.png"},
	# --- 트리플 ---
	{"id": "steel_arbalest", "ko": "강철석궁수", "tier": 3, "profile": "sniper", "bullet": "pierce", "desc": "먼 적을 꿰뚫는 저격수", "color": "#AEBFCF", "h": 111, "sc": 1.02, "art": "res://art/units/steel_arbalest.png"},
	{"id": "mace_warden", "ko": "망치 기사", "tier": 3, "profile": "heavy", "bullet": "splash", "desc": "망치로 땅을 내려찍는다", "color": "#FFC53D", "h": 111, "sc": 0.92, "art": "res://art/units/mace_warden.png"},
	{"id": "ember_adept", "ko": "불꽃 술사", "tier": 3, "profile": "rapid", "bullet": "burn", "desc": "불을 붙여 계속 태운다", "color": "#FF5A2D", "h": 111, "sc": 1.00, "art": "res://art/units/ember_adept.png"},
	# --- 스트레이트 ---
	{"id": "pike_captain", "ko": "장창기사", "tier": 4, "profile": "sniper", "bullet": "pierce", "desc": "긴 창으로 멀리서 꿰뚫는다", "color": "#5EC8F5", "h": 116, "sc": 1.10, "art": "res://art/units/pike_captain.png"},
	{"id": "onyx_breaker", "ko": "검은망치", "tier": 4, "profile": "heavy", "bullet": "splash", "desc": "큰 망치로 내리쳐 터뜨린다", "color": "#B06CF5", "h": 116, "sc": 1.06, "art": "res://art/units/onyx_breaker.png"},
	{"id": "spark_adept", "ko": "뇌전술사", "tier": 4, "profile": "rapid", "bullet": "chain", "desc": "번개가 적들에게 튄다", "color": "#FFD84D", "h": 116, "sc": 1.16, "art": "res://art/units/spark_adept.png"},
	# --- 플러시 ---
	{"id": "ember_titan", "ko": "잿불거인", "tier": 5, "profile": "heavy", "bullet": "burn", "desc": "불덩이로 태워버리는 거인", "color": "#FF5A2B", "h": 121, "sc": 0.90, "art": "res://art/units/ember_titan.png"},
	{"id": "tide_caller", "ko": "파도술사", "tier": 5, "profile": "balance", "bullet": "splash", "desc": "물벼락을 터뜨리는 술사", "color": "#2E9BFF", "h": 121, "sc": 1.10, "art": "res://art/units/tide_caller.png"},
	{"id": "gale_dancer", "ko": "바람춤꾼", "tier": 5, "profile": "rapid", "bullet": "aura", "desc": "회오리를 두르고 도는 춤꾼", "color": "#6BF0C8", "h": 121, "sc": 1.10, "art": "res://art/units/gale_dancer.png"},
	{"id": "bolt_lancer", "ko": "번개창잡이", "tier": 5, "profile": "sniper", "bullet": "chain", "desc": "번개를 멀리 튕겨 보내는 창잡이", "color": "#FFD62E", "h": 121, "sc": 1.06, "art": "res://art/units/bolt_lancer.png"},
	# --- 풀하우스 ---
	{"id": "drake_knight", "ko": "용기사", "tier": 6, "profile": "heavy", "bullet": "burn", "desc": "불꽃 대검으로 내리찍는다", "color": "#FF5A1F", "h": 126, "sc": 0.94, "art": "res://art/units/drake_knight.png"},
	{"id": "halo_saint", "ko": "성녀", "tier": 6, "profile": "balance", "bullet": "aura", "desc": "주위에 황금 빛 장판을 깐다", "color": "#FFD966", "h": 126, "sc": 1.00, "art": "res://art/units/halo_saint.png"},
	{"id": "arc_duelist", "ko": "마검사", "tier": 6, "profile": "rapid", "bullet": "chain", "desc": "번개가 적들 사이로 튄다", "color": "#A855F7", "h": 126, "sc": 1.00, "art": "res://art/units/arc_duelist.png"},
	{"id": "ninetail_fox", "ko": "구미호", "tier": 6, "profile": "sniper", "bullet": "beam", "desc": "먼 데서 여우불 광선을 쏜다", "color": "#3BE8FF", "h": 126, "sc": 1.00, "art": "res://art/units/ninetail_fox.png"},
	# --- 포카드 ---
	{"id": "storm_seraph", "ko": "번개천사", "tier": 7, "profile": "balance", "bullet": "chain", "desc": "사슬번개로 여럿 감전", "color": "#7DF9FF", "h": 131, "sc": 0.90, "art": "res://art/units/storm_seraph.png"},
	{"id": "solar_archon", "ko": "태양궁수", "tier": 7, "profile": "sniper", "bullet": "beam", "desc": "빛줄기로 멀리 저격", "color": "#FFC933", "h": 131, "sc": 1.08, "art": "res://art/units/solar_archon.png"},
	{"id": "magma_titan", "ko": "불꽃거인", "tier": 7, "profile": "heavy", "bullet": "splash", "desc": "내려쳐서 땅을 폭발", "color": "#FF3B0D", "h": 131, "sc": 0.96, "art": "res://art/units/magma_titan.png"},
	# --- 스트레이트플러시 ---
	{"id": "astral_lance", "ko": "별빛창", "tier": 8, "profile": "sniper", "bullet": "beam", "desc": "별빛 창으로 멀리 뚫는다", "color": "#6FE3FF", "h": 136, "sc": 1.04, "art": "res://art/units/astral_lance.png"},
	{"id": "abyss_binder", "ko": "어둠사슬", "tier": 8, "profile": "heavy", "bullet": "chain", "desc": "사슬을 던져 줄줄이 묶는다", "color": "#A45CFF", "h": 136, "sc": 0.86, "art": "res://art/units/abyss_binder.png"},
	{"id": "time_keeper", "ko": "시간지기", "tier": 8, "profile": "balance", "bullet": "aura", "desc": "둘레에 시간 고리를 편다", "color": "#FFC24A", "h": 136, "sc": 0.96, "art": "res://art/units/time_keeper.png"},
	# --- 로열플러시 ---
	{"id": "spade_monarch", "ko": "스페이드왕", "tier": 9, "profile": "heavy", "bullet": "aura", "desc": "빛 폭풍으로 주변을 쓸어버린다", "color": "#FFC630", "h": 141, "sc": 0.92, "art": "res://art/units/spade_monarch.png"},
	{"id": "prism_empress", "ko": "다이아 여왕", "tier": 9, "profile": "sniper", "bullet": "beam", "desc": "먼 곳까지 빛줄기로 저격", "color": "#FF4FA3", "h": 141, "sc": 0.98, "art": "res://art/units/prism_empress.png"},
]

## 몬스터 14종.
const MONSTERS := [
	{"id": "slime_blob", "ko": "초록슬라임", "kind": "swarm", "stage": "early", "desc": "느릿느릿 굴러오는 잡몹", "color": "#57E04A", "h": 52, "art": "res://art/monsters/slime_blob.png"},
	{"id": "cave_bat", "ko": "동굴박쥐", "kind": "fast", "stage": "early", "desc": "파닥이며 빠르게 달려든다", "color": "#9B7BE8", "h": 48, "art": "res://art/monsters/cave_bat.png"},
	{"id": "spore_cap", "ko": "포자버섯", "kind": "caster", "stage": "early", "desc": "멀리서 포자를 뿜는다", "color": "#FF5C7A", "h": 58, "art": "res://art/monsters/spore_cap.png"},
	{"id": "shell_bug", "ko": "딱정벌레", "kind": "tank", "stage": "early", "desc": "껍질이 단단해 안 죽는다", "color": "#35B9C4", "h": 68, "art": "res://art/monsters/shell_bug.png"},
	{"id": "goblin", "ko": "고블린", "kind": "swarm", "stage": "mid", "desc": "단검 들고 떼로 몰려온다", "color": "#B9D93C", "h": 52, "art": "res://art/monsters/goblin.png"},
	{"id": "bone_soldier", "ko": "해골병사", "kind": "tank", "stage": "mid", "desc": "녹슨 칼을 든 뼈다귀", "color": "#EDE6CE", "h": 68, "art": "res://art/monsters/bone_soldier.png"},
	{"id": "dire_wolf", "ko": "사나운늑대", "kind": "fast", "stage": "mid", "desc": "엄청 빠르게 파고든다", "color": "#7FA8E8", "h": 48, "art": "res://art/monsters/dire_wolf.png"},
	{"id": "kobold_bow", "ko": "코볼트궁수", "kind": "caster", "stage": "mid", "desc": "멀리서 불화살을 쏜다", "color": "#F2A03D", "h": 58, "art": "res://art/monsters/kobold_bow.png"},
	{"id": "orc_brute", "ko": "오크전사", "kind": "tank", "stage": "late", "desc": "도끼를 휘두르는 덩치", "color": "#C0452F", "h": 68, "art": "res://art/monsters/orc_brute.png"},
	{"id": "stone_golem", "ko": "돌골렘", "kind": "tank", "stage": "late", "desc": "느리지만 아주 튼튼하다", "color": "#C89B5A", "h": 68, "art": "res://art/monsters/stone_golem.png"},
	{"id": "hex_witch", "ko": "마녀", "kind": "caster", "stage": "late", "desc": "저주 구슬을 날린다", "color": "#C64BE8", "h": 58, "art": "res://art/monsters/hex_witch.png"},
	{"id": "wraith", "ko": "망령", "kind": "fast", "stage": "late", "desc": "스르륵 빠르게 스쳐간다", "color": "#5FEFC6", "h": 48, "art": "res://art/monsters/wraith.png"},
	{"id": "flame_dragon", "ko": "화염용", "kind": "boss", "stage": "boss", "desc": "불을 뿜는 거대한 용", "color": "#FF5A16", "h": 132, "art": "res://art/monsters/flame_dragon.png"},
	{"id": "demon_king", "ko": "트럼프마왕", "kind": "boss", "stage": "boss", "desc": "카드 세계의 최종보스", "color": "#FF2D55", "h": 132, "art": "res://art/monsters/demon_king.png"},
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
