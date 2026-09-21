extends Node2D

const IDS := ["thalassa", "brasa", "sigrid", "lugh", "blank"]
var phase := 0.0
var units: Array[Dictionary] = []
var output := "build/element-aoe-sprites/1280x800"
var battle_mode := false
var showcase := false

func _ready() -> void:
	Save._readonly = true
	for id in IDS:
		for unit in Roster.UNITS:
			if unit["id"] == id:
				units.append(unit)
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	for frame in range(12):
		phase = float(frame) / 12.0
		queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/animation_%02d.png" % [output, frame])
	showcase = true
	queue_redraw()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/showcase.png" % output)
	print("Elemental atlas rendered: ", output)
	await _battle_capture()
	get_tree().quit()

func _battle_capture() -> void:
	battle_mode = true
	queue_redraw()
	Run.start_run(14092026)
	Run.heroes.clear()
	Run.bench.clear()
	for unit in units:
		Run.gain_hero(unit, int(unit["tier"]))
	Run.wave = 24
	Run.phase = Run.Phase.BATTLE
	var battle := BattleScreen.new()
	add_child(battle)
	battle.set_process(false)
	battle.sim.monsters.clear()
	for i in range(15):
		battle.sim._spawn(Roster.MONSTERS[i % 4])
		battle.sim.monsters[-1]["s"] = Balance.path_len() * (0.12 + float(i) * 0.045)
		battle.sim.monsters[-1]["hp"] = 100000.0
		battle.sim.monsters[-1]["max"] = 100000.0
	battle.sim._cache_positions()
	for i in range(battle.sim.heroes.size()):
		battle._hero_aim(i, Anim.hit_time(units[i]), Vector2.RIGHT)
	for frame in range(14):
		if frame == 4:
			var used: Array[int] = []
			for i in range(battle.sim.heroes.size()):
				var hero: Dictionary = battle.sim.heroes[i]
				var nearest := -1
				var distance := INF
				for j in range(battle.sim._mp.size()):
					var target: Vector2 = battle.sim._mp[j]
					if target.y < 230 or target.y > 660 or used.has(j):
						continue
					var d: float = Vector2(hero["pos"]).distance_to(target)
					if d <= float(hero["range"]) and d < distance:
						distance = d
						nearest = j
				if nearest >= 0:
					used.append(nearest)
					battle.sim._shoot(i, nearest, 120.0, "zone", false)
			battle._drain()
		battle.t = float(frame) * 0.15
		battle.sim.elapsed = battle.t
		battle._tick_heroes(0.15)
		battle.area_fx.update(0.15)
		battle.fx.update(0.15)
		battle.queue_redraw()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/battle_%02d.png" % [output, frame])
	battle.queue_free()
	print("Elemental battle rendered: ", output)

func _draw() -> void:
	if battle_mode:
		return
	draw_rect(Rect2(0, 0, 1280, 800), Look.BG_DEEP)
	Look.text_center(self, Vector2(640, 38), "속성별 광역 영웅 · Idle / Attack / Shot", 26, Look.INK)
	for i in range(units.size()):
		var unit := units[i]
		var x := 136.0 + i * 252.0
		draw_rect(Rect2(x - 120, 58, 240, 720), Color(0.07, 0.09, 0.14))
		Look.text_center(self, Vector2(x, 87), String(unit["ko"]), 23, Look.GOLD)
		Look.text_center(self, Vector2(x, 112), String(unit["elem"]), 16, Look.INK)
		Look.text_center(self, Vector2(x, 146), "IDLE", 15, Look.INK)
		Anim.draw_unit(self, unit, "idle", phase, x, 320, 1.1)
		draw_line(Vector2(x - 70, 321), Vector2(x + 70, 321), Color(0.3, 0.4, 0.46), 1)
		Look.text_center(self, Vector2(x, 366), "ATTACK", 15, Look.INK)
		Anim.draw_unit(self, unit, "attack", Anim.hit_time(unit) if showcase else phase, x, 538, 1.1)
		draw_line(Vector2(x - 70, 539), Vector2(x + 70, 539), Color(0.3, 0.4, 0.46), 1)
		Look.text_center(self, Vector2(x, 585), "SHOT", 15, Look.INK)
		var shot := Anim.clip(unit, "shot")
		if not shot.is_empty():
			Anim.draw_frame(self, shot, 2 if showcase else int(phase * 12) % int(shot["n"]), x, 687, 1.1)
