extends Harness

var main: Node2D

func _ready() -> void:
	if not require_no_save():
		return
	main = load("res://game/main.gd").new()
	add_child(main)
	for scenario in ["ko", "en", "final_wave"]:
		I18n.set_locale("en" if scenario == "en" else "ko")
		Fixture.fresh(92126, 50 if scenario == "final_wave" else 12)
		if scenario == "final_wave":
			Run.wave = Balance.LAST_WAVE
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
			check(main.screen.revive_reward.result["gold"] == 1_000_000, "displayed gold matches the revival reward")
			check(not tap(main.screen, "revive:confirm"), "confirmation waits for the reveal to become visible")
			mouse(main.screen, Vector2(650, 390), true)
			check(main.screen.state == DrawScreen.REVIVE_REWARD and Run.last_result["reward_pending"], "background taps cannot dismiss the reward")
			main.menu.open()
			check(not main.menu.opened and main.screen_modal_open(), "reward modal blocks underlying menu actions")
			var pending := Run.snapshot()
			main.screen.revive_reward.update(1.2)
			await paint(main.screen)
			check(tap(main.screen, "revive:confirm"), "explicit main-camp confirmation is available")
			main._process(1.0)
			main._process(1.0)
			check(main.screen is ShopScreen and Run.phase == Run.Phase.SHOP and not Run.last_result["reward_pending"], "confirmation opens the main camp and saves acknowledgement")
			check(Run.snapshot()["heroes"] == before["heroes"] and Run.bench.size() == before["bench"].size(), "revealing and confirming never auto-deploy or duplicate the reward")
			check(main.screen.formation.selected == -1 and main.screen.formation.bench_selected == -1, "placement remains the player's choice")
			var accepted := Run.snapshot()
			Save.cur_run = pending
			check(main.resume_run(), "unconfirmed reward save can resume")
			main._process(1.0)
			main._process(1.0)
			check(main.screen.state == DrawScreen.REVIVE_REWARD, "resume returns to the unseen reward")
			check(Run.bench.size() == before["bench"].size(), "resuming reward reveal grants nothing again")
			Save.cur_run = accepted
			check(main.resume_run(), "confirmed reward save can resume")
			main._process(1.0)
			main._process(1.0)
			check(main.screen is ShopScreen and Run.retry_wave, "confirmed reward resumes in the main camp")
			check(Run.next_battle_wave() == before["wave"], "camp previews the failed wave, including the final wave")
			check(Run.gold == before["gold"] + 1_000_000 and Run.buy_upgrade("atk"), "revival gold is immediately usable for camp upgrades")
			var prepared := Run.snapshot()
			await paint(main.screen)
			check(tap(main.screen, "next"), "camp can start the retry")
			main._process(1.0)
			main._process(1.0)
			check(main.screen is BattleScreen and Run.wave == before["wave"] and not Run.retry_wave, "retry starts the same wave without dealing again or skipping the final wave")
			main.screen.set_process(false)
			check(Run.cards == prepared["cards"] and Run.gold == prepared["gold"] and Run.snapshot()["heroes"] == prepared["heroes"], "retry preserves cards, upgrades, gold and formation")
			if attempt == 2:
				Run.settle_wave(false)
				if scenario == "final_wave":
					check(Run.phase == Run.Phase.WIN, "winning the retried final wave completes the run")
				else:
					check(Run.phase == Run.Phase.SHOP and not Run.retry_wave and Run.next_battle_wave() == Run.wave + 1, "winning a retry restores normal next-wave progression")
			await frames(2)
	main.queue_free()
	await frames(2)
	finish("광고 부활 획득 연출 연동 검사")
