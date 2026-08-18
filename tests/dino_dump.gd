## 공룡 찾기 전용 개발 진입점 — 화면 없는 서버에서 배치를 검사하고 그림으로 뽑는다.
##
## ★ 게임 자신은 커맨드라인을 읽지 않는다. 예전에는 games/dino/scripts/game.gd 가
##   직접 --dump/--selftest 를 읽고 끝에 get_tree().quit() 을 불렀는데,
##   통합 앱에서는 그게 개구리 용사의 촬영 도구(tests/shot.gd)와 인자가 섞여
##   촬영 도중 앱을 죽인다. 진입점을 여기 하나로 분리한다.
##
##   ~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump
##   ~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump --boxes
##   ~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --selftest
##   ~/.local/bin/godot --headless --path . res://tests/dino_dump.tscn -- --dump --pre
##       (--pre 는 미취학 프로필의 난이도로 검사한다)
extends Node


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	# 검증이 아이 기록을 덮지 않게 한다. 예전에는 test_runner 를 돌릴 때마다
	# 저장 파일이 오염됐고, 통합 후에는 공룡 기록까지 같이 덮인다.
	Shell.save_disabled = true
	# ★ 프레임 제한을 푼다. 통합 project.godot 은 개구리 용사에서 온 run/max_fps=60 을
	#   갖고 있는데(폰 배터리용), 공룡 찾기의 자동 플레이는 매 탭마다 한 프레임을
	#   기다리므로 60fps 에 묶이면 몇 배로 느려진다 — 예전 dino 프로젝트에는 이 설정이
	#   없어서 헤드리스가 무제한으로 돌았다. 검증 진입점에서만 푼다.
	Engine.max_fps = 0
	if "--pre" in args:
		Shell.profile()["age_band"] = "pre"
		Shell.profile()["tuning"] = Shell.default_tuning("pre")
		MathGame.pull_settings()

	var packed: PackedScene = load("res://games/dino/dino.tscn")
	var g := packed.instantiate()
	g.set("dev_mode", true)
	add_child(g)
	await get_tree().process_frame

	if "--selftest" in args:
		await g.call("run_selftest")
	else:
		await g.call("run_dump", "--boxes" in args)

	await get_tree().process_frame
	get_tree().quit()
