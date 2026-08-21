extends Node

const DT := 1.0 / 60.0

func _ready() -> void:
	var all: Array = []
	for r in range(3):
		Run.start_run(30250000 + r * 131)
		while Run.running and Run.wave < Balance.LAST_WAVE:
			Run.begin_draw()
			PlayPolicy.do_rerolls(Run)
			Run.confirm_hand()
			var sim := DbgSim.new()
			sim.setup(Run, Run.wave, 555 + Run.wave)
			var guard := 0
			while not sim.done and guard < 60000:
				sim.step(DT)
				sim.events.clear()
				guard += 1
			if sim.errors.size() > 0:
				print("wave %d: %d errors" % [Run.wave, sim.errors.size()])
				for e in sim.errors.slice(0, 6):
					print("   ", e)
				all.append_array(sim.errors)
			Run.add_gold(Balance.clear_bonus(Run.wave, sim.wiped, sim.time_left))
			if sim.leaked > 0:
				Run.add_lives(-sim.leaked)
			if not Run.running:
				break
			PlayPolicy.shop(Run)
	print("총 오류 %d" % all.size())
	get_tree().quit(0)
