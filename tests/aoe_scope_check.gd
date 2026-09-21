extends "res://tests/element_aoe_check.gd"

func _ready() -> void:
	if not require_no_save():
		return
	var area_count := 0
	for unit in Roster.UNITS:
		if unit["bullet"] == "zone":
			area_count += 1
			_check_field(unit)
			_check_field(unit, ["mortar"])
	check(area_count == 10, "all ten area heroes have boundary and enhanced-radius checks")
	for tier in range(10):
		Fixture.fresh(14092026)
		Run.gain_hero(Roster.units_of_tier(tier)[0], tier)
		var screen := BattleScreen.new()
		screen.sim.setup(Run, 1)
		var at := Vector2(350, 350)
		for radius in [44.0, 48.0, 66.0, 72.0, Balance.PASSIVE_WILDFIRE_R]:
			var rect := AreaFx.sprite_rect(at, radius)
			for corner in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
				check(at.distance_to(corner) <= radius, "every sprite corner fits inside damage circle")
			for em in [.5, 1.0, 2.0]:
				for split in [false, true]:
					screen.area_fx.fields.clear()
					screen.sim.events.append({"t":"splash", "p":at, "r":radius, "em":em, "el":"fire", "src":0, "split":split})
					screen._drain()
					check(screen.area_fx.fields.size() == 1, "splash and split each create one area effect")
					if screen.area_fx.fields.size() == 1:
						check(is_equal_approx(screen.area_fx.fields[0]["r"], radius), "weakness and rarity never inflate splash radius")
		screen.area_fx.fields.clear()
		screen.sim.events.append({"t":"wildfire", "p":at, "r":Balance.PASSIVE_WILDFIRE_R})
		screen._drain()
		check(screen.area_fx.fields.size() == 1 and is_equal_approx(screen.area_fx.fields[0]["r"], Balance.PASSIVE_WILDFIRE_R), "wildfire keeps its exact propagated radius")
		screen.free()
	finish("전체 광역 범위 회귀 검사")
