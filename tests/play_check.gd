extends Harness

## 화면을 실제로 세워 놓고 **손가락으로 눌러** 타이틀 → 의식 → 전투 → 상점을 돌린다.
##
## 왜 필요한가: 이 머신에는 화면이 없다. 배치가 어긋나는 건 사진으로 보지만,
## "버튼을 눌렀는데 아무 일도 안 일어난다" 같은 것은 사진으로도 안 보인다.
## 여기서는 **그리기가 등록한 바로 그 자리**를 눌러서, 그린 것과 눌리는 것이
## 같은지까지 확인한다.
##
##   godot --headless --path . res://tests/play_check.tscn
##
## ★ 의식 화면의 단추 id 는 화면과의 약속이다: 소환 확정 `go` · 다시 돌리기 `rite:respin` ·
##   광고로 별 끌어오기 `rite:pull`. 확정 연출은 0.7초 뒤부터 아무 데나 눌러 넘기고,
##   편성 판의 `tobattle` · `formation:*` 는 그대로다.

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
	if main.screen.state != DrawScreen.PICK:
		_bad("%d탄: 의식 화면이 고르는 단계가 아니다 (state %d)" % [Run.wave, main.screen.state])
	if not Rite.valid(Run.orbit):
		_bad("%d탄: 의식의 별 자리가 성하지 않다 (%s)" % [Run.wave, str(Run.orbit)])
		return
	if Run.wave == 1 and Run.rite_stars() < Balance.RITE_FIRST_STARS:
		_bad("1탄: 판의 첫 의식이 %d성으로 열렸다 (%d성 이상이어야 한다)" % [Run.rite_stars(), Balance.RITE_FIRST_STARS])
	# ★ 무료 횟수는 **탄마다 새로 찬다.** 지난 탄에 쓴 횟수가 딸려 오면 2탄부터는 처음부터 골드를 낸다.
	if Run.spins != 0 or Run.paid_spins != 0 or Run.pulls != 0 or Run.respins_left() != Run.free_rerolls():
		_bad("%d탄: 새 의식인데 돌린 횟수가 남아 있다 (돌림 %d · 유료 %d · 끌어옴 %d · 무료 %d/%d)"
				% [Run.wave, Run.spins, Run.paid_spins, Run.pulls, Run.respins_left(), Run.free_rerolls()])
	for id in ["go", "rite:respin", "rite:pull"]:
		if zone_of(main.screen, id).is_empty():
			_bad("%d탄: 의식 화면에 %s 단추가 없다" % [Run.wave, id])
	# 다시 돌리기 — 공짜가 남아 있다. 문 밖에 별이 있으면 눌러서 돌린다.
	var before: Array[int] = Run.orbit.duplicate()
	var missed := Rite.misses(before)
	var gold_before := Run.gold
	if Run.respin_cost() != 0:
		_bad("%d탄: 첫 다시 돌리기가 공짜가 아니다" % Run.wave)
	if missed.is_empty():
		# 처음부터 다섯이 다 들었다(드물다). 돌릴 것이 없으니 단추가 꺼져 있어야 하고,
		# 눌러도 횟수도 골드도 그대로여야 한다.
		if _tap(u, "rite:respin") or Run.spins != 0 or Run.gold != gold_before:
			_bad("%d탄: 다섯 별이 다 들었는데 다시 돌리기가 눌린다" % Run.wave)
	else:
		if not _tap(u, "rite:respin"):
			_bad("%d탄: 다시 돌리기 단추를 못 눌렀다" % Run.wave)
		if Run.spins != 1:
			_bad("%d탄: 다시 돌리기를 눌렀는데 안 돌았다 (돌린 횟수 %d)" % [Run.wave, Run.spins])
		# ★ **문 안에 든 별은 잠긴다.** 다시 돌려서 이미 든 별이 빠지면 누를수록 손해인 단추가 된다.
		for ring in range(Rite.RINGS):
			if not missed.has(ring) and Run.orbit[ring] != before[ring]:
				_bad("%d탄: 다시 돌렸더니 문 안의 %d번 별이 움직였다" % [Run.wave, ring])
		if Run.rite_stars() < Rite.stars(before):
			_bad("%d탄: 다시 돌렸더니 별이 줄었다 (%d → %d)" % [Run.wave, Rite.stars(before), Run.rite_stars()])
		if Run.gold != gold_before:
			_bad("%d탄: 공짜 다시 돌리기인데 골드가 줄었다" % Run.wave)
		# 공짜를 다 쓰면 값이 붙어야 한다
		if Run.free_rerolls() == 1 and Run.respin_cost() != Balance.reroll_cost(0):
			_bad("%d탄: 한 번 돌린 뒤의 값이 %d 다 (%d 이어야 한다) — 규칙이 깨졌다"
					% [Run.wave, Run.respin_cost(), Balance.reroll_cost(0)])
	# ★ **다시 돌리기는 누른 그 순간 담겨야 한다.** 안 담기면 의식 화면에서 앱을 껐다 켰을 때
	#   돌린 횟수가 0 으로 되돌아가서 **공짜 다시 돌리기가 되살아난다** — 그게 곧 무한 리롤이다.
	#   별 자리도 같이 담겨야 한다. 안 그러면 껐다 켜는 것으로 맘에 드는 별이 나올 때까지 굴린다.
	#   (STELLARDEFENSE_NO_SAVE=1 에서도 잡힌다: Save.store_run 이 파일에 쓰기 **전에**
	#    cur_run 에 담고 나서 읽기 전용인지를 보기 때문이다.)
	if not missed.is_empty() and Save.cur_run.get("rite", {}) != Run.snapshot()["rite"]:
		_bad("%d탄: 다시 돌렸는데 이어할 판에 안 담겼다 (앱을 껐다 켜면 공짜 횟수와 별 자리가 되살아난다) — 담긴 것 %s / 실제 %s"
				% [Run.wave, str(Save.cur_run.get("rite", {})), str(Run.snapshot()["rite"])])

	# 별 끌어오기(광고) — 문 밖에 별이 남아 있으면 골드 · 무료 횟수와 무관하게 켜져 있고,
	# 다 들었으면 꺼져 있다.
	u = await _paint()
	var pull_zone := zone_of(main.screen, "rite:pull")
	if not pull_zone.is_empty() and bool(pull_zone["on"]) != (Run.pull_target() >= 0):
		_bad("%d탄: 별 끌어오기 단추가 %s 있는데 끌어올 별은 %d번이다"
				% [Run.wave, "켜져" if bool(pull_zone["on"]) else "꺼져", Run.pull_target()])
	var respin_zone := zone_of(main.screen, "rite:respin")
	if not respin_zone.is_empty() and bool(respin_zone["on"]) != Run.can_respin():
		_bad("%d탄: 다시 돌리기 단추의 켜짐이 규칙(can_respin %s)과 다르다" % [Run.wave, str(Run.can_respin())])
	# ★ **보상은 광고를 끝까지 본 뒤에만 온다.** 이 기계에는 광고가 없으므로 눌러도 별은
	#   그대로여야 하고, 광고 대기 화면이 입력을 잠근 채로 남아도 안 된다.
	var rite_before: Dictionary = Run.snapshot()["rite"]
	_tap(u, "rite:pull")
	if Run.snapshot()["rite"] != rite_before or Ads.busy:
		_bad("%d탄: 광고를 안 봤는데 별이 끌려왔거나 광고 대기가 걸렸다 (%s → %s · busy %s)"
				% [Run.wave, str(rite_before), str(Run.snapshot()["rite"]), str(Ads.busy)])

	u = await _paint()
	var stars_shown := Run.rite_stars()
	if not _tap(u, "go"):
		_bad("%d탄: 소환 단추를 못 눌렀다" % Run.wave)
	# ★ 같은 캐릭터가 또 나오면 성역에 서지 않고 **전당에 따로 보관된다.** 그래서 세는 것은
	#   성역의 자릿수가 아니라 전당까지 더한 hero_total() 이다.
	if Run.hero_total() != w + 1:
		_bad("%d탄: 영웅이 %d명이다 (%d명이어야 한다)" % [Run.wave, Run.hero_total(), w + 1])
	if Run.heroes.size() > Balance.HERO_SLOTS:
		_bad("%d탄: 성역에 %d명이 섰다 (%d명까지다)"
				% [Run.wave, Run.heroes.size(), Balance.HERO_SLOTS])
	# ★ **화면이 보여 준 별 수가 그대로 등급이어야 한다.** 문 안에 셋이 섰는데 2성이 나오면
	#   그 순간 이 뽑기는 못 믿을 것이 된다. (패시브가 없는 판이라 조커도 눈도 안 낀다)
	var got: Dictionary = Run.last_result
	if Run.has("joker") or Run.has("eye"):
		pass          # 조커는 별을 하나 더하고 눈은 반 별을 얹는다 — 그 셈은 tests/rite_check 가 본다
	elif int(got.get("stars", -1)) != stars_shown or int(got.get("tier", -1)) != Rite.tier_of(stars_shown):
		_bad("%d탄: 문 안의 별은 %d개였는데 %d성(등급 %d)이 나왔다"
				% [Run.wave, stars_shown, int(got.get("stars", -1)), int(got.get("tier", -1))])
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
	Run.confirm_summon()
	if Run.hero_total() != dup_before:
		_bad("%d탄: confirm_summon() 을 두 번 불렀더니 영웅이 %d → %d 가 됐다"
				% [Run.wave, dup_before, Run.hero_total()])
	# ★ 확정한 뒤 연출이 도는 동안 화면은 아직 트리에 있다. 여기서 「소환」을 또 누르면
	#   영웅이 공짜로 하나 더 생기는 버그가 있었다. 단추 셋을 다 눌러 보고 영웅도, 별도,
	#   골드도 그대로인지 확인한다.
	var again: Ui = main.screen.ui
	var rite_done: Dictionary = Run.snapshot()["rite"]
	var gold_done := Run.gold
	_tap(again, "go")
	_tap(again, "rite:respin")
	_tap(again, "rite:pull")
	if Run.hero_total() != w + 1:
		_bad("%d탄: 연출 중에 또 눌렀더니 영웅이 %d명이 됐다" % [Run.wave, Run.hero_total()])
	if Run.snapshot()["rite"] != rite_done or Run.gold != gold_done or Ads.busy:
		_bad("%d탄: 확정한 뒤에 의식 단추가 눌려서 별이나 골드가 바뀌었다" % Run.wave)
	# ★ 확정하자마자 누른 것은 연출을 넘기지도 못한다 — 넘어가면 방금 무엇이 나왔는지 못 본다
	#   (연출은 0.7초 뒤부터 넘길 수 있다).
	if main.screen.state != DrawScreen.REVEAL:
		_bad("%d탄: 확정하자마자 누른 것으로 확정 연출이 넘어갔다 (state %d)" % [Run.wave, main.screen.state])
	# 연출이 끝나면 **편성 판**이 뜬다 — 이제 탄마다 빠짐없이.
	# 한 탄은 0.7초가 지나자마자 넘기고, 한 탄은 연출을 끝까지 본 뒤에 넘긴다.
	await _to_battle_via_board(main.screen, 900 if w % 2 == 0 else 2200)


## 확정 연출(REVEAL)이 끝나 편성 판(SWAP)이 뜰 때까지 간다. 떴으면 참.
##
## ★ 연출은 **0.7초 뒤부터 아무 데나 누르면** 넘어간다(화면과의 약속). 화면 안쪽의 시계를
##   읽지 않고 벽시계로 `hold_ms` 만큼 본 뒤에 넘어갈 때까지 누른다 — 누르기 전에 화면이
##   바뀌어 버리는 쪽도 같이 본다(state 만 기다리면 그때 여기서 20초를 그냥 서 있는다).
## ★ 시작하자마자 누른 것은 흘려야 한다. 그게 넘어가면 무엇이 나왔는지 못 보고 지나간다.
func _skip_reveal(d, hold_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var poked := false
	while d.state != DrawScreen.SWAP and main.screen == d \
			and Time.get_ticks_msec() - t0 < 20000:
		await get_tree().process_frame
		d.queue_redraw()
		if d.state != DrawScreen.REVEAL:
			continue
		var waited := Time.get_ticks_msec() - t0
		if not poked and waited < 250:
			poked = true
			mouse(d, Vector2(640, 760), true)
			if d.state != DrawScreen.REVEAL:
				_bad("%d탄: 확정 연출이 시작하자마자(%dms) 눌려서 넘어갔다 — 0.7초는 보여야 한다" % [Run.wave, waited])
		elif waited >= hold_ms:
			mouse(d, Vector2(640, 760), true)
	return d.state == DrawScreen.SWAP


## 확정 연출이 끝나면 편성 판(SWAP)이 뜬다 — **탄마다 빠짐없이**. 그 판을 눌러 전투로 간다.
##
## ★ 예전에는 성역이 꽉 찼을 때만 떴고, 그래서 이 검사도 확정한 뒤 곧장 전투를 기다렸다.
##   지금은 판을 안 넘기면 전투가 영영 시작되지 않는다 — 여기를 빼먹으면 검사가
##   "전투로 안 넘어간다"고만 말하고 진짜 이유는 안 알려 준다.
func _to_battle_via_board(d, hold_ms: int = 900) -> void:
	if not await _skip_reveal(d, hold_ms):
		_bad("%d탄: 확정했는데 편성 판이 안 떴다 (state %d)" % [Run.wave, d.state])
		await _wait_for("battle_screen", 600)
		return
	# 편성 판에는 의식 단추가 없어야 한다 — 남아 있으면 확정한 탄에서 또 돌리거나 또 소환한다.
	await _paint()
	for id in ["go", "rite:respin", "rite:pull"]:
		if bool(zone_of(main.screen, id).get("on", false)):
			_bad("%d탄: 편성 판에 의식 단추 %s 가 켜진 채 남아 있다" % [Run.wave, id])
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
		if b.sim.support_pending:
			b.sim.resolve_support("promote", 0)
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
## ★ **전당의 그 영웅이 성역의 다른 자리에 이미 선 캐릭터면 맞바꿔지지 않아야 한다**
##   (중복 출전 금지). 뽑기가 쉰 명에서 고르므로 방금 뽑은 영웅이 그런 경우가 흔하다 —
##   그때는 「거절되고 아무것도 안 바뀐다」를 본다. 실제로 맞바꿨으면 참을 돌려준다.
func _swap_once(u: Ui, where: String, b: int = 0) -> bool:
	if Run.heroes.is_empty() or b >= Run.bench.size():
		return false
	var before_f := String(Run.heroes[0]["unit"]["id"])
	var before_b := String(Run.bench[b]["unit"]["id"])
	var allowed: bool = Run.can_deploy(Run.bench[b]["unit"], 0)
	var total := Run.hero_total()
	if not _tap(u, "formation:roster"):
		_bad("영웅 정보 탭을 못 눌렀다")
	u = await _paint()
	if not _tap(u, "hv:f0"):
		_bad("%s: 성역 0번을 못 눌렀다" % where)
		return false
	u = await _paint()
	# 팝업이 떴어야 한다.
	var hv = main.screen.hv
	if hv.info < 0:
		_bad("%s: 캐릭터를 눌렀는데 설명 팝업이 안 떴다" % where)
		return false
	if not _tap(u, "hv:move"):
		_bad("%s: 팝업의 「옮기기」를 못 눌렀다" % where)
		return false
	u = await _paint()
	if not _tap_release(u, "hv:b%d" % b):
		_bad("%s: 전당 %d번을 못 눌렀다" % [where, b])
		return false
	var now_f := String(Run.heroes[0]["unit"]["id"])
	var now_b := String(Run.bench[b]["unit"]["id"])
	if allowed and (now_f != before_b or now_b != before_f):
		_bad("%s: 두 자리를 눌렀는데 안 바뀌었다 (%s / %s)" % [where, now_f, now_b])
	if not allowed and (now_f != before_f or now_b != before_b):
		_bad("%s: 성역의 다른 자리에 이미 선 %s 가 0번 자리로 올라왔다 — 같은 캐릭터가 두 자리에 선다"
				% [where, before_b])
	if Run.hero_total() != total:
		_bad("%s: 자리를 바꿨더니 영웅 수가 %d → %d 로 바뀌었다"
				% [where, total, Run.hero_total()])
	return allowed


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
	# 서로 다른 캐릭터로 성역을 가득 채운다(같은 캐릭터는 성역에 한 번만 서므로 자리가 안 찬다).
	# 표의 뒤쪽부터 채우고, 등급은 표의 원화 격을 그대로 준다(Fixture.fresh 와 같은 약속이다).
	for i in range(Roster.UNITS.size() - 1, -1, -1):
		if Run.heroes.size() >= Balance.HERO_SLOTS:
			break
		var u: Dictionary = Roster.UNITS[i]
		Run.gain_hero(u, int(u["tier"]))
	if Run.heroes.size() != Balance.HERO_SLOTS:
		_bad("성역 %d자리를 못 채웠다 (%d명)" % [Balance.HERO_SLOTS, Run.heroes.size()])
		return
	Run.begin_draw()
	var d := DrawScreen.new()
	main._swap(d)
	await frames(3)
	var u2 := await _paint()
	if not _tap(u2, "go"):
		_bad("교체 검사: 소환 단추를 못 눌렀다")
		return
	# 연출이 끝날 때까지 기다린다 — 끝나면 편성 판(SWAP)으로 가야 한다.
	if not await _skip_reveal(d, 900):
		_bad("확정했는데 편성 판이 안 떴다 (state %d, 전당 %d명)"
				% [d.state, Run.bench.size()])
		await _wait_for("battle_screen", 600)
		return
	# 성역이 가득 찼으므로 방금 뽑은 영웅은 전당 0번에 있다.
	if Run.bench.is_empty():
		_bad("교체 검사: 성역이 가득 찬 채로 뽑았는데 전당이 비었다")
		return
	var u3 := await _paint()
	if not await _swap_once(u3, "편성 판"):
		# 방금 뽑은 영웅이 성역의 다른 캐릭터와 겹쳐서 위에서는 「거절」을 봤다. 성역에 없는
		# 캐릭터를 전당에 하나 더 두고, 실제로 맞바뀌는 것까지 본다.
		for spare in Roster.UNITS:
			if int(Run.find_hero(String(spare["id"]))[1]) < 0:
				Run.gain_hero(spare, int(spare["tier"]), false, false)
				break
		var u3b := await _paint()
		if not await _swap_once(u3b, "편성 판(성역에 없는 캐릭터)", Run.bench.size() - 1):
			_bad("교체 검사: 성역에 없는 캐릭터인데도 맞바꾸지 못했다")
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
	# ★ 성역을 **가장 약한 영웅 하나만**(0.5성) 남기고 비운다. 앞 검사(_step_swap)가 5성까지
	#   섞인 열둘을 세워 놓기 때문에, 그대로 두면 12탄이 한 마리도 안 뚫려서 이 검사가
	#   조용히 아무것도 확인하지 않게 된다(실제로 그랬다).
	Run.heroes.clear()
	Run.bench.clear()
	Run.gain_hero(Roster.UNITS[0], int(Roster.UNITS[0]["tier"]))
	Run.wave = 12
	Run.lives = Run.max_lives()
	Run.phase = Run.Phase.SWAP
	Run.prepare_battle()
	var before: int = Run.lives
	var b := BattleScreen.new()
	main._swap(b)
	await frames(3)
	b.speed = 3.0
	var t0 := Time.get_ticks_msec()
	while not b.sim.done and Time.get_ticks_msec() - t0 < 90000:
		if b.sim.support_pending:
			b.sim.resolve_support("promote", 0)
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
## ★ 담아야 하는 것: 탄·크리스탈·골드·성역·전당·능력치·패시브·별 다섯의 자리·다시 돌린 횟수.
##   하나라도 빠지면 이어 한 판이 조용히 달라진다 — 다시 돌리기가 공짜로 되살아나는 것이
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
	Run.begin_draw()            # 새 의식을 연다 (탄이 8 이 된다)
	# 별 둘이 든 자리에서 한 번 다시 돌린다 — 별 자리와 돌린 횟수가 둘 다 담겨야 한다.
	Run.orbit.assign(Fixture.orbit_for(2))
	if Run.respin().is_empty():
		_bad("자동 저장: 검사용 의식을 다시 돌리지 못했다")
	var want := {
		"wave": Run.wave, "lives": Run.lives, "gold": Run.gold,
		"heroes": Run.heroes.size(), "bench": Run.bench.size(),
		"total": Run.hero_total(), "atk": Run.lv("atk"),
		# ★ 깊은 복사가 없으면 Run 이 들고 있는 **그 배열**을 쥐게 되어, 되돌린 뒤 제 것과
		#   비교하는 셈이 된다 — 그러면 검사가 언제나 통과한다.
		"pas": Run.passives.size(), "rite": (Run.snapshot()["rite"] as Dictionary).duplicate(true),
		"left": Run.respins_left(), "cost": Run.respin_cost(), "seed": Run.run_seed,
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
	if Run.snapshot()["rite"] != want["rite"] or not Rite.valid(Run.orbit):
		_bad("자동 저장: 별 다섯의 자리와 돌린 횟수가 안 돌아왔다 (%s → %s)"
				% [str(want["rite"]), str(Run.snapshot()["rite"])])
	if Run.respins_left() != int(want["left"]) or Run.respin_cost() != int(want["cost"]):
		_bad("자동 저장: 남은 무료 횟수가 %d → %d, 값이 %d → %d 로 바뀌었다 — 이어 하면 공짜 다시 돌리기가 되살아난다"
				% [int(want["left"]), Run.respins_left(), int(want["cost"]), Run.respin_cost()])
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
