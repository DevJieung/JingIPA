extends Node
const DT := 1.0/30.0

# 사람과 똑같이: 상점 방문당 offer 를 딱 한 번만 뽑고, 산 것만 지운다.
static func shop_human(run) -> void:
	var offer: Array = run.offer_passives(3)
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
				"atk","rate","crit","critx":
					run.levels[id] = l + 1
					var after: float = run.total_dps()
					run.levels[id] = l
					v = ((after - dps)/dps)/float(cost)
				"rng": v = (0.060 if l < 6 else 0.020)/float(cost)
				"gold": v = (0.100 if run.wave <= 15 else 0.030)/float(cost)
				"life":
					if run.lives <= 6: v = 1.500/float(cost)
					elif run.lives <= 12: v = 0.250/float(cost)
					else: v = 0.040/float(cost)
				"reroll": v = (0.120 if l < 2 else 0.040)/float(cost)
				"time": v = 0.100/float(cost)
			if v > best_v:
				best_v = v; best = id
		var pbest := ""
		var pbest_v := 0.0
		for p in offer:
			var cost: int = int(p["cost"])
			if run.gold < int(cost * 1.5): continue
			var v: float = 0.35/float(cost)
			if v > pbest_v:
				pbest_v = v; pbest = String(p["id"])
		if pbest != "" and pbest_v > best_v:
			if run.buy_passive(pbest):
				offer = offer.filter(func(p): return String(p["id"]) != pbest)
				continue
		if best == "": break
		if not run.buy_upgrade(best): break

func _run(sv: int, human: bool) -> Dictionary:
	Run.start_run(sv)
	while Run.running and Run.wave < Balance.LAST_WAVE:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		Run.confirm_hand()
		var sim := BattleSim.new()
		sim.setup(Run, Run.wave, sv + Run.wave)
		var g := 0
		while not sim.done and g < 40000:
			sim.step(DT); sim.events.clear(); g += 1
		Run.kills += sim.kills
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left))
		if sim.leaked > 0: Run.add_lives(-sim.leaked)
		if not Run.running: break
		if human: shop_human(Run)
		else: PlayPolicy.shop(Run)
	return {"wave": Run.wave, "cleared": Run.wave >= Balance.LAST_WAVE and Run.lives > 0,
			"p": Run.passives.size()}

func _ready() -> void:
	for mode in [false, true]:
		var reached: Array = []
		var cleared := 0
		var ps := 0
		for r in range(24):
			var res := _run(20260000 + r*977, mode)
			reached.append(int(res["wave"]))
			ps += int(res["p"])
			if bool(res["cleared"]): cleared += 1
		reached.sort()
		print(("사람식(방문당 1뽑기)" if mode else "현재정책(루프마다 재뽑기)"),
			" 중간값=", reached[reached.size()/2], " 최소=", reached[0], " 최고=", reached[-1],
			" 클리어=", cleared, "/24  평균패시브수=", "%.2f" % (float(ps)/24.0))
		print("   전체: ", reached)
	get_tree().quit(0)
