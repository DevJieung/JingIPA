extends Node

## 앱 시작에만 로고를 재생한다. 타이틀 재진입은 Main 안에서 처리한다.
const Splash := preload("res://game/startup_splash.gd")
const Main := preload("res://game/main.gd")

var splash: CanvasLayer
var main: Node2D


func _ready() -> void:
	splash = Splash.new()
	splash.finished.connect(_enter_game, CONNECT_ONE_SHOT)
	add_child(splash)


func _enter_game() -> void:
	# 로고의 마지막 단색 화면까지 끝난 후에만 타이틀과 입력을 활성화한다.
	# splash의 종료 처리(화면 비율 복원)가 Main의 화면 초기화보다 먼저다.
	remove_child(splash)
	splash.queue_free()
	splash = null
	main = Main.new()
	main.name = "Main"
	add_child(main)
