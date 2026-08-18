## tests/ns_check.gd 를 돌려 결과를 찍고 종료한다.
extends Node


func _ready() -> void:
	Shell.save_disabled = true
	var checker = load("res://tests/ns_check.gd").new()
	add_child(checker)
	var problems: Array = checker.run()
	if problems.is_empty():
		print("  전역 이름 규칙: 이상 없음")
	else:
		for p in problems:
			printerr("!! %s" % p)
		printerr("!! 전역 이름 규칙 %d건 위반" % problems.size())
	await get_tree().process_frame
	get_tree().quit(0 if problems.is_empty() else 1)
