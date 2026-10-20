extends Harness
## The jewel box in the real game (D1 integration): a run opens its first stage, the free first box
## opens over the paused 3D field and ArenaBoxView draws it on the real ArenaScreen. Run with
## --fixed-fps 30 so the screen clock is deterministic; every `--every` frame is saved.
##
##   godot --path . --resolution 1280x800 --fixed-fps 30 res://tests/box_game_preview.tscn -- \
##       --out=DIR [--lang=en] [--seed=20261019] [--dur=6.5] [--every=2] [--pick-at=SEC] [--reroll-at=SEC]

var screen: Node2D

func _ready() -> void:
	if not require_no_save(): return
	var out := arg("--out", "build/feedback-2026-10-19/D1/game")
	DirAccess.make_dir_recursive_absolute(out)
	I18n.set_locale(arg("--lang", "ko"))
	Arena.start_run(arg_int("--seed", 20261019))
	screen = load("res://tests/box_game_screen.gd").new()
	add_child(screen)
	await frames(4)
	check(Arena.modal == "stage", "run opens on the stage card")
	Arena.confirm_stage()
	await frames(2)
	check(Arena.modal == "box", "the stage's free first box opens (modal box)")
	var dur := arg_float("--dur", 6.5)
	var every := maxi(1, arg_int("--every", 2))
	var pick_at := arg_float("--pick-at", -1.0)
	var reroll_at := arg_float("--reroll-at", -1.0)
	var picked := false
	var rerolled := false
	var n := 0
	var saved := 0
	var t := 0.0
	var log: Array = []
	while t <= dur:
		if reroll_at >= 0.0 and not rerolled and t >= reroll_at:
			rerolled = true
			check(screen.box_view.is_ready(), "reroll waits for the settled cards")
			check(not Arena.respin().is_empty(), "the box rerolls")
		if pick_at >= 0.0 and not picked and t >= pick_at:
			picked = true
			check(screen.box_view.is_ready(), "the pick waits for the settled cards")
			var best := JewelBox.best(Arena.box_cards)
			check(not Arena.pick_card(best).is_empty(), "the pick lands")
		await RenderingServer.frame_post_draw
		if n % every == 0:
			get_viewport().get_texture().get_image().save_png("%s/%04d.png" % [out, saved])
			var zones: Array = []
			for z in screen.ui.zones:
				if bool(z["on"]): zones.append(String(z["id"]))
			log.append({"frame": saved, "t": snappedf(t, 0.001), "deal": snappedf(screen.box_view.deal_age(), 0.001),
				"pick": snappedf(screen.box_view.pick_age(), 0.001), "ready": screen.box_view.is_ready(), "zones": zones.slice(-8)})
			saved += 1
		n += 1
		t += 1.0 / 30.0
	var f := FileAccess.open(out + "/meta.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"tier": Arena.box_tier, "cards": Arena.box_cards.map(func(c): return [String(c["unit"]["id"]), int(c["stars"]), bool(c["guaranteed"])]),
		"settle": screen.box_view.settle_time(), "frames": log}, " "))
	f.close()
	check(saved > 0, "frames saved")
	finish("보석상자 게임 화면")
