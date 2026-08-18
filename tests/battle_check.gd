## 개구리 용사 — **시연을 켠 채로** 한 탄을 끝까지 플레이해 본다.
##
## ★ tests/test_runner.gd 는 이 경로를 안 본다. 빠르게 돌리려고 skip_demo 를 켜고
##   전투를 돌기 때문이다(그 파일의 [5] 항목). 그래서 블록 시연이 중간에 멈추는
##   종류의 사고는 지금까지 어떤 검사에도 안 걸렸다 — 아이 화면에서는 그대로 멈춘다.
##
##   ~/.local/bin/godot --headless --path . res://tests/battle_check.tscn
##   ~/.local/bin/godot --headless --path . res://tests/battle_check.tscn -- --tiers 0,3,8,12
extends Node

## 기본으로 볼 탄들. 표시 방식이 바뀌는 지점(5탄=index 4, 13탄=index 12)과
## 빈칸 문제가 나오는 탄을 반드시 포함한다.
var tiers: Array[int] = [0, 3, 4, 8, 11, 12]

var _i := 0
var _battle: Node
var _t0 := 0
var _last := ""
var _stuck := 0.0
var _fail := 0


func _ready() -> void:
	Shell.save_disabled = true
	Engine.max_fps = 0
	var args := OS.get_cmdline_user_args()
	for a in args.size():
		if String(args[a]) == "--tiers" and a + 1 < args.size():
			tiers = []
			for part in String(args[a + 1]).split(","):
				tiers.append(int(part))
	var t := Shell.tuning()
	t["fast_animation"] = true
	t["skip_demo"] = false        # ★ 이 검사의 전부
	t["session_limit"] = 0
	MathGame.pull_settings()
	_next_tier()


func _next_tier() -> void:
	if _battle != null and is_instance_valid(_battle):
		_battle.queue_free()
		_battle = null
	if _i >= tiers.size():
		print("   판정: %s" % ("정상" if _fail == 0 else "이상"))
		get_tree().quit(1 if _fail > 0 else 0)
		return
	var tier: int = clampi(tiers[_i], 0, Curriculum.tier_count() - 1)
	Router.pending_tier = tier
	Router.pending_endless = false
	Router.journey_stage = 0
	_t0 = Time.get_ticks_msec()
	_last = ""
	_stuck = 0.0
	_battle = (load("res://games/math/game/battle.tscn") as PackedScene).instantiate()
	add_child(_battle)


func _process(delta: float) -> void:
	if _battle == null or not is_instance_valid(_battle):
		return
	var b := _battle
	var token := "%s/%s/%s" % [b.get("_index"), b.get("_attempts"), b.get("_finished")]
	if token != _last:
		_last = token
		_stuck = 0.0
	else:
		_stuck += delta

	if bool(b.get("_finished")):
		print("   %d탄: 문제 %s개 완주 %.1f초" % [int(tiers[_i]) + 1, b.get("_total"),
				float(Time.get_ticks_msec() - _t0) / 1000.0])
		_i += 1
		_next_tier()
		return

	if _stuck > 45.0:
		var pr: Object = b.get("_problem")
		var st: Object = b.get("_stage")
		print("!! %d탄 %s번째 문제에서 시연이 멈췄습니다 — form=%s op=%s 무대running=%s"
				% [int(tiers[_i]) + 1, b.get("_index"),
				   pr.get("form") if pr != null else "?",
				   pr.get("op") if pr != null else "?",
				   st.get("_running") if st != null else "?"])
		_fail += 1
		_i += 1
		_next_tier()
		return

	if bool(b.get("_busy")):
		return
	var nb: Object = b.get("_next_btn")
	if nb != null and bool(nb.get("visible")):
		b.call("_on_next_pressed")
		return
	var p: Object = b.get("_problem")
	if p != null:
		b.call("_on_answered", int(p.get("answer")))
