extends Node2D

## 화면을 갈아 끼우는 곳. 게임의 진행 순서가 여기 한 줄로 보인다:
##   타이틀 → 1탄 전장 카드(무작위 전장) → 첫 의식 → 탄마다 보스 → 다음 전장 … → 최종 보스 → 끝
##
## 화면들은 .tscn 없이 코드로 만든다. 화면 하나가 파일 하나(.gd)라 옮기고 지우기 쉽고,
## 헤드리스 검사기가 씬 파일 없이 화면을 그대로 세워 볼 수 있다.
##
## ★ **단계가 바뀔 때의 자동 저장은 여기서 건다.** 화면마다 저장을 부르면 언젠가 한 곳을
##   빠뜨린다 — 그러면 "그 화면에서만 안 저장되는" 버그가 된다.
## ★ 다만 **되돌릴 수 없는 것을 얻거나 쓴 순간**은 단계가 안 바뀐다 — 다시 돌리기·의식 확정·
##   영웅 자리 바꾸기·상점 구매가 그렇다. 그 자리는 **core/run.gd 안**에 있다
##   (CLAUDE.md 15-4). 여기만 걸었더니 뽑기 화면 전체가 저장 밖이라, 앱을 껐다 켜면
##   공짜 다시 돌리기와 골드가 환불되고 홈 버튼을 누르면 영웅이 복제됐다.

var screen: Node2D = null
## 화면 사이 페이드. 0 이면 안 보이고 1 이면 새까맣다.
var _fade: float = 0.0
var _fade_dir: float = 0.0
var _next: Callable = Callable()
var _fade_rect: ColorRect = null
## 테마 판을 이미 보여 준 블록 번호. 열 탄마다 한 번만 뜨게 하는 표시다.
var _theme_shown: int = -1
var menu: MenuOverlay
## The title's live arena field (F7, 2026-10-19). Main keeps ONE ArenaView for the whole
## session — its SubViewport is Main's child — instead of every TitleScreen building a new 3D
## world and render target in its first draw. StellarBackdrop.draw() finds it through the
## screen's `main`. It renders only while a screen that draws it is up (_uses_backdrop);
## under the arena it keeps its last picture, so a battle never renders two 3D worlds.
## Null until first asked for (backdrop_view()).
var backdrop: ArenaView = null
## False while the cold-start loading cover (game/startup_loading.gd) still hides this Main
## (F8): the title is built underneath, but input, the Android back button, the title music
## and the frame budget wait for uncover() / reveal(). game/startup.gd sets it before
## add_child; tests and tools that build Main directly keep true and get the title at once.
var interactive := true
var _waiting_music := ""
## Battery saver (O8a/M13, 2026-10-19): the engine's frame cap follows what is on screen. A
## live battle runs at the player's setting (Save.fps: 30 phone default, 60 desktop default);
## every screen where nothing fights — title, menus, cards and other modals, the shop,
## results — runs at IDLE_FPS. Headless runs and tests (STELLARDEFENSE_NO_SAVE=1) are never
## capped (the project's run/max_fps stays) so the checks keep their speed. Polled every
## frame in _process, so no screen has to remember to call it; set_fps() applies at once.
const IDLE_FPS := 30
var _budget_state := -1


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
	# Under the boot loading cover the loader asks for the backdrop and the title itself,
	# one step per frame, so its bar follows the work (game/startup_loading.gd).
	if interactive:
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
	refresh_render_budget()
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
	if is_instance_valid(screen):
		remove_child(screen)
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
	if backdrop != null:
		backdrop.set_live(_uses_backdrop(s))
	if s is ArenaScreen:
		_screen_music("camp" if Arena.theme_index < 0 else "ritual" if Arena.modal in ["rite", "box"] else "theme_" + String(Arena.theme_for(1)["id"]))
	elif s is BattleScreen:
		_screen_music(Sfx.battle_music_id(Run.wave))
	elif s is ThemeScreen:
		_screen_music(Sfx.battle_music_id(Run.wave + 1))
	elif s is DrawScreen:
		_screen_music("ritual")
	else:
		_screen_music("camp")


## A screen's music starts at once, except under the boot cover: then when it lifts.
func _screen_music(id: String) -> void:
	if interactive:
		Sfx.play_music(id)
	else:
		_waiting_music = id


## The persistent title backdrop, created on first use (the boot loader asks for it under
## its cover; screens built without the boot get it from their first StellarBackdrop.draw).
func backdrop_view() -> ArenaView:
	if backdrop == null:
		backdrop = ArenaView.new()
		backdrop.live = not is_instance_valid(screen) or _uses_backdrop(screen)
		backdrop.set_pace(BACKDROP_PACE)
		backdrop.attach(self, Look.SCREEN)
	return backdrop


## The title backdrop renders one frame in this many while its screen is bare (M13): about
## 10 fps under the 30 fps idle cap — the water and the wind still move, at a third of the GPU
## work. Under a sheet or the menu it is frozen; under the arena it is off (_swap).
const BACKDROP_PACE := 3


## Every screen except the arena draws the title backdrop: the title and the legacy wave
## screens (draw, shop, battle, theme, over) through StellarBackdrop / Look.camp_backdrop /
## Scenery.draw_backdrop. The arena renders its own world (ArenaScreen.view_3d).
func _uses_backdrop(s: Node) -> bool:
	return not s is ArenaScreen


# --------------------------------------------------------------------------- #
# 프레임 예산 (O8a) · 덮개 (F8)
# --------------------------------------------------------------------------- #
## Whether a battle is actually running on screen: the same condition under which
## ArenaScreen steps its simulator (no modal, no menu, no shop), and no transition.
func battle_live() -> bool:
	if not is_instance_valid(screen) or _fade_dir != 0.0 or (menu != null and menu.opened):
		return false
	if screen is ArenaScreen:
		return Arena.running and Arena.sim != null and Arena.modal.is_empty() and not screen.store.opened
	if screen is BattleScreen:
		return Run.running and not screen_modal_open()
	return false


## The frame cap for a state: the player's battle setting, or IDLE_FPS.
func frame_cap(live_battle: bool) -> int:
	return Save.fps if live_battle else IDLE_FPS


## Whether caps are applied at all: never headless, never under tests.
static func budget_enabled() -> bool:
	return DisplayServer.get_name() != "headless" and OS.get_environment("STELLARDEFENSE_NO_SAVE") != "1"


## Apply the cap for what is on screen now. Polled each frame; `force` re-applies after the
## setting itself changed. Nothing happens under the boot cover (loading runs uncapped).
func refresh_render_budget(force: bool = false) -> void:
	if not interactive:
		return
	var state := 1 if battle_live() else 0
	if state == _budget_state and not force:
		return
	_budget_state = state
	if budget_enabled():
		Engine.max_fps = frame_cap(state == 1)


## The menu's 30 / 60 toggle: stores Save.fps and applies it at once.
func set_fps(v: int) -> void:
	Save.set_fps(v)
	refresh_render_budget(true)


## The boot cover starts to lift: the title music begins with the picture.
func uncover() -> void:
	if not _waiting_music.is_empty():
		var id := _waiting_music
		_waiting_music = ""
		Sfx.play_music(id)


## The boot cover is gone: from now on this Main takes input and the frame budget.
func reveal() -> void:
	uncover()
	interactive = true
	refresh_render_budget(true)


func screen_modal_open() -> bool:
	if not is_instance_valid(screen):
		return false
	if screen is ArenaScreen:
		# The aim and the pick's flourish also keep the menu out: Esc and back reach them first.
		return not Arena.modal.is_empty() or screen.store.opened or screen.overlay_open()
	if screen is TitleScreen:
		return screen.overlay_open()
	if screen is DrawScreen:
		return screen.fusion.active() or screen.hv.info >= 0
	if screen is ShopScreen:
		return screen.fusion.active() or screen.hv.info >= 0
	if screen is BattleScreen:
		return screen.sim.support_pending or not screen.support_result.is_empty()
	return false


func _notification(what: int) -> void:
	# Under the boot loading cover the back button does nothing (F8).
	if menu == null or not interactive:
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# The battlefield's own layers first: the starburst's aim, the constellation map
		# (zoomed → overview → closed), the jewel box's ceremony (ArenaScreen.back).
		if screen is ArenaScreen and screen.back():
			return
		if (screen is ArenaScreen or screen is TitleScreen) and screen.store.opened:
			screen.store.close()
			return
		if screen is ArenaScreen and Arena.modal in ["talent", "bench"]:
			# A level-up offer refuses to close: one of the three stars has to be picked.
			if Arena.close_modal():
				return
		# The title's sheets close from the top: shop, squad, stage select, collection.
		if screen is TitleScreen and screen.close_overlay():
			return
		if menu.opened:
			menu.close()
		else:
			menu.open()


# --------------------------------------------------------------------------- #
# 진행 순서
# --------------------------------------------------------------------------- #
func show_title() -> void:
	# ★ F7: the title always shows the default road layout. The arena chooses its own again
	#   whenever a run starts or resumes (ArenaRun._open_stage / restore), so the last
	#   battlefield's roads no longer leak into the title, and the persistent backdrop keeps
	#   the map it was built with (same key: no rebuild on return).
	ArenaGeometry.use_layout(ArenaGeometry.DEFAULT_LAYOUT)
	_swap(TitleScreen.new())


## Start a ladder stage: `stage_no`, or the next unlocked one (Save.stage_unlocked) when 0.
## The title's 「시작」 passes Save.stage_unlocked, the stage select the stage it picked.
func start_run(seed_value: int = 0, stage_no: int = 0) -> void:
	Run.running = false
	Arena.running = false
	Arena.start_run(seed_value, stage_no)
	go(show_arena)


## The result card's 「다음 STAGE」 (LB1 may use it): the next stage behind the usual black fade,
## on a fresh arena screen. False while the stage is still running or the next one is locked.
func next_stage() -> bool:
	if Arena.running or Arena.hell or not Arena.can_play(Arena.stage + 1):
		return false
	start_run(0, Arena.stage + 1)
	return true


## The result card's 「재도전」: the same stage again (or the same Hellbound squad) from the start.
func retry_stage() -> bool:
	if Arena.running:
		return false
	if Arena.hell:
		var squad: Variant = Arena.get("squad")
		return start_hellbound(squad if squad is Array else Save.hell_squad)
	start_run(0, Arena.stage)
	return true


## Hellbound (DLC): endless waves with the heroes picked on the squad screen (game/squad_view.gd).
## When the run refuses the squad (Arena.start_hellbound: no DLC, a hero not in the codex, too
## many) nothing moves and the answer is false.
func start_hellbound(ids: Array, seed_value: int = 0) -> bool:
	if not hellbound_ready() or ids.is_empty():
		return false
	Run.running = false
	Arena.running = false
	if not Arena.start_hellbound(ids, seed_value):
		return false
	go(show_arena)
	return true


## Whether a Hellbound run can start now: the DLC and a codex to pick from (the squad screen's
## Start asks).
func hellbound_ready() -> bool:
	return Arena.can_hellbound()

func show_arena() -> void:
	_swap(ArenaScreen.new())

func active_run() -> Node:
	return Arena if screen is ArenaScreen else Run


## 하다 만 판을 이어 한다. 타이틀의 「이어하기」가 부른다.
##
## ★ **전투 도중에 저장된 판은 그 탄을 처음부터 다시 튼다**(Run.restore 주석).
##   전투 한복판을 통째로 담는 대신 그렇게 정했다 — 되돌린 판이 조금이라도 어긋나면
##   크리스탈 개수가 안 맞는데, 그건 이 게임에서 제일 못 믿을 어긋남이다.
func resume_run() -> bool:
	if Save.cur_run.get("mode") == "arena":
		if not Arena.restore(Save.cur_run):
			Save.clear_run()
			return false
		Run.running = false
		go(show_arena)
		return true
	if not Run.restore(Save.cur_run):
		Save.clear_run()
		return false
	Arena.running = false
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


## 별을 **다시 돌리지 않고** 의식 화면만 세운다. 이어 하기에서만 쓴다 —
## ★ go_draw() 를 쓰면 begin_draw() 가 탄을 하나 더 올리고 별을 새로 돌려서,
##   이어 할 때마다 탄이 하나씩 건너뛰고 무료 다시 돌리기가 공짜로 되살아난다.
func show_draw() -> void:
	if not Run.running:
		show_title()
		return
	if not Rite.valid(Run.orbit) and Run.phase != Run.Phase.SWAP:
		go_draw()
		return
	_swap(DrawScreen.new())


func go_battle() -> void:
	Run.prepare_battle()
	# ★ 이번 탄이 끝나면 상점 진열을 새로 굴린다는 표시. 여기서 비워 두면 상점이
	#   들어올 때 한 번만 굴리게 되어, **이어 하기로 돌아와도 같은 진열**이 뜬다.
	#   (상점에 들어올 때마다 굴리면 앱을 껐다 켤 때마다 진열이 달라져서, 아껴 둔
	#    패시브를 사려고 돌아온 사람이 그 패시브를 영영 못 본다)
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
