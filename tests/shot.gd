## 화면을 PNG 로 찍어 두는 개발용 도구 (빌드에 포함되지 않는다 — tests/* 는 익스포트 제외).
##
## 이 머신은 화면이 없어서 눈으로 확인할 방법이 웹 빌드뿐이었다.
## 가상 프레임버퍼(Xvfb) 위에서 이 씬을 돌리면 화면을 그대로 파일로 받을 수 있다.
##   python3 tools/screenshot.py hub:0 map:0 battle:2
extends Node

var _out := "user://shots"
var _shots: Array = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--out="):
			_out = a.substr(6)
		else:
			_shots.append(a)
	if _shots.is_empty():
		_shots = ["map:0"]
	DirAccess.make_dir_recursive_absolute(_out)
	# ★ 촬영이 아이 기록을 덮지 않게 한다. 아래에서 stars 를 잠깐 조작한다.
	Shell.save_disabled = true
	# 진행도를 잠깐 조작하므로(잠긴 탄만 있으면 지도가 밋밋하다) 원래 값을 되돌려 둔다.
	# MathGame 은 창이 닫힐 때 저장하므로, 안 되돌리면 개발자의 저장 파일이 덮어써진다.
	var saved := MathGame.stars.duplicate()
	await _run()
	MathGame.stars = saved
	get_tree().quit()


func _run() -> void:
	for spec in _shots:
		var parts := String(spec).split(":")
		var kind := parts[0]
		var arg := int(parts[1]) if parts.size() > 1 else 0
		var scene := ""
		match kind:
			"kanoodle":
				scene = "res://games/kanoodle/kanoodle.tscn"
				# arg 를 탄으로 쓴다 — 쉬운 판만 찍으면 "아직 차례가 아닌 조각"이
				# 옅게 나오는 모습이나 큰 격자를 눈으로 확인할 수가 없다.
				Shell.profile()["kanoodle"] = {
					"best_stage": maxi(1, arg), "skill": 0, "cleared": 0,
				}
			"tiers", "map":
				scene = Router.TIERS
				MathGame.stars = {"0": 3, "1": 2, "2": 1, "3": 3, "4": 1}
			"hub":
				scene = Router.HUB
				# 허브가 텅 비면 배치를 못 본다 — 도감을 조금 채워서 찍는다.
				Shell.dex = {}
				for i in mini(14, DinoSpecies.count()):
					Shell.dex[DinoSpecies.id_of(i)] = {
						"first_by": "p_1", "first_at": 0,
						"count": Shell.FAMILY_MEETS if i < 9 else 1,
					}
				MathGame.stars = {"0": 3, "1": 2, "2": 1}
			"title":
				scene = Router.TITLE
			"battle":
				scene = "res://games/math/game/battle.tscn"
				Router.pending_tier = arg
				Router.pending_endless = false
			_:
				continue
		var packed: PackedScene = load(scene)
		var inst := packed.instantiate()
		add_child(inst)
		# ★ 이 씬의 부모는 Control 이 아니라 그냥 Node 라, 앵커만으로는 크기가 안 잡힌다.
		#   크기가 0 이면 화면이 통째로 비어서 "게임이 안 그려진다"로 오해하게 된다.
		if inst is Control:
			(inst as Control).size = get_viewport().get_visible_rect().size
		if inst.has_method("_layout"):
			inst.call("_layout")
		for i in 40:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var path := "%s/%s_%d.png" % [_out, kind, arg]
		img.save_png(path)
		print("찍음: %s (%dx%d)" % [path, img.get_width(), img.get_height()])
		inst.queue_free()
		await get_tree().process_frame
