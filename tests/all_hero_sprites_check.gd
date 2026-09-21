extends Harness

## 영웅 쉰 명의 시트가 계약(all_hero_sprites_contract.json)대로 들어와 있는가.
##
##   godot --headless --path . res://tests/all_hero_sprites_check.tscn -- --only id1,id2

const APPROVED := ["thalassa", "brasa", "sigrid", "lugh", "blank"]
const TRAVELING := ["shot", "splash", "pierce", "ricochet", "chain"]


func _ready() -> void:
	Save._readonly = true
	var contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://tests/all_hero_sprites_contract.json"))
	var muzzle_map: Dictionary = {}
	var muzzle_path := "res://art/animation/roster_v1/muzzle_map.json"
	if FileAccess.file_exists(muzzle_path):
		muzzle_map = JSON.parse_string(FileAccess.get_file_as_string(muzzle_path))
	check(Roster.UNITS.size() == 50 and contract.size() == 50, "all 50 heroes covered")
	var only := PackedStringArray()
	if arg("--only", "") != "":
		only = arg("--only", "").split(",")
	var groups := {}
	for unit in Roster.UNITS:
		var id := String(unit["id"])
		if not only.is_empty() and id not in only:
			continue
		check(contract.has(id), id + ": original hero exists")
		if not contract.has(id):
			continue
		var baseline: Dictionary = contract[id]
		var kind := String(unit["bullet"])
		groups[kind] = true
		check(unit["elem"] == baseline["elem"] and kind == baseline["bullet"]
				and unit["weapon"] == baseline["weapon"], id + ": identity and attack type preserved")
		var meta := Anim._meta(String(unit["anim"]))
		var source := "imagegen_element_aoe_v1" if id in APPROVED else "imagegen_roster_v1"
		check(meta.get("source", "") == source, id + ": new approved art style installed")
		check(absf(Anim.hit_time(unit) * 1000.0 - float(baseline["hit_ms"])) < 0.001,
				id + ": attack release timing preserved")
		check(is_equal_approx(float(meta.get("scale", 0)), float(baseline["scale"])),
				id + ": world actor scale preserved")
		check(meta.get("anchor", {}) == baseline["anchor"], id + ": planted actor origin preserved")
		if id in APPROVED:
			check(meta.get("muzzle_at", {}) == baseline["muzzle_at"], id + ": approved muzzle preserved")
		else:
			check(muzzle_map.has(id) and meta.get("muzzle_at", {}) == muzzle_map.get(id, {}),
					id + ": release origin matches the artist's measured weapon tip")
		_check_muzzle(unit, meta)
		for name in ["idle", "attack", "shot"]:
			var clip := Anim.clip(unit, name)
			check(not clip.is_empty(), id + ": " + name + " loads")
			if clip.is_empty():
				continue
			var count: int = {"idle": 8, "attack": 12, "shot": 4}[name]
			check(int(clip["n"]) == count, id + ": " + name + " frame count")
			check(float(clip["total"]) > 0 and clip["ms"].size() == count,
					id + ": " + name + " frame durations")
			check(int(clip["tex"].get_width()) == count * int(clip["w"]),
					id + ": " + name + " sheet divides into complete cells")
			if name != "shot":
				check(is_equal_approx(float(clip["ax"]) * float(clip["w"]), float(baseline["anchor"]["x"]))
						and is_equal_approx(float(clip["ay"]) * float(clip["h"]), float(baseline["anchor"]["y"])),
						id + ": padded cell keeps the same pixel origin")
			var looping: bool = name == "idle" or (name == "shot" and kind in TRAVELING)
			check(bool(clip["loop"]) == looping, id + ": " + name + " loop behavior")
			if looping:
				check(Anim.frame_at(clip, float(clip["total"]) / 1000.0) == 0,
						id + ": " + name + " repeats past one cycle")
		_check_firing(unit)
		if kind == "chain":
			# The live screen uses DbgSim. Its override must forward the artwork
			# source both while the debug overlay is enabled and while disabled.
			Dbg.reset()
			Dbg.on = true
			_check_firing(unit)
			Dbg.on = false
			Dbg.reset()
	if only.is_empty():
		check(groups.size() == 7, "all seven attack types exercised")
	finish("전체 영웅 스프라이트 검사")


func _check_muzzle(unit: Dictionary, meta: Dictionary) -> void:
	var point: Dictionary = meta.get("muzzle_at", {})
	if point.is_empty():
		check(false, String(unit["id"]) + ": missing projectile origin")
		return
	for scale in [0.66, 1.0, 1.2]:
		for face in [-1.0, 1.0]:
			var expected: Vector2 = Vector2(absf(float(point["x"])) * face, float(point["y"])) \
					* float(meta["scale"]) * float(unit.get("sc", 1.0)) * scale
			var actual := Balance.muzzle_off(unit, scale, face)
			check(actual.distance_to(expected) < 0.02,
					String(unit["id"]) + ": roster origin matches rendered weapon at scale %.2f / face %.0f" % [scale, face])


func _check_firing(unit: Dictionary) -> void:
	var id := String(unit["id"])
	var kind := String(unit["bullet"])
	Run.start_run(14502026)
	Run.begin_draw()
	Run.gain_hero(unit, int(unit["tier"]))
	var screen := BattleScreen.new()
	screen.sim.setup(Run, 1, 14502026)
	var sim: BattleSim = screen.sim
	sim.monsters.clear()
	for i in range(4):
		sim._spawn(Roster.MONSTERS[0])
		sim.monsters[-1]["hp"] = 10000.0
		sim.monsters[-1]["max"] = 10000.0
		sim.monsters[-1]["s"] = 200.0 + i * 24.0
		sim.monsters[-1]["off"] = 0.0
		sim.monsters[-1]["route"] = 0
	sim._cache_positions()
	sim.heroes[0]["pos"] = BattleSim.mpos(sim.monsters[0]) - Vector2(70, 0)
	sim.events.clear()
	sim._aim(0, 0, 120.0, kind, false, 2.0)
	check(sim._pending.size() == 1, id + ": attack winds up before release")
	if sim._pending.is_empty():
		screen.free()
		return
	var wind := float(sim._pending[0]["t"])
	sim._release(maxf(0, wind - 0.00001))
	check(not sim.events.any(func(e): return e["t"] == "fire"), id + ": no early fire")
	sim._release(0.00002)
	var fires := sim.events.filter(func(e): return e["t"] == "fire")
	check(fires.size() == 1, id + ": one release after windup")
	if not fires.is_empty():
		check(fires[0]["kind"] == kind and fires[0]["el"] == unit["elem"],
				id + ": release retains attack and element")
	screen._drain()
	var shot := Anim.clip(unit, "shot")
	if kind == "zone":
		check(sim.zones.size() == 1 and sim.bullets.is_empty(), id + ": delayed area remains a field")
		check(screen.area_fx.fields.size() == 1, id + ": field reaches renderer")
		if not screen.area_fx.fields.is_empty():
			var field: Dictionary = screen.area_fx.fields[0]
			var visual: Dictionary = field.get("shot", {})
			check(not shot.is_empty() and not visual.is_empty() and visual.get("tex") == shot.get("tex"),
					id + ": field uses its character Shot")
		check(sim.monsters.all(func(m): return float(m["hp"]) == 10000.0),
				id + ": area warning remains harmless")
	elif kind == "beam":
		var beams := screen.fx.items.filter(func(it): return it["t"] == "clip_beam")
		check(not beams.is_empty(), id + ": instantaneous beam uses a sprite")
		if not beams.is_empty():
			check(not shot.is_empty() and beams[0]["clip"]["tex"] == shot.get("tex"),
					id + ": beam carries the correct Shot")
		check(float(sim.monsters[0]["hp"]) < 10000.0 and sim.bullets.is_empty(),
				id + ": beam keeps instant damage")
	else:
		check(sim.bullets.size() == 1, id + ": traveling attack still creates a projectile")
		if not sim.bullets.is_empty():
			var bullet: Dictionary = sim.bullets[0]
			check(bullet["kind"] == kind and int(bullet["src"]) == 0,
					id + ": projectile retains its source and collision mode")
			check(Vector2(bullet["v"]).length() > 0,
					id + ": sprite projectile continues traveling")
			check(sim.monsters.all(func(m): return float(m["hp"]) == 10000.0),
					id + ": firing does not inflict premature projectile damage")
			if kind == "chain":
				_check_chain(screen, bullet, unit, shot)
	screen.free()


func _check_chain(screen: BattleScreen, bullet: Dictionary, unit: Dictionary, shot: Dictionary) -> void:
	var id := String(unit["id"])
	var sim: BattleSim = screen.sim
	sim.events.clear()
	bullet["p"] = sim._mp[0]
	sim._impact(bullet, 0)
	var bolts := sim.events.filter(func(e): return e["t"] == "bolt")
	check(not bolts.is_empty(), id + ": native chain jumps between targets")
	check(bolts.all(func(e): return int(e.get("shot_src", -1)) == 0),
			id + ": each native chain segment carries its artwork source")
	check(float(sim.monsters[0]["hp"]) < 10000.0 and float(sim.monsters[1]["hp"]) < 10000.0,
			id + ": native chain damage still reaches multiple enemies")
	screen.fx.clear()
	screen._drain()
	var strips := screen.fx.items.filter(func(it): return bool(it.get("native_chain", false)))
	check(strips.size() == bolts.size(), id + ": each native hop renders a Shot strip")
	for strip in strips:
		check(not shot.is_empty() and strip["clip"]["tex"] == shot.get("tex"),
				id + ": chain strip uses this hero's texture")
	screen.fx.clear()
	sim._chain(0, 1.0, 2, 0.7, 150.0, [0], Color.CYAN, 0, "elec")
	var passive := sim.events.filter(func(e): return e["t"] == "bolt")
	check(not passive.is_empty() and passive.all(func(e): return int(e.get("shot_src", -1)) == -1),
			id + ": passive lightning stays separate from native attack artwork")
	screen._drain()
	check(not screen.fx.items.any(func(it): return bool(it.get("native_chain", false))),
			id + ": passive lightning retains common visuals")
