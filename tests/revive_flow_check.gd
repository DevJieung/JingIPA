extends Harness

var main: Node2D

func _ready() -> void:
	if not require_no_save():
		return
	main = load("res://game/main.gd").new()
	add_child(main)
	for locale in ["ko", "en"]:
		I18n.set_locale(locale)
		Fixture.fresh(92126, 12)
		for attempt in range(3):
			Run.prepare_battle()
			var before := Run.snapshot()
			Run.add_lives(-Run.max_lives())
			main.go_over()
			main.screen.set_process(false)
			Ads.busy = true
			check(Run.apply_ad_reward("continue", {}), "earned continue reward applies")
			main.screen._process(0.1)
			check(main.screen is OverScreen and main._fade_dir == 0, "reveal waits until the ad closes")
			Ads.busy = false
			main.screen._process(0.1)
			main._process(1.0)
			main._process(1.0)
			check(main.screen is DrawScreen and main.screen.state == DrawScreen.REVIVE_REWARD, "ad dismissal opens dedicated reward reveal")
			main.screen.set_process(false)
			main.screen.revive_reward.age = 0.0
			await paint(main.screen)
			check(main.screen.revive_reward.result["unit"]["id"] == Run.bench[-1]["unit"]["id"], "displayed identity is the newly granted reserve hero")
			check(not tap(main.screen, "revive:confirm"), "confirmation waits for the reveal to become visible")
			mouse(main.screen, Vector2(650, 390), true)
			check(main.screen.state == DrawScreen.REVIVE_REWARD and Run.last_result["reward_pending"], "background taps cannot dismiss the reward")
			main.menu.open()
			check(not main.menu.opened and main.screen_modal_open(), "reward modal blocks underlying menu actions")
			var pending := Run.snapshot()
			main.screen.revive_reward.update(1.2)
			await paint(main.screen)
			check(tap(main.screen, "revive:confirm"), "explicit hero-placement confirmation is available")
			check(main.screen.state == DrawScreen.SWAP and not Run.last_result["reward_pending"], "confirmation opens formation and saves acknowledgement")
			check(Run.snapshot()["heroes"] == before["heroes"] and Run.bench.size() == before["bench"].size() + 1, "revealing and confirming never auto-deploy or duplicate the reward")
			check(main.screen.formation.selected == -1 and main.screen.formation.bench_selected == -1, "placement remains the player's choice")
			var accepted := Run.snapshot()
			Save.cur_run = pending
			check(main.resume_run(), "unconfirmed reward save can resume")
			main._process(1.0)
			main._process(1.0)
			check(main.screen.state == DrawScreen.REVIVE_REWARD, "resume returns to the unseen reward")
			check(Run.bench.size() == before["bench"].size() + 1, "resuming reward reveal grants nothing again")
			Save.cur_run = accepted
			check(main.resume_run(), "confirmed reward save can resume")
			main._process(1.0)
			main._process(1.0)
			check(main.screen.state == DrawScreen.SWAP, "confirmed reward resumes at formation")
			await frames(2)
	main.queue_free()
	await frames(2)
	finish("광고 부활 획득 연출 연동 검사")
