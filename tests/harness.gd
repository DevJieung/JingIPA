extends Node
class_name Harness

## 검사 스크립트의 공통 뼈대. 세는 것(check) · 판정과 종료(finish) · 저장 보호 ·
## 화면 누르기(tap/press/mouse) · 프레임 기다리기(frames/paint) · 사진(snap) · 인자 읽기.
## 열두 파일이 저마다 베껴 쓰던 것들을 한 곳에 둔다 — 베낀 것은 언젠가 한 곳만 고쳐진다.
##
## ★ 판정 문구는 「판정: 정상」 하나뿐이다. tools/verify.sh 가 그 글자를 **찾아서** 판정한다
##   (Godot 은 printerr 로 실패를 알려도 종료 코드가 0 인 경우가 있다).
## ★ 커맨드라인을 읽는 코드는 tests/ 에만 둔다(CLAUDE.md 19). 여기도 그 안이다.
## ★ ns_check · play_check · poker_check · dmg_check 는 실패만 세는 제 방식(_bad)을 그대로
##   쓴다 — 넷 다 출력이 곧 보고서라, 「몇 건 중 몇 건」보다 「무엇이 틀렸나」가 본체다.

var checks := 0
var failures := 0


## 조건 하나를 센다. 틀리면 「!! 」로 시작하는 한 줄을 남긴다.
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("!! " + label)


## 마무리 — 몇 건 중 몇 건이 틀렸는지 적고 판정한 뒤 끝낸다.
func finish(title: String) -> void:
	print("%s %d건 · 실패 %d건" % [title, checks, failures])
	print("판정: 정상" if failures == 0 else "판정: 실패")
	get_tree().quit(0 if failures == 0 else 1)


## POCKER_NO_SAVE=1 없이 돌면 검사가 만든 판이 「내 기록」이 된다. 그러면 여기서 세운다.
## 통과하면 참, 아니면 `code` 로 끝내고 거짓.
func require_no_save(code: int = 1) -> bool:
	if OS.get_environment("POCKER_NO_SAVE") == "1":
		return true
	printerr("POCKER_NO_SAVE=1로 실행하세요. 실제 기록을 보호합니다.")
	get_tree().quit(code)
	return false


# --------------------------------------------------------------------------- #
# 프레임과 사진
# --------------------------------------------------------------------------- #
func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## 화면을 한 번 그리게 하고 버튼 자리가 등록될 때까지 기다린다.
func paint(screen: CanvasItem) -> void:
	screen.queue_redraw()
	await frames(2)


## 지금 화면을 PNG 로 남기고 그 그림을 돌려준다.
func snap(path: String) -> Image:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	return img


## `main.screen` 이 그 파일(확장자 없는 이름)의 화면이 될 때까지 기다린다.
## `limit` 프레임 안에 안 오면 거짓.
func wait_screen(main: Node, cls: String, limit: int) -> bool:
	for i in range(limit):
		await get_tree().process_frame
		var s = main.screen
		if s != null and s.get_script() != null \
				and String(s.get_script().resource_path).get_file().get_basename() == cls:
			return true
	return false


# --------------------------------------------------------------------------- #
# 손가락 — 화면이 그리면서 등록한 바로 그 자리를 누른다(CLAUDE.md 7)
# --------------------------------------------------------------------------- #
## 화면에 왼쪽 단추 하나를 넣는다.
static func mouse(screen: Node, at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = at
	e.pressed = pressed
	screen._input(e)


## 그 화면이 등록한 id 의 자리. 켜진 것이 있으면 그것을, 없으면 첫 번째 것을, 아예 없으면 {}.
static func zone_of(screen: Node, id: String) -> Dictionary:
	var ui: Ui = screen.get("ui") if screen != null else null
	if ui == null:
		return {}
	var first: Dictionary = {}
	for z in ui.zones:
		if String(z["id"]) != id:
			continue
		if bool(z["on"]):
			return z
		if first.is_empty():
			first = z
	return first


## 그 자리를 **눌렀다 뗀다.** 없거나 꺼져 있으면 거짓.
## ★ 전당 칸처럼 끌어서 굴리는 자리는 **떼는 순간**에 고르기가 정해진다(HeroView.release).
static func tap(screen: Node, id: String) -> bool:
	var z := zone_of(screen, id)
	if z.is_empty() or not bool(z["on"]):
		return false
	var at: Vector2 = Rect2(z["rect"]).get_center()
	mouse(screen, at, true)
	mouse(screen, at, false)
	return true


## 그 자리를 **누르기만** 한다(떼지 않는다). 단추는 누르는 순간 처리되므로 이것으로 충분하다.
static func press(screen: Node, id: String) -> bool:
	var z := zone_of(screen, id)
	if z.is_empty() or not bool(z["on"]):
		return false
	mouse(screen, Rect2(z["rect"]).get_center(), true)
	return true


# --------------------------------------------------------------------------- #
# 인자 — `godot ... res://tests/x.tscn -- --runs 12 --verbose`
# --------------------------------------------------------------------------- #
static func has_arg(k: String) -> bool:
	return k in OS.get_cmdline_user_args()


## `k` 바로 뒤의 값. 없으면 `d`.
static func arg(k: String, d: String) -> String:
	var a := OS.get_cmdline_user_args()
	for i in range(a.size() - 1):
		if a[i] == k:
			return a[i + 1]
	return d


static func arg_int(k: String, d: int) -> int:
	var s := arg(k, "")
	return int(s) if s != "" else d


static func arg_float(k: String, d: float) -> float:
	var s := arg(k, "")
	return float(s) if s != "" else d
