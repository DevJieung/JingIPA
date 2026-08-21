extends Node

func _ready() -> void:
	Run.start_run(11)
	Run.begin_draw()
	Run.confirm_hand()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 99)
	# 몬스터 한 마리만 손으로 세운다
	sim._queue.clear()
	sim._spawn({"kind": "tank", "h": 68.0, "color": "#ffffff", "id": "x"})
	var mo: Dictionary = sim.monsters[0]
	mo["hp"] = 1.0e9
	mo["max"] = 1.0e9

	# 1) 센 화상(치명타 가정) → 만료 → 약한 화상
	sim._burn(0, 300.0, 3.0)
	print("센 화상 직후 burn=%.1f burn_t=%.2f" % [float(mo["burn"]), float(mo["burn_t"])])
	for i in range(400):          # 4초
		sim.step(0.01)
	print("4초 뒤   burn=%.1f burn_t=%.2f  (만료됨)" % [float(mo["burn"]), float(mo["burn_t"])])
	var hp0: float = float(mo["hp"])
	sim._burn(0, 50.0, 3.0)       # 약한 화상 — 초당 50 이어야 한다
	print("약한 화상(50dps) 적용 → burn=%.1f" % float(mo["burn"]))
	for i in range(300):          # 3초
		sim.step(0.01)
	print("3초 동안 실제로 들어간 피해 = %.0f  (기대 150)" % (hp0 - float(mo["hp"])))

	# 2) 둔화도 같은 문제
	sim._slow(0, 0.25, 2.0)
	for i in range(300):
		sim.step(0.01)
	print("둔화 만료 뒤 slow=%.2f" % float(mo["slow"]))
	sim._slow(0, 0.22, 2.0)
	print("서리부적(0.22) 적용 → slow=%.2f  (기대 0.22)" % float(mo["slow"]))
	get_tree().quit(0)
