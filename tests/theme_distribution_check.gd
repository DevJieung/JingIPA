extends Harness


func _ready() -> void:
	if not require_no_save():
		return
	for seed_value in [15, 71, 999]:
		Fixture.fresh(seed_value)
		for theme_index in range(Roster.THEMES.size()):
			Run.themes.fill(theme_index)
			var theme: Dictionary = Roster.THEMES[theme_index]
			var main_body := String(theme["main_body"])
			var before := Run.snapshot().duplicate(true)
			for wave in range(1, Balance.LAST_WAVE + 1):
				var spawns := Run.spawns_for(wave)
				var counts: Dictionary = {}
				var regular := true
				var early_safe := true
				for monster in spawns:
					var body := String(monster["body"])
					counts[body] = int(counts.get(body, 0)) + 1
					regular = regular and monster["kind"] != "boss"
					if wave <= 5:
						early_safe = early_safe and Balance.body_immune(body).is_empty()
					if wave <= 2:
						early_safe = early_safe and monster["kind"] == "swarm"
					elif wave == 3:
						early_safe = early_safe and monster["kind"] in ["swarm", "fast"]
				check(spawns.size() == Balance.wave_count(wave) and regular, "regular wave count stays unchanged")
				check(counts.size() >= 2, "minority elements remain in every wave")
				check(early_safe, "early immunity and movement protections remain")
				if wave > 5 or Balance.body_immune(main_body).is_empty():
					var target := float(theme["weights"][main_body]) * spawns.size()
					check(absf(float(counts.get(main_body, 0)) - target) <= 0.501,
						"main element quota: %s wave %d" % [theme["id"], wave])
				if Balance.is_boss_wave(wave):
					var sim := BattleSim.new()
					sim.setup(Run, wave)
					check(sim._queue.size() == spawns.size() + 1, "exactly one additional boss")
					check(sim._queue[0]["kind"] == "boss" and sim._queue[0]["body"] == main_body,
						"boss matches theme: %s wave %d" % [theme["id"], wave])
					check(Run.spawns_for(wave) == spawns, "combat does not reroll the distribution")
			check(Run.snapshot() == before, "spawn preview does not consume gameplay RNG or change saves")
	for seed_value in range(100):
		Fixture.fresh(seed_value)
		check(Balance.body_immune(String(Run.theme_for(1)["main_body"])).is_empty(),
			"new runs start in a theme compatible with early immunity protection")
	finish("50개 테마 속성 집중·보스 검사")
