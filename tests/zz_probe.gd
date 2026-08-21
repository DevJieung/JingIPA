extends Node
const DT := 1.0 / 30.0
var prng := RandomNumberGenerator.new()

func _offer(run, n: int) -> Array:
	var pool: Array = []
	for p in Balance.PASSIVES:
		if not run.passives.has(p["id"]):
			pool.append(p)
	for i in range(pool.size() - 1, 0, -1):
		var j := prng.randi_range(0, i)
		var t = pool[i]; pool[i] = pool[j]; pool[j] = t
	return pool.slice(0, mini(n, pool.size()))

# mode 0 = 현재 정책(루프마다 새 offer), 1 = 화면과 같은 방문당 1회 offer
func shop2(run, mode: int) -> int:
	var bought := 0
	var offer: Array = _offer(run, 3)
	var guard := 0
	while guard < 120:
		guard += 1
		var best := ""
		var best_v := 0.0
		var dps: float = max(1.0, run.total_dps())
		for u in Balance.UPGRADES:
			var id := String(u["id"])
			var l: int = run.lv(id)
			if Balance.upgrade_maxed(id, l): continue
			var cost: int = Balance.upgrade_cost(id, l)
			if cost > run.gold: continue
			var v := 0.0
			match id:
				"atk", "rate", "crit", "critx":
					run.levels[id] = l + 1
					var after: float = run.total_dps()
					run.levels[id] = l
					v = ((after - dps) / dps) / float(cost)
				"rng": v = (0.060 if l < 6 else 0.020) / float(cost)
				"gold": v = (0.100 if run.wave <= 15 else 0.030) / float(cost)
				"life":
					if run.lives <= 6: v = 1.500 / float(cost)
					elif run.lives <= 12: v = 0.250 / float(cost)
					else: v = 0.040 / float(cost)
				"reroll": v = (0.120 if l < 2 else 0.040) / float(cost)
				"time": v = 0.100 / float(cost)
			if v > best_v:
				best_v = v
				best = id
		var pbest := ""
		var pbest_v := 0.0
		var cand: Array = (_offer(run, 3) if mode == 0 else offer)
		for p in cand:
			var cost: int = int(p["cost"])
			if run.gold < int(cost * 1.5): continue
			var v: float = 0.35 / float(cost)
			if v > pbest_v:
				pbest_v = v
				pbest = String(p["id"])
		if pbest != "" and pbest_v > best_v:
			if run.buy_passive(pbest):
				bought += 1
				offer = offer.filter(func(q): return String(q["id"]) != pbest)
				continue
		if best == "": break
		if not run.buy_upgrade(best): break
	return bought

func one(seed_value: int, mode: int) -> Dictionary:
	Run.start_run(seed_value)
	prng.seed = seed_value * 31 + 7
	var maxvisit := 0
	var p10 := 0; var p20 := 0; var p30 := 0
	while Run.running and Run.wave < Balance.LAST_WAVE:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		Run.confirm_hand()
		var sim := BattleSim.new()
		sim.setup(Run, Run.wave, seed_value + Run.wave)
		var guard := 0
		while not sim.done and guard < 40000:
			sim.step(DT); sim.events.clear(); guard += 1
		Run.kills += sim.kills
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left))
		if sim.leaked > 0: Run.add_lives(-sim.leaked)
		if not Run.running: break
		maxvisit = maxi(maxvisit, shop2(Run, mode))
		if Run.wave == 10: p10 = Run.passives.size()
		if Run.wave == 20: p20 = Run.passives.size()
		if Run.wave == 30: p30 = Run.passives.size()
	return {"wave": Run.wave, "cleared": Run.wave >= Balance.LAST_WAVE and Run.lives > 0,
		"maxvisit": maxvisit, "p10": p10, "p20": p20, "p30": p30, "pend": Run.passives.size()}

func _ready() -> void:
	var runs := 12
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--runs": runs = int(args[i + 1])
	for mode in [0, 1]:
		var reached: Array[int] = []
		var cl := 0; var mv := 0
		var s10 := 0.0; var s20 := 0.0; var s30 := 0.0; var sp := 0.0
		for r in range(runs):
			var res := one(20260000 + r * 977, mode)
			reached.append(int(res["wave"]))
			if bool(res["cleared"]): cl += 1
			mv = maxi(mv, int(res["maxvisit"]))
			s10 += float(res["p10"]); s20 += float(res["p20"]); s30 += float(res["p30"]); sp += float(res["pend"])
		reached.sort()
		print("mode %d  중간값 %d  최소 %d  최고 %d  클리어 %d/%d  한방문최대구매 %d  패시브 10탄 %.1f 20탄 %.1f 30탄 %.1f 끝 %.1f"
			% [mode, reached[reached.size()/2], reached[0], reached[-1], cl, runs, mv, s10/runs, s20/runs, s30/runs, sp/runs])
	get_tree().quit(0)
