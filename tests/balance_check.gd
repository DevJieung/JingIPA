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
	var runs := Harness.arg_int("--runs", 16)
	var verbose := Harness.has_arg("--verbose")
	if Harness.has_arg("--curve"):
		for w in [1, 10, 20, 29, 30, 31, 40, 49, 60, 80, 99, 100]:
			print("  %3d탄  체력 %14.0f  마릿수 %3d  합 %16.0f  처치골드 %d"
					% [w, Balance.wave_hp(w), Balance.wave_count(w),
					   Balance.wave_hp(w) * Balance.wave_count(w), Balance.kill_gold(w, "swarm")])
		get_tree().quit(0)
		return

	var reached: Array[int] = []
	var cleared := 0
	var lost_at := {}      # 탄 -> 그 탄에서 잃은 목숨의 합
	var seen_at := {}
	var gold_at := {}
	var hands := {}
	## 성역에 실제로 **선** 영웅의 속성을 센다.
	## ★ 이 줄이 이 검사에서 제일 값어치가 있을지도 모른다 — 사용자가 정한 표에서
	##   전기는 바위에 **0배**다. "전기 영웅이 그래서 아예 안 쓰이게 됐는가"는 클리어율로는
	##   절대 안 보이고, 여기서만 보인다. 다섯이 고루 나와야 뽑기가 선택으로 남는다.
	var elems := {}
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
		for e in res["elems"]:
			elems[e] = int(elems.get(e, 0)) + int(res["elems"][e])

	reached.sort()
	var mid: int = reached[reached.size() / 2]
	print("\n== 자동 플레이 %d판 (%.0f초) ==" % [runs, (Time.get_ticks_msec() - t0) / 1000.0])
	print("도달 탄: 중간값 %d · 최소 %d · 최고 %d · 클리어 %d판"
			% [mid, reached[0], reached[-1], cleared])

	print("\n탄별 (판수 / 깨진 크리스탈 평균 / 판 끝 골드 평균)")
	var ws: Array = seen_at.keys()
	ws.sort()
	for w in ws:
		# 100탄이라 다 찍으면 백 줄이다. 앞 여섯 탄은 다 보고(거기서 크리스탈을 잃으면
		# 게임을 켜자마자 벌을 받는 셈이라 제일 중요하다) 그 뒤는 다섯 탄마다 본다.
		if int(w) > 6 and int(w) % 5 != 0:
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
	print("\n성역에 선 영웅의 속성 (탄마다 출전한 영웅을 세었다)")
	var etot := 0
	for e in elems:
		etot += int(elems[e])
	for e in Balance.ELEM_ORDER:
		var n2 := int(elems.get(e, 0))
		print("  %-6s %6d  (%.1f%%)" % [Balance.elem_ko(String(e)), n2,
				float(n2) * 100.0 / float(maxi(1, etot))])
	print("\n판정: 정상")
	get_tree().quit(0)


func _one_run(seed_value: int, verbose: bool) -> Dictionary:
	Run.start_run(seed_value)
	var lost := {}
	var gold := {}
	var hands := {}
	var elems := {}
	while Run.running and Run.wave < Balance.LAST_WAVE:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		var res := Run.confirm_hand()
		hands[int(res["hand"])] = int(hands.get(int(res["hand"]), 0)) + 1
		# 새 영웅이 왔다 — 성역 여섯 자리를 다시 짠다(사람이라면 교체 창에서 하는 일).
		PlayPolicy.arrange(Run)

		for h in Run.heroes:
			var he := String(h["unit"].get("elem", "none"))
			elems[he] = int(elems.get(he, 0)) + 1

		var sim := BattleSim.new()
		sim.setup(Run, Run.wave, seed_value + Run.wave)
		var guard := 0
		while not sim.done and guard < 40000:
			sim.step(DT)
			sim.events.clear()
			guard += 1
		# 처치 수는 BattleSim 이 잡을 때마다 Run.kills 에 올린다(여기서 또 더하면 두 배).
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped))
		lost[Run.wave] = sim.leaked
		# ★ 목숨은 몬스터가 크리스탈에 닿는 순간 BattleSim 이 이미 깎았다. 여기서 또 깎지 마라.
		if verbose:
			var th := Run.theme_for(Run.wave)
			print("  %3d탄 %-10s %-10s 성역%d 전당%2d  뚫림%2d  크리스탈%3d  골드%6d  DPS%9.0f  패시브%d"
					% [Run.wave, String(th.get("ko", "")).left(10),
					   Poker.HAND_KO[int(res["hand"])], Run.heroes.size(),
					   Run.bench.size(), sim.leaked, Run.lives, Run.gold,
					   Run.total_dps(), Run.passives.size()])
		if not Run.running:
			break
		# ★ 진열은 **상점에 들어올 때 한 번** 굴린다(화면에서는 main.go_shop 이 한다).
		#   검사기는 화면을 안 타므로 여기서 같은 일을 해 준다 — 안 하면 첫 진열이
		#   판이 끝날 때까지 그대로라, 정책이 살 수 있는 패시브가 셋으로 굳는다.
		Run.shop_offer.clear()
		Run.roll_shop()
		PlayPolicy.shop(Run)
		gold[Run.wave] = Run.gold
	var cleared: bool = Run.wave >= Balance.LAST_WAVE and Run.lives > 0
	return {"wave": Run.wave, "cleared": cleared, "lost": lost, "gold": gold,
			"hands": hands, "elems": elems}
