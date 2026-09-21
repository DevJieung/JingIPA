extends Harness

## 30탄 출현 수 상한, 후반 체력 성장/골드 보정, 실제 3배속 스폰 회귀 검사.

func _ready() -> void:
	if not require_no_save():
		return
	if not has_arg("--profile-only"):
		check_curve_and_rewards()
		check_spawn_queues()
	for wave in [29, 30, 31, 49, 59, 99, 100]:
		check_triple_speed(wave)
	finish("후반 몬스터 수·체력·3배속 검사")


func old_count(wave: int) -> int:
	if Balance.is_boss_wave(wave):
		return mini(40, 4 + floori(wave * 0.5))
	return 3 + wave if wave <= 2 else mini(72, 5 + floori(wave * 1.2))


func check_curve_and_rewards() -> void:
	for wave in range(1, Balance.LAST_WAVE + 1):
		var count := Balance.wave_count(wave)
		var boss_wave := Balance.is_boss_wave(wave)
		check(count + int(boss_wave) <= 41, "every wave including its boss stays within 41 monsters")
		if wave <= 30:
			check(count == old_count(wave), "waves 1 through 30 retain their original population")
		else:
			check(count == (19 if boss_wave else 41), "late waves use the fixed normal or boss population")
		for rank in range(1, 6):
			var hp := Balance.wave_hp(wave, rank)
			check(is_finite(hp) and hp > 0.0, "all wave and theme health values remain valid")
			if wave > 30:
				check(hp > Balance.wave_hp(wave - 1, rank), "health keeps increasing after population stops growing")
		for kind in Balance.MKIND:
			var old_reward := roundi((2.82 + wave * 0.105) * float(Balance.MKIND[kind]["gold"]))
			var reward := Balance.kill_gold(wave, kind)
			if wave <= 30 or kind == "boss":
				check(reward == old_reward, "early rewards and single-boss rewards remain unchanged")
			else:
				var old_budget := old_reward * old_count(wave)
				check(absi(reward * count - old_budget) <= ceili(count * 0.5),
						"fewer enemies preserve the wave's kill-gold budget within per-kill rounding")
	check(Balance.wave_hp(40) > Balance.wave_hp(30) * 3.5, "ten later waves are materially tougher with a fixed count")


func check_spawn_queues() -> void:
	Fixture.fresh(2192026, 1)
	for wave in range(1, Balance.LAST_WAVE + 1):
		var before := Run.snapshot()
		var preview := Run.spawns_for(wave)
		var sim := BattleSim.new()
		sim.setup(Run, wave)
		var boss_count := 0
		var actual_hp := 0.0
		var actual_ids := {}
		for monster in sim._queue:
			var kind := String(monster["kind"])
			actual_hp += Balance.wave_hp(wave, Run.theme_rank(wave)) * float(Balance.MKIND[kind]["hp"])
			if kind == "boss":
				boss_count += 1
			else:
				actual_ids[monster["id"]] = int(actual_ids.get(monster["id"], 0)) + 1
		var preview_ids := {}
		for monster in preview:
			preview_ids[monster["id"]] = int(preview_ids.get(monster["id"], 0)) + 1
		check(actual_ids == preview_ids, "theme preview exactly matches the capped battle queue")
		check(boss_count == int(Balance.is_boss_wave(wave)), "boss waves still contain exactly one boss")
		check(sim._queue.size() == Balance.wave_count(wave) + boss_count, "real queue uses the population cap")
		check(sim._queue.size() <= 41, "no spawn path bypasses the cap")
		check(is_equal_approx(sim.total_hp, actual_hp), "battle health budget uses current wave health")
		check(Run.snapshot() == before, "preview and queue creation preserve saved state and gameplay RNG")


func check_triple_speed(wave: int) -> void:
	Fixture.fresh(2192026, 12)
	Run.wave = wave
	Run.phase = Run.Phase.BATTLE
	var sim := BattleSim.new()
	sim.setup(Run, wave, 2192026)
	var expected := sim._queue.size()
	var peak := 0
	var started := Time.get_ticks_usec()
	# Same substeps as BattleScreen: 60 display frames/sec at 3x, <= 0.02s per step.
	for frame in range(240):
		var left := 3.0 / 60.0
		while left > 0.0001 and not sim.done:
			var dt := minf(0.02, left)
			sim.step(dt)
			sim.events.clear()
			peak = maxi(peak, sim.monsters.size())
			left -= dt
	var elapsed_us := Time.get_ticks_usec() - started
	check(sim._queue.is_empty() and sim._spawn_route == expected, "3x play spawns the full queue exactly once")
	check(sim.kills + sim.leak_n + sim.monsters.size() == expected, "3x play loses or duplicates no monsters")
	if not has_arg("--profile-only"):
		check(peak <= (20 if Balance.is_boss_wave(wave) else 41), "live monsters stay capped at 3x")
	for monster in sim.monsters:
		check(float(monster["motion_t"]) > 0.0 and is_finite(float(monster["hp"])),
				"3x monsters retain progressing motion and valid health")
	print("%d탄 · 총 %d · 동시 최대 %d · 3배속 240프레임 시뮬레이션 %.1fms" % [wave, expected, peak, elapsed_us / 1000.0])
