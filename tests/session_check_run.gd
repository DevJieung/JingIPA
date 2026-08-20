## 세션 상한 검사 진입점.
##
## ★ 검사기를 current_scene 밑에 두면 첫 화면 전환에서 같이 지워진다.
##   오토로드(Shell) 밑에 붙이면 씬이 아무리 갈려도 살아남는다 (journey_check 와 같은 규약).
extends Node


func _ready() -> void:
	var script: GDScript = load("res://tests/session_check.gd")
	var runner: Node = script.new()
	runner.name = "SessionCheck"
	Shell.add_child(runner)
