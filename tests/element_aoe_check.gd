extends Harness

## Real sprite loading and event routing must preserve attack timing and damage.
##
##   godot --headless --path . res://tests/element_aoe_check.tscn
const SELECTED := {
	"thalassa": ["water", 7.0 / 12.0],
	"brasa": ["fire", 7.0 / 12.0],
	"sigrid": ["ice", 7.0 / 12.0],
	"lugh": ["elec", 0.5],
	"blank": ["none", 0.5],
}


func _ready() -> void:
	Save._readonly = true
	for unit in Roster.UNITS:
		var id := String(unit["id"])
		if not SELECTED.has(id):
			continue
		check(unit["elem"] == SELECTED[id][0] and unit["bullet"] == "zone",
				id + ": selected elemental area attacker")
		for name in ["idle", "attack", "shot"]:
			var clip := Anim.clip(unit, name)
			check(not clip.is_empty(), id + ": " + name + " loads")
			if clip.is_empty():
				continue
			check(int(clip["n"]) > 1 and float(clip["total"]) > 0,
					id + ": " + name + " is animated")
			check(int(clip["tex"].get_width()) == int(clip["w"]) * int(clip["n"]),
					id + ": " + name + " frame slicing")
		check(absf(Anim.hit_time(unit) - float(SELECTED[id][1])) < 0.00001,
				id + ": original release timing")
		_check_field(unit)
	_check_fallback()
	finish("속성별 광역 스프라이트 검사")


func _check_field(unit: Dictionary, passives: Array[String] = []) -> void:
	var id := String(unit["id"])
	Run.start_run(14092026)
	Run.begin_draw()
	Run.passives.assign(passives)
	Run.gain_hero(unit, int(unit["tier"]))
	var screen := BattleScreen.new()
	screen.sim.setup(Run, 1, 14092026)
	var sim: BattleSim = screen.sim
	sim.monsters.clear()
	for i in range(3):
		sim._spawn(Roster.MONSTERS[0])
		sim.monsters[i]["hp"] = 10000.0
		sim.monsters[i]["max"] = 10000.0
	sim._cache_positions()
	var at := BattleSim.mpos(sim.monsters[0])
	var radius := float(Balance.BULLET["zone"]["radius"]) * Run.pas_mult("radius")
	sim._mp[0] = at
	sim._mp[1] = at + Vector2(radius, 0)
	sim._mp[2] = at + Vector2(radius + 1.0, 0)
	sim.heroes[0]["pos"] = at - Vector2(100, 0)
	sim.events.clear()
	sim._shoot(0, 0, 120.0, "zone", false)
	check(sim.zones.size() == 1 and sim.bullets.is_empty(), id + ": field cast has no projectile damage")
	screen._drain()
	check(screen.area_fx.fields.size() == 1, id + ": real zone event creates visual field")
	if screen.area_fx.fields.is_empty() or sim.zones.is_empty():
		screen.free()
		return
	var field: Dictionary = screen.area_fx.fields[0]
	var shot: Dictionary = field.get("shot", {})
	var source := Anim.clip(unit, "shot")
	check(not shot.is_empty(), id + ": zone event routes character Shot sprite")
	if not shot.is_empty() and not source.is_empty():
		check(shot["tex"] == source["tex"] and shot["n"] == source["n"],
				id + ": field uses this character's Shot sheet")
	check(field["at"] == at and is_equal_approx(float(field["r"]), radius),
			id + ": field visual matches damage center and radius")
	var delay := float(sim.zones[0]["delay"])
	check(is_equal_approx(float(field["age"]), -delay), id + ": field preserves cast delay")
	if delay > 0.001:
		sim._step_zones(delay - 0.001)
		check(sim.monsters.all(func(m): return float(m["hp"]) == 10000.0),
				id + ": preview does not damage enemies")
		sim._step_zones(0.002)
	else:
		sim._step_zones(delay + 0.001)
	check(float(sim.monsters[0]["hp"]) < 10000.0,
			id + ": center enemy takes damage after cast delay")
	check(float(sim.monsters[1]["hp"]) < 10000.0,
			id + ": enemy at radius boundary takes damage")
	check(float(sim.monsters[2]["hp"]) == 10000.0,
			id + ": enemy outside radius remains unharmed")
	var tick_events := sim.events.filter(func(e): return e["t"] == "zone_tick")
	check(tick_events.size() == 1 and int(tick_events[0]["cnt"]) == 2,
			id + ": area event reports the two affected enemies")
	screen.area_fx.update(10.0)
	check(screen.area_fx.fields.is_empty(), id + ": expired visual releases its Shot reference")
	screen.free()


func _check_fallback() -> void:
	var effect := AreaFx.new()
	effect.zone(Vector2(200, 200), 64, "water", Color.CYAN, 0, 0.1, 0.25, 4)
	check(effect.fields.size() == 1, "characters without custom Shot keep the common field")
	check(effect.fields[0].get("shot", {}).is_empty(), "fallback accepts an absent custom clip")
	effect.impact(Vector2(200, 200), 64, "fire", Color.ORANGE, 0)
	check(effect.fields.size() == 2, "splash impact keeps working with custom zone support")
