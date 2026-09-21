extends Harness

func _ready() -> void:
	if not require_no_save():
		return
	Fixture.fresh(20260920, 3)
	Run.prepare_battle()
	var sim := BattleSim.new()
	sim.setup(Run, Run.wave, 24)
	sim.monsters.clear()
	sim._spawn(Roster.MONSTERS[0])
	sim.monsters[0]["hp"] = 100.0
	sim.monsters[0]["max"] = 100.0
	sim._hurt(0, 35.0, false, 0, "none", false)
	sim._hurt(0, 200.0, false, 1, "none", false)
	var first := String(Run.heroes[0]["unit"]["id"])
	var second := String(Run.heroes[1]["unit"]["id"])
	check(is_equal_approx(Run.hero_damage[first]["damage"], 35.0), "actual damage is credited to first hero")
	check(is_equal_approx(Run.hero_damage[second]["damage"], 65.0), "overkill is excluded from cumulative damage")
	check(Run.best_player()["unit"]["id"] == second, "highest cumulative damage wins")
	Run.phase = Run.Phase.SHOP
	check(Run.swap_field_bench(1, -1), "damage winner can move to reserve")
	check(Run.best_player()["unit"]["id"] == second, "reserve hero keeps earned damage")
	Run.bench.clear()
	check(Run.best_player()["unit"]["id"] == second, "consumed hero keeps earned damage")
	Run.phase = Run.Phase.BATTLE
	Run.record_hero_damage(Run.heroes[0], 50.0)
	check(Run.best_player()["unit"]["id"] == first and is_equal_approx(Run.best_player()["damage"], 85.0), "damage accumulates beyond one battle")
	Run.phase = Run.Phase.SHOP
	var saved := Run.snapshot()
	check(Run.restore(saved) and is_equal_approx(Run.best_player()["damage"], 85.0), "damage survives save and restore")
	for bad_value in [-1.0, INF, NAN, "invalid"]:
		var bad := saved.duplicate(true)
		bad["hero_damage"][first]["damage"] = bad_value
		check(not Run.restore(bad), "invalid saved damage rejected")
	Run.prepare_battle()
	Run.record_hero_damage(Run.heroes[0], 1000.0)
	Run.add_lives(-Run.max_lives())
	check(Run.phase == Run.Phase.OVER and is_equal_approx(Run.best_player()["damage"], 1085.0), "defeat includes damage from failed wave")
	check(Run.restore(Save.cur_run) and is_equal_approx(Run.best_player()["damage"], 1085.0), "defeat result survives app restart")
	check(Run.revive_wave() and is_equal_approx(Run.best_player()["damage"], 85.0), "revive rolls damage back with replayed wave checkpoint")
	var old := Run.snapshot()
	old.erase("hero_damage")
	old.erase("owned_passives")
	check(Run.restore(old) and Run.best_player()["damage"] == 0.0, "legacy save migrates without fabricated damage")
	Fixture.fresh(20260921, 1)
	Run.phase = Run.Phase.SHOP
	Run.gold = 100000
	for p in Balance.PASSIVES:
		check(Run.buy_passive(String(p["id"])), "every offered passive can be owned")
	check(Run.owned_passives.size() == Balance.PASSIVES.size() and Run.passives.size() == 3, "full inventory with exactly three active")
	check(Run.offer_passives().is_empty(), "owned inactive passives are excluded from offers")
	check(Run.restore(Run.snapshot()) and Run.owned_passives.size() == Balance.PASSIVES.size(), "full inventory survives reload")
	var bad := Run.snapshot()
	bad["owned_passives"].erase(Run.passives[0])
	check(not Run.restore(bad), "active passive absent from ownership is rejected")
	Run.start_run(1)
	check(Run.hero_damage.is_empty() and Run.owned_passives.is_empty() and Run.passives.is_empty(), "new run clears run-scoped inventory and damage")
	check(int(Balance.upgrade_by_id("reroll")["base"]) == 100, "free reroll upgrade starts at 100 gold")
	finish("누적 전과·패시브 보유 회귀 검사")
