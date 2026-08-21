extends Node

func _ready() -> void:
	# 1) 주장 재현
	Run.start_run(4242)
	Run.begin_draw()
	Run.confirm_hand()
	Run.gold = 6000
	PlayPolicy.shop(Run)
	print("재현 A: 골드6000 한 번 호출 -> passives=", Run.passives.keys(), " 남은골드=", Run.gold)

	# 2) 실제 자동플레이에서 한 번의 상점 방문에 몇 개나 사는가
	var DT := 1.0/30.0
	var hist := {}
	var first_visit_over3 := 0
	var total_visits := 0
	for r in range(16):
		var sv := 20260000 + r*977
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
			if sim.leaked > 0:
				Run.add_lives(-sim.leaked)
			if not Run.running:
				break
			var before: int = Run.passives.size()
			PlayPolicy.shop(Run)
			var bought: int = Run.passives.size() - before
			total_visits += 1
			hist[bought] = int(hist.get(bought,0)) + 1
			if bought > 3:
				first_visit_over3 += 1
	var ks: Array = hist.keys(); ks.sort()
	print("상점 방문 ", total_visits, "회, 한 방문에 산 패시브 수 분포:")
	for k in ks:
		print("   ", k, "개 -> ", hist[k], "회")
	print("3개 초과로 산 방문: ", first_visit_over3)
	get_tree().quit(0)
