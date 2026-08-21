extends Node
const DT := 1.0 / 60.0
func _avg(a: Array) -> float:
	if a.is_empty(): return -1.0
	var s := 0.0
	for x in a: s += float(x)
	return s / float(a.size())
func _ready() -> void:
	Run.start_run(4321)
	var l1: Array = []
	var lf: Array = []
	var homing := 0
	var tot := 0
	while Run.running and Run.wave < 16:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		Run.confirm_hand()
		var sim := Dbg3.new()
		sim.setup(Run, Run.wave, 31 + Run.wave)
		var g := 0
		while not sim.done and g < 60000:
			sim.step(DT); sim.events.clear(); g += 1
		l1.append_array(sim.life_1hit)
		lf.append_array(sim.life_full)
		homing += sim.still_homing_after_hit
		tot += sim.hit_total
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left))
		if sim.leaked > 0: Run.add_lives(-sim.leaked)
		if not Run.running: break
		PlayPolicy.shop(Run)
	print("관통탄 명중 %d회 중 '방금 때린 놈이 아직 유도 목표' %d회 (%.0f%%)"
		% [tot, homing, float(homing)*100.0/float(max(1,tot))])
	print("1마리만 맞힌 관통탄 %d발 · 평균 생존 %.2f초 (수명 2.2초)" % [l1.size(), _avg(l1)])
	print("3마리 이상 맞힌 관통탄 %d발 · 평균 생존 %.2f초" % [lf.size(), _avg(lf)])
	get_tree().quit(0)
