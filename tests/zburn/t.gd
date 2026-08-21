extends Node
func _ready() -> void:
	var Sim = load("res://game/battle_sim.gd")
	var sim = Sim.new()
	sim.wave = 1
	sim._spawn({"kind":"grunt","h":40.0,"ko":"x"})
	var mo = sim.monsters[0]
	mo["hp"] = 100000.0
	sim._burn(0, 100.0, 3.0)
	print("강한 화상 직후: burn=", mo["burn"], " t=", mo["burn_t"])
	for i in range(200):
		sim._move_monsters(0.05)
	print("10초 뒤: burn=", mo["burn"], " t=", mo["burn_t"])
	var hp0: float = mo["hp"]
	sim._burn(0, 1.0, 3.0)
	print("약한 화상(dps=1) 건 직후: burn=", mo["burn"], " t=", mo["burn_t"])
	for i in range(60):
		sim._move_monsters(0.05)
	print("이후 3초 화상 피해 =", hp0 - float(mo["hp"]), " (정상이면 3.0)")
	sim._slow(0, 0.25, 2.0)
	for i in range(100):
		sim._move_monsters(0.05)
	sim._slow(0, 0.05, 2.0)
	print("약한 둔화 뒤 slow =", mo["slow"], " (정상이면 0.05)")
	get_tree().quit()
