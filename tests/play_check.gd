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
	if Run.heroes.size() != w + 1:
		_bad("%d탄: 영웅이 %d명이다 (%d명이어야 한다)" % [Run.wave, Run.heroes.size(), w + 1])
	# 연출이 끝나고 전투로
	await _wait_for("battle_screen", 600)


func _step_battle(_w: int) -> void:
	var b = main.screen
	b.speed = 3.0
	var guard := 0
	while not b.sim.done and guard < 3000:
		await get_tree().process_frame
		guard += 1
		if guard % 30 == 0:
			b.queue_redraw()
	if not b.sim.done:
		_bad("%d탄 전투가 안 끝난다" % Run.wave)
		return
	if b.sim.kills == 0 and b.sim.leaked == 0:
		_bad("%d탄: 잡지도 놓치지도 않았다 — 전투가 안 돌았다" % Run.wave)
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
	u = await _paint()
	if not _tap(u, "next"):
		_bad("상점의 다음 버튼을 못 눌렀다")
	await _wait_for("draw_screen", 600)


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
