extends Harness

var output := "build/progression-design/motion"

func _ready() -> void:
	if not require_no_save():
		return
	Save._readonly=true
	output=arg("--out",output)
	DirAccess.make_dir_recursive_absolute(output)
	Fixture.fresh(20261006)
	Run.heroes.clear()
	for unit in Roster.fusion_units(9):
		Run.gain_hero(unit,9,false,true,{"awakened":true,"awakening_mult":1.35})
	Run.wave=12
	Run.phase=Run.Phase.BATTLE
	var main=load("res://game/main.gd").new()
	add_child(main)
	var battle:=BattleScreen.new()
	main._swap(battle)
	battle.set_process(false)
	battle.sim.support_enabled=false
	battle.sim._queue.clear()
	for hero in battle.sim.heroes:
		hero["crit"]=1.0
	for index in range(12):
		battle.sim._spawn(Roster.MONSTERS[index%Roster.MONSTERS.size()])
		var monster:Dictionary=battle.sim.monsters.back()
		monster["s"]=210 + index*80
		monster["hp"]=100000.0
		monster["max"]=100000.0
	battle.sim._cache_positions()
	var actual_strike:=false
	for index in range(20):
		battle._process(0.12)
		for effect in battle.fx.items:
			actual_strike=actual_strike or String(effect.get("t",""))=="strike"
		await paint(battle)
		await snap(output+"/combat_%02d.png"%index)
	check(actual_strike,"real simulation critical hit creates new fracture impact")
	check(not battle.sim.monsters.is_empty(),"continuous combat remains live")
	main.queue_free()
	await frames(3)
	Sfx.stop_effects()
	for player in Sfx._music_players:
		player.stop()
		player.stream=null
	await get_tree().create_timer(0.15).timeout
	finish("Actual critical combat animation review")
