extends Node
const DT := 1.0 / 60.0
func _ready() -> void:
	var errs := 0
	var made := 0
	var used := {}
	Run.start_run(4321)
	while Run.running and Run.wave < 30:
		Run.begin_draw()
		PlayPolicy.do_rerolls(Run)
		Run.confirm_hand()
		var sim := Dbg2.new()
		sim.setup(Run, Run.wave, 31 + Run.wave)
		var g := 0
		while not sim.done and g < 60000:
			sim.step(DT)
			sim.events.clear()
			g += 1
		errs += sim.errors.size()
		if sim.errors.size() > 0:
			print(sim.errors[0])
		made += sim.pierce_made
		for bid in sim.pierce_hits:
			var n := int(sim.pierce_hits[bid])
			used[n] = int(used.get(n, 0)) + 1
		Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left))
		if sim.leaked > 0:
			Run.add_lives(-sim.leaked)
		if not Run.running:
			break
		PlayPolicy.shop(Run)
	print("오류 %d · 관통탄 %d발" % [errs, made])
	var ks: Array = used.keys(); ks.sort()
	for k in ks:
		print("   %d마리 명중: %d발 (%.1f%%)" % [int(k), int(used[k]), float(used[k])*100.0/float(max(1,made))])
	get_tree().quit(0)
