## 앱 진입점. 저장 이관이 끝났는지 확인하고 곧장 허브로 넘긴다.
##
## ★ 여기서 시간을 끌지 않는다. 아이는 앱을 열고 3초 안에 놀이가 시작돼야 한다.
##   (예전 개구리 용사는 스플래시 -> 타이틀 -> 지도 -> 탄으로 4단계였다.)
extends Control


func _ready() -> void:
	Shell.begin_session()
	# Shell._ready() 가 이미 저장을 읽거나 이관을 끝냈다. 한 프레임만 쉬고 넘어간다.
	await get_tree().process_frame
	Router.goto_hub()


func _draw() -> void:
	# 부팅 한 순간만 보이는 바탕. 허브와 같은 색이라 이어져 보인다.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.976, 0.945, 0.882))
