extends Harness

class PreviewAd extends RewardedInterstitialAd:
	var shown := false
	var destroyed := false
	var listener: OnUserEarnedRewardListener

	func _init() -> void:
		super(0)

	func show(reward_listener := OnUserEarnedRewardListener.new()) -> void:
		shown = true
		listener = reward_listener

	func destroy() -> void:
		destroyed = true


var main: Node2D
var output := "build/fusion-undo/1280x800"


func capture(name_: String) -> void:
	main.screen.queue_redraw()
	main.menu.queue_redraw()
	await frames(2)
	await snap(output + "/" + name_ + ".png")


func seed_for_result(material_tier: int, target_tier: int) -> int:
	var probabilities := Balance.fusion_probabilities((material_tier + 1) * 5)
	var random := RandomNumberGenerator.new()
	for candidate in range(10000):
		random.seed = candidate
		var roll := random.randf()
		for tier in range(probabilities.size()):
			roll -= probabilities[tier]
			if roll <= 0:
				if tier == target_tier:
					return candidate
				break
	check(false, "fixture can generate requested fusion tier")
	return 0


func setup_materials(tier: int) -> DrawScreen:
	Fixture.fresh(21092026)
	Run.heroes.clear()
	Run.bench.clear()
	var material := Roster.pick_unit(tier, Run.rng)
	for i in range(5):
		Run.gain_hero(material, tier, false, false)
	Run.phase = Run.Phase.SWAP
	var draw := DrawScreen.new()
	main._swap(draw)
	draw.set_process(false)
	draw.fusion.opened = true
	return draw


func check_result(language: String, material_tier: int, target_tier: int, label: String, repeats: int) -> void:
	var draw := setup_materials(material_tier)
	var materials_before: Array = Run.snapshot()["bench"].duplicate(true)
	for iteration in range(repeats):
		Run.rng.seed = seed_for_result(material_tier, target_tier)
		draw.fusion.selected.assign(Run.fusion_candidates())
		await paint(draw)
		check(tap(draw, "fusion:go"), label + " starts through the fusion button")
		check(int(Run.fusion_pending.get("tier", -1)) == target_tier, label + " generated the requested actual result")
		draw.fusion.reveal_age = 1.5
		await paint(draw)
		check(not bool(zone_of(draw, "fusion:undo").get("on", true)), "undo waits for the reveal to finish")
		draw.fusion.reveal_age = 3.0
		var stem := language + "_" + label + ("_after_undo" if iteration > 0 else "")
		await capture(stem)
		var undo := zone_of(draw, "fusion:undo")
		check(bool(undo.get("on", false)), label + " shows an enabled rewarded undo action")
		if not undo.is_empty():
			check(Look.SCREEN.encloses(undo["rect"]), "undo touch target stays inside the screen")
			check(not Rect2(undo["rect"]).intersects(zone_of(draw, "fusion:accept")["rect"]), "undo and accept touch targets do not overlap")
		var ad := PreviewAd.new()
		Ads._ad = ad
		Ads._ad_kind = "fusion_undo"
		Ads._loaded_at = Time.get_ticks_msec()
		check(tap(draw, "fusion:undo") and ad.shown and Ads.busy, "undo button requests a fresh rewarded ad")
		await paint(draw)
		check(not bool(zone_of(draw, "fusion:undo").get("on", true)), "undo is disabled during its ad")
		check(not bool(zone_of(draw, "fusion:accept").get("on", true)), "accept is disabled during the ad")
		if ad.shown:
			ad.listener.on_user_earned_reward.call(null)
			ad.full_screen_content_callback.on_ad_dismissed_full_screen_content.call()
		check(not Ads.busy and ad.destroyed, "completed ad releases the result controls")
		check(Run.fusion_pending.is_empty() and Run.snapshot()["bench"] == materials_before,
				"earned reward returns all five original materials")
		Ads._message_left = 0
		Ads._reward_notice = false
		draw.fusion.update(0.0)
		check(draw.fusion.restore_age >= 0, "rewarded undo starts the five-card restoration animation")
		draw.fusion.update(1.6)
		await paint(draw)
		check(tap(draw, "fusion:restored"), "restored cards wait for explicit confirmation")
		await paint(draw)
		check(zone_of(draw, "fusion:undo").is_empty(), "restored state returns to material selection")
		check(draw.fusion.selected.is_empty(), "restored materials can be selected for another fusion")
		if label == "upgraded" and iteration == 0:
			await capture(language + "_restored")


func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly = true
	output = arg("--out", output)
	DirAccess.make_dir_recursive_absolute(output)
	Ads.set_process(false)
	Ads._native = true
	Ads._initialized = true
	main = load("res://game/main.gd").new()
	add_child(main)
	I18n.audit_enabled = true
	for language in ["ko", "en"]:
		I18n.set_locale(language)
		await check_result(language, 0, 1, "upgraded", 2)
		await check_result(language, 8, 8, "same_tier", 1)
		await check_result(language, 9, 9, "highest_tier", 1)
		check(I18n.missing.is_empty(), "fusion labels are translated in " + language)
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream = null
	await get_tree().create_timer(0.15).timeout
	finish("Fusion repeat rewarded undo preview")
