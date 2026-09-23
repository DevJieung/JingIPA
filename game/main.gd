extends Node2D

## 화면을 갈아 끼우는 곳. 게임의 진행 순서가 여기 한 줄로 보인다:
##   타이틀 → [테마 판] → (카드 뽑기 → 전투 → 상점) 반복 → 끝
##
## 화면들은 .tscn 없이 코드로 만든다. 화면 하나가 파일 하나(.gd)라 옮기고 지우기 쉽고,
## 헤드리스 검사기가 씬 파일 없이 화면을 그대로 세워 볼 수 있다.
##
## ★ **단계가 바뀔 때의 자동 저장은 여기서 건다.** 화면마다 저장을 부르면 언젠가 한 곳을
##   빠뜨린다 — 그러면 "그 화면에서만 안 저장되는" 버그가 된다.
## ★ 다만 **되돌릴 수 없는 것을 얻거나 쓴 순간**은 단계가 안 바뀐다 — 리롤·족보 확정·
##   영웅 자리 바꾸기·상점 구매가 그렇다. 그 자리는 **core/run.gd 안**에 있다
##   (CLAUDE.md 15-4). 여기만 걸었더니 뽑기 화면 전체가 저장 밖이라, 앱을 껐다 켜면
##   공짜 리롤과 골드가 환불되고 홈 버튼을 누르면 영웅이 복제됐다.

var screen: Node2D = null
## 화면 사이 페이드. 0 이면 안 보이고 1 이면 새까맣다.
var _fade: float = 0.0
var _fade_dir: float = 0.0
var _next: Callable = Callable()
var _fade_rect: ColorRect = null
## 테마 판을 이미 보여 준 블록 번호. 열 탄마다 한 번만 뜨게 하는 표시다.
var _theme_shown: int = -1
var menu: MenuOverlay


func _ready() -> void:
	RenderingServer.set_default_clear_color(Look.BG)
	I18n.language_changed.connect(_update_window_title)
	_update_window_title(I18n.locale)
	# ★ 페이드를 이 노드의 _draw() 로 그리면 **안 보인다.**
	#   Godot 의 그리기 순서는 "부모 먼저, 자식이 그 위"라, 자식으로 붙는 화면들이
	#   부모가 그린 검은 막을 덮어 버린다. 그래서 화면 전환이 그냥 0.28초씩 두 번
	#   멈췄다가 뚝 끊기는 것처럼 보였다. CanvasLayer 로 확실히 맨 위에 올린다.
	var cl := CanvasLayer.new()
	cl.layer = 100
	add_child(cl)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# 입력은 통과시킨다 — 전환 중 두 번 눌리는 것은 각 화면이 스스로 막는다.
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_fade_rect)
	show_title()
	var menu_layer := CanvasLayer.new()
	menu_layer.layer = 90
	add_child(menu_layer)
	menu = MenuOverlay.new()
	menu.main = self
	menu_layer.add_child(menu)
	# 화면은 메뉴보다 먼저 입력을 받지 않도록 같은 부모 아래 항상 앞에 둔다.


func _update_window_title(_locale: String) -> void:
	get_window().title = I18n.t(String(ProjectSettings.get_setting("application/config/name")))


func _process(dt: float) -> void:
	if _fade_dir != 0.0:
		_fade = clampf(_fade + _fade_dir * dt * 3.6, 0.0, 1.0)
		if _fade_rect != null:
			_fade_rect.color = Color(0, 0, 0, _fade)
		if _fade_dir > 0.0 and _fade >= 1.0:
			# ★ 화면을 갈아 끼우는 순간 잠금을 푼다. 트윈이 끝나기를 기다리다가
			#   그 트윈이 finished 를 한 번이라도 안 내면 화면이 영영 안 바뀐다.
			if _next.is_valid():
				_next.call()
			_next = Callable()
			_fade_dir = -1.0
		elif _fade_dir < 0.0 and _fade <= 0.0:
			_fade_dir = 0.0


## 페이드가 덮은 순간에 화면을 바꾼다.
func go(f: Callable) -> void:
	if _fade_dir > 0.0:
		return       # 이미 넘어가는 중
	_next = f
	_fade_dir = 1.0
	if is_instance_valid(screen):
		screen.set_process(false)
		screen.set_process_input(false)


func _swap(s: Node2D) -> void:
	if screen != null and is_instance_valid(screen):
		screen.queue_free()
	screen = s
	s.set("main", self)
	# ★ 이름을 지어 준다. 안 지으면 Godot 이 **네이티브** 클래스로 짓는다(@Node2D@42) —
	#   에디터의 「디버거 > 원격」 씬 트리에서 지금 어느 화면의 변수를 보고 있는지
	#   알 수가 없다. 이름으로 노드를 찾는 코드는 이 저장소에 하나도 없으므로 안전하다.
	var sc: Script = s.get_script()
	if sc != null and sc.get_global_name() != "":
		s.name = sc.get_global_name()
	add_child(s)
	move_child(s, 0)
	if s is BattleScreen:
		Sfx.play_music(Sfx.battle_music_id(Run.wave))
	elif s is ThemeScreen:
		Sfx.play_music(Sfx.battle_music_id(Run.wave + 1))
	elif s is DrawScreen:
		Sfx.play_music("ritual")
	else:
		Sfx.play_music("camp")


func screen_modal_open() -> bool:
	if not is_instance_valid(screen):
		return false
	if screen is TitleScreen:
		return screen.collection.opened
	if screen is DrawScreen:
		return screen.state == DrawScreen.REVIVE_REWARD or screen.fusion.active() or screen.hv.info >= 0 or screen.card_choice.opened
	if screen is ShopScreen:
		return screen.fusion.active() or screen.hv.info >= 0
	return false


func _notification(what: int) -> void:
	if menu == null:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if screen is TitleScreen and screen.collection.opened:
			screen.collection.close()
			return
		if screen is DrawScreen and screen.card_choice.opened:
			if not Ads.busy:
				screen.card_choice.close()
			return
		if menu.opened:
			menu.close()
		else:
			menu.open()


# --------------------------------------------------------------------------- #
# 진행 순서
# --------------------------------------------------------------------------- #
func show_title() -> void:
	_swap(TitleScreen.new())


func start_run(seed_value: int = 0) -> void:
	Run.start_run(seed_value)
	_theme_shown = -1
	go(go_draw)


## 하다 만 판을 이어 한다. 타이틀의 「이어하기」가 부른다.
##
## ★ **전투 도중에 저장된 판은 그 탄을 처음부터 다시 튼다**(Run.restore 주석).
##   전투 한복판을 통째로 담는 대신 그렇게 정했다 — 되돌린 판이 조금이라도 어긋나면
##   크리스탈 개수가 안 맞는데, 그건 이 게임에서 제일 못 믿을 어긋남이다.
func resume_run() -> bool:
	if not Run.restore(Save.cur_run):
		Save.clear_run()
		return false
	_theme_shown = Balance.theme_block(maxi(1, Run.wave))
	match Run.phase:
		Run.Phase.OVER:
			go(go_over)
		Run.Phase.BATTLE:
			go(go_battle)
		Run.Phase.SHOP:
			go(go_shop)
		Run.Phase.SWAP:
			# ★ **보상을 이미 받은 뒤로는 절대 안 돌아간다.** 뽑기 화면을 다시 띄우면
			#   「결정!」을 한 번 더 눌러 영웅이 하나 더 생긴다. DrawScreen 이 스스로
			#   편성 판부터 열므로(draw_screen._ready) 편성 판은 그대로 뜬다.
			go(show_draw)
		_:
			go(show_draw)
	return true


## 다음 탄으로 넘어간다. 테마가 바뀌는 자리면 **테마 판을 한 번 끼운다.**
func go_draw() -> void:
	if not Run.running:
		show_title()
		return
	if Run.retry_wave:
		go_battle()
		return
	if Run.wave >= Balance.LAST_WAVE:
		Run.end_run(true)
		go_over()
		return
	var blk := Balance.theme_block(Run.wave + 1)
	if blk != _theme_shown:
		_theme_shown = blk
		_swap(ThemeScreen.new())
		return
	Run.begin_draw()
	Run.autosave()
	_swap(DrawScreen.new())


## 카드를 **다시 뽑지 않고** 뽑기 화면만 세운다. 이어 하기에서만 쓴다 —
## ★ go_draw() 를 쓰면 begin_draw() 가 탄을 하나 더 올리고 카드를 새로 돌려서,
##   이어 할 때마다 탄이 하나씩 건너뛰고 리롤이 공짜로 되살아난다.
func show_draw() -> void:
	if not Run.running:
		show_title()
		return
	if Run.cards.size() != 5 and Run.phase != Run.Phase.SWAP:
		go_draw()
		return
	_swap(DrawScreen.new())


func go_battle() -> void:
	Run.prepare_battle()
	# ★ 이번 탄이 끝나면 상점 진열을 새로 굴린다는 표시. 여기서 비워 두면 상점이
	#   들어올 때 한 번만 굴리게 되어, **이어 하기로 돌아와도 같은 진열**이 뜬다.
	#   (상점에 들어올 때마다 굴리면 앱을 껐다 켤 때마다 진열이 달라져서, 아껴 둔
	#    카드를 사려고 돌아온 사람이 그 카드를 영영 못 본다)
	Run.shop_offer.clear()
	Run.autosave()
	_swap(BattleScreen.new())


func go_shop() -> void:
	if not Run.running:
		go_over()
		return
	Run.phase = Run.Phase.SHOP
	if Run.shop_offer.is_empty():
		Run.roll_shop()
	Run.autosave()
	_swap(ShopScreen.new())


func go_over() -> void:
	_swap(OverScreen.new())
