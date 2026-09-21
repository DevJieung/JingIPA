extends Node

## 한 판(런)의 상태 전부. 화면들은 이 노드만 보고 자기를 그린다.
##
## 왜 오토로드인가: 카드 뽑기 → 전투 → 상점 이 셋이 서로 다른 씬인데 목숨·골드·영웅은
## 셋 사이를 계속 넘어다닌다. 씬끼리 값을 들고 다니게 하면 어느 한 곳에서만 갱신을
## 빠뜨려도 조용히 어긋난다.

signal gold_changed(gold: int)
signal lives_changed(lives: int)

## 지금 어느 단계인가. 화면 전환을 이 값으로 결정한다.
##
## ★ **SWAP 은 「족보를 확정하고 영웅을 받았다」는 뜻이다.** 예전에는 확정을 해도 phase 가
##   DRAW 그대로였는데, 그러면 저장된 판 하나가 뜻이 둘이 된다 — 「아직 안 뽑았다」와
##   「이미 받았다」가 구별이 안 된다. 실제로 그것이 익스플로잇이 됐다: 확정 뒤 홈 버튼을
##   누르면 phase 가 DRAW 인 채로 담기고, 이어하기가 뽑기 화면을 다시 띄워 「결정!」을
##   한 번 더 누를 수 있어서 **영웅이 공짜로 하나 더** 생겼다.
enum Phase { TITLE, DRAW, BATTLE, SHOP, OVER, WIN, SWAP }

var phase: int = Phase.TITLE
var wave: int = 0
var lives: int = 0
var gold: int = 0
var kills: int = 0
var best_hand: int = -1        ## 이번 판의 최고 족보 (평생 기록과 분리)
var running: bool = false

## 전장에 세워 둔 영웅들. **최대 Balance.HERO_SLOTS 명**이고, 여기 있는 영웅만 싸운다.
## 각 원소는
##   {"unit": <Roster 의 표 한 줄>, "tier": int, "wave": int, "n": int}
## n 은 같은 캐릭터가 몇 겹으로 쌓였는가 — 그만큼 공격력이 배가 된다.
var heroes: Array = []
## 영웅 전당. 자리가 없어 물러나 있는 영웅들. 모양은 heroes 와 같다.
## ★ 벤치에 있는 영웅은 **싸우지 않는다.** 겹치기(n)만 그대로 쌓인다 —
##   나중에 전장로 올리면 쌓인 만큼 그대로 세진다.
var bench: Array = []

## 상점에서 산 능력치 단계. id -> lv
var levels: Dictionary = {}
## 활성 패시브만 전투에 적용한다. 보유 목록에서는 자유롭게 최대 3개를 선택한다.
var passives: Array[String] = []
var owned_passives: Array[String] = []
## 캐릭터별 이번 런의 누적 실피해. 합성·전당 이동 이후에도 기록을 보존한다.
var hero_damage: Dictionary = {}
## 이번 상점이 내놓은 패시브 셋. **상점에 들어올 때 한 번만 굴린다** —
## 매 프레임 굴리면 화면이 깜빡이고, 저장했다 이어 하면 진열이 통째로 달라진다.
var shop_offer: Array[String] = []
## 이 판에서 크리스탈을 몇 개나 되샀는가. 살수록 값이 오른다(Balance.repair_cost).
var repairs: int = 0

## 이번 판에 받은 카드 다섯 장.
var cards: Array[int] = []
## 카드별 교체 횟수 (공짜 리롤·광고 직접 선택 포함).
var rerolled: Array[int] = []
## 카드별 **유료** 리롤 횟수. 값을 매기는 데 쓴다.
var paid: Array[int] = []
## 칸마다의 카드 더미. 섞은 52장을 다섯 칸에 **한 장씩 돌려** 나눠 준 것이다 —
## 11 · 11 · 10 · 10 · 10 장. 칸끼리 겹치는 카드가 하나도 없으므로 손패 다섯 장도 안 겹친다.
var _piles: Array = []
## 칸마다 그 더미의 몇 번째를 보고 있는가. `cards[i] == _piles[i][_at[i]]` 가 언제나 참이다.
var _at: Array[int] = []

const FUSION_BENCH := 100000
var fusion_pending: Dictionary = {}
var fusion_serial: int = 0
var continue_used: bool = false # 부활 이력/저장 호환용. 부활 횟수를 제한하지 않는다.
var battle_checkpoint: Dictionary = {}
var rng := RandomNumberGenerator.new()

## 이 판의 씨앗. **탄마다의 몬스터 편성이 여기서 나온다.**
##
## ★ 왜 따로 두는가: 편성을 전투가 시작될 때 굴리면 플레이어는 무엇이 올지 모른 채로
##   전장 여섯을 짜야 한다. 그러면 상성은 선택이 아니라 사고다 — 저항에 걸리는 그 탄에
##   크리스탈 스무 개가 통째로 날아가는데 피할 길이 없다(자동 플레이 24판이 한 판도
##   못 깼다). 씨앗과 탄 번호만으로 정해 두면 **상점이 다음 탄을 정확히 보여 줄 수 있고**,
##   화면·검사기·전투가 언제 물어도 같은 답을 받는다.
## ★ rng 로 굴리지 않는 이유도 같다 — 리롤을 몇 번 했느냐에 따라 편성이 달라지면
##   상점에서 보여 준 것과 실제가 어긋난다.
var run_seed: int = 0

## 이 판의 **테마 차례**. 열 칸이고 한 칸이 열 탄을 맡는다(Balance.THEME_BLOCK).
## 값은 Roster.THEMES 의 인덱스다.
##
## ★ 판이 시작될 때 **한 번만** 뽑는다. 매번 물을 때마다 굴리면 상점이 보여 준 다음 탄의
##   몬스터와 실제가 달라지고, 그 순간 상성은 플레이어가 쓸 수 없는 규칙이 된다
##   (CLAUDE.md 5-7 과 같은 뜻이다).
## ★ 사용자가 정한 규칙: **테마는 무작위로 걸리고 반복되어도 된다. 다만 뒤로 갈수록
##   몬스터가 세진다.** 그래서 뒤 블록일수록 험한 테마(rank 가 높은 것)가 걸리게 뽑는다 —
##   반복은 막지 않되 **바로 이어서 같은 테마**만 피한다. 같은 곳이 스무 탄 이어지면
##   그 스무 탄이 한 탄처럼 보인다.
var themes: Array[int] = []

## 마지막으로 확정한 결과 — 전투 화면과 연출이 읽는다.
var last_hand: int = -1
var last_cards: Array[int] = []
var last_key: Array[int] = []
var last_unit: Dictionary = {}
var last_bumped: bool = false     ## 도박꾼의 눈으로 한 단계 올라갔는가
var last_joker: int = -1          ## 조커가 바꿔 준 카드 자리(없으면 -1)
## 확정 결과를 통째로 담아 둔 것. 두 가지 일을 한다:
##   1. confirm_hand() 을 **멱등**으로 만든다 — 어떤 경로로 두 번 불려도 영웅은 한 번만 준다.
##   2. 이어하기가 편성 판을 **그대로 다시 세운다** — 확정 연출이 끝나면 편성 판이
##      탄마다 떠야 하는데(CLAUDE.md 2-1), 이것이 없으면 이어할 때만 그 판을 건너뛴다.
var last_result: Dictionary = {}


func _ready() -> void:
	rng.randomize()


# --------------------------------------------------------------------------- #
# 판 시작 / 끝
# --------------------------------------------------------------------------- #
func start_run(seed_value: int = 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	run_seed = seed_value if seed_value != 0 else int(rng.randi())
	# ★ 지난 판의 테마 그림을 잊는다. 캐시가 한 번 읽은 것을 영영 들고 있어서, 앱을 안 끄고
	#   판을 여러 번 하면 쉰 곳의 배경·바닥이 다 쌓인다(그림만 300MB). 한 판은 열 곳만
	#   쓰므로 여기서 한 번 비우면 언제나 60MB 안쪽이다. (core/art.gd 의 forget 주석)
	Art.forget("res://art/themes/")
	roll_themes()
	wave = 0
	lives = Balance.START_LIVES
	gold = Balance.START_GOLD
	kills = 0
	best_hand = -1
	heroes.clear()
	bench.clear()
	levels.clear()
	passives.clear()
	owned_passives.clear()
	hero_damage.clear()
	shop_offer.clear()
	fusion_pending = {}
	fusion_serial = 0
	continue_used = false
	battle_checkpoint = {}
	repairs = 0
	cards.clear()
	last_result = {}
	rerolled.clear()
	paid.clear()
	last_hand = -1
	last_cards.clear()
	last_key.clear()
	last_bumped = false
	last_joker = -1
	last_unit = {}
	running = true
	phase = Phase.DRAW
	Save.runs += 1
	Save.cur_run = {}
	Save.save_file()
	gold_changed.emit(gold)
	lives_changed.emit(lives)


## ★ 두 번 부르면 안 된다. add_lives() 가 목숨 0 을 볼 때마다 여기로 오는데, 한 걸음에
##   몬스터 여럿이 크리스탈에 닿으면 그 수만큼 불린다. 막지 않으면 Save.record_run 이
##   여러 번 돌아 **평생 누적 처치 수가 두 배·세 배로 부풀고** 저장 파일이 한 프레임에
##   여러 번 쓰인다. (실제로 자동 플레이 14판 중 1판에서 재현됐다)
func end_run(won: bool) -> void:
	if not running:
		return
	running = false
	phase = Phase.WIN if won else Phase.OVER
	if won:
		Save.record_run(wave, kills, true)
	else:
		# Keep defeat resumable until the player accepts it or earns a continue.
		autosave()


func finish_defeat() -> void:
	if phase == Phase.OVER:
		Save.record_run(wave, kills, false)
		phase = Phase.TITLE
		battle_checkpoint = {}


## 보상과 다음 단계를 함께 저장한다. 결과를 읽는 도중 종료해도 전투를 되풀이하지 않는다.
func settle_wave(wiped: bool) -> int:
	if not running or phase != Phase.BATTLE:
		return 0
	var bonus := Balance.clear_bonus(wave, wiped)
	add_gold(bonus)
	if wave >= Balance.LAST_WAVE:
		end_run(true)
	else:
		phase = Phase.SHOP
		roll_shop()
		autosave()
	return bonus


## w 탄의 편성을 정하는 씨앗. 탄 번호만으로 정해진다.
func wave_seed(w: int) -> int:
	return run_seed * 1000003 + w * 7919 + 11


## 이 판의 테마 열 개를 뽑는다. **판 씨앗만으로 정해진다** — 리롤을 몇 번 했든 같다.
##
## ★ 뒤 블록일수록 험한 곳이 걸린다. 첫 블록은 rank 1~2, 마지막 블록은 rank 4~5 다.
##   창(窓)을 셋으로 잡아(r-1 ~ r+1) 굳어 버리지 않게 했다 — 못 박으면 "몇 번째 판이든
##   3블록은 언제나 그 다섯 곳 중 하나"가 되어 판이 다 똑같아진다.
func roll_themes() -> void:
	themes.clear()
	if Roster.THEMES.is_empty():
		return
	var n := int(ceil(float(Balance.LAST_WAVE) / float(Balance.THEME_BLOCK)))
	var r := RandomNumberGenerator.new()
	r.seed = run_seed * 31 + 7
	var last := -1
	for i in range(n):
		# 0번 블록 → 목표 rank 1, 마지막 블록 → 5.
		var want: int = 1 + int(round(float(i) * 4.0 / float(maxi(1, n - 1))))
		var pool: Array[int] = []
		for j in range(Roster.THEMES.size()):
			# 처음부터 주 속성을 보여 주되, 영웅이 적은 첫 다섯 탄의 면역 보호를 지킨다.
			if i == 0 and not Balance.body_immune(String(Roster.THEMES[j]["main_body"])).is_empty():
				continue
			var rk := int(Roster.THEMES[j].get("rank", 1))
			if absi(rk - want) <= 1 and j != last:
				pool.append(j)
		# 창에 아무것도 없으면(테마 표가 얇으면) 창을 푼다. 판이 멈추는 것보다 낫다.
		if pool.is_empty():
			for j2 in range(Roster.THEMES.size()):
				if j2 != last:
					pool.append(j2)
		if pool.is_empty():
			pool.append(0)
		var pick: int = pool[r.randi_range(0, pool.size() - 1)]
		themes.append(pick)
		last = pick


## w 탄이 걸린 테마. 표가 비었거나 판이 안 시작됐으면 빈 딕셔너리다.
func theme_for(w: int) -> Dictionary:
	if themes.is_empty() or Roster.THEMES.is_empty():
		return {}
	var b: int = Balance.theme_block(w)
	return Roster.THEMES[themes[clampi(b, 0, themes.size() - 1)]]


## 그 탄의 테마가 얼마나 험한가(1~5). 체력 곡선이 이 값을 곱한다.
func theme_rank(w: int) -> int:
	var th := theme_for(w)
	return int(th.get("rank", 1)) if not th.is_empty() else 1


## w 탄에 실제로 나올 몬스터 종류(보스 제외). **언제 물어도 같은 답이다.**
## 보스는 따로다 — Balance.is_boss_wave(w) 이면 boss_for(w) 가 하나 더 온다.
##
## ★ 테마의 몸 분포(weights)로 굴린다. 「호수면 물 몬스터가 많이 나온다」가 이 한 줄이다.
func kinds_for(w: int) -> Array:
	var th := theme_for(w)
	if th.is_empty():
		return Roster.wave_kinds_seeded(w, wave_seed(w))
	return Roster.theme_kinds(w, th, wave_seed(w))


## 실제 일반 몬스터 개체 목록. 전투와 테마 미리보기가 같은 배분을 사용한다.
func spawns_for(w: int) -> Array:
	var th := theme_for(w)
	if not th.is_empty():
		return Roster.theme_spawns(w, th, wave_seed(w))
	var kinds := kinds_for(w)
	var out: Array = []
	for i in range(Balance.wave_count(w)):
		out.append(kinds[i % kinds.size()])
	return out


## 이번 보스가 누구인가. **테마가 정한다** — 화산이면 불 보스, 설산이면 얼음 보스.
func boss_for(w: int) -> Dictionary:
	var th := theme_for(w)
	if th.is_empty():
		return Roster.boss_of_body("flame")
	return Roster.boss_of_body(String(th.get("main_body", "flame")))


## w 탄에 나오는 것 전부(보스 포함). 화면이 "다음 탄에 뭐가 오나"를 그릴 때 쓴다.
func wave_lineup(w: int) -> Array:
	var out: Array = []
	if Balance.is_boss_wave(w):
		var b := boss_for(w)
		if not b.is_empty():
			out.append(b)
	for m in kinds_for(w):
		if not out.has(m):
			out.append(m)
	return out


## 다음 테마 구간에 실제로 나오는 일반 몬스터의 수와 목록. 보스는 별도로 표시한다.
## spawns_for는 전용 씨앗을 쓰므로 이 미리보기가 뽑기·전투 난수를 소비하지 않는다.
func theme_preview(w: int) -> Dictionary:
	var start_wave := clampi(w, 1, Balance.LAST_WAVE)
	var end_wave := mini((Balance.theme_block(start_wave) + 1) * Balance.THEME_BLOCK, Balance.LAST_WAVE)
	var groups: Dictionary = {}
	var bosses: Array = []
	var total := 0
	for stage in range(start_wave, end_wave + 1):
		for monster in spawns_for(stage):
			var body := String(monster["body"])
			if not groups.has(body):
				groups[body] = {"body": body, "count": 0, "percent": 0, "monsters": []}
			groups[body]["count"] += 1
			if not groups[body]["monsters"].has(monster):
				groups[body]["monsters"].append(monster)
			total += 1
		if Balance.is_boss_wave(stage):
			var monster := boss_for(stage)
			if not monster.is_empty():
				bosses.append({"wave": stage, "monster": monster})
	var rows: Array = []
	var remainders: Array = []
	var assigned := 0
	for body in Balance.MBODY_ORDER:
		if not groups.has(body):
			continue
		var row: Dictionary = groups[body]
		var exact := float(row["count"]) * 100.0 / float(total)
		row["percent"] = int(floor(exact))
		assigned += int(row["percent"])
		remainders.append(exact - float(row["percent"]))
		# 원본 로스터 순서로 정렬해 재방문 시 같은 몬스터를 쉽게 찾도록 한다.
		row["monsters"].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return Roster.MONSTERS.find(a) < Roster.MONSTERS.find(b))
		rows.append(row)
	# 정수 퍼센트 합계가 항상 100이 되도록 가장 큰 소수부부터 1씩 배분한다.
	for point in range(100 - assigned if total > 0 else 0):
		var best := 0
		for i in range(1, remainders.size()):
			if remainders[i] > remainders[best]:
				best = i
		rows[best]["percent"] += 1
		remainders[best] = -1.0
	return {"start_wave": start_wave, "end_wave": end_wave, "total": total,
		"rows": rows, "bosses": bosses}


func lv(id: String) -> int:
	return int(levels.get(id, 0))


## 그 능력치를 **레벨 L 에서** 실제로 얼마가 되는가. 패시브는 안 섞는다.
##
## ★ 상점이 공식을 다시 적으면 안 된다(CLAUDE.md 18). 「+15%」라고 적어 두고 실제로는
##   1.09배가 걸리는 어긋남은 아무도 못 잡는다 — 전투가 부르는 바로 그 함수를 부른다.
func up_at(id: String, l: int) -> float:
	match id:
		"atk":
			return Balance.atk_mult(l)
		"rate":
			return Balance.rate_mult(l)
		"crit":
			return Balance.crit_chance(l)
		"critx":
			return Balance.crit_mult(l)
		"gold":
			return Balance.gold_mult(l)
		"mire":
			return Balance.mire_mult(l)
		"reroll":
			return float(Balance.FREE_REROLL + l)
	return 1.0


## **지금 전투가 실제로 쓰는 값** — 능력치 단계에 패시브까지 얹은 것.
## ★ 패시브 표의 열쇠 이름이 능력치 id 와 **같은 글자**다(atk · rate · crit ·
##   critx · gold). 그래서 따로 짝지어 주는 표가 없다 — 있으면 언젠가 한 줄이 어긋난다.
## ★ hero_stats() 와 **같은 식**이어야 한다. tests/ns_check 가 둘을 나란히 놓고 잰다.
func stat_now(id: String) -> float:
	match id:
		"crit":
			return min(0.85, up_at(id, lv(id)) + pas_add("crit"))
		"critx":
			return up_at(id, lv(id)) + pas_add("critx")
		"reroll":
			return float(free_rerolls())
		"mire":
			return up_at(id, lv(id))
	return up_at(id, lv(id)) * pas_mult(id)


func has(passive_id: String) -> bool:
	return passives.has(passive_id)


## ★ **최대치는 늘지 않는다.** 사용자가 정한 규칙이다 — 크리스탈은 언제나 스무 개까지고,
##   깨진 것은 상점에서 골드로 되산다. 예전에는 상점의 「크리스탈 +1」이 최대치를 같이
##   올려서 잘 하는 판일수록 목숨이 늘었다(20 → 31). 그러면 디펜스가 아니다.
func max_lives() -> int:
	return Balance.MAX_LIVES


func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)
	gold_changed.emit(gold)


func add_lives(n: int) -> void:
	lives = clampi(lives + n, 0, max_lives())
	lives_changed.emit(lives)
	if lives <= 0:
		end_run(false)


# --------------------------------------------------------------------------- #
# 카드 다섯 장 — 뽑기와 리롤
# --------------------------------------------------------------------------- #
## 새 판의 카드를 뽑는다. 덱은 탄마다 새로 섞고, 그것을 **다섯 칸에 나눠 준다.**
##
## ★ 사용자가 정한 규칙이다: 「칸마다 미리 열 장 혹은 열한 장 깔아 놓고, 리롤할 때마다
##   그 더미에서 **순서대로** 나오게. 한 묶음 다 돌면 제자리로 돌아와서 반복.」
##   그래서 한 칸이 이번 탄에 보여 줄 수 있는 카드가 미리 정해져 있고, 리롤은 52장에서
##   새로 뽑는 것이 아니라 **그 줄을 한 칸 넘기는** 일이다.
## ★ 나눠 주는 것은 **한 장씩 돌려서**다(실제로 카드를 나눠 주는 것과 같다).
##   52 = 11+11+10+10+10 이라 앞의 두 칸만 한 장 많은데, 나누는 덱이 이미 섞여 있으므로
##   그 한 장 차이가 특정 칸을 유리하게 만들지는 않는다.
## ★ 칸끼리 카드가 안 겹치는 것이 여기서 나온다 — 52장을 **쪼개** 나눠 주기 때문이다.
##   그래서 리롤을 몇 번을 하든 손패에 같은 카드가 두 장 설 수가 없다.
func begin_draw() -> void:
	wave += 1
	phase = Phase.DRAW
	last_result = {}
	battle_checkpoint = {}
	var deck := Poker.full_deck()
	_shuffle(deck)
	cards.assign(deck.slice(0, 5))
	rerolled.assign([0, 0, 0, 0, 0])
	paid.assign([0, 0, 0, 0, 0])
	_piles.clear()
	_at.clear()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 강화 단계와 현재 활성 패시브를 반영한 카드 한 장당 무료 횟수.
## 상점의 현재·다음 값과 실제 포커가 같은 계산을 사용한다.
func free_rerolls_at(level: int) -> int:
	return int(up_at("reroll", level)) + (Balance.PASSIVE_DEAL if has("deal") else 0)


func free_rerolls() -> int:
	return free_rerolls_at(lv("reroll"))


## 카드별 남은 무료 횟수. 유료 교체 이후에도 음수를 표시하지 않는다.
func rerolls_left(i: int) -> int:
	if i < 0 or i >= cards.size() or i >= rerolled.size():
		return 0
	return maxi(0, free_rerolls() - rerolled[i])


## i 번 카드를 지금 다시 뽑는 데 드는 값. 0 이면 공짜다.
##
## ★ 규칙: 공짜 횟수를 다 쓴 카드는 **골드를 내지 않으면 더 리롤할 수 없다.**
##   값은 그 카드를 유료로 리롤한 횟수에 따라 두 배씩 오른다(15 → 30 → 60 …).
func reroll_cost_of(i: int) -> int:
	if i < 0 or i >= cards.size():
		return 0
	if rerolls_left(i) > 0:
		return 0
	return Balance.reroll_cost(paid[i])


## ★ 더미가 돌고 돌므로 **바닥나서 못 바꾸는 일은 없다.** 막는 것은 골드뿐이다.
##   (예전에는 다섯 칸이 덱 하나를 나눠 썼고, 47장을 다 쓰면 리롤이 통째로 잠겼다)
func can_reroll(i: int) -> bool:
	return running and phase == Phase.DRAW and i >= 0 and i < cards.size() \
			and gold >= reroll_cost_of(i)


## 실제로 다시 뽑는다. 성공하면 참.
func reroll(i: int) -> bool:
	if not can_reroll(i):
		return false
	var pool: Array[int] = []
	for card in range(52):
		if not cards.has(card):
			pool.append(card)
	var cost := reroll_cost_of(i)
	if cost > 0:
		add_gold(-cost)
		paid[i] += 1
	rerolled[i] += 1
	cards[i] = pool[rng.randi_range(0, pool.size() - 1)]
	autosave()
	return true


## 원하는 카드 선택은 무료 리롤 잔여 횟수·골드와 무관하게 족보 확정 전에 이용한다.
func can_choose_card(slot: int) -> bool:
	return running and phase == Phase.DRAW and slot >= 0 and slot < cards.size()


func card_choice_allowed(slot: int, desired: int, expected: int) -> bool:
	return can_choose_card(slot) and desired >= 0 and desired < 52 \
			and cards[slot] == expected and not cards.has(desired)


# --------------------------------------------------------------------------- #
# 족보 확정 → 영웅 등장
# --------------------------------------------------------------------------- #
## 지금 카드로 족보를 판정하고 그 등급의 캐릭터 중 하나를 무작위로 세운다.
## 화면은 반환값(딕셔너리)만 보고 연출한다.
func confirm_hand() -> Dictionary:
	# ★ **한 탄에 한 번만 준다.** 확정 연출 도중에 앱이 죽었다 살아나도, 화면이
	#   실수로 두 번 불러도 영웅은 한 명이다. 화면 쪽 _leaving 방어(draw_screen.gd)와
	#   같은 뜻인데 이쪽은 **재시작까지** 막는다.
	if phase == Phase.SWAP:
		return last_result
	if not running or phase != Phase.DRAW or cards.size() != 5:
		return {}
	var use: Array[int] = cards.duplicate()
	last_joker = -1
	var hand := Poker.evaluate(use)

	# 조커: 다섯 장 중 한 장을 **가장 좋은 패가 되는 카드**로 친다.
	if has("joker"):
		var best := hand
		var best_i := -1
		var best_c := -1
		for i in range(5):
			for c in range(52):
				if use.has(c):
					continue
				var trial: Array[int] = use.duplicate()
				trial[i] = c
				var h := Poker.evaluate(trial)
				if h > best:
					best = h
					best_i = i
					best_c = c
		if best_i >= 0:
			use[best_i] = best_c
			hand = best
			last_joker = best_i

	last_bumped = false
	if has("eye") and hand < Poker.Hand.ROYAL and rng.randf() < Balance.PASSIVE_EYE_P:
		hand += 1
		last_bumped = true

	var unit := Roster.pick_unit(hand, rng)
	last_hand = hand
	best_hand = maxi(best_hand, hand)
	last_cards = use.duplicate()
	last_key = Poker.key_cards(use, hand) if not last_bumped else use.duplicate()
	last_unit = unit
	var got := gain_hero(unit, hand)
	last_result = {"hand": hand, "cards": last_cards, "key": last_key, "unit": unit,
			"bumped": last_bumped, "joker": last_joker,
			"showy": hand >= Poker.SHOWY,
			"stacked": bool(got["stacked"]), "where": String(got["where"]),
			"slot": int(got["slot"]), "n": int(got["n"])}
	# ★ 영웅을 받은 **바로 그 순간** 담는다. 여기서 안 담으면 편성 판에 머무는 동안
	#   (시간 제한이 없다) 판 전체가 저장 밖이라, 앱을 껐다 켜면 그 탄의 뽑기가
	#   통째로 되돌아간다.
	phase = Phase.SWAP
	# 도감과 획득 영웅을 같은 저장에 담는다. 중간 저장은 재시작 시 도감만 중복 집계한다.
	Save.record_hand(hand, String(unit.get("id", "")), false)
	autosave()
	return last_result


# --------------------------------------------------------------------------- #
# 영웅 편성 — 전장 여섯 자리와 영웅 전당
# --------------------------------------------------------------------------- #
## 그 캐릭터가 지금 어디에 있는가. ["field"|"bench", 자리] 를 돌려준다. 없으면 ["", -1].
##
## ★ 배열 자체를 돌려주지 않는다. GDScript 의 `==` 는 배열을 **값으로** 비교해서,
##   돌려받은 배열이 heroes 인지 bench 인지를 `arr == heroes` 로 물으면 내용이 우연히
##   같을 때 엉뚱한 답이 나온다. 어디에 있었는지는 찾은 쪽이 말해 주는 것이 맞다.
func find_hero(unit_id: String) -> Array:
	for i in range(heroes.size()):
		if String(heroes[i]["unit"]["id"]) == unit_id:
			return ["field", i]
	for i in range(bench.size()):
		if String(bench[i]["unit"]["id"]) == unit_id:
			return ["bench", i]
	return ["", -1]


func field_full() -> bool:
	return heroes.size() >= Balance.HERO_SLOTS


## 중복 캐릭터가 있어도 이번에 얻은 카드의 위치를 찾는다.
## wave는 저장에도 보존되며, 배치/정렬로 달라진 slot보다 우선한다.
func latest_draw_location() -> Array:
	if last_result.is_empty():
		return ["", -1]
	var unit_id := String(last_result.get("unit", {}).get("id", ""))
	# 획득 확인 전에는 배열을 재정렬하지 않는다. 같은 탄에 얻은 동명 카드와 구별한다.
	if bool(last_result.get("reward_pending", false)) and last_result.get("where", "") == "bench":
		var reward_slot := int(last_result.get("slot", -1))
		if reward_slot >= 0 and reward_slot < bench.size() \
				and String(bench[reward_slot]["unit"]["id"]) == unit_id:
			return ["bench", reward_slot]
	var found: Array = ["", -1]
	var newest := -1
	for group in ["field", "bench"]:
		var cards_here: Array = heroes if group == "field" else bench
		for i in range(cards_here.size()):
			var h: Dictionary = cards_here[i]
			if String(h["unit"]["id"]) != unit_id:
				continue
			var acquired := int(h.get("wave", 1))
			var recorded_location: bool = group == String(last_result.get("where", "")) \
					and i == int(last_result.get("slot", -1))
			if acquired > newest or (acquired == newest and recorded_location):
				newest = acquired
				found = [group, i]
	return found


## 새로 뽑은 영웅 하나를 받는다.
##
## 같은 캐릭터는 중첩하지 않고 전당의 별도 카드로 보관한다.
## 출전 가능한 새 캐릭터는 빈 발판에 세우고, 전장이 가득 찼으면 전당에 보관한다.
## 광고 부활처럼 사용자가 직접 배치할 보상은 auto_deploy=false로 지급한다.
##
## 돌려주는 것: {"stacked": 겹쳤는가, "where": "field"|"bench", "slot": 자리, "n": 겹친 수}
func gain_hero(unit: Dictionary, tier: int, allow_echo: bool = true, auto_deploy: bool = true) -> Dictionary:
	var duplicate := int(find_hero(String(unit.get("id", "")))[1]) >= 0
	var h := {"unit": unit, "tier": tier, "wave": maxi(1, wave), "n": 1}
	var where := "bench"
	var slot := bench.size()
	if auto_deploy and not field_full() and can_deploy(unit):
		heroes.append(h)
		ensure_posts()
		where = "field"
		slot = heroes.size() - 1
	else:
		bench.append(h)
	if duplicate and allow_echo and has("echo"):
		bench.append(h.duplicate(true))
		bench[-1].erase("post")
	return {"stacked": false, "duplicate": duplicate, "where": where, "slot": slot, "n": 1}


func can_deploy(unit: Dictionary, replacing: int = -1) -> bool:
	for i in range(heroes.size()):
		if i != replacing and String(heroes[i]["unit"]["id"]) == String(unit.get("id", "")):
			return false
	return true


## 전장의 f 번과 전당의 b 번을 맞바꾼다. b 가 -1 이면 전장에서 전당으로 물린다.
## ★ 여기 한 곳에서만 두 배열을 건드린다. 화면 두 곳(뽑기·상점)이 같은 규칙을 봐야
##   "상점에서는 바뀌는데 뽑기 화면에서는 안 바뀌는" 종류의 어긋남이 안 생긴다.
func swap_field_bench(f: int, b: int) -> bool:
	if not fusion_pending.is_empty() or f < 0 or f >= heroes.size():
		return false
	if b < 0:
		if heroes.size() <= 1:
			return false
		heroes[f].erase("post")
		bench.append(heroes[f])
		heroes.remove_at(f)
		autosave()
		return true
	if b >= bench.size() or not can_deploy(bench[b]["unit"], f):
		return false
	ensure_posts()
	var t = heroes[f]
	bench[b]["post"] = int(t["post"])
	t.erase("post")
	heroes[f] = bench[b]
	bench[b] = t
	autosave()
	return true


## 전당의 b 번을 전장의 빈 자리에 세운다. 자리가 없으면 거짓.
func bench_to_field(b: int) -> bool:
	if not fusion_pending.is_empty() or b < 0 or b >= bench.size() or field_full():
		return false
	if not can_deploy(bench[b]["unit"]):
		return false
	heroes.append(bench[b])
	bench.remove_at(b)
	ensure_posts()
	autosave()
	return true


## 전장 안에서 자리를 바꾼다.
## 이동한 발판이 공격 사거리의 원점이 된다.
func swap_field(a: int, b: int) -> bool:
	if not fusion_pending.is_empty() or a == b or a < 0 or b < 0 or a >= heroes.size() or b >= heroes.size():
		return false
	ensure_posts()
	var post_a: int = heroes[a]["post"]
	heroes[a]["post"] = heroes[b]["post"]
	heroes[b]["post"] = post_a
	var t = heroes[a]
	heroes[a] = heroes[b]
	heroes[b] = t
	autosave()
	return true


## Repair missing positions in legacy saves while preserving valid occupied posts.
func ensure_posts() -> void:
	var used := {}
	for h in heroes:
		var post := int(h.get("post", -1))
		if post >= 0 and post < Balance.POST_SLOTS and not used.has(post):
			used[post] = true
		else:
			h["post"] = -1
	for h in heroes:
		if int(h.get("post", -1)) >= 0:
			continue
		for post in Balance.POST_ORDER:
			if not used.has(post):
				h["post"] = post
				used[post] = true
				break

func hero_at_post(post: int) -> int:
	for i in range(heroes.size()):
		if int(heroes[i].get("post", -1)) == post:
			return i
	return -1

## Occupied destinations exchange posts; hero order and combat identity stay stable.
func move_hero(index: int, post: int) -> bool:
	if not fusion_pending.is_empty() or index < 0 or index >= heroes.size() or post < 0 or post >= Balance.POST_SLOTS:
		return false
	ensure_posts()
	var previous: int = heroes[index]["post"]
	if previous == post:
		return false
	var other := hero_at_post(post)
	if other >= 0:
		heroes[other]["post"] = previous
	heroes[index]["post"] = post
	if phase == Phase.BATTLE:
		# Combat resumes at wave start. Persist placement only, not earned gold/leaks.
		var saved := Save.cur_run.duplicate(true)
		if not saved.is_empty():
			var posts := {}
			for h in heroes:
				posts[String(h["unit"]["id"])] = int(h["post"])
			for h in saved.get("heroes", []):
				if posts.has(String(h["u"])):
					h["post"] = posts[String(h["u"])]
			Save.store_run(saved)
	else:
		autosave()
	return true

## 전당 안에서 자리를 옮긴다. b 가 전당 크기를 넘으면 **맨 뒤로** 보낸다
## (빈 칸에 떨군 것이라, 화면이 금색으로 「여기로」라고 말해 놓고 아무 일도 안 하면 안 된다).
##
## ★ 화면이 Run.bench 를 직접 자르면 안 된다(CLAUDE.md 14-3). 예전에는 HeroView 가
##   여기 없이 스스로 배열을 맞바꿔서, 이 판만 저장 밖에 있었다.
func move_bench(a: int, b: int) -> bool:
	if not fusion_pending.is_empty() or a < 0 or a >= bench.size() or b < 0 or a == b:
		return false
	if b >= bench.size():
		var e = bench[a]
		bench.remove_at(a)
		bench.append(e)
	else:
		var t2 = bench[a]
		bench[a] = bench[b]
		bench[b] = t2
	autosave()
	return true


## 전당을 **등급 높은 순**으로 세운다. 등급이 같으면 겹이 많은 쪽, 그것도 같으면 이름 차례.
## ★ 전장(싸우는 여섯)은 건드리지 않는다 — **누구를 세울지**를 이번 탄의 상성 보고
##   사람이 고른 것이라, 정렬 한 번에 뒤섞이면 방금 짜 놓은 편성이 통째로 날아간다.
##   (서는 차례 자체는 사거리가 없어진 뒤로 탄이 나는 시간밖에 안 정한다. 그래도
##   사람이 손으로 정한 줄을 코드가 말없이 뒤집을 일은 아니다.)
func sort_bench() -> void:
	if not fusion_pending.is_empty():
		return
	bench.sort_custom(func(a, b):
		var ta: int = int(a["tier"])
		var tb: int = int(b["tier"])
		if ta != tb:
			return ta > tb
		var na: int = int(a.get("n", 1))
		var nb: int = int(b.get("n", 1))
		if na != nb:
			return na > nb
		return Look.unit_name(a["unit"]) < Look.unit_name(b["unit"]))
	autosave()


## 전장 + 전당을 통틀어 겹친 것까지 센 영웅 수. "여태 몇 명 뽑았나"가 이 값이다.
func hero_total() -> int:
	return heroes.size() + bench.size()


# --------------------------------------------------------------------------- #
# 패시브 효과 — 들고 있는 셋이 **모든 영웅에게 함께** 걸린다
# --------------------------------------------------------------------------- #
## 패시브 표에 적힌 곱셈 효과를 모은다(공격력·공격속도·골드·광역 반경).
## ★ 전투(BattleSim)와 상점 표시가 반드시 이 함수를 함께 써야 "상점에는 +20% 라고
##   적혀 있는데 실제로는 안 오르는" 종류의 어긋남이 안 생긴다.
func pas_mult(key: String) -> float:
	var m := 1.0
	for id in passives:
		m *= float(Balance.passive_by_id(String(id)).get(key, 1.0))
	return m


## 덧셈 효과(치명타 확률·치명타 배율처럼 더하는 것).
func pas_add(key: String) -> float:
	var t := 0.0
	for id in passives:
		t += float(Balance.passive_by_id(String(id)).get(key, 0.0))
	return t


## 그 효과를 가진 패시브 중 가장 센 값. 둔화처럼 **겹치지 않고 센 쪽만** 쓰는 것에.
func pas_best(key: String) -> float:
	var best := 0.0
	for id in passives:
		best = max(best, float(Balance.passive_by_id(String(id)).get(key, 0.0)))
	return best


func passive_full() -> bool:
	return passives.size() >= Balance.PASSIVE_SLOTS


func owns_passive(id: String) -> bool:
	return owned_passives.has(id) or passives.has(id)


func toggle_passive(id: String) -> bool:
	if not running or not phase in [Phase.SHOP, Phase.SWAP] or not owns_passive(id):
		return false
	if not owned_passives.has(id):
		owned_passives.append(id)
	if passives.has(id):
		passives.erase(id)
	elif not passive_full():
		passives.append(id)
	else:
		return false
	autosave()
	return true


## 활성 칸이 가득 차도 보유할 수 있다. 빈 활성 칸은 구매와 함께 채운다.
func buy_passive(id: String) -> bool:
	if owns_passive(id):
		return false
	var p := Balance.passive_by_id(id)
	if p.is_empty() or gold < int(p["cost"]):
		return false
	add_gold(-int(p["cost"]))
	owned_passives.append(id)
	if not passive_full():
		passives.append(id)
	autosave()
	return true


## 이전 UI나 오래된 입력으로도 차액 거래·판매는 허용하지 않는다.
func replace_passive(_slot: int, _id: String) -> bool:
	return false


func sell_passive(_id: String) -> bool:
	return false


## 이번 상점이 내놓을 패시브 셋을 굴린다. **상점에 들어올 때 한 번만** 부른다.
##
## ★ 이미 든 것과, 아직 나올 때가 아닌 rank(Balance.passive_rank_cap)는 뺀다.
##   1탄 상점에 1100골드짜리 조커가 뜨면 셋 중 한 자리가 통째로 헛돈다.
func roll_shop() -> void:
	var pool: Array[String] = []
	var cap := Balance.passive_rank_cap(maxi(1, wave))
	for p in Balance.PASSIVES:
		var pid := String(p["id"])
		if owns_passive(pid) or int(p.get("rank", 1)) > cap:
			continue
		pool.append(pid)
	_shuffle(pool)
	shop_offer = pool.slice(0, mini(3, pool.size()))


## 지금 진열된 패시브(표 한 줄들). 이미 산 것은 조용히 빠진다.
func offer_passives(n: int = 3) -> Array:
	if shop_offer.is_empty():
		roll_shop()
	var out: Array = []
	for id in shop_offer:
		if owns_passive(String(id)):
			continue
		var p := Balance.passive_by_id(String(id))
		if not p.is_empty():
			out.append(p)
		if out.size() >= n:
			break
	return out


## **전장에 같은 속성이 둘 이상이면** 그 속성의 피해가 오른다 — 패시브 「속성 공명」.
## ★ 왜 hero_stats 에 넣는가: 여기서 곱해 두면 상점의 「초당 피해」와 자동 플레이 정책이
##   전투와 **같은 값**을 본다. 전투에서만 곱하면 화면에는 안 오른 것처럼 보이는데
##   실제로는 오르는, 아무도 못 잡는 어긋남이 생긴다(상성 배수와 반대되는 경우다).
func resonance_mult(elem: String) -> float:
	if not has("resonance") or elem == "":
		return 1.0
	var n := 0
	for h in heroes:
		if String(h["unit"].get("elem", "none")) == elem:
			n += 1
			if n >= 2:
				return Balance.PASSIVE_RESONANCE
	return 1.0


# --------------------------------------------------------------------------- #
# 크리스탈 되사기 — 깨진 것을 상점에서 골드로 채운다 (최대치는 안 는다)
# --------------------------------------------------------------------------- #
func repair_cost() -> int:
	return Balance.repair_cost(maxi(1, wave), repairs)


func can_repair() -> bool:
	return lives < max_lives() and gold >= repair_cost()


func buy_repair() -> bool:
	if not can_repair():
		return false
	add_gold(-repair_cost())
	repairs += 1
	add_lives(1)
	autosave()
	return true


# --------------------------------------------------------------------------- #
# 영웅의 실제 능력치 — 전투와 검사기가 **이 함수 하나만** 쓴다
# --------------------------------------------------------------------------- #
func hero_stats(h: Dictionary) -> Dictionary:
	var u: Dictionary = h["unit"]
	var t: int = int(h["tier"])
	var prof: Dictionary = Balance.PROFILE[String(u.get("profile", "balance"))]
	var bul: Dictionary = Balance.BULLET.get(String(u.get("bullet", "shot")), Balance.BULLET["shot"])
	# ★ 같은 캐릭터가 겹친 만큼 **공격력만** 배가 된다(공격속도는 그대로).
	#   같은 영웅 n명을 나란히 세웠던 예전과 단일 대상 피해가 정확히 같아지는 값이다.
	# ★ 속성마다의 **기본 화력**(Balance.elem_dmg)을 여기서 곱한다. 1.0 이 아닌 것이 둘이다 —
	#   물은 상태이상이 없어서(1.12), 전기는 **면역이 둘**이라 상성 폭이 좁아서(1.32)
	#   그 몫을 순수 피해로 돌려받는다.
	# ★ 왜 전투(BattleSim._hurt)가 아니라 여기인가: 여기에 두면 상점의 「초당 피해」와
	#   자동 플레이 정책이 **같은 값**을 본다. 전투에서만 곱하면 화면에는 안 오른 것처럼
	#   보이는데 실제로는 오르는, 아무도 못 잡는 어긋남이 생긴다.
	#   (상성 배수는 반대다 — 어느 몬스터를 때릴지 모르므로 전투에서만 곱한다)
	var el := String(u.get("elem", "none"))
	# ★ **역할**(일격·도탄·특효·광역). 방식과 다른 축이다 — 같은 `shot` 이라도 일격은
	#   한 대가 무겁고(x1.26) 특효는 가벼운 대신(x0.74) 상태이상이 두 배다.
	#   표에 없는 값이 오면 「일격」으로 받는다(화면이 안 죽게 하려는 것이고, 실제로
	#   어긋나면 ns_check 가 잡는다).
	var role := String(u.get("role", "single"))
	var rol: Dictionary = Balance.ROLE.get(role, Balance.ROLE["single"])
	var n: int = int(h.get("n", 1))
	# ★ **겹치면 탄이 그 수만큼 나간다**(Balance.stack_shots). 여기 atk 는 **한 발**의
	#   세기이고, 발 수를 곱해야 n배가 된다 — 그래서 total_dps 는 shots 를 같이 곱한다.
	var atk: float = Balance.TIER_ATK[t] * float(prof["atk"]) * float(bul["dmg"]) \
			* float(rol["atk"]) \
			* Balance.elem_dmg(el) * resonance_mult(el) \
			* Balance.atk_mult(lv("atk")) * pas_mult("atk")
	var rate: float = Balance.TIER_RATE[t] * float(prof["rate"]) \
			* Balance.rate_mult(lv("rate")) * pas_mult("rate")
	# 사거리는 배치 미리보기와 실제 겨냥이 같은 값을 사용한다.
	# ★ **무상성 특효는 치명타에 특화된다.** 무상성에는 상태이상이 없어서(CLAUDE.md 5-2)
	#   「특효」가 걸 것이 없기 때문이다. 몬스터에게 아무것도 안 붙이므로 5-2 는 그대로다 —
	#   이것은 쏘는 쪽의 능력치다. 여기(hero_stats)에서 얹는 까닭은 상점의 「치명타」 줄과
	#   자동 플레이 정책이 **같은 값**을 봐야 하기 때문이다.
	var crit: float = Balance.crit_chance(lv("crit")) + pas_add("crit")
	if role == "rider" and el == "none":
		crit += Balance.RIDER_CRIT
	return {
		"atk": atk, "rate": rate,
		"range": Balance.attack_range(u, t),
		"shots": 1,
		"bullet": String(u.get("bullet", "shot")),
		# 역할. 전투가 상태이상 세기(특효)와 밀어내기를 여기서 읽는다.
		"role": role,
		# 공격 속성. 상성 배수는 전투(BattleSim._hurt)에서만 곱한다 —
		# 여기서 미리 곱해 두면 "어느 몬스터를 때리느냐"를 모르는 채로 곱하는 셈이 된다.
		"elem": el,
		"crit": min(0.85, crit),
		"critx": Balance.crit_mult(lv("critx")) + pas_add("critx"),
	}


## 영웅 한 명의 **단일 대상** 초당 데미지(치명타 기대값 포함). 상점의 「초당 피해」,
## 설명 팝업, 편성 상성표, 자동 플레이 정책이 전부 이 한 줄을 본다 — 화면마다 다시 적으면
## 「팝업에는 120 인데 합계는 다른 식」이 되는 어긋남을 아무도 못 잡는다.
## ★ 겹친 만큼 **발이 여러 개** 나간다(shots). 안 곱하면 x5 영웅이 1겹으로 세어져서
##   상점의 「초당 피해」와 자동 플레이 정책이 전장을 통째로 잘못 짠다.
static func stats_dps(st: Dictionary) -> float:
	var mult: float = 1.0 + float(st["crit"]) * (float(st["critx"]) - 1.0)
	return float(st["atk"]) * float(st["rate"]) * mult * float(st.get("shots", 1))


func hero_dps(h: Dictionary) -> float:
	return stats_dps(hero_stats(h))


## 지금 세워 둔 영웅 전부의 **단일 대상** 초당 데미지 합(치명타 기대값 포함).
## ⚠ 광역·연쇄·장판이 여럿을 동시에 때리는 몫은 여기 안 들어간다. 어림수로만 써라.
## ⚠ **상성 배수도 안 들어간다.** 어느 몬스터를 때릴지 모르는 값이라 넣을 자리가 없다 —
##   같은 영웅이 식물에게는 2배, 물에게는 반이다. 화면의 「초당 피해」도 그래서 어림수다.
func total_dps() -> float:
	var s := 0.0
	for h in heroes:
		s += hero_dps(h)
	return s


# --------------------------------------------------------------------------- #
# 상점
# --------------------------------------------------------------------------- #
## 직격의 속성 배수만 비교한다. 광역의 대상 수·화상·군중 제어를 포함한 승률 예측은 아니다.
func formation_matchups() -> Array:
	var powers := {}
	var total := 0.0
	for h in heroes:
		var power := hero_dps(h)
		var el := String(h["unit"].get("elem", "none"))
		powers[el] = float(powers.get(el, 0.0)) + power
		total += power
	var out: Array = []
	var seen := {}
	for m in wave_lineup(wave):
		var body := String(m.get("body", ""))
		if seen.has(body):
			continue
		seen[body] = true
		var effective := 0.0
		for el in powers:
			effective += float(powers[el]) * Balance.elem_mult(el, body)
		out.append({"body": body, "mult": effective / maxf(0.001, total)})
	out.sort_custom(func(a, b): return float(a["mult"]) < float(b["mult"]))
	return out


func buy_upgrade(id: String) -> bool:
	var l := lv(id)
	if Balance.upgrade_maxed(id, l):
		return false
	var cost := Balance.upgrade_cost(id, l)
	if gold < cost:
		return false
	add_gold(-cost)
	levels[id] = l + 1
	autosave()
	return true


# --------------------------------------------------------------------------- #
# 자동 저장 — 판을 통째로 담고 되돌린다
# --------------------------------------------------------------------------- #
## 저장 형식의 판 번호. 규칙이 바뀌어 옛 저장을 못 읽게 되면 여기를 올린다 —
## 그러면 restore() 가 조용히 거절하고 새 판을 시작한다. **버전 없이 두면**
## 옛 저장의 반쯤 맞는 값이 새 규칙에 섞여 들어와 아무도 못 잡는 판이 만들어진다.
## ★ 4 → 5. **사거리를 없앴기 때문이다.** 옛 판에는 상점에서 산 「사거리」 단계와
##   패시브 「긴 활대」가 그대로 담겨 있는데, 둘 다 지금 규칙에 **없는 것**을 가리킨다 —
##   그대로 읽으면 없는 능력치에 골드를 쏟아부은 판이 되살아난다.
## ★ 5 → 6. **카드 더미가 덱 하나에서 칸마다의 더미로 바뀌었다.** 옛 판에는 「아직 안 쓴
##   덱」 한 줄만 담겨 있어서 칸마다의 더미도, 어디까지 넘겼는지도 없다 — 그대로 읽으면
##   리롤이 처음 자리로 돌아가고 그 탄의 손패가 규칙 밖의 것이 된다.
## ★★ **7 로 올렸다 — 캐릭터 여든 명으로 통째로 갈아 끼우면서 옛 id 서른 개가 전부
##   없어졌기 때문이다.** 올리지 않으면 옛 저장이 **조용히** 살아난다: `_hero_in()` 이
##   `Roster.unit_by_id()` 로 캐릭터를 찾는데 못 찾으면 그 영웅을 그냥 건너뛰므로,
##   이어하기가 **전장이 텅 빈 채로 40탄**을 여는 판을 만든다. 그건 "못 이어졌다"보다
##   나쁘다 — 플레이어는 왜 졌는지 모른다.
##   ☆ 판이 아예 안 열리는 쪽이 낫다. `restore()` 가 판 번호가 다르면 통째로 버린다.
const SAVE_VERSION := 7


## 영웅 한 명을 저장할 수 있는 모양으로. **캐릭터 표는 통째로 담지 않는다** —
## id 만 담고 되돌릴 때 표에서 다시 찾는다. 표를 담으면 캐릭터를 한 명 고치는 순간
## 저장 파일 안의 옛 캐릭터가 되살아난다.
static func _hero_out(h: Dictionary) -> Dictionary:
	return {"u": String(h["unit"].get("id", "")), "t": int(h.get("tier", 0)),
			"w": int(h.get("wave", 1)), "n": int(h.get("n", 1)), "post": int(h.get("post", -1))}


static func _hero_in(d: Dictionary) -> Dictionary:
	var u := Roster.unit_by_id(String(d.get("u", "")))
	if u.is_empty():
		return {}
	return {"unit": u, "tier": int(d.get("t", 0)), "wave": int(d.get("w", 1)),
			"n": maxi(1, int(d.get("n", 1))), "post": int(d.get("post", -1))}


## 영웅 목록(전장이든 전당이든)을 통째로 저장 꼴로.
static func _heroes_out(list: Array) -> Array:
	var out: Array = []
	for h in list:
		out.append(_hero_out(h))
	return out


## 파일에서 온 배열을 정수 배열로. 저장 파일의 숫자는 float 로 돌아올 수 있다.
static func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for v in values:
		out.append(int(v))
	return out


## 지금 이 판을 통째로 담는다. Save 가 이 딕셔너리 하나만 파일에 쓴다.
##
## ★ 카드 다섯 장과 리롤 횟수까지 담는다. 안 담으면 뽑기 화면에서 앱을 껐다 켰을 때
##   **리롤을 다시 공짜로** 할 수 있고, 그게 곧 무한 리롤이다.
## ★ 칸마다의 더미(_piles)와 어디까지 넘겼는가(_at)도 담는다. 안 담으면 이어 한 판에서
##   더미가 새로 섞여 **같은 카드가 두 칸에 서고**, 넘긴 자리도 처음으로 돌아간다.
func snapshot(include_checkpoint: bool = true) -> Dictionary:
	ensure_posts()
	return {
		"v": SAVE_VERSION, "rules_v": 2, "formation_v": 2, "seed": run_seed, "themes": themes.duplicate(),
		"phase": phase, "wave": wave, "lives": lives, "gold": gold, "kills": kills,
		"best_hand": best_hand,
		"heroes": _heroes_out(heroes), "bench": _heroes_out(bench),
		"levels": levels.duplicate(), "passives": Array(passives).duplicate(),
		"owned_passives": _owned_passives_out(), "hero_damage": hero_damage.duplicate(true),
		"offer": Array(shop_offer).duplicate(), "repairs": repairs,
		"cards": Array(cards).duplicate(), "rerolled": Array(rerolled).duplicate(), "paid": Array(paid).duplicate(),
		"piles": _piles.duplicate(true), "at": Array(_at).duplicate(),
		"last": _last_out(), "rng": rng.state,
		"fusion": fusion_pending.duplicate(true), "fusion_serial": fusion_serial,
		"continue_used": continue_used,
		"checkpoint": battle_checkpoint.duplicate(true) if include_checkpoint else {},
	}


func _owned_passives_out() -> Array[String]:
	var out: Array[String] = owned_passives.duplicate()
	for id in passives:
		if not out.has(id):
			out.append(id)
	return out


func record_hero_damage(hero: Dictionary, damage: float) -> void:
	if not running or phase != Phase.BATTLE or damage <= 0.0 or not is_finite(damage):
		return
	var id := String(hero["unit"]["id"])
	var entry: Dictionary = hero_damage.get(id, {"tier": int(hero["tier"]), "damage": 0.0})
	entry["damage"] = float(entry["damage"]) + damage
	entry["tier"] = maxi(int(entry["tier"]), int(hero["tier"]))
	hero_damage[id] = entry


func best_player() -> Dictionary:
	var best: Dictionary = {}
	for id in hero_damage:
		var entry: Dictionary = hero_damage[id]
		if best.is_empty() or float(entry["damage"]) > float(best["damage"]):
			best = {"unit": Roster.unit_by_id(String(id)), "tier": int(entry["tier"]),
					"damage": float(entry["damage"])}
	# 이전 버전 저장에는 전과가 없다. 0 피해 동률에서는 먼저 출전한 영웅을 표시한다.
	if best.is_empty() and not heroes.is_empty():
		best = {"unit": heroes[0]["unit"], "tier": int(heroes[0]["tier"]), "damage": 0.0}
	return best


## 확정 결과를 저장할 수 있는 꼴로. 캐릭터 표(unit)는 id 하나로 줄인다 —
## 표 자체를 담으면 저장 파일이 캐릭터 표의 사본이 되어, 표가 바뀌면 옛 판이 거짓말을 한다.
func _last_out() -> Dictionary:
	if last_result.is_empty():
		return {}
	var d := last_result.duplicate()
	d["unit"] = String((last_result.get("unit", {}) as Dictionary).get("id", ""))
	d["cards"] = Array(last_result.get("cards", []) as Array)
	d["key"] = Array(last_result.get("key", []) as Array)
	return d


func _last_in(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	var u := Roster.unit_by_id(String(d.get("unit", "")))
	if u.is_empty():
		return {}
	var r := d.duplicate()
	r["unit"] = u
	r["cards"] = _ints(d.get("cards", []) as Array)
	r["key"] = _ints(d.get("key", []) as Array)
	r["hand"] = int(d.get("hand", 0))
	return r


## 담아 둔 판을 되돌린다. 되돌릴 수 없으면 거짓 — 그때는 새 판을 시작한다.
##
## ★ **전투 도중에 저장된 판은 그 탄의 시작으로 되돌린다**(phase 를 BATTLE 로 담아 두고
##   화면이 그 탄을 처음부터 다시 튼다). 전투 한복판의 몬스터 예순 마리와 탄 이백 개를
##   담는 것은 형식이 통째로 커지는 데다, 되돌린 판이 조금이라도 어긋나면 크리스탈이
##   맞지 않는다 — 「그 탄을 다시 한다」가 훨씬 정직하고 플레이어에게도 손해가 아니다.
func restore(d: Dictionary) -> bool:
	# 검사를 끝낸 뒤에만 현재 판을 바꾼다. 실패한 복구가 살아 있는 판을 훼손하면 안 된다.
	if not RunValidation.valid(d, SAVE_VERSION):
		return false
	d = d.duplicate(true)
	var w := int(d.get("wave", 0))
	if w <= 0:
		return false
	run_seed = int(d.get("seed", 0))
	# ★ 배열은 **제자리에서** 갈아 채운다(assign). 새 배열을 대입하면 이 배열을 들고 있던
	#   쪽(화면 · 검사기)이 옛것을 계속 본다 — 실제로 play_check 의 자동 저장 검사가 그렇게 깨졌다.
	themes.assign(_ints(d.get("themes", []) as Array))
	if themes.is_empty():
		roll_themes()
	# ★ 난수 상태를 그대로 잇는다. 씨앗을 (판 씨앗, 탄)으로 다시 심으면 등급마다
	#   캐릭터가 정확히 셋이라(CLAUDE.md 4-0) 뽑히는 인덱스가 족보와 무관하게 고정되고,
	#   그것을 알아낸 사람은 원하는 캐릭터를 골라 뽑을 수 있게 된다.
	if d.has("rng"):
		rng.state = int(d["rng"])
	else:
		rng.seed = run_seed + w * 7919
	wave = w
	lives = clampi(int(d.get("lives", Balance.START_LIVES)), 0, Balance.MAX_LIVES)
	gold = maxi(0, int(d.get("gold", 0)))
	kills = maxi(0, int(d.get("kills", 0)))
	best_hand = int(d.get("best_hand", -1))
	heroes.clear()
	bench.clear()
	for group in ["heroes", "bench"]:
		for entry in d.get(group, []):
			var h := _hero_in(entry)
			var copies := int(h.get("n", 1))
			h["n"] = 1
			for copy in range(copies):
				var item := h.duplicate(true)
				if group == "heroes" and copy == 0 and not field_full() and can_deploy(item["unit"]):
					heroes.append(item)
				else:
					item.erase("post")
					bench.append(item)
	ensure_posts()
	levels = (d.get("levels", {}) as Dictionary).duplicate()
	passives.clear()
	for pid in (d.get("passives", []) as Array):
		if not Balance.passive_by_id(String(pid)).is_empty() and passives.size() < Balance.PASSIVE_SLOTS:
			passives.append(String(pid))
	owned_passives.assign(d.get("owned_passives", d.get("passives", [])))
	hero_damage = d.get("hero_damage", {}).duplicate(true)
	shop_offer.clear()
	for oid in (d.get("offer", []) as Array):
		shop_offer.append(String(oid))
	repairs = maxi(0, int(d.get("repairs", 0)))
	cards.assign(_ints(d.get("cards", []) as Array))
	rerolled.assign(_ints(d.get("rerolled", []) as Array))
	paid.assign(_ints(d.get("paid", []) as Array))
	_piles = []
	for row in (d.get("piles", []) as Array):
		_piles.append(_ints(row as Array))
	_at.assign(_ints(d.get("at", []) as Array))
	last_result = _last_in(d.get("last", {}) as Dictionary)
	if not last_result.is_empty():
		# 이전 12인 편성을 옮긴 뒤에도 획득 팝업이 현재 대기 위치를 가리키게 한다.
		var found := latest_draw_location()
		if int(found[1]) >= 0:
			last_result["where"] = found[0]
			last_result["slot"] = found[1]
	last_hand = int(last_result.get("hand", -1))
	last_cards.assign(last_result.get("cards", []))
	last_key.assign(last_result.get("key", []))
	last_unit = last_result.get("unit", {})
	last_bumped = bool(last_result.get("bumped", false))
	last_joker = int(last_result.get("joker", -1))
	if best_hand < 0:
		for h in heroes + bench:
			best_hand = maxi(best_hand, int(h["tier"]))
	phase = int(d.get("phase", Phase.DRAW))
	# 확정했다고 담겼는데 그 결과가 없으면(캐릭터 표가 바뀌어 id 를 못 찾는 등)
	# 편성 판을 세울 수가 없다 — 전투로 보낸다. 영웅은 이미 받았으므로 손해가 없다.
	if phase == Phase.SWAP and last_result.is_empty():
		phase = Phase.BATTLE
	fusion_pending = d.get("fusion", {}).duplicate(true)
	fusion_serial = int(d.get("fusion_serial", 0))
	continue_used = bool(d.get("continue_used", false))
	battle_checkpoint = d.get("checkpoint", {}).duplicate(true)
	running = phase != Phase.OVER
	gold_changed.emit(gold)
	lives_changed.emit(lives)
	return true


## 지금 상태를 저장 파일에 적는다. **단계가 바뀔 때마다** 부른다(game/main.gd).
func autosave() -> void:
	if running or phase == Phase.OVER:
		Save.store_run(snapshot())
	else:
		Save.clear_run()


# Five-card fusion keeps an undo snapshot until its result is accepted.
## 대기 카드만 낮은 별부터, 같은 별이면 물·불·얼음·전기·무상성 순으로 표시한다.
const ELEMENT_ORDER := ["water", "fire", "ice", "elec", "none"]
func fusion_candidates() -> Array[int]:
	var out: Array[int] = []
	for i in range(bench.size()):
		out.append(FUSION_BENCH + i)
	out.sort_custom(func(a: int, b: int) -> bool:
		var ah: Dictionary = bench[a - FUSION_BENCH]
		var bh: Dictionary = bench[b - FUSION_BENCH]
		if int(ah["tier"]) != int(bh["tier"]):
			return int(ah["tier"]) < int(bh["tier"])
		var ae := ELEMENT_ORDER.find(String(ah["unit"].get("elem", "none")))
		var be := ELEMENT_ORDER.find(String(bh["unit"].get("elem", "none")))
		if ae != be:
			return ae < be
		var aid := String(ah["unit"]["id"])
		var bid := String(bh["unit"]["id"])
		return aid < bid if aid != bid else a < b)
	return out


## 현재 출전 슬롯은 합성으로 소모할 수 없다. 같은 캐릭터의 전당 보유분은 허용한다.
func fusion_material_allowed(code: int) -> bool:
	return code >= FUSION_BENCH and code - FUSION_BENCH < bench.size()


func fusion_materials(codes: Array) -> Array:
	var out: Array = []
	var seen := {}
	for value in codes:
		var code := int(value)
		if seen.has(code) or not fusion_material_allowed(code):
			return []
		seen[code] = true
		out.append(bench[code - FUSION_BENCH])
	return out


## 재료의 **누적 희귀도** — 등급(1~10)의 합. 합성 확률표(Balance.fusion_probabilities)의 입력이다.
static func fusion_score(materials: Array) -> int:
	var score := 0
	for h in materials:
		score += int(h["tier"]) + 1
	return score


func fusion_probabilities(codes: Array) -> Array[float]:
	var materials := fusion_materials(codes)
	if materials.size() != 5:
		return []
	return Balance.fusion_probabilities(fusion_score(materials))


func fuse_heroes(codes: Array) -> Dictionary:
	if not running or not phase in [Phase.SWAP, Phase.SHOP] or not fusion_pending.is_empty():
		return {}
	var materials := fusion_materials(codes)
	if materials.size() != 5:
		return {}
	var before_h := _heroes_out(heroes)
	var before_b := _heroes_out(bench)
	var top := 0
	for h in materials:
		top = maxi(top, int(h["tier"]))
	var score := fusion_score(materials)
	var probabilities := Balance.fusion_probabilities(score)
	var roll := rng.randf()
	var tier := 9
	for i in range(probabilities.size()):
		roll -= probabilities[i]
		if roll <= 0:
			tier = i
			break
	var descending := codes.duplicate()
	descending.sort()
	descending.reverse()
	for code in descending:
		bench.remove_at(int(code) - FUSION_BENCH)
	var unit := Roster.pick_unit(tier, rng)
	gain_hero(unit, tier, false)
	fusion_serial += 1
	fusion_pending = {"id": fusion_serial, "before_h": before_h, "before_b": before_b,
			"unit": String(unit["id"]), "tier": tier, "score": score,
			"failed": tier <= top and not (tier == 9 and top == 9)}
	Save.seen_units[String(unit["id"])] = true
	autosave()
	return fusion_pending


func accept_fusion() -> void:
	fusion_pending = {}
	autosave()


func undo_fusion() -> bool:
	if not reward_allowed("fusion_undo", {"fusion_id": fusion_pending.get("id", -1)}):
		return false
	heroes.clear()
	bench.clear()
	for h in fusion_pending["before_h"]:
		heroes.append(_hero_in(h))
	for h in fusion_pending["before_b"]:
		bench.append(_hero_in(h))
	fusion_pending = {}
	ensure_posts()
	autosave()
	return true


func prepare_battle() -> void:
	fusion_pending = {}
	if phase != Phase.BATTLE or battle_checkpoint.is_empty():
		phase = Phase.BATTLE
		battle_checkpoint = snapshot(false)
	autosave()


func reward_allowed(kind: String, data: Dictionary = {}) -> bool:
	if data.has("seed") and (int(data["seed"]) != run_seed or int(data.get("wave", -1)) != wave):
		return false
	match kind:
		"card":
			var slot := int(data.get("slot", -1))
			if not card_choice_allowed(slot, int(data.get("card", -1)), int(data.get("expected", -1))):
				return false
			return not data.has("revision") or int(data["revision"]) == rerolled[slot]
		"fusion_undo":
			return running and phase in [Phase.SWAP, Phase.SHOP] \
					and not fusion_pending.is_empty() \
					and int(data.get("fusion_id", -1)) == int(fusion_pending.get("id", -2))
		"crystal":
			return running and phase == Phase.SHOP and lives < max_lives()
		"continue":
			return phase == Phase.OVER and not battle_checkpoint.is_empty()
	return false


func apply_ad_reward(kind: String, data: Dictionary) -> bool:
	if not reward_allowed(kind, data):
		return false
	match kind:
		"card":
			var slot := int(data["slot"])
			cards[slot] = int(data["card"])
			rerolled[slot] += 1
		"fusion_undo":
			return undo_fusion()
		"crystal":
			add_lives(max_lives())
		"continue":
			return revive_wave()
	autosave()
	return true


func revive_wave() -> bool:
	if not reward_allowed("continue"):
		return false
	var checkpoint := battle_checkpoint.duplicate(true)
	if not restore(checkpoint):
		return false
	continue_used = true
	lives = max_lives()
	var pool: Array = []
	for unit in Roster.units_of_tier(Poker.Hand.ROYAL):
		if can_deploy(unit):
			pool.append(unit)
	if pool.is_empty():
		pool = Roster.units_of_tier(Poker.Hand.ROYAL)
	var unit: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	# 광고 보상은 전당에 보관한다. 전장의 누구를 교체할지는 사용자가 결정한다.
	var got := gain_hero(unit, Poker.Hand.ROYAL, false, false)
	last_result = {"hand": Poker.Hand.ROYAL, "cards": Array(cards), "key": [],
			"unit": unit, "bumped": false, "joker": -1, "showy": true,
			"stacked": false, "where": got["where"], "slot": got["slot"],
			"n": 1, "revived": true, "reward_pending": true}
	Save.seen_units[String(unit["id"])] = true
	battle_checkpoint = {}
	phase = Phase.SWAP
	running = true
	lives_changed.emit(lives)
	autosave()
	return true


## 획득 연출 확인만 저장한다. 재접속/중복 터치로 영웅을 다시 지급하지 않는다.
func acknowledge_revive_reward() -> bool:
	if not running or phase != Phase.SWAP or not continue_used \
			or not bool(last_result.get("revived", false)) \
			or not bool(last_result.get("reward_pending", false)):
		return false
	last_result["reward_pending"] = false
	autosave()
	return true
