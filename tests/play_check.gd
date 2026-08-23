extends Node

## 화면을 실제로 세워 놓고 **손가락으로 눌러** 타이틀 → 카드 → 전투 → 상점을 돌린다.
##
## 왜 필요한가: 이 머신에는 화면이 없다. 배치가 어긋나는 건 사진으로 보지만,
## "버튼을 눌렀는데 아무 일도 안 일어난다" 같은 것은 사진으로도 안 보인다.
## 여기서는 **그리기가 등록한 바로 그 자리**를 눌러서, 그린 것과 눌리는 것이
## 같은지까지 확인한다.
##
##   godot --headless --path . res://tests/play_check.tscn

const WAVES := 4

var fail := 0
var main: Node2D = null


func _bad(msg: String) -> void:
	printerr("!! " + msg)
	fail += 1


func _ready() -> void:
	main = load("res://game/main.gd").new()
	main.name = "Main"
	add_child(main)
	await _frames(2)

	await _step_title()
	for w in range(WAVES):
		await _step_draw(w)
		await _step_battle(w)
		if not Run.running:
			break
		await _step_shop(w)

	await _step_swap()
	await _step_leak()
	await _step_gameover()

	if fail == 0:
		print("판정: 정상")
	else:
		printerr("!! 실패 %d건" % fail)
	get_tree().quit(0 if fail == 0 else 1)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## 화면을 한 번 그리게 하고 버튼 자리가 등록될 때까지 기다린다.
func _paint() -> Ui:
	var s = main.screen
	s.queue_redraw()
	await _frames(2)
	var u: Ui = s.ui
	if u.zones.is_empty():
		_bad("%s 가 아무 버튼도 등록하지 않았다 (_draw 가 안 돈다)" % s.get_class())
	return u


func _tap(u: Ui, id: String) -> bool:
	for z in u.zones:
		if String(z["id"]) == id:
			if not bool(z["on"]):
				return false
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = true
			ev.position = Rect2(z["rect"]).get_center()
			main.screen._input(ev)
			return true
	return false


## 화면이 바뀔 때까지 기다린다(페이드가 있으므로 몇 프레임 걸린다).
func _wait_for(cls: String, limit: int = 300) -> bool:
	for i in range(limit):
		await get_tree().process_frame
		if main.screen != null and main.screen.get_script() != null:
			var p: String = main.screen.get_script().resource_path
			if p.get_file().get_basename() == cls:
				return true
	_bad("%s 로 넘어가지 않는다 (지금은 %s)" % [cls, main.screen])
	return false


func _step_title() -> void:
	if not (main.screen is TitleScreen):
		_bad("첫 화면이 타이틀이 아니다")
		return
	var u := await _paint()
	if not _tap(u, "start"):
		_bad("타이틀의 시작 버튼을 못 눌렀다")
	await _wait_for("draw_screen")


func _step_draw(w: int) -> void:
	var u := await _paint()
	if Run.cards.size() != 5:
		_bad("%d탄: 카드가 %d장이다" % [Run.wave, Run.cards.size()])
	# 리롤 — 공짜가 남아 있는 첫 카드를 한 번 바꾼다.
	var before: int = Run.cards[0]
	var gold_before := Run.gold
	if Run.reroll_cost_of(0) != 0:
		_bad("%d탄: 첫 리롤이 공짜가 아니다" % Run.wave)
	if not _tap(u, "re0"):
		_bad("%d탄: 리롤 버튼을 못 눌렀다" % Run.wave)
	if Run.cards[0] == before and Run.rerolled[0] == 0:
		_bad("%d탄: 리롤을 눌렀는데 카드가 그대로다" % Run.wave)
	if Run.gold != gold_before:
		_bad("%d탄: 공짜 리롤인데 골드가 줄었다" % Run.wave)
	# 공짜를 다 쓴 카드는 값이 붙어야 한다
	if Run.free_rerolls() == 1 and Run.reroll_cost_of(0) <= 0:
		_bad("%d탄: 한 번 바꾼 카드가 여전히 공짜다 — 규칙이 깨졌다" % Run.wave)

	u = await _paint()
	if not _tap(u, "go"):
		_bad("%d탄: 결정 버튼을 못 눌렀다" % Run.wave)
	# ★ 같은 캐릭터가 또 나오면 옆에 서지 않고 **겹친다.** 그래서 세는 것은 자릿수가
	#   아니라 겹친 수까지 더한 hero_total() 이다.
	if Run.hero_total() != w + 1:
		_bad("%d탄: 영웅이 %d명이다 (%d명이어야 한다)" % [Run.wave, Run.hero_total(), w + 1])
	if Run.heroes.size() > Balance.HERO_SLOTS:
		_bad("%d탄: 안뜰에 %d명이 섰다 (%d명까지다)"
				% [Run.wave, Run.heroes.size(), Balance.HERO_SLOTS])
	# ★ 확정한 뒤 연출이 도는 동안 화면은 아직 트리에 있다. 여기서 「결정!」을 또 누르면
	#   영웅이 공짜로 하나 더 생기는 버그가 있었다. 눌러 보고 안 늘어나는지 확인한다.
	var again: Ui = main.screen.ui
	_tap(again, "go")
	_tap(again, "re0")
	if Run.hero_total() != w + 1:
		_bad("%d탄: 연출 중에 또 눌렀더니 영웅이 %d명이 됐다" % [Run.wave, Run.hero_total()])
	# 연출이 끝나고 전투로
	await _wait_for("battle_screen", 600)


func _step_battle(_w: int) -> void:
	var b = main.screen
	b.speed = 3.0
	# 아이템을 하나 쥐여 주고 **전투 화면에서 실제로 눌러** 본다.
	Run.items["bomb"] = maxi(1, Run.item_count("bomb"))
	var used := false
	# ★ 프레임 수가 아니라 **벽시계**로 잰다. 헤드리스는 초당 프레임 수가 기계마다
	#   달라서, 프레임으로 세면 빠른 기계에서 전투가 끝나기도 전에 실패로 친다.
	var t0 := Time.get_ticks_msec()
	while not b.sim.done and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		b.queue_redraw()
		await _frames(1)
		if not used and b.sim.elapsed > 2.0:
			used = true
			var before: int = Run.item_count("bomb")
			if not _tap(b.ui, "it:bomb"):
				_bad("%d탄: 아이템 버튼을 못 눌렀다" % Run.wave)
			elif Run.item_count("bomb") != before - 1:
				_bad("%d탄: 아이템을 썼는데 개수가 안 줄었다" % Run.wave)
	if not b.sim.done:
		_bad("%d탄 전투가 안 끝난다" % Run.wave)
		return
	if b.sim.kills == 0 and b.sim.leaked == 0:
		_bad("%d탄: 잡지도 놓치지도 않았다 — 전투가 안 돌았다" % Run.wave)
	# ★ 크리스탈은 몬스터가 닿는 순간에만 깎인다. 결과창에서 또 깎이면 두 배로 깎인다.
	var before_lives: int = Run.lives
	await _frames(4)
	if Run.lives != before_lives:
		_bad("%d탄: 전투가 끝난 뒤에 크리스탈이 또 깎였다 (%d → %d)"
				% [Run.wave, before_lives, Run.lives])
	await _paint()      # 결과 배너도 그려 본다
	if Run.running:
		await _wait_for("shop_screen", 600)


func _step_shop(_w: int) -> void:
	var u := await _paint()
	var gold_before := Run.gold
	var bought := false
	for up in Balance.UPGRADES:
		var id := String(up["id"])
		if Run.gold >= Balance.upgrade_cost(id, Run.lv(id)):
			if _tap(u, "u:" + id):
				bought = true
				break
	if bought and Run.gold >= gold_before:
		_bad("상점에서 샀는데 골드가 안 줄었다")

	# 무기 탭 — 사고, 다시 빼서 절반을 돌려받는다
	u = await _paint()
	if not _tap(u, "tab:w"):
		_bad("상점의 무기 탭을 못 눌렀다")
	u = await _paint()
	Run.gold += 400          # 검사에서는 살 수 있게 넉넉히 쥐여 준다
	u = await _paint()
	var wid := String(Balance.WEAPONS[0]["id"])
	if not Run.has_weapon(wid) and not Run.weapon_full():
		if not _tap(u, "w:" + wid):
			_bad("무기를 못 샀다")
		elif not Run.has_weapon(wid):
			_bad("무기 버튼을 눌렀는데 장착이 안 됐다")
		else:
			u = await _paint()
			var g0 := Run.gold
			if not _tap(u, "ws:" + wid):
				_bad("무기 빼기를 못 눌렀다")
			elif Run.has_weapon(wid):
				_bad("무기를 뺐는데 그대로 장착돼 있다")
			elif Run.gold <= g0:
				_bad("무기를 뺐는데 골드가 안 돌아왔다")

	# 아이템 탭 — 하나 산다
	u = await _paint()
	if not _tap(u, "tab:i"):
		_bad("상점의 아이템 탭을 못 눌렀다")
	u = await _paint()
	var iid := String(Balance.ITEMS[0]["id"])
	var have := Run.item_count(iid)
	# ★ _tap 이 거짓을 돌려주면 조용히 넘어가면 안 된다 — 버튼이 사라져도 검사가 통과한다.
	if have >= Balance.ITEM_MAX:
		pass                       # 다 찼으면 못 사는 게 맞다
	elif not _tap(u, "i:" + iid):
		_bad("상점의 아이템 버튼을 못 눌렀다 (골드 %d, 값 %d)"
				% [Run.gold, int(Balance.ITEMS[0]["cost"])])
	elif Run.item_count(iid) != have + 1:
		_bad("아이템을 샀는데 개수가 안 늘었다")

	# 영웅 탭 — 안뜰과 인벤토리를 실제로 맞바꾼다
	u = await _paint()
	if not _tap(u, "tab:h"):
		_bad("상점의 영웅 탭을 못 눌렀다")
	u = await _paint()
	await _swap_once(u, "상점")

	u = await _paint()
	if not _tap(u, "next"):
		_bad("상점의 다음 버튼을 못 눌렀다")
	await _wait_for("draw_screen", 600)


## 편성 판에서 안뜰 0번과 인벤토리 0번을 눌러 맞바꾼다. 둘 다 있을 때만 뜻이 있다.
## ★ 이 판은 뽑기 화면과 상점 **둘 다**에 뜬다. 같은 함수로 둘을 다 눌러 본다 —
##   한쪽만 확인하면 나머지 한쪽에서 버튼 id 가 어긋나도 검사가 통과한다.
func _swap_once(u: Ui, where: String) -> void:
	if Run.heroes.is_empty() or Run.bench.is_empty():
		return
	var before_f := String(Run.heroes[0]["unit"]["id"])
	var before_b := String(Run.bench[0]["unit"]["id"])
	var total := Run.hero_total()
	if not _tap(u, "hv:f0"):
		_bad("%s: 안뜰 0번을 못 눌렀다" % where)
		return
	u = await _paint()
	if not _tap(u, "hv:b0"):
		_bad("%s: 인벤토리 0번을 못 눌렀다" % where)
		return
	if String(Run.heroes[0]["unit"]["id"]) != before_b \
			or String(Run.bench[0]["unit"]["id"]) != before_f:
		_bad("%s: 두 자리를 눌렀는데 안 바뀌었다 (%s / %s)"
				% [where, Run.heroes[0]["unit"]["id"], Run.bench[0]["unit"]["id"]])
	if Run.hero_total() != total:
		_bad("%s: 자리를 바꿨더니 영웅 수가 %d → %d 로 바뀌었다"
				% [where, total, Run.hero_total()])


## 안뜰이 꽉 찬 채로 새 영웅이 오면 **교체 창**이 뜨는가.
##
## ★ 앞 네 탄으로는 이걸 못 잡는다 — 여섯 자리가 안 차기 때문이다. 그래서 여기서
##   일부러 서로 다른 캐릭터로 여섯 자리를 채운 다음 한 명을 더 받는다.
func _step_swap() -> void:
	if not Run.running:
		return
	Run.heroes.clear()
	Run.bench.clear()
	# 서로 다른 캐릭터 여섯으로 안뜰을 채운다(같은 캐릭터면 겹쳐 버려서 자리가 안 찬다).
	# ★ **높은 등급 쪽부터** 채운다. 낮은 등급으로 채우면 다음에 뽑는 흔한 족보가
	#   이미 선 캐릭터와 겹쳐서 교체 창이 안 뜨고, 검사가 조용히 아무것도 안 한다.
	for i in range(Roster.UNITS.size() - 1, -1, -1):
		if Run.heroes.size() >= Balance.HERO_SLOTS:
			break
		var u: Dictionary = Roster.UNITS[i]
		Run.gain_hero(u, int(u["tier"]))
	if Run.heroes.size() != Balance.HERO_SLOTS:
		_bad("안뜰 여섯 자리를 못 채웠다 (%d명)" % Run.heroes.size())
		return
	Run.begin_draw()
	var d := DrawScreen.new()
	main._swap(d)
	await _frames(3)
	var u2 := await _paint()
	if not _tap(u2, "go"):
		_bad("교체 검사: 결정 버튼을 못 눌렀다")
		return
	# 연출이 끝날 때까지 기다린다 — 끝나면 교체 창(SWAP)으로 가야 한다.
	# ★ 화면이 먼저 바뀌어 버리는 쪽도 봐야 한다. state 만 기다리면 겹쳤을 때
	#   여기서 20초를 그냥 서 있는다.
	var t0 := Time.get_ticks_msec()
	while d.state != DrawScreen.SWAP and main.screen == d \
			and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		d.queue_redraw()
	if d.state != DrawScreen.SWAP:
		# 겹쳤으면 교체 창이 안 뜨는 것이 맞다 — 그때는 검사할 것이 없다.
		if not bool(d.result.get("stacked", false)):
			_bad("안뜰이 꽉 찼는데 교체 창이 안 떴다 (state %d, 대기 %d명)"
					% [d.state, Run.bench.size()])
		await _wait_for("battle_screen", 600)
		return
	var u3 := await _paint()
	await _swap_once(u3, "교체 창")
	var u4 := await _paint()
	if not _tap(u4, "tobattle"):
		_bad("교체 창의 「이대로 전투로」를 못 눌렀다")
	await _wait_for("battle_screen", 600)


## 뚫렸을 때 크리스탈이 **딱 그만큼만** 깎이는가.
##
## ★ 앞 네 탄은 한 마리도 안 놓쳐서 이걸 물어볼 상황 자체가 안 만들어진다. 그래서
##   일부러 감당 못 할 탄을 세운다. 예전 규칙(시간이 끝나면 남은 수만큼)의 흔적이
##   화면 쪽에 남아 있으면 여기서 두 배로 깎여 걸린다.
func _step_leak() -> void:
	if not Run.running:
		return
	# ★ 안뜰을 **가장 약한 영웅 하나만** 남기고 비운다. 앞 검사(_step_swap)가 로열급
	#   여섯을 세워 놓기 때문에, 그대로 두면 12탄이 한 마리도 안 뚫려서 이 검사가
	#   조용히 아무것도 확인하지 않게 된다(실제로 그랬다).
	Run.heroes.clear()
	Run.bench.clear()
	Run.gain_hero(Roster.UNITS[0], int(Roster.UNITS[0]["tier"]))
	Run.wave = 12
	Run.levels["life"] = 20
	Run.lives = Run.max_lives()
	var before: int = Run.lives
	var b := BattleScreen.new()
	main._swap(b)
	await _frames(3)
	b.speed = 3.0
	var t0 := Time.get_ticks_msec()
	while not b.sim.done and Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
	if not b.sim.done:
		_bad("일부러 어려운 탄을 세웠는데 전투가 안 끝난다")
		return
	if b.sim.leaked <= 0:
		_bad("영웅 %d명(%s)으로 12탄을 세웠는데 한 마리도 안 뚫렸다 — 검사가 뜻이 없어졌다"
				% [Run.heroes.size(), Run.heroes[0]["unit"]["ko"] if not Run.heroes.is_empty() else "-"])
	# 결과 정산이 도는 몇 프레임을 지나 보낸다
	await _frames(8)
	if Run.lives != maxi(0, before - b.sim.leaked):
		_bad("크리스탈이 %d → %d 인데 깨진 것은 %d 이다 — 어디선가 두 번 깎는다"
				% [before, Run.lives, b.sim.leaked])
	if b.sim.leak_n < b.sim.leaked and not Balance.is_boss_wave(12):
		_bad("닿은 마릿수(%d)보다 깨진 크리스탈(%d)이 많다" % [b.sim.leak_n, b.sim.leaked])


## 목숨이 0 이 되면 정말로 끝나는가.
func _step_gameover() -> void:
	Run.lives = 1
	Run.add_lives(-1)
	if Run.running:
		_bad("목숨이 0 인데 판이 안 끝났다")
	if Run.phase != Run.Phase.OVER:
		_bad("목숨이 0 인데 단계가 OVER 가 아니다")
	main._swap(OverScreen.new())
	var u := await _paint()
	if not _tap(u, "again"):
		_bad("끝 화면의 다시 버튼을 못 눌렀다")
