## 전역 이름(class_name) 규칙 검사.
##
## 게임이 하나였을 때는 아무 이름이나 써도 됐다. 게임이 늘면 Palette / Art / Fonts /
## Layout 같은 흔한 이름이 반드시 부딪히고, Godot 은 그때 **경고 없이** 하나를 버린다.
##
## 규칙 넷:
##   1. 접두사 없는 전역 class_name 은 core/ 와 shell/ 만 쓸 수 있다.
##   2. games/<id>/ 의 class_name 은 그 게임 접두사로 시작한다 (dino -> Dino*, frog -> Frog*).
##   3. 접두사 없는 이름을 쓰고 싶으면 core/ 로 승격하라 — 승격이 곧 개명 면제다.
##   4. 아래 유예 목록은 병합 시점에 **동결**했다. 늘리려면 이 파일을 고쳐야 하고,
##      그게 곧 리뷰 지점이다.
extends Node

## 병합 시점의 유예 목록. ★ 여기에 이름을 더하지 마라 —
## 더하고 싶으면 그 스크립트를 core/ 로 옮기는 것이 옳은 해법이다.
const GRANDFATHERED := [
	# 개구리 용사에서 왔지만 사실상 공용인 것들 (10단계에서 core/ 로 승격 예정)
	"Palette", "DrawUtil", "Fonts", "Glyphs", "Layout", "Loc",
	"BigButton", "ResultPanel", "Fx", "Art",
	# 개구리 용사 전용인데 접두사가 없는 것들
	"Curriculum", "Problem", "ProblemGen", "AnswerPad", "AnswerButton",
	"BlockStage", "BlockUnit", "Hud", "ProblemCard",
	# 공룡 찾기 전용인데 접두사가 없는 것들
	"Rooms", "RoomGen", "RoomBg", "Prop", "Sfx", "Confetti",
]

## 게임 id -> class_name 접두사.
## ★ 새 게임을 넣고 여기를 안 채우면 id 를 그대로 대문자화한 이름을 요구하게 되어
##   ns_check 가 빨간불이 된다. 게임을 등록할 때 같이 채워라.
const PREFIX := {"dino": "Dino", "math": "Math", "kanoodle": "Nood"}


func run() -> Array:
	var problems: Array = []
	var seen := {}
	var files: Array[String] = []
	_collect("res://games", files)
	_collect("res://shell", files)
	_collect("res://core", files)

	for path in files:
		var name := _class_name_of(path)
		if name.is_empty():
			continue
		if seen.has(name):
			problems.append("이름 충돌: %s 가 %s 와 %s 두 곳에 있습니다" % [name, seen[name], path])
			continue
		seen[name] = path
		if GRANDFATHERED.has(name):
			continue
		if path.begins_with("res://core/") or path.begins_with("res://shell/"):
			continue
		var parts := path.trim_prefix("res://games/").split("/")
		if parts.size() < 2:
			continue
		var game := String(parts[0])
		var want := String(PREFIX.get(game, game.capitalize()))
		if not name.begins_with(want):
			problems.append("%s: class_name %s 는 %s 로 시작해야 합니다 (또는 core/ 로 승격)"
					% [path, name, want])
	return problems


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	while true:
		var f := d.get_next()
		if f.is_empty():
			break
		if f.begins_with("."):
			continue
		var full := dir_path.path_join(f)
		if d.current_is_dir():
			_collect(full, out)
		elif f.ends_with(".gd"):
			out.append(full)
	d.list_dir_end()


func _class_name_of(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("class_name "):
			f.close()
			return line.substr(11).split(" ")[0].strip_edges()
		# class_name 은 파일 맨 앞에만 올 수 있다. 함수가 시작되면 더 볼 것이 없다.
		if line.begins_with("func "):
			break
	f.close()
	return ""
