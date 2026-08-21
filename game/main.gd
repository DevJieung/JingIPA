extends Node2D

## 화면을 갈아 끼우는 곳. 게임의 진행 순서가 여기 한 줄로 보인다:
##   타이틀 → (카드 뽑기 → 전투 → 상점) 반복 → 끝
##
## 화면들은 .tscn 없이 코드로 만든다. 화면 하나가 파일 하나(.gd)라 옮기고 지우기 쉽고,
## 헤드리스 검사기가 씬 파일 없이 화면을 그대로 세워 볼 수 있다.

const SCREEN := Rect2(0, 0, 1280, 800)

var screen: Node2D = null
## 화면 사이 페이드. 0 이면 안 보이고 1 이면 새까맣다.
var _fade: float = 0.0
var _fade_dir: float = 0.0
var _next: Callable = Callable()


func _ready() -> void:
	RenderingServer.set_default_clear_color(Look.BG)
	show_title()


func _process(dt: float) -> void:
	if _fade_dir != 0.0:
		_fade = clampf(_fade + _fade_dir * dt * 3.6, 0.0, 1.0)
		queue_redraw()
		if _fade_dir > 0.0 and _fade >= 1.0:
			# ★ 화면을 갈아 끼우는 순간 잠금을 푼다. 트윈이 끝나기를 기다리다가
			#   그 트윈이 finished 를 한 번이라도 안 내면 화면이 영영 안 바뀐다.
			if _next.is_valid():
				_next.call()
			_next = Callable()
			_fade_dir = -1.0
		elif _fade_dir < 0.0 and _fade <= 0.0:
			_fade_dir = 0.0


func _draw() -> void:
	if _fade > 0.0:
		draw_rect(SCREEN, Color(0, 0, 0, _fade))


## 페이드가 덮은 순간에 화면을 바꾼다.
func go(f: Callable) -> void:
	if _fade_dir > 0.0:
		return       # 이미 넘어가는 중
	_next = f
	_fade_dir = 1.0


func _swap(s: Node2D) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	s.set("main", self)
	add_child(s)
	move_child(s, 0)   # 페이드(자기 _draw)가 항상 맨 위에 오게


# --------------------------------------------------------------------------- #
# 진행 순서
# --------------------------------------------------------------------------- #
func show_title() -> void:
	_swap(TitleScreen.new())


func start_run(seed_value: int = 0) -> void:
	Run.start_run(seed_value)
	go(go_draw)


func go_draw() -> void:
	if not Run.running:
		show_title()
		return
	if Run.wave >= Balance.LAST_WAVE:
		Run.end_run(true)
		_swap(OverScreen.new())
		return
	Run.begin_draw()
	_swap(DrawScreen.new())


func go_battle() -> void:
	_swap(BattleScreen.new())


func go_shop() -> void:
	if not Run.running:
		_swap(OverScreen.new())
		return
	_swap(ShopScreen.new())


func go_over() -> void:
	_swap(OverScreen.new())
