extends Node

## 앱을 처음 켤 때만 지나가는 길(F8, 2026-10-19):
##   MindMorph 로고(StartupSplash: 페이드 인 → 유지 → 페이드 아웃)
##   → Stellar Defense 그림과 그 밑의 로딩 바(StartupLoading) → 타이틀.
## 로고가 시작되는 순간 실제 로딩(스레드 로드)을 건다. 로딩 화면이 그 진행, Main 만들기,
## 타이틀 배경(3D) 만들기, 셰이더 데우기를 덮개 밑에서 끝낸 뒤에 걷히고, 그때부터 Main 이
## 입력을 받는다. main.gd 는 preload 하지 않는다 — 부팅 화면(초록) 동안이 아니라 로딩 바
## 밑에서 읽힌다. 타이틀 재진입은 Main 안에서 처리한다.
const Splash := preload("res://game/startup_splash.gd")
const Loading := preload("res://game/startup_loading.gd")

var splash: CanvasLayer
var loading: CanvasLayer
var main: Node2D
## ★ The engine quits the app on the Android back button by default
##   (application/config/quit_on_go_back). While the logo and the loading cover are up the
##   button must do nothing at all, so that is switched off until the title is revealed and
##   then put back as it was (Main ignores the button under the cover as well).
var _quit_on_back := true


func _ready() -> void:
	_quit_on_back = get_tree().quit_on_go_back
	get_tree().quit_on_go_back = false
	splash = Splash.new()
	loading = Loading.new()
	loading.host = self
	splash.finished.connect(_enter_loading, CONNECT_ONE_SHOT)
	add_child(splash)
	# The real loading starts with the logo; nothing waits on it until the loading cover.
	loading.request()


func _enter_loading() -> void:
	# Same frame, same green: the loading cover replaces the logo's blank end frame, and the
	# window keeps the full-screen aspect until the cover gives the game its own back.
	loading.restore_aspect = splash.original_aspect()
	splash.hand_over = true
	loading.finished.connect(_enter_game, CONNECT_ONE_SHOT)
	add_child(loading)
	remove_child(splash)
	splash.queue_free()
	splash = null


func _enter_game() -> void:
	main = loading.main
	remove_child(loading)
	loading.queue_free()
	loading = null
	get_tree().quit_on_go_back = _quit_on_back


func _exit_tree() -> void:
	get_tree().quit_on_go_back = _quit_on_back
	# Quit during the logo: the cover never entered the tree, so free it here.
	if loading != null and not loading.is_inside_tree():
		loading.collect()
		loading.free()
		loading = null
