extends Harness

## 몬스터 이동 클립 · 상태이상 · 희귀 착탄 검사.
##
##   godot --headless --path . res://tests/monster_check.tscn -- --assets


func _ready() -> void:
	# 단독 실행해도 실제 플레이 기록에 검사 판을 쓰지 않는다.
	Save._readonly = true
	Run.start_run(9102026)
	Run.begin_draw()
	var sim := BattleSim.new()
	sim.setup(Run, 1, 9102026)
	sim.monsters.clear()
	sim._spawn(Roster.MONSTERS[0])
	sim._spawn(Roster.MONSTERS[0])
	var mo: Dictionary = sim.monsters[0]
	check(mo["motion_phase"] != sim.monsters[1]["motion_phase"], "같은 종도 시작 박자가 다름")
	sim._move_monsters(0.2)
	var normal: float = mo["motion_t"]
	check(normal > 0.0, "이동 중 애니메이션 진행")
	mo["slow_t"] = 2.0
	mo["slow"] = 0.5
	sim._move_monsters(0.2)
	check(is_equal_approx(float(mo["motion_t"]) - normal, normal * 0.5), "둔화 시 보행 속도도 절반")
	mo["stun_t"] = 1.0
	var frozen: float = mo["motion_t"]
	var distance: float = mo["s"]
	sim._move_monsters(0.2)
	check(is_equal_approx(float(mo["motion_t"]), frozen), "마비 중 애니메이션 정지")
	check(is_equal_approx(float(mo["s"]), distance), "마비 중 이동 정지")
	mo["s"] = maxf(0.0, distance - 10.0)
	mo["slow_t"] = 0.0
	mo["stun_t"] = 0.0
	sim._move_monsters(0.2)
	check(float(mo["motion_t"]) > frozen, "밀쳐내기 후 보행 역재생 방지")
	sim._spawn(Roster.MONSTERS[1])
	var fast: Dictionary = sim.monsters[-1]
	sim._move_monsters(0.2)
	check(is_equal_approx(float(fast["motion_t"]), 0.2 * float(fast["spd"])), "쾌속 몬스터는 이동 속도에 맞춰 빠르게 재생")

	# 실제 화면 이벤트를 통해 면역과 희귀도 착탄 분기를 검증한다.
	var screen := BattleScreen.new()
	Run.gain_hero(Roster.UNITS[-1], 9)
	screen.sim.setup(Run, 1, 9102026)
	screen._on_hit(Vector2(200, 200), {"em": 0.0, "src": 0, "n": 0.0})
	check(screen.fx.items.filter(func(it): return it["t"] == "rarity").is_empty(), "면역 대상에는 희귀 착탄 연출 없음")
	screen.fx.clear()
	screen._on_hit(Vector2(200, 200), {"em": 1.0, "src": 0, "n": 20.0})
	check(screen.fx.items.filter(func(it): return it["t"] == "rarity").size() == 1, "희귀 영웅 착탄은 한 항목으로 묶음")
	screen.free()

	if has_arg("--assets"):
		for m in Roster.MONSTERS:
			var clip := Anim.clip(m, "move")
			check(not clip.is_empty(), "%s 이동 클립 로드" % m["id"])
			if clip.is_empty():
				continue
			check(int(clip["n"]) >= 8 and bool(clip["loop"]), "%s 반복 프레임" % m["id"])
			check(Anim.frame_at(clip, float(clip["total"]) / 1000.0) == 0, "%s 루프 시간 경계" % m["id"])
			var meta := Anim._meta(String(m["anim"]))
			if m["id"] in ["flame_dragon", "glacier_dragon", "abyss_leviathan", "rapid_ray"]:
				check(meta["movement"] == "fly", "%s 날개/지느러미 모션" % m["id"])
	finish("몬스터·희귀 이펙트 검사")
