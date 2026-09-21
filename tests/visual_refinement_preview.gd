extends Node2D

## Deterministic render fixtures for rarity bounds, stun, area footprint and push motion.
var output := "build/visual-refinement/1280x800"
var checks := 0
var failures := 0
var battle: BattleScreen
var main = null
var preview_mode := true
var area := AreaFx.new()
var phase := 0.0
const IDS := ["thalassa", "brasa", "sigrid", "lugh", "blank"]
var units: Array[Dictionary] = []

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func capture(name_: String) -> void:
	queue_redraw()
	if battle != null:
		battle.queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output + "/" + name_ + ".png")

func _ready() -> void:
	Save._readonly = true
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	for id in IDS:
		for u in Roster.UNITS:
			if u["id"] == id:
				units.append(u)
	# Verify the actual shared layout geometry, including narrow 12-hero cards.
	for width in [51, 63, 100, 116, 127, 149, 200]:
		for tier in range(10):
			var box := Rect2(25, 4, width, 20)
			check(box.grow(0.001).encloses(Look.rarity_rect(box, 5.0)), "rarity backing fits its allocated header")
	for radius in [32.0, 64.0, 128.0, 192.0]:
		var rect := AreaFx.sprite_rect(Vector2.ZERO, radius)
		for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			check(corner.length() <= radius, "area burst stays inside damage circle")
	for u in Roster.UNITS:
		var box := Rect2(0, 0, 66, 59)
		var src: Rect2 = Art.unit_preview(u)["src"]
		check(box.grow(0.001).encloses(Art.fit_rect(src.size, box)), "wide hero equipment respects preview box")
	for i in range(units.size()):
		var u := units[i]
		area.zone(Vector2(136 + i * 252, 590), 104, String(u["elem"]), Balance.elem_color(String(u["elem"])), 9, 0.20, 0.25, 4, Anim.clip(u, "shot"))
	area.update(0.10)
	await capture("rarity_and_warning")
	for i in range(9):
		phase = i * 0.12
		area.update(0.12)
		await capture("area_%02d" % i)
	preview_mode = false
	Run.start_run(14092026)
	Run.heroes.clear()
	Run.bench.clear()
	for u in units:
		Run.gain_hero(u, int(u["tier"]))
	Run.wave = 24
	Run.phase = Run.Phase.BATTLE
	battle = BattleScreen.new()
	add_child(battle)
	battle.set_process(false)
	battle.sim._queue.clear()
	battle.sim.monsters.clear()
	for i in range(8):
		battle.sim._spawn(Roster.MONSTERS[i % Roster.MONSTERS.size()])
		var mo: Dictionary = battle.sim.monsters[-1]
		mo["s"] = 290.0 + float(i / 2) * 180.0
		mo["route"] = i % 2
		mo["hp"] = 100000.0
		mo["max"] = 100000.0
		mo["stun_t"] = 1.5 if i < 6 else 0.0
	battle.sim._cache_positions()
	for i in range(8):
		battle.t = i * 0.08
		await capture("stun_%02d" % i)
	for mo in battle.sim.monsters:
		mo["stun_t"] = 0.0
	# Single impact: first image is the unchanged collision position, then 50 fps.
	battle.sim._push(0)
	battle._drain()
	for i in range(19):
		battle.t = i * 0.02
		await capture("push_%02d" % i)
		battle.sim._move_monsters(0.02)
		battle.sim._cache_positions()
		battle.fx.update(0.02)
	print("VISUAL REFINEMENT CHECK: %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _draw() -> void:
	if not preview_mode:
		return
	draw_rect(Rect2(0, 0, 1280, 800), Look.BG_DEEP)
	Look.text_left(self, Vector2(35, 38), "희귀도 · 좁은 카드 · 선택 상태", 25, Look.GOLD)
	for i in range(10):
		var u: Dictionary = Roster.units_of_tier(i)[i % 5]
		HeroCard.draw(self, Rect2(40 + i * 123, 68, 83, 147), {"unit": u, "tier": i}, i % 2 == 0)
		HeroCard.draw(self, Rect2(35 + i * 123, 240, 112, 156), {"unit": u, "tier": 9 - i}, i % 2 != 0)
	Look.text_left(self, Vector2(35, 428), "광역 공격 · 원은 실제 피해 반경 / 폭발과 파편은 원 안에 유지", 23, Look.GOLD)
	for i in range(units.size()):
		var u := units[i]
		Look.text_center(self, Vector2(136 + i * 252, 461), String(u["ko"]), 22, Look.INK)
		Look.draw_elem(self, Vector2(136 + i * 252, 735), 14, String(u["elem"]))
	area.draw_back(self)
	area.draw_front(self)
