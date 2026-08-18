## 「섬 한 바퀴」 검사 진입점.
##
## 실제 검사는 tests/journey_runner.gd 가 한다.
## ★ 러너를 current_scene 밑에 두면 첫 화면 전환에서 같이 지워진다.
##   오토로드(Shell) 밑에 붙이면 씬이 아무리 갈려도 살아남는다.
##
##   ~/.local/bin/godot --headless --path . res://tests/journey_check.tscn
extends Node


func _ready() -> void:
	var script: GDScript = load("res://tests/journey_runner.gd")
	var runner: Node = script.new()
	runner.name = "JourneyRunner"
	Shell.add_child(runner)
