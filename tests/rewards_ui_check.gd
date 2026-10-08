extends Harness

## 보상(광고) 흐름의 화면들을 실제로 눌러 보고 build/ 에 사진으로 남긴다.
##
##   godot --path . res://tests/rewards_ui_check.tscn   (tools/visual_refinement_review.py 가 부른다)

var main: Node2D


func show_frame(path: String) -> void:
	await frames(2)
	await snap("res://build/" + path + ".png")


func click(id: String) -> bool:
	var ok := tap(main.screen, id)
	check(ok, "UI action unavailable: " + id)
	return ok


func _ready() -> void:
	if not require_no_save(2):
		return
	main = load("res://game/main.gd").new()
	add_child(main)
	Run.start_run(50123)
	Run.begin_draw()
	Run.confirm_summon()
	for unit in Roster.UNITS.slice(0, 24):
		Run.gain_hero(unit, int(unit["tier"]))
	main.show_draw()
	await show_frame("formation-rewards")
	click("formation:roster")
	await show_frame("hall-rewards")
	click("formation:fusion")
	await show_frame("fusion-rewards")
	var field_before := Run.heroes.duplicate(true)
	var count_before := Run.hero_total()
	for zone in main.screen.ui.zones:
		var id := String(zone["id"])
		if id.begins_with("material:") and int(id.get_slice(":", 1)) < Run.FUSION_BENCH:
			check(not bool(zone["on"]), "deployed material hit target is disabled")
			mouse(main.screen, Rect2(zone["rect"]).get_center(), true)
			mouse(main.screen, Rect2(zone["rect"]).get_center(), false)
	check(main.screen.fusion.selected.is_empty(), "touching deployed cards selects no fusion material")
	for code in Run.fusion_candidates():
		if not Run.fusion_material_allowed(code):
			continue
		var id := "material:%d" % code
		while zone_of(main.screen, id).is_empty():
			if not click("fusion:next"):
				break
			await paint(main.screen)
		click(id)
		await paint(main.screen)
		if main.screen.fusion.selected.size() == 5:
			break
	check(main.screen.fusion.selected.size() == 5, "five reserve cards can be selected across pages")
	await show_frame("fusion-selected")
	click("fusion:go")
	check(not Run.fusion_pending.is_empty() and Run.hero_total() == count_before - 4, "UI fusion consumes five reserve cards for one result")
	check(Run.heroes == field_before, "UI fusion preserves all deployed heroes and posts")
	await get_tree().create_timer(2.0).timeout
	await show_frame("fusion-result")
	click("fusion:accept")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	click("fusion:close")
	Run.phase = Run.Phase.SHOP
	main.go_shop()
	main.screen.tab = "c"
	Run.lives = 8
	await show_frame("crystal-rewards")
	Run.phase = Run.Phase.DRAW
	Run.last_result = {}
	# 무료 다시 돌리기를 다 쓴 의식 — 문 안에 별 둘, 문 밖에 셋. 골드는 넉넉하다.
	Fixture.stack(2)
	Run.spins = Run.free_rerolls()
	var original_gold := maxi(Run.gold, Balance.reroll_cost(0) * 4)
	Run.gold = original_gold
	main.show_draw()
	# 별이 다 멈춘 뒤에 찍는다(들어올 때 다섯이 차례로 돌다 선다).
	await get_tree().create_timer(2.4).timeout
	await show_frame("draw-rewards")
	check(main.screen.state == DrawScreen.PICK, "the rite stays on its pick state")
	check(bool(zone_of(main.screen, "rite:pull").get("on", false)), "star pull remains available after the free re-spins")
	check(bool(zone_of(main.screen, "rite:respin").get("on", false)), "a paid re-spin is offered while gold remains")
	check(bool(zone_of(main.screen, "go").get("on", false)), "summon is always available")
	Run.gold = 0
	await show_frame("draw-no-gold-rewards")
	check(bool(zone_of(main.screen, "rite:pull").get("on", false)), "star pull remains available at zero gold")
	check(not bool(zone_of(main.screen, "rite:respin").get("on", true)), "paid re-spins disable at zero gold")
	check(bool(zone_of(main.screen, "go").get("on", false)), "summon remains available at zero gold")
	# 다 든 5성 — 돌릴 것도 끌어올 것도 없다.
	Run.gold = original_gold
	Run.orbit.assign(Fixture.orbit_for(Rite.MAX_STARS))
	await show_frame("draw-five-stars-rewards")
	check(not bool(zone_of(main.screen, "rite:pull").get("on", true)) and not bool(zone_of(main.screen, "rite:respin").get("on", true)),
			"with five stars in the gate neither pull nor re-spin is offered")
	Fixture.stack(2)
	Run.phase = Run.Phase.SWAP
	Run.prepare_battle()
	main.go_battle()
	await get_tree().create_timer(2).timeout
	await show_frame("battle-rewards")
	Run.add_lives(-Run.max_lives())
	main.go_over()
	await show_frame("over-rewards")
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("보상 화면 검사")
