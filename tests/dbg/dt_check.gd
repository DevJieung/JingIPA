extends Node

func _run(dts: Array, w: int) -> Dictionary:
	var sim := BattleSim.new()
	sim.setup(Run, w, 4242 + w)
	var i := 0
	var guard := 0
	while not sim.done and guard < 200000:
		sim.step(float(dts[i % dts.size()]))
		sim.events.clear()
		i += 1
		guard += 1
	return {"kills": sim.kills, "leaked": sim.leaked, "left": sim.time_left, "wiped": sim.wiped}

func _ready() -> void:
	# 같은 영웅 구성 · 같은 시드로 dt 만 바꿔 본다
	Run.start_run(777)
	for k in range(14):
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		Run.confirm_hand()
		PlayPolicy.shop(Run)
	print("영웅 %d명  DPS %.0f" % [Run.heroes.size(), Run.total_dps()])
	for w in [14, 20, 25]:
		var a := _run([1.0/60.0], w)                 # 60fps · 1배속
		var b := _run([1.0/30.0], w)                 # 검사기가 쓰는 값
		var c := _run([0.02, 0.02, 0.01], w)         # 60fps · 3배속 (게임의 실제 잘라 쓰기)
		var d := _run([0.02, 0.0133333], w)          # 60fps · 2배속
		print("%2d탄  1/60: kill %3d leak %2d left %.2f | 1/30: kill %3d leak %2d left %.2f | 3배속: kill %3d leak %2d left %.2f | 2배속: kill %3d leak %2d left %.2f"
			% [w, a["kills"], a["leaked"], a["left"], b["kills"], b["leaked"], b["left"],
			   c["kills"], c["leaked"], c["left"], d["kills"], d["leaked"], d["left"]])
	get_tree().quit(0)
