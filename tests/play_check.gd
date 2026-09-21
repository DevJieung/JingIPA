extends Harness

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
	await frames(2)

	await _step_title()
	for w in range(WAVES):
		await _step_draw(w)
		await _step_battle(w)
		if not Run.running:
			break
		await _step_shop(w)

	await _step_swap()
	await _step_hall()
	await _step_battle_flush()
	await _step_save()
	await _step_leak()
	await _step_gameover()

	if fail == 0:
		print("판정: 정상")
	else:
		printerr("!! 실패 %d건" % fail)
	get_tree().quit(0 if fail == 0 else 1)


## 화면을 한 번 그리게 하고 버튼 자리가 등록될 때까지 기다린다.
func _paint() -> Ui:
	var s = main.screen
	s.queue_redraw()
	await frames(2)
	var u: Ui = s.ui
	if u.zones.is_empty():
		_bad("%s 가 아무 버튼도 등록하지 않았다 (_draw 가 안 돈다)" % s.get_class())
	return u


## `_paint()` 가 돌려준 Ui 의 자리를 누른다. Ui 는 main.screen.ui 그것이라 화면에서 다시 찾는다.
func _tap(_u: Ui, id: String) -> bool:
	return press(main.screen, id)


## **눌렀다 뗀다.** 편성 판의 전당 칸은 끌어서 굴릴 수 있어서, 누르는 순간이 아니라
## **떼는 순간**에 고르기가 정해진다(HeroView.release). 누르기만 하면 아무 일도 안 난다.
func _tap_release(_u: Ui, id: String) -> bool:
	return tap(main.screen, id)


## 테마 판이 떠 있으면 눌러 넘긴다. **열 탄마다 한 번** 뜨므로 1탄 앞에도 뜬다.
func _pass_theme() -> void:
	if not (main.screen is ThemeScreen):
		return
	await frames(30)          # 넘길 수 있게 되기를 기다린다(0.35초)
	mouse(main.screen, Vector2(640, 400), true)
	await _wait_for("draw_screen", 600)


## 화면이 바뀔 때까지 기다린다(페이드가 있으므로 몇 프레임 걸린다).
func _wait_for(cls: String, limit: int = 300) -> bool:
	if await wait_screen(main, cls, limit):
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
	# ★ 1탄 앞에는 **테마 판**이 먼저 뜬다(열 탄마다 한 번). 그것을 넘겨야 뽑기다.
	if not await _wait_for("theme_screen", 300):
		_bad("타이틀에서 테마 판으로 안 넘어간다")
		return
	await _pass_theme()


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
	# ★ **리롤은 누른 그 순간 담겨야 한다.** 안 담기면 뽑기 화면에서 앱을 껐다 켰을 때
	#   리롤 횟수가 0 으로 되돌아가서 **공짜 리롤이 되살아난다** — 그게 곧 무한 리롤이다.
	#   (POCKER_NO_SAVE=1 에서도 잡힌다: Save.store_run 이 파일에 쓰기 **전에**
	#    cur_run 에 담고 나서 읽기 전용인지를 보기 때문이다.)
	if Array(Save.cur_run.get("rerolled", [])) != Array(Run.rerolled):
		_bad("%d탄: 리롤을 눌렀는데 이어할 판에 안 담겼다 (앱을 껐다 켜면 공짜 리롤이 되살아난다) — 담긴 것 %s / 실제 %s"
				% [Run.wave, str(Save.cur_run.get("rerolled", [])), str(Run.rerolled)])

	u = await _paint()
	if not _tap(u, "go"):
		_bad("%d탄: 결정 버튼을 못 눌렀다" % Run.wave)
	# ★ 같은 캐릭터가 또 나오면 옆에 서지 않고 **겹친다.** 그래서 세는 것은 자릿수가
	#   아니라 겹친 수까지 더한 hero_total() 이다.
	if Run.hero_total() != w + 1:
		_bad("%d탄: 영웅이 %d명이다 (%d명이어야 한다)" % [Run.wave, Run.hero_total(), w + 1])
	if Run.heroes.size() > Balance.HERO_SLOTS:
		_bad("%d탄: 성역에 %d명이 섰다 (%d명까지다)"
				% [Run.wave, Run.heroes.size(), Balance.HERO_SLOTS])
	# ★ **확정하는 순간 담겨야 하고, 담긴 단계가 SWAP 이어야 한다.** 예전에는 phase 가
	#   DRAW 인 채로 담겨서, 확정 뒤 홈 버튼을 누르면 이어하기가 뽑기 화면을 다시 띄웠고
	#   「결정!」을 한 번 더 눌러 **영웅이 공짜로 하나 더** 생겼다. 그 익스플로잇을 막는다.
	if int(Save.cur_run.get("phase", -1)) != Run.Phase.SWAP:
		_bad("%d탄: 확정했는데 이어할 판이 아직 확정 전이다 (재시작하면 영웅이 복제된다) — 담긴 단계 %d"
				% [Run.wave, int(Save.cur_run.get("phase", -1))])
	# 담긴 영웅 수는 **겹친 몫(n)까지 세어** 지금과 같아야 한다. 하나라도 어긋나면
	# 이어 한 판의 화력이 조용히 달라진다.
	var snap_total := 0
	for hd in Array(Save.cur_run.get("heroes", [])):
		snap_total += int((hd as Dictionary).get("n", 1))
	for hd2 in Array(Save.cur_run.get("bench", [])):
		snap_total += int((hd2 as Dictionary).get("n", 1))
	if snap_total != Run.hero_total():
		_bad("%d탄: 확정했는데 이어할 판의 영웅이 %d명이다 (지금은 %d명) — 재시작하면 그만큼 어긋난다"
				% [Run.wave, snap_total, Run.hero_total()])
	# ★ 확정은 **한 탄에 한 번**이다. 화면을 안 거치고 함수를 곧장 두 번 불러도 영웅이
	#   늘면 안 된다 — 화면 쪽 빗장(_leaving)이 아니라 규칙 자체가 막아야 한다.
	var dup_before: int = Run.hero_total()
	Run.confirm_hand()
	if Run.hero_total() != dup_before:
		_bad("%d탄: confirm_hand() 를 두 번 불렀더니 영웅이 %d → %d 가 됐다"
				% [Run.wave, dup_before, Run.hero_total()])
	# ★ 확정한 뒤 연출이 도는 동안 화면은 아직 트리에 있다. 여기서 「결정!」을 또 누르면
	#   영웅이 공짜로 하나 더 생기는 버그가 있었다. 눌러 보고 안 늘어나는지 확인한다.
	var again: Ui = main.screen.ui
	_tap(again, "go")
	_tap(again, "re0")
	if Run.hero_total() != w + 1:
		_bad("%d탄: 연출 중에 또 눌렀더니 영웅이 %d명이 됐다" % [Run.wave, Run.hero_total()])
	# 연출이 끝나면 **편성 판**이 뜬다 — 이제 탄마다 빠짐없이.
	await _to_battle_via_board(main.screen)


## 확정 연출이 끝나면 편성 판(SWAP)이 뜬다 — **탄마다 빠짐없이**. 그 판을 눌러 전투로 간다.
##
## ★ 예전에는 성역이 꽉 찼을 때만 떴고, 그래서 이 검사도 확정한 뒤 곧장 전투를 기다렸다.
##   지금은 판을 안 넘기면 전투가 영영 시작되지 않는다 — 여기를 빼먹으면 검사가
##   "전투로 안 넘어간다"고만 말하고 진짜 이유는 안 알려 준다.
func _to_battle_via_board(d) -> void:
	var t0 := Time.get_ticks_msec()
	while d.state != DrawScreen.SWAP and main.screen == d \
			and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		d.queue_redraw()
		if d.state == DrawScreen.REVEAL and d.rt > 1.6:
			mouse(d, Vector2(640, 760), true)
	if d.state != DrawScreen.SWAP:
		_bad("%d탄: 확정했는데 편성 판이 안 떴다 (state %d)" % [Run.wave, d.state])
		await _wait_for("battle_screen", 600)
		return
	var u := await _paint()
	if not _tap(u, "tobattle"):
		_bad("%d탄: 편성 판의 「전투 시작」을 못 눌렀다" % Run.wave)
	await _wait_for("battle_screen", 600)


func _step_battle(_w: int) -> void:
	var b = main.screen
	# ★ 배속은 **눌러서** 건다. 그래야 「눌렀더니 설정에 남는가」까지 같이 본다 —
	#   사용자가 정한 것이 그것이다(배속 설정해 놓으면 유지되게).
	var su := await _paint()
	if not _tap(su, "sp3"):
		_bad("%d탄: 배속 버튼을 못 눌렀다" % Run.wave)
	elif not is_equal_approx(b.speed, 3.0):
		_bad("%d탄: 배속을 눌렀는데 화면이 %0.1f배다" % [Run.wave, b.speed])
	elif not is_equal_approx(Save.speed, 3.0):
		_bad("%d탄: 배속이 설정에 안 남았다 (%0.1f)" % [Run.wave, Save.speed])
	# ★ 프레임 수가 아니라 **벽시계**로 잰다. 헤드리스는 초당 프레임 수가 기계마다
	#   달라서, 프레임으로 세면 빠른 기계에서 전투가 끝나기도 전에 실패로 친다.
	var t0 := Time.get_ticks_msec()
	while not b.sim.done and Time.get_ticks_msec() - t0 < 60000:
		await get_tree().process_frame
		b.queue_redraw()
		await frames(1)
	if not b.sim.done:
		_bad("%d탄 전투가 안 끝난다" % Run.wave)
		return
	if b.sim.kills == 0 and b.sim.leaked == 0:
		_bad("%d탄: 잡지도 놓치지도 않았다 — 전투가 안 돌았다" % Run.wave)
	# ★ 크리스탈은 몬스터가 닿는 순간에만 깎인다. 결과창에서 또 깎이면 두 배로 깎인다.
	var before_lives: int = Run.lives
	await frames(4)
	if Run.lives != before_lives:
		_bad("%d탄: 전투가 끝난 뒤에 크리스탈이 또 깎였다 (%d → %d)"
				% [Run.wave, before_lives, Run.lives])
	await _paint()      # 전과 판도 그려 본다
	# ★ 전과 판은 이제 영웅별 피해와 처치를 줄줄이 그린다. 합이 실제와 맞는지 본다 —
	#   여기가 어긋나면 "누가 일했는지"를 보고 편성을 짜는 사람이 속는다.
	var sum_k := 0
	for he in b.sim.heroes:
		sum_k += int(he.get("kills", 0))
	if sum_k > b.sim.kills:
		_bad("%d탄: 영웅별 처치 합(%d)이 실제 처치(%d)보다 많다"
				% [Run.wave, sum_k, b.sim.kills])
	# 전과 판은 플레이어가 탭해야 넘어간다.
	await frames(40)
	mouse(main.screen, Vector2(640, 700), true)
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

	# 보유 구매와 활성 선택은 분리되며, 판매/크리스탈 구매 탭은 없다.
	u = await _paint()
	if not _tap(u, "tab:p"):
		_bad("상점의 패시브 탭을 못 눌렀다")
	Run.gold += 3000
	u = await _paint()
	var offer := Run.offer_passives(3)
	if not offer.is_empty():
		var pid := String(offer[0]["id"])
		var had := Run.owned_passives.size()
		var g0 := Run.gold
		if not _tap(u, "p:" + pid):
			_bad("활성 칸과 관계없이 패시브를 구매할 수 있어야 함")
		elif not Run.owns_passive(pid) or Run.owned_passives.size() != had + 1:
			_bad("구매한 패시브가 보유 목록에 없음")
		elif Run.gold != g0 - int(offer[0]["cost"]):
			_bad("패시브 구매는 전체 가격을 지불해야 함")
		if Run.passives.size() > Balance.PASSIVE_SLOTS:
			_bad("활성 패시브 세 칸을 넘음")
		if Run.has(pid):
			u = await _paint()
			g0 = Run.gold
			if not _tap(u, "active:" + pid) or Run.has(pid):
				_bad("활성 패시브 해제 실패")
			if not Run.owns_passive(pid) or Run.gold != g0:
				_bad("활성 해제는 보유/골드를 바꾸면 안 됨")
			u = await _paint()
			if not _tap(u, "active:" + pid) or not Run.has(pid):
				_bad("보유 패시브 재활성 실패")
	u = await _paint()
	if _tap(u, "tab:c") or _tap(u, "repair"):
		_bad("삭제된 크리스탈 구매 화면이 노출됨")

	u = await _paint()
	if not _tap(u, "next"):
		_bad("상점의 다음 버튼을 못 눌렀다")
	# 열한 탄째 앞에는 테마 판이 한 번 더 뜬다. 넉 탄만 도는 검사에서는 안 뜬다.
	await _wait_for("draw_screen", 600)


## 편성 판에서 성역 0번과 전당 0번을 눌러 맞바꾼다. 둘 다 있을 때만 뜻이 있다.
##
## ★ 누르는 규칙이 바뀌었다: 아무것도 안 고른 상태에서 누르면 **설명 팝업**이 먼저 뜨고,
##   거기서 「옮기기」를 눌러야 골라진다. 팝업을 안 거치고 맞바꿔지면 규칙이 깨진 것이다.
## ★ 전당 칸은 **끌어서 굴리는** 자리라 누르기만 해서는 안 골라진다 — 떼야 한다
##   (_tap_release). 여기가 어긋나면 폰에서 목록을 굴릴 때마다 영웅이 골라진다.
func _swap_once(u: Ui, where: String) -> void:
	if Run.heroes.is_empty() or Run.bench.is_empty():
		return
	var before_f := String(Run.heroes[0]["unit"]["id"])
	var before_b := String(Run.bench[0]["unit"]["id"])
	var total := Run.hero_total()
	if not _tap(u, "formation:roster"):
		_bad("영웅 정보 탭을 못 눌렀다")
	u = await _paint()
	if not _tap(u, "hv:f0"):
		_bad("%s: 성역 0번을 못 눌렀다" % where)
		return
	u = await _paint()
	# 팝업이 떴어야 한다.
	var hv = main.screen.hv
	if hv.info < 0:
		_bad("%s: 캐릭터를 눌렀는데 설명 팝업이 안 떴다" % where)
		return
	if not _tap(u, "hv:move"):
		_bad("%s: 팝업의 「옮기기」를 못 눌렀다" % where)
		return
	u = await _paint()
	if not _tap_release(u, "hv:b0"):
		_bad("%s: 전당 0번을 못 눌렀다" % where)
		return
	if String(Run.heroes[0]["unit"]["id"]) != before_b \
			or String(Run.bench[0]["unit"]["id"]) != before_f:
		_bad("%s: 두 자리를 눌렀는데 안 바뀌었다 (%s / %s)"
				% [where, Run.heroes[0]["unit"]["id"], Run.bench[0]["unit"]["id"]])
	if Run.hero_total() != total:
		_bad("%s: 자리를 바꿨더니 영웅 수가 %d → %d 로 바뀌었다"
				% [where, total, Run.hero_total()])


## 성역이 꽉 찬 채로 새 영웅이 오면 편성 판에서 **맞바꿀 수 있는가.**
##
## ★ 판이 뜨는가는 앞 네 탄이 이미 본다(탄마다 뜬다). 여기서 보는 것은 그 판에서
##   성역과 전당을 실제로 맞바꿀 수 있는가다 — 여섯 자리가 안 차면 전당이
##   비어서 맞바꿀 것이 아예 없다. 그래서 일부러 서로 다른 캐릭터로 여섯을 채운다.
func _step_swap() -> void:
	if not Run.running:
		return
	Run.heroes.clear()
	Run.bench.clear()
	# 서로 다른 캐릭터 여섯으로 성역을 채운다(같은 캐릭터면 겹쳐 버려서 자리가 안 찬다).
	# ★ **높은 등급 쪽부터** 채운다. 낮은 등급으로 채우면 다음에 뽑는 흔한 족보가
	#   이미 선 캐릭터와 겹쳐서 교체 창이 안 뜨고, 검사가 조용히 아무것도 안 한다.
	for i in range(Roster.UNITS.size() - 1, -1, -1):
		if Run.heroes.size() >= Balance.HERO_SLOTS:
			break
		var u: Dictionary = Roster.UNITS[i]
		Run.gain_hero(u, int(u["tier"]))
	if Run.heroes.size() != Balance.HERO_SLOTS:
		_bad("성역 여섯 자리를 못 채웠다 (%d명)" % Run.heroes.size())
		return
	Run.begin_draw()
	var d := DrawScreen.new()
	main._swap(d)
	await frames(3)
	var u2 := await _paint()
	if not _tap(u2, "go"):
		_bad("교체 검사: 결정 버튼을 못 눌렀다")
		return
	# 연출이 끝날 때까지 기다린다 — 끝나면 편성 판(SWAP)으로 가야 한다.
	# ★ 화면이 먼저 바뀌어 버리는 쪽도 봐야 한다. state 만 기다리면 겹쳤을 때
	#   여기서 20초를 그냥 서 있는다.
	var t0 := Time.get_ticks_msec()
	while d.state != DrawScreen.SWAP and main.screen == d \
			and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		d.queue_redraw()
		if d.state == DrawScreen.REVEAL and d.rt > 1.6:
			mouse(d, Vector2(640, 760), true)
	if d.state != DrawScreen.SWAP:
		_bad("확정했는데 편성 판이 안 떴다 (state %d, 전당 %d명)"
				% [d.state, Run.bench.size()])
		await _wait_for("battle_screen", 600)
		return
	var u3 := await _paint()
	await _swap_once(u3, "편성 판")
	var u4 := await _paint()
	if not _tap(u4, "tobattle"):
		_bad("편성 판의 「전투 시작」을 못 눌렀다")
	await _wait_for("battle_screen", 600)


## **전당을 굴렸을 때, 창 밖으로 나간 칸이 여전히 눌리지는 않는가.**
##
## ★ 실제로 있던 버그다: 창 밖으로 굴러 나간 전당 칸이 `Ui` 에 그대로 등록된 채라,
##   「전투 시작」을 누르려던 손가락이 **보이지도 않는 영웅**을 골랐다. 사진으로는
##   절대 안 보인다 — 그 칸은 안 그려져 있으니까. 그래서 그린 것이 아니라
##   **누를 자리**를 잰다.
## ★ hv:b 로 시작하는 자리는 하나도 빠짐없이 전당 창(HeroView._view) 안에 있어야 한다.
func _step_hall() -> void:
	if not Run.running:
		return
	# 창을 한 번에 다 못 보여 줄 만큼 쌓는다.
	# ★ `Run.gain_hero` 는 **같은 id 를 겹친다**(x2 …) — 같은 캐릭터를 몇 번을 줘도
	#   전당은 한 칸도 안 는다. 서로 다른 id 로 훑어야 열여덟이 쌓인다.
	Run.heroes.clear()
	Run.bench.clear()
	for u in Roster.UNITS:
		if Run.bench.size() >= 18:
			break
		Run.gain_hero(u, int(u["tier"]))
	if Run.bench.size() < 12:
		_bad("전당 검사: 서로 다른 영웅으로 전당을 못 채웠다 (%d명) — 검사가 뜻이 없어졌다"
				% Run.bench.size())
		return
	if Run.last_result.is_empty():
		_bad("전당 검사: 확정 결과가 비어 편성 판을 열 수 없다")
		return
	# 확정 뒤의 편성 판을 그대로 연다 — DrawScreen 은 phase 가 SWAP 이면 그 판부터 띄운다.
	Run.phase = Run.Phase.SWAP
	var d := DrawScreen.new()
	main._swap(d)
	await frames(3)
	if d.state != DrawScreen.SWAP:
		_bad("전당 검사: 편성 판이 안 떴다 (state %d)" % d.state)
		return
	d.formation_tab = false
	var hv = d.hv
	# 「새로 온 영웅」으로 창이 저절로 끌려가면 맨 위부터 굴려 보는 뜻이 없어진다.
	hv.new_id = ""
	hv.scroll = 0.0
	var seen := {}
	var guard := 0
	while guard < 12:
		guard += 1
		var u2 := await _paint()
		# ★ 설명 팝업이 떠 있는 동안은 건너뛴다 — 팝업은 전당 자리를 **지우지 않고
		#   덮는다**(나중에 등록한 것이 이긴다). 그때 자리가 남아 있는 것은 규칙이다.
		if hv.info < 0:
			for z in u2.zones:
				var id := String(z["id"])
				if not id.begins_with("hv:b"):
					continue
				seen[int(id.substr(4))] = true
				var r := Rect2(z["rect"])
				if not hv._view.grow(1.0).encloses(r):
					_bad("전당 검사: 창 밖으로 나간 칸(%s · %s)이 아직 눌린다 (창 %s) — 「전투 시작」을 누르려다 안 보이는 영웅이 골라진다"
							% [id, str(r), str(hv._view)])
					return
		var before_s: float = hv.scroll
		hv.wheel(1.0)
		if is_equal_approx(hv.scroll, before_s):
			break          # 바닥이다. 방금 그 프레임까지 다 봤다
	var last_i: int = Run.bench.size() - 1
	if not seen.has(last_i):
		_bad("전당 검사: 끝까지 굴렸는데 마지막 영웅(%d번)의 자리가 한 번도 안 나온다 — 굴려도 닿지 못하는 영웅이 있다"
				% last_i)
	if hv._rows <= hv._vis_rows:
		_bad("전당 검사: %d명을 넣었는데 창이 %d줄 전부를 한 번에 보여 준다 — 굴릴 것이 없어 검사가 아무것도 안 본다"
				% [Run.bench.size(), hv._rows])
	print("  전당 %d명 · 창 %d줄 / 전체 %d줄 · 굴려서 닿은 칸 %d개"
			% [Run.bench.size(), hv._vis_rows, hv._rows, seen.size()])


## 뚫렸을 때 크리스탈이 **딱 그만큼만** 깎이는가.
##
## ★ 앞 네 탄은 한 마리도 안 놓쳐서 이걸 물어볼 상황 자체가 안 만들어진다. 그래서
##   일부러 감당 못 할 탄을 세운다. 예전 규칙(시간이 끝나면 남은 수만큼)의 흔적이
##   화면 쪽에 남아 있으면 여기서 두 배로 깎여 걸린다.
func _step_leak() -> void:
	if not Run.running:
		return
	# ★ 성역을 **가장 약한 영웅 하나만** 남기고 비운다. 앞 검사(_step_swap)가 로열급
	#   여섯을 세워 놓기 때문에, 그대로 두면 12탄이 한 마리도 안 뚫려서 이 검사가
	#   조용히 아무것도 확인하지 않게 된다(실제로 그랬다).
	Run.heroes.clear()
	Run.bench.clear()
	Run.gain_hero(Roster.UNITS[0], int(Roster.UNITS[0]["tier"]))
	Run.wave = 12
	Run.lives = Run.max_lives()
	var before: int = Run.lives
	var b := BattleScreen.new()
	main._swap(b)
	await frames(3)
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
	await frames(8)
	if Run.lives != maxi(0, before - b.sim.leaked):
		_bad("크리스탈이 %d → %d 인데 깨진 것은 %d 이다 — 어디선가 두 번 깎는다"
				% [before, Run.lives, b.sim.leaked])
	if b.sim.leak_n < b.sim.leaked and not Balance.is_boss_wave(12):
		_bad("닿은 마릿수(%d)보다 깨진 크리스탈(%d)이 많다" % [b.sim.leak_n, b.sim.leaked])


## **자동 저장이 판을 통째로 담고 되돌리는가.**
##
## ★ 사용자가 제일 급하다고 한 것이 이것이다(「게임 자동저장이 안 되네」). 화면으로는
##   확인할 길이 없다 — 앱을 껐다 켜야 보이는 것이라, 담고(snapshot) 되돌리는(restore)
##   두 함수를 여기서 직접 맞춰 본다.
## ★ 담아야 하는 것: 탄·크리스탈·골드·성역·전당·능력치·패시브·카드 다섯 장·리롤 횟수.
##   하나라도 빠지면 이어 한 판이 조용히 달라진다 — 리롤이 공짜로 되살아나는 것이
##   그중 제일 나쁘다.
## ★ **전투 도중에 홈 버튼을 누르면 그 탄의 처음이 담겨야 한다.**
##   되돌리기는 「그 탄을 처음부터 다시」인데(Run.restore 주석), 지금 값을 담으면
##   그 탄에 번 골드와 처치를 챙긴 채로 그 탄을 다시 하게 된다 — 홈 버튼 한 번에
##   한 탄 벌이가 공짜로 또 들어오고, 반복하면 골드가 무한이다. 반대로 이미 깨진
##   크리스탈은 깎인 채로 남아 온전한 몬스터와 다시 싸운다.
##   ★ 이 검사가 없으면 아무도 못 잡는다 — 다른 저장 검사는 전부 단계가 바뀌는
##     자리에서만 담아 봐서, 아직 아무것도 안 번 상태라 저절로 통과한다.
func _step_battle_flush() -> void:
	if not Run.running:
		return
	Run.phase = Run.Phase.BATTLE
	Run.autosave()                       # main.go_battle() 이 하는 일
	var g0 := Run.gold
	var k0 := Run.kills
	var l0 := Run.lives
	# 전투가 도는 것처럼 굴린다 (BattleSim._reap 이 Run 을 직접 건드린다)
	Run.add_gold(650)
	Run.kills += 12
	Run.add_lives(-3)
	Save._flush()                        # 안드로이드 홈 버튼
	if int(Save.cur_run.get("gold", -1)) != g0:
		_bad("전투 중 저장: 번 골드가 담겼다 (%d → %d) — 그 탄을 다시 하면 두 번 받는다"
				% [g0, int(Save.cur_run.get("gold", -1))])
	if int(Save.cur_run.get("kills", -1)) != k0:
		_bad("전투 중 저장: 처치가 담겼다 — 평생 기록이 부풀어 오른다")
	if int(Save.cur_run.get("lives", -1)) != l0:
		_bad("전투 중 저장: 깎인 크리스탈이 담겼다 — 깎인 채로 그 탄을 다시 한다")
	# 되돌리고, 단계가 바뀌는 자리에서는 지금 값이 담겨야 한다.
	Run.gold = g0
	Run.kills = k0
	Run.lives = l0
	Run.phase = Run.Phase.SHOP
	Run.gold += 77
	Save._flush()
	if int(Save.cur_run.get("gold", -1)) != Run.gold:
		_bad("상점 단계인데 지금 골드가 안 담겼다 — 전투 갈래가 너무 넓게 막고 있다")
	Run.phase = Run.Phase.DRAW


func _step_save() -> void:
	if not Run.running:
		return
	# 담기 전에 알아보기 쉬운 값으로 만들어 둔다.
	Run.wave = 7
	Run.lives = 13
	Run.gold = 4321
	Run.levels["atk"] = 3
	Run.passives.clear()
	Run.passives.append(String(Balance.PASSIVES[0]["id"]))
	Run.begin_draw()            # 카드 다섯 장과 덱을 채운다 (탄이 8 이 된다)
	Run.reroll(0)
	var want := {
		"wave": Run.wave, "lives": Run.lives, "gold": Run.gold,
		"heroes": Run.heroes.size(), "bench": Run.bench.size(),
		"total": Run.hero_total(), "atk": Run.lv("atk"),
		# ★ duplicate() 가 없으면 Run.cards **그 배열**을 쥐게 되어(Array() 는 복사가 아니다)
		#   되돌린 뒤 제 것과 비교하는 셈이 된다 — 검사가 언제나 통과했다.
		"pas": Run.passives.size(), "cards": Array(Run.cards).duplicate(),
		"rer": Array(Run.rerolled).duplicate(), "seed": Run.run_seed,
		"lineup": Run.wave_lineup(Run.wave).size(),
	}
	Run.autosave()
	if not Save.has_run():
		_bad("자동 저장: 담았는데 이어 할 판이 없다고 나온다")
		return
	if Save.run_wave() != want["wave"]:
		_bad("자동 저장: 담은 탄이 %d 인데 %d 로 읽힌다" % [want["wave"], Save.run_wave()])
	var snap: Dictionary = Save.cur_run.duplicate(true)

	# 판을 통째로 흐트러뜨린 뒤 되돌린다.
	Run.start_run(999119)
	if not Run.restore(snap):
		_bad("자동 저장: 담은 판을 되돌리지 못했다")
		return
	for k in ["wave", "lives", "gold", "atk", "pas", "seed"]:
		var got: int = int(Run.wave) if k == "wave" else (
				int(Run.lives) if k == "lives" else (
				int(Run.gold) if k == "gold" else (
				Run.lv("atk") if k == "atk" else (
				Run.passives.size() if k == "pas" else int(Run.run_seed)))))
		if got != int(want[k]):
			_bad("자동 저장: %s 가 %d 여야 하는데 %d 다" % [k, int(want[k]), got])
	if Run.heroes.size() != int(want["heroes"]) or Run.bench.size() != int(want["bench"]):
		_bad("자동 저장: 성역/전당이 %d/%d 여야 하는데 %d/%d 다"
				% [int(want["heroes"]), int(want["bench"]), Run.heroes.size(), Run.bench.size()])
	if Run.hero_total() != int(want["total"]):
		_bad("자동 저장: 겹친 수까지 센 영웅이 %d 여야 하는데 %d 다"
				% [int(want["total"]), Run.hero_total()])
	if Array(Run.cards) != Array(want["cards"]):
		_bad("자동 저장: 카드 다섯 장이 안 돌아왔다")
	if Array(Run.rerolled) != Array(want["rer"]):
		_bad("자동 저장: 리롤 횟수가 안 돌아왔다 — 이어 하면 공짜 리롤이 되살아난다")
	# ★ 씨앗이 같으면 **그 탄에 오는 몬스터도 같아야** 한다. 안 그러면 상점이 보여 준
	#   예고와 실제가 달라진다.
	if Run.wave_lineup(Run.wave).size() != int(want["lineup"]):
		_bad("자동 저장: 되돌린 판의 몬스터 편성이 달라졌다")
	# 패배 판은 부활 선택이 끝날 때까지 보존하고, 종료를 수락하면 지운다.
	Run.end_run(false)
	if not Save.has_run():
		_bad("자동 저장: 부활을 선택할 패배 판이 사라졌다")
	Run.finish_defeat()
	if Save.has_run():
		_bad("자동 저장: 판이 끝났는데 이어 할 판이 남아 있다")
	Run.running = true          # 뒤 검사들이 이어 돌 수 있게 되돌린다
	Run.lives = maxi(1, Run.lives)


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
