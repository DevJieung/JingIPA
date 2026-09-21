extends Harness


func _ready() -> void:
	if not require_no_save():
		return
	_test_preview()
	await _test_notice()
	finish("테마 출현 정보·보상 알림 검사")


func _test_preview() -> void:
	for seed_value in [15, 71, 999]:
		Fixture.fresh(seed_value)
		var saved := Run.snapshot().duplicate(true)
		for start in range(1, Balance.LAST_WAVE + 1, Balance.THEME_BLOCK):
			var preview := Run.theme_preview(start)
			check(preview["start_wave"] == start and preview["end_wave"] == start + 9,
				"preview covers the upcoming ten waves")
			var actual: Dictionary = {}
			var bosses: Array = []
			var total := 0
			# Compare with the real combat queue, including early-wave restrictions and remainders.
			for wave in range(start, int(preview["end_wave"]) + 1):
				var sim := BattleSim.new()
				sim.setup(Run, wave)
				for monster in sim._queue:
					if monster["kind"] == "boss":
						bosses.append({"wave": wave, "monster": monster})
						continue
					var body := String(monster["body"])
					if not actual.has(body):
						actual[body] = {"count": 0, "ids": []}
					actual[body]["count"] += 1
					if not actual[body]["ids"].has(monster["id"]):
						actual[body]["ids"].append(monster["id"])
					total += 1
			check(preview["total"] == total, "preview total matches actual regular spawns")
			check(preview["bosses"] == bosses, "boss identity and wave match combat")
			check(preview["rows"].size() == actual.size(), "all spawned elements are represented")
			var percent := 0
			for row in preview["rows"]:
				var body := String(row["body"])
				check(row["count"] == actual[body]["count"], "element count matches combat: " + body)
				check(absf(float(row["percent"]) - float(actual[body]["count"]) * 100.0 / total) < 1.0,
					"displayed percentage rounds the actual count: " + body)
				percent += int(row["percent"])
				var ids: Array = []
				for monster in row["monsters"]:
					ids.append(monster["id"])
				ids.sort()
				actual[body]["ids"].sort()
				check(ids == actual[body]["ids"], "monster list contains exactly the actual species: " + body)
			check(percent == 100, "displayed percentages sum to 100")
		check(Run.snapshot() == saved, "preview leaves cards, rewards, RNG and save state untouched")
		check(Run.theme_preview(10)["end_wave"] == 10, "partial block does not spill into the next theme")
		check(Run.theme_preview(100)["end_wave"] == 100, "last-wave preview stays within the run")


func _test_notice() -> void:
	var main := load("res://game/main.gd").new() as Node2D
	add_child(main)
	Fixture.fresh(15092026)
	main.show_draw()
	await paint(main.screen)
	Ads.set_process(false)
	var before := Run.snapshot().duplicate(true)
	Ads._finish(true, "광고 보상을 받았습니다.")
	Ads._process(3.1)
	check(Ads._message_left == 0.0, "reward notice expires automatically")
	check(Run.snapshot() == before, "notice expiry does not award another reward")
	Ads._finish(true, "광고 보상을 받았습니다.")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(752, 34)
	get_viewport().push_input(click)
	check(Ads._message_left == 0.0 and not Ads._reward_notice, "mouse press dismisses reward notice")
	check(not main.menu.opened, "dismiss press does not activate the menu underneath")
	check(Run.snapshot() == before, "dismiss press leaves gameplay unchanged")
	await frames(2)
	Ads._finish(true, "광고 보상을 받았습니다.")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(752, 34)
	get_viewport().push_input(touch)
	check(Ads._message_left == 0.0, "native screen touch dismisses reward notice")
	get_viewport().push_input(click)
	check(not main.menu.opened, "emulated mouse event from the same touch is consumed")
	await frames(2)
	Ads._finish(true, "광고 보상을 받았습니다.")
	Ads.busy = true
	get_viewport().push_input(touch)
	check(Ads._message_left > 0.0, "notice dismissal does not cancel a busy advertisement")
	Ads.busy = false
	Ads._message_left = 0.0
	Ads.set_process(true)
	main.queue_free()
	await frames(2)
