extends "res://tests/voc_hero_preview.gd"

const PreviewAd = preload("res://tests/fusion_undo_preview.gd").PreviewAd


func review_legacy_materials() -> void:
	for result_on_field in [true, false]:
		Fixture.fresh(23092026)
		Run.phase = Run.Phase.SWAP
		var unit: Dictionary = Roster.units_of_tier(0)[0]
		var leftover := {"unit": unit, "tier": 0, "wave": 7, "n": 1}
		Run.bench.append(leftover)
		var originals: Array = []
		for tier in [0, 1, 4, 8, 9]:
			var hero := {"unit": Roster.units_of_tier(tier)[0], "tier": tier, "wave": 1, "n": 1}
			originals.append(hero)
			Run.bench.append(hero)
		if not result_on_field:
			Run.heroes.append(leftover.duplicate(true))
			Run.ensure_posts()
		var before_h := Run._heroes_out(Run.heroes)
		var before_b := Run._heroes_out(Run.bench)
		Run.bench.resize(1)
		Run.gain_hero(unit, 0, false)
		Run.fusion_pending = {"id": 1, "before_h": before_h, "before_b": before_b,
			"unit": String(unit["id"]), "tier": 0, "score": 27, "failed": true}
		var fusion := FusionView.new()
		fusion._cache_materials()
		check(Run._heroes_out(fusion._materials) == Run._heroes_out(originals),
			"legacy material cache preserves unconsumed matching hero with result on " + ("field" if result_on_field else "bench"))


func fusion_fixture() -> DrawScreen:
	Fixture.fresh(23092026)
	Run.bench.clear()
	Run.phase = Run.Phase.SWAP
	var tiers := [0, 1, 4, 8, 9]
	for tier in tiers:
		var unit: Dictionary = Roster.units_of_tier(tier)[0]
		Run.bench.append({"unit": unit, "tier": tier, "wave": 1, "n": 1})
	var draw := DrawScreen.new()
	main._swap(draw)
	draw.set_process(false)
	draw.fusion.opened = true
	draw.fusion.selected.assign(Run.fusion_candidates())
	return draw


func reward_ad(screen: Node, action: String, kind: String) -> void:
	var ad := PreviewAd.new()
	Ads._ad = ad
	Ads._ad_kind = kind
	Ads._loaded_at = Time.get_ticks_msec()
	check(tap(screen, action) and ad.shown and Ads.busy, "actual UI starts " + kind + " ad")
	if ad.shown:
		ad.listener.on_user_earned_reward.call(null)
		ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
	check(not Ads.busy and ad.destroyed, "rewarded ad finishes " + kind)
	check(not Ads._reward_notice, "dedicated animation is unobscured by generic notice")


func review_fusion(language: String) -> void:
	var draw := fusion_fixture()
	await capture(language + "_fusion_average")
	var average_visible := false
	for entry in Look.text_audit:
		if entry["text"] == "2.7":
			average_visible = true
	check(average_visible, "five-card rarity average displays exact 2.7 stars")
	draw.fusion.selected.resize(4)
	await capture(language + "_fusion_four")
	check(not bool(zone_of(draw, "fusion:go").get("on", true)), "incomplete selection cannot fuse")
	draw.fusion.selected.assign(Run.fusion_candidates())
	await paint(draw)
	check(tap(draw, "fusion:go"), "fusion starts from five selected cards")
	draw.fusion.reveal_age = 3.0
	await capture(language + "_fusion_result")
	var materials := draw.fusion._materials.duplicate(true)
	# A fresh view simulates reopening a saved pending result.
	draw.fusion = FusionView.new()
	draw.fusion.opened = true
	await paint(draw)
	check(Run._heroes_out(draw.fusion._materials) == Run._heroes_out(materials), "pending save restores the five original animation cards")
	reward_ad(draw, "fusion:undo", "fusion_undo")
	draw.fusion.update(0.0)
	check(draw.fusion.restore_age == 0.0, "completed rewarded undo starts restoration")
	check(Run.fusion_pending.is_empty(), "card restoration reflects actual rewarded state")
	var times := [0.0, 0.16, 0.34, 0.50, 0.75, 1.0, 1.35, 1.8, 2.5]
	for index in range(times.size()):
		draw.fusion.update(float(times[index]) - draw.fusion.restore_age)
		await capture(language + "_restore_motion_%02d" % index)
		check(zone_of(draw, "fusion:go").is_empty(), "fusion inputs stay blocked during restoration")
		check(bool(zone_of(draw, "fusion:restored").get("on", false)) == (float(times[index]) >= 1.35), "confirm follows restoration timing")
	check(Run._heroes_out(draw.fusion._materials) == Run._heroes_out(materials), "animation preserves original identity, order, and rarity")
	check(tap(draw, "fusion:restored"), "restoration waits for explicit confirmation")
	await capture(language + "_fusion_restored")
	check(draw.fusion.restore_age < 0 and draw.fusion.selected.is_empty(), "confirmation returns to unselected restored hall")
	# The shared view is also used by the main camp.
	Run.phase = Run.Phase.SHOP
	var shop := ShopScreen.new()
	main._swap(shop)
	shop.set_process(false)
	shop.fusion.opened = true
	shop.fusion.selected.assign(Run.fusion_candidates())
	await capture(language + "_camp_fusion_average")
	check(tap(shop, "fusion:go"), "main camp starts fusion")
	shop.fusion.reveal_age = 3.0
	await paint(shop)
	reward_ad(shop, "fusion:undo", "fusion_undo")
	shop.fusion.update(1.8)
	await capture(language + "_camp_fusion_restored")
	check(tap(shop, "fusion:restored"), "main camp confirms restoration")


func review_revive(language: String, all_owned: bool) -> void:
	Fixture.fresh(23092026, 12)
	Run.wave = 18
	Run.gold = 2000
	Run.levels["atk"] = 6
	Run.levels["rate"] = 3
	Run.confirm_hand()
	if all_owned:
		for unit in Roster.units_of_tier(Poker.Hand.ROYAL):
			Run.bench.append({"unit": unit, "tier": Poker.Hand.ROYAL, "wave": 1, "n": 1})
	Run.phase = Run.Phase.BATTLE
	Run.prepare_battle()
	check(RunValidation.valid(Run.battle_checkpoint, Run.SAVE_VERSION), "revival preview begins from a valid checkpoint")
	Run.add_lives(-Run.max_lives())
	var over := OverScreen.new()
	main._swap(over)
	over.set_process(false)
	var stem := language + ("_all_owned" if all_owned else "_normal")
	await capture(stem + "_over")
	reward_ad(over, "continue", "continue")
	over._process(0.0)
	check(await wait_screen(main, "draw_screen", 120), "revive opens dedicated gold reveal")
	main._process(1.0)
	var draw := main.screen as DrawScreen
	draw.set_process(false)
	check(draw.state == DrawScreen.REVIVE_REWARD, "revive keeps saved pending reward")
	check(draw.revive_reward.result.get("gold", 0) == 1_000_000, "every roster gets one million gold")
	if not all_owned:
		var times := [0.0, 0.16, 0.34, 0.50, 0.75, 1.1, 1.5, 2.2, 4.0]
		draw.revive_reward.begin(Run.last_result)
		for index in range(times.size()):
			draw.revive_reward.update(float(times[index]) - draw.revive_reward.age)
			await capture(language + "_gold_motion_%02d" % index)
	else:
		for tick in range(150):
			draw.revive_reward.update(0.02)
	await capture(stem + "_gold_reward")
	check(tap(draw, "revive:confirm"), "gold reward has explicit main camp confirmation")
	check(await wait_screen(main, "shop_screen", 120), "confirmation lands in main camp")
	main._process(1.0)
	var shop := main.screen as ShopScreen
	shop.set_process(false)
	check(Run.phase == Run.Phase.SHOP and Run.retry_wave and Run.next_battle_wave() == 18, "camp previews the same revived stage")
	await capture(stem + "_camp_upgrades")
	shop.tab = "f"
	await capture(stem + "_camp_formation")
	Run.heroes.clear()
	await capture(stem + "_camp_empty")
	check(not bool(zone_of(shop, "next").get("on", true)), "empty battlefield cannot begin retry")


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	output = arg("--out", "build/revive-fusion/1280x800")
	DirAccess.make_dir_recursive_absolute(output)
	Ads.set_process(false)
	Ads._native = true
	Ads._initialized = true
	main = load("res://game/main.gd").new()
	add_child(main)
	I18n.audit_enabled = true
	Look.text_audit_enabled = true
	review_legacy_materials()
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		await review_fusion(language)
		await review_revive(language, false)
		await review_revive(language, true)
	Look.text_audit_enabled = false
	var file := FileAccess.open(output + "/text-audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Revive gold and restored fusion visual review")
