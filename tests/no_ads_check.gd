extends Harness

func _ready() -> void:
	if not require_no_save(): return
	check(not ProjectSettings.has_setting("autoload/Ads") and not get_tree().root.has_node("Ads"), "advertising service is absent")
	for state in [Run, Arena]:
		for method in ["apply_ad_reward", "reward_allowed", "revive_wave", "undo_fusion", "can_pull"]:
			check(not state.has_method(method), "removed reward endpoint: " + method)
	Fixture.fresh(1919, 2)
	Run.confirm_summon()
	var legacy := Run.snapshot()
	legacy["rite"]["pulls"] = 7
	legacy["continue_used"] = true
	var gold_before := Run.gold
	check(Run.restore(legacy), "legacy wave save tolerates retired fields")
	check(Run.gold == gold_before and not Run.snapshot()["rite"].has("pulls") and not Run.snapshot().has("continue_used"), "legacy fields grant no new reward and are not persisted")
	# A reward already credited by an older version must resume past the removed modal.
	legacy = Run.snapshot()
	legacy["phase"] = Run.Phase.SWAP
	legacy["retry_wave"] = true
	legacy["last"] = {"unit": "", "tier": Balance.TIER_MAX, "stars": Rite.MAX_STARS,
		"orbit": [], "joker": -1, "gold": Balance.REVIVE_GOLD, "gold_only": true,
		"revived": true, "reward_pending": true}
	check(Run.restore(legacy) and Run.phase == Run.Phase.SHOP and Run.last_result.is_empty(), "legacy credited reward resumes at shop")
	check(Run.gold == gold_before and Run.hero_total() == 3, "resume never credits removed reward again")
	Arena.start_run(2929)
	Arena.choose_theme(0)
	legacy = Arena.snapshot()
	legacy["rite"]["pulls"] = 4
	check(Arena.restore(legacy) and not Arena.snapshot()["rite"].has("pulls"), "continuous save migrates retired rite counter")
	Run.running = false
	var main = load("res://game/main.gd").new()
	add_child(main)
	main.show_arena()
	main.screen.set_process(false)
	await paint(main.screen)
	check(zone_of(main.screen, "rite:pull").is_empty(), "ritual has no rewarded action")
	var previous = main.screen
	main.show_title()
	check(not previous.is_inside_tree() and previous.is_queued_for_deletion(), "screen swap immediately detaches old input and simulation")
	main.queue_free()
	Arena.running = false
	finish("광고 없는 실행·저장 호환")
