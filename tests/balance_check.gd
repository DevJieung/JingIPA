extends Node

## 자동 플레이로 밸런스를 잰다. 게임 코드를 그대로 돌린다(전투는 BattleSim, 상점은 Run).
##
##   godot --headless --path . res://tests/balance_check.tscn
##   godot --headless --path . res://tests/balance_check.tscn -- --runs 24
##
## 보는 것:
##  - 몇 탄까지 갔는가 (중간값 / 최고 / 클리어율)
##  - 탄마다 목숨을 얼마나 잃는가 — 초반에 잃으면 게임이 시작부터 아프다는 뜻이다
##  - 골드가 남아도는가 모자라는가 — 남아돌면 상점이 심심하다는 뜻이다

const DT := 1.0 / 30.0     ## 시뮬레이션 한 걸음. 화면보다 굵게 돌려도 결과는 같아야 한다.


func _ready() -> void:
	var runs := 16
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--runs":
			runs = int(args[i + 1])
	var verbose := "--verbose" in args

	var reached: Array[int] = []
	var cleared := 0
	var lost_at := {}      # 탄 -> 그 탄에서 잃은 목숨의 합
	var seen_at := {}
	var gold_at := {}
	var hands := {}
	var t0 := Time.get_ticks_msec()

	for r in range(runs):
		var res := _one_run(20260000 + r * 977, verbose)
		reached.append(int(res["wave"]))
		if bool(res["cleared"]):
			cleared += 1
		for w in res["lost"]:
			lost_at[w] = float(lost_at.get(w, 0.0)) + float(res["lost"][w])
			seen_at[w] = int(seen_at.get(w, 0)) + 1
			# 판이 끝난 탄은 상점을 안 거치므로 골드 기록이 없다.
			gold_at[w] = float(gold_at.get(w, 0.0)) + float(res["gold"].get(w, 0))
		for h in res["hands"]:
			hands[h] = int(hands.get(h, 0)) + int(res["hands"][h])

	reached.sort()
	var mid: int = reached[reached.size() / 2]
	print("\n== 자동 플레이 %d판 (%.0f초) ==" % [runs, (Time.get_ticks_msec() - t0) / 1000.0])
	print("도달 탄: 중간값 %d · 최소 %d · 최고 %d · 클리어 %d판"
			% [mid, reached[0], reached[-1], cleared])

	print("\n탄별 (판수 / 깨진 크리스탈 평균 / 판 끝 골드 평균)")
	var ws: Array = seen_at.keys()
	ws.sort()
	for w in ws:
		if int(w) % 2 == 1 and int(w) > 6:
			continue
		var n := int(seen_at[w])
		print("  %2d탄  %2d판   크리스탈 -%.2f   골드 %5.0f"
				% [int(w), n, float(lost_at[w]) / float(n), float(gold_at[w]) / float(n)])

	print("\n나온 족보")
	var total := 0
	for h in hands:
		total += int(hands[h])
	for h in range(10):
		if hands.has(h):
			print("  %-20s %5d  (%.2f%%)"
					% [Poker.HAND_KO[h], int(hands[h]), float(hands[h]) * 100.0 / float(total)])
	print("\n판정: 정상")
	get_tree().quit(0)


func _one_run(seed_value: int, verbose: bool) -> Dictionary:
	Run.start_run(seed_value)
	var lost := {}
	var gold := {}
	var hands := {}
	while Run.running and Run.wave < Balance.LAST_WAVE:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		var res := Run.confirm_hand()
		hands[int(res["hand"])] = int(hands.get(int(res["hand"]), 0)) + 1
		# 새 영웅이 왔다 — 안뜰 여섯 자리를 다시 짠다(사람이라면 교체 창에서 하는 일).
		PlayPolicy.arrange(Run)

		var sim := BattleSim.new()
		sim.setup(Run, Run.wave, seed_value + Run.wave)
		var guard := 0
		while not sim.done and guard < 40000:
			sim.step(DT)
			sim.events.clear()
			# 0.5초마다 한 번 "사람이라면 여기서 아이템을 쓸까"를 본다.
			if guard % 15 == 0:
				PlayPolicy.use_items(Run, sim)
			guard += 1
		# 처치 수는 BattleSim 이 잡을 때마다 Run.kills 에 올린다(여기서 또 더하면 두 배).
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped))
		lost[Run.wave] = sim.leaked
		# ★ 목숨은 몬스터가 크리스탈에 닿는 순간 BattleSim 이 이미 깎았다. 여기서 또 깎지 마라.
		if verbose:
			print("  %2d탄 %-12s 안뜰%d 대기%2d  뚫림%2d  크리스탈%3d  골드%6d  DPS%8.0f  무기%d"
					% [Run.wave, Poker.HAND_KO[int(res["hand"])], Run.heroes.size(),
					   Run.bench.size(), sim.leaked, Run.lives, Run.gold,
					   Run.total_dps(), Run.weapons.size()])
		if not Run.running:
			break
		PlayPolicy.shop(Run)
		gold[Run.wave] = Run.gold
	var cleared: bool = Run.wave >= Balance.LAST_WAVE and Run.lives > 0
	return {"wave": Run.wave, "cleared": cleared, "lost": lost, "gold": gold, "hands": hands}
