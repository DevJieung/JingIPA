extends Node2D

## 공룡을 찾아라!  —  집 안 여러 방에 숨은 공룡을 찾는 게임.

const W := 1280.0
const H := 720.0

var rooms: Array = []          ## 손으로 꾸민 방 6개 (1~6탄)
var stage := 1                 ## 7탄부터는 room_gen.gd 가 새 방을 만들어 준다
var room: Dictionary = {}
var dinos: Array[Dino] = []
var props: Array[Prop] = []
var found := 0
var total_found := 0           ## 이번 판에서 찾은 수
var best_stage := 1            ## 지금까지 간 최고 탄
var lifetime_found := 0        ## 여태까지 찾은 공룡 수 (계속 쌓임)
var state := "title"
var idle := 0.0
var busy := false

var world: Node2D
var fx: Confetti
var sfx: Sfx
var ui: CanvasLayer

var hud: Control
var hud_name: Label
var hud_sub: Label
var row: DinoRow
var home_btn: Button

var title_ui: Control
var title_record: Label
var continue_btn: Button
var banner: Panel
var banner_label: Label
var fade: ColorRect

var card: Panel
var card_img: TextureRect
var card_label: Label
var card_tween: Tween

var _pool: Array = []  ## 공룡 종류를 골고루 뽑기 위한 주머니
var _slow := 1.0       ## 연출 길이 배수 (자동 테스트에서만 짧게 줄인다)

## --- 적응형 난이도 ------------------------------------------------------- ##
## 아이 눈에 절대 보이지 않는 값. 탄 번호는 그대로 두고 난이도만 조용히 움직인다.
## 신호는 **힌트 발동 횟수 하나뿐**이다 — 초시계(발견 시간)를 쓰면
## 아이가 잠깐 자리를 비우거나 형이 대신 눌러 줄 때 무너진다.
const SKILL_MIN := -8   ## 30탄에서도 E>=22 — 아래로 무너지지 않는다
const SKILL_MAX := 10   ## 1탄에서 시작해도 E<=11 — 첫 판이 절대 안 어렵다
var skill := 0
var ease_streak := 0
var cushion := 0        ## 어려운 판 바로 뒤 한 방은 더 쉽게
var hints_this_room := 0
var misses_this_room := 0
var axes: Dictionary = {}
var target_ids: Array[int] = []   ## 지정된 종만 찾는 판 (E>=24)

## tests/dino_dump.gd 가 켠다. 켜지면 타이틀에서 멈춰 서서 검사만 한다.
var dev_mode := false

const INK := Color("463a45")


# ================================================================= 준비

func _ready() -> void:
	randomize()
	rooms = Rooms.all()
	_load_record()

	world = Node2D.new()
	add_child(world)
	fx = Confetti.new()
	add_child(fx)
	sfx = Sfx.new()
	add_child(sfx)

	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	_build_hud()
	_build_title()
	_build_banner()
	_build_card()

	var fl := CanvasLayer.new()
	fl.layer = 20
	add_child(fl)
	fade = ColorRect.new()
	fade.color = Color(1, 1, 1, 0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade)

	# ★ 커맨드라인은 게임이 읽지 않는다. --dump / --selftest 는
	#   tests/dino_dump.tscn 이 전용 진입점으로 들고 있다 (셸 규칙).
	#   여기서 읽으면 개구리 용사의 촬영 도구와 인자가 섞이고,
	#   _dump() 끝의 get_tree().quit() 이 촬영 도중 앱을 죽인다.
	if dev_mode:
		show_title()
		return
	# 허브의 문을 열고 들어왔다 — 탭 한 번으로 놀이가 시작돼야 한다.
	_start_game(best_stage)


# ================================================================= UI 만들기

func _label(text: String, fsize: int, col: Color, outline := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Color.WHITE)
		l.add_theme_constant_override("outline_size", outline)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _wide_label(text: String, fsize: int, y: float, col: Color, outline := 0) -> Label:
	var l := _label(text, fsize, col, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.anchor_right = 1.0
	l.offset_top = y
	l.offset_bottom = y + fsize * 1.7
	return l


func _button(text: String, fsize: int, base: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fsize)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = base
	sb.set_corner_radius_all(int(fsize * 0.7))
	sb.content_margin_left = fsize * 0.9
	sb.content_margin_right = fsize * 0.9
	sb.content_margin_top = fsize * 0.35
	sb.content_margin_bottom = fsize * 0.45
	sb.border_width_bottom = 7
	sb.border_color = base.darkened(0.28)
	b.add_theme_stylebox_override("normal", sb)
	var sh: StyleBoxFlat = sb.duplicate()
	sh.bg_color = base.lightened(0.10)
	b.add_theme_stylebox_override("hover", sh)
	var sp: StyleBoxFlat = sb.duplicate()
	sp.bg_color = base.darkened(0.08)
	sp.border_width_bottom = 2
	sp.content_margin_top = fsize * 0.42
	sp.content_margin_bottom = fsize * 0.38
	b.add_theme_stylebox_override("pressed", sp)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


func _center_row(y: float, height: float) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 28)
	hb.anchor_right = 1.0
	hb.offset_top = y
	hb.offset_bottom = y + height
	return hb


func _build_hud() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)

	var bar := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.80)
	sb.set_corner_radius_all(30)
	sb.shadow_size = 8
	sb.shadow_color = Color(0, 0, 0, 0.10)
	bar.add_theme_stylebox_override("panel", sb)
	bar.position = Vector2(22, 16)
	bar.size = Vector2(W - 44, 88)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(bar)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	hb.position = Vector2(56, 34)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(hb)
	hud_name = _label("거실", 40, INK)
	hb.add_child(hud_name)
	hud_sub = _label("1 / 6", 24, Color("8a7c8c"))
	hb.add_child(hud_sub)

	row = DinoRow.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.position = Vector2(700, 20)
	hud.add_child(row)

	# ★ 소리 버튼은 없앴다. 놀이 화면 우상단에 있어서 놀다가 아이 손에 닿았고,
	#   설정은 기기 것이라 부모 화면(허브의 톱니)에서만 바꾼다.
	home_btn = _button("집으로", 22, Color("ffe0e6"))
	home_btn.position = Vector2(W - 180, 32)
	home_btn.pressed.connect(_go_home)
	hud.add_child(home_btn)


func _build_title() -> void:
	title_ui = Control.new()
	title_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title_ui)

	title_ui.add_child(_wide_label("공룡을 찾아라!", 92, 48, Color("ff7a59"), 14))
	title_ui.add_child(_wide_label("집 안에 숨은 공룡을 콕! 눌러 찾아보세요", 30, 200, Color("5c4a5c"), 8))
	title_record = _wide_label("", 28, 262, Color("7a6a7c"), 8)
	title_ui.add_child(title_record)

	var hb := _center_row(598, 116)
	var b := _button("시작!", 54, Color("ffd166"))
	b.pressed.connect(_start_game.bind(1))
	hb.add_child(b)
	continue_btn = _button("이어서", 40, Color("9be36f"))
	continue_btn.pressed.connect(_continue_game)
	hb.add_child(continue_btn)
	title_ui.add_child(hb)


## 기록은 이제 Shell 이 소유한다 (user://rogame_save.json 의 활성 프로필).
## 게임별 저장 파일을 두면 형제 프로필로 나눌 수 없다.
func _load_record() -> void:
	var d := Shell.dino_state()
	best_stage = maxi(1, int(d.get("best_stage", 1)))
	lifetime_found = maxi(0, int(d.get("lifetime_found", 0)))
	skill = clampi(int(d.get("skill", 0)), SKILL_MIN, SKILL_MAX)
	ease_streak = maxi(0, int(d.get("ease_streak", 0)))
	cushion = maxi(0, int(d.get("cushion", 0)))


func _save_record() -> void:
	best_stage = maxi(best_stage, stage)
	var d := Shell.dino_state()
	d["best_stage"] = best_stage
	d["lifetime_found"] = lifetime_found
	d["skill"] = skill
	d["ease_streak"] = ease_streak
	d["cushion"] = cushion
	Shell.mark_dirty()


func _build_banner() -> void:
	banner = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.92)
	sb.set_corner_radius_all(40)
	sb.border_width_bottom = 8
	sb.border_color = Color("ffd166")
	sb.shadow_size = 12
	sb.shadow_color = Color(0, 0, 0, 0.12)
	banner.add_theme_stylebox_override("panel", sb)
	banner.size = Vector2(560, 150)
	banner.position = Vector2(W * 0.5 - 280, 200)
	banner.pivot_offset = Vector2(280, 75)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.visible = false
	ui.add_child(banner)

	banner_label = _label("잘했어요!", 60, Color("ff7a59"))
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(banner_label)


## 공룡을 찾으면 3초쯤 떠오르는 카드 — 큰 그림 + 이름 전부
func _build_card() -> void:
	card = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.95)
	sb.set_corner_radius_all(44)
	sb.border_width_bottom = 10
	sb.border_color = Color("ffd166")
	sb.shadow_size = 16
	sb.shadow_color = Color(0, 0, 0, 0.16)
	card.add_theme_stylebox_override("panel", sb)
	card.size = Vector2(460, 330)
	card.position = Vector2(W * 0.5 - 230, 110)
	card.pivot_offset = Vector2(230, 165)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	ui.add_child(card)

	card_img = TextureRect.new()
	card_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_img.position = Vector2(20, 18)
	card_img.size = Vector2(420, 208)
	card_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(card_img)

	card_label = _label("", 40, INK)
	card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card_label.position = Vector2(0, 238)
	card_label.size = Vector2(460, 72)
	card.add_child(card_label)


func _show_card(d: Dino) -> void:
	var tex := d.texture()
	card_img.texture = tex
	card_img.visible = tex != null
	card_label.text = d.full_name()
	card_label.position.y = 238 if tex != null else 130
	card.visible = true
	card.modulate.a = 1.0
	card.scale = Vector2(0.5, 0.5)
	if card_tween != null and card_tween.is_valid():
		card_tween.kill()
	card_tween = create_tween()
	card_tween.tween_property(card, "scale", Vector2(1.06, 1.06), 0.22 * _slow).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	card_tween.tween_property(card, "scale", Vector2.ONE, 0.12 * _slow)
	card_tween.tween_interval(2.05 * _slow)
	card_tween.tween_property(card, "modulate:a", 0.0, 0.40 * _slow)
	card_tween.tween_callback(_hide_card)


func _hide_card() -> void:
	if card_tween != null and card_tween.is_valid():
		card_tween.kill()
	card.visible = false


# ================================================================= 화면 전환

func show_title() -> void:
	state = "title"
	busy = false
	stage = 1
	found = 0
	total_found = 0
	title_ui.visible = true
	hud.visible = false
	banner.visible = false
	_hide_card()
	fx.clear_all()
	_pool.clear()
	if best_stage > 1:
		title_record.text = "최고 기록 %d탄 · 지금까지 공룡 %d마리" % [best_stage, lifetime_found]
		continue_btn.text = "%d탄부터" % best_stage
		continue_btn.visible = true
	else:
		title_record.text = ""
		continue_btn.visible = false
	_build_showcase(0, [3, 0, 2])


func _go_title() -> void:
	if busy:
		return
	sfx.play("tap")
	show_title()


func _continue_game() -> void:
	_start_game(best_stage)


func _start_game(from_stage := 1) -> void:
	if busy:
		return
	sfx.play("start")
	title_ui.visible = false
	hud.visible = true
	_hide_card()
	_pool.clear()
	stage = maxi(1, from_stage)
	total_found = 0
	_build_room()


## 허브로 돌아간다. 방 중간이어도 지금까지 찾은 건 이미 저장돼 있다.
func _go_home() -> void:
	if busy:
		return
	sfx.play("tap")
	_save_record()
	Shell.journey_end()
	Router.goto_hub()


# ================================================================= 방 만들기

func _clear_world() -> void:
	for c in world.get_children():
		c.queue_free()
	dinos.clear()
	props.clear()


func _add_bg(room: Dictionary) -> void:
	var bg := RoomBg.new()
	bg.data = room
	bg.z_index = -20
	world.add_child(bg)


func _add_props(list: Array, z: int) -> Array[Prop]:
	var out: Array[Prop] = []
	for d in list:
		var p := Prop.new()
		p.setup(String(d["kind"]), float(d["w"]), float(d["h"]), d["col"], d["col2"])
		p.position = Vector2(float(d["x"]), float(d["y"]))
		p.z_index = z
		world.add_child(p)
		out.append(p)
	return out


## 공룡끼리 겹치지 않도록 충분히 떨어진 자리들을 고른다.
func _pick_spots(room: Dictionary, count: int) -> Array:
	var front: Array = room["front"]
	var pool: Array = (room["spots"] as Array).duplicate()
	pool.shuffle()
	var picked: Array = []
	var xs: Array = []
	for gap in [230.0, 170.0, 0.0]:  # 자리가 모자라면 조건을 완화
		for s in pool:
			if picked.size() >= count:
				break
			if picked.has(s):
				continue
			var x: float = (Rooms.spot_transform(front, s)["pos"] as Vector2).x
			var ok := true
			for other in xs:
				if absf(float(other) - x) < gap:
					ok = false
					break
			if ok:
				picked.append(s)
				xs.append(x)
		if picked.size() >= count:
			break
	return picked


## 난이도용 유효탄. 아이가 보는 탄 번호(stage)와 분리돼 있다.
##
## ★ 완충 장치 B5: 10탄 배수는 축하 연출이 붙는 방이라 항상 조금 쉽게 만든다.
##   축하 방이 제일 어려우면 안 된다.
func effective_stage() -> int:
	var e := stage + skill - cushion * 2
	if stage % 10 == 0:
		e -= 3
	return clampi(e, 1, 999)


## 1~6탄은 손으로 꾸민 방, 7탄부터는 그때그때 새로 만든 방
func _room_for(s: int, e: int) -> Dictionary:
	if s <= rooms.size():
		return rooms[s - 1]
	var r := RandomNumberGenerator.new()
	r.seed = randi()
	return RoomGen.stage_room(e, r, s, Shell.tuning())


func _build_room() -> void:
	var e := effective_stage()
	axes = RoomGen.axes(e, Shell.tuning())
	room = _room_for(stage, e)
	_clear_world()
	fx.clear_all()
	found = 0
	idle = 0.0
	busy = false
	hints_this_room = 0
	misses_this_room = 0
	state = "play"

	_add_bg(room)
	_add_props(room["back"], -10)

	# 자동 생성 방은 생성기가 이미 간격 120px 이상을 보장한다.
	# 손으로 꾸민 1~6탄만 예전처럼 자리를 고른다.
	var spots: Array = room["spots"]
	if stage <= rooms.size():
		spots = _pick_spots(room, int(room["count"]))
	else:
		spots = (spots as Array).slice(0, int(room["count"]))
	var count := spots.size()

	var species: Array = []
	for i in count:
		var sp := _next_species(species)
		var st: Dictionary = Rooms.spot_transform(room["front"], spots[i])
		var d := Dino.new()
		d.setup(sp, st["pos"], st["face"])
		world.add_child(d)
		dinos.append(d)
		species.append(sp)

	props = _add_props(room["front"], 20)
	_pick_targets(species)
	_place_decoys()

	hud_name.text = String(room["name"])
	if Shell.journey_active:
		hud_sub.text = "섬 %d번째" % Shell.journey_stage
	else:
		hud_sub.text = "%d탄 · 공룡 %d마리" % [stage, total_found]
	# 목표 지정 판에서는 찾아야 할 종만 위에 보인다 — 그게 곧 "무엇을 찾는지"다.
	row.set_room(target_ids if not target_ids.is_empty() else species)
	row.position = Vector2(930.0 - row.size.x, 20)


## 미끼 (난이도 축 D6). 목표가 아닌 공룡을 목표와 닮은 종으로 바꾼다.
## 화면에 있는 마리 수는 그대로다 — 어려워지는 것은 "고르는 일"뿐이다.
func _place_decoys() -> void:
	var want := int(axes.get("decoys", 0))
	if want <= 0 or target_ids.is_empty():
		return
	var made := 0
	for d in dinos:
		if made >= want:
			break
		if target_ids.has(d.species):
			continue
		var pool: Array[int] = []
		for t in target_ids:
			for a in DinoSpecies.look_alikes(t):
				if not target_ids.has(a):
					pool.append(a)
		if pool.is_empty():
			continue
		var pick := int(pool[randi() % pool.size()])
		d.setup(pick, d.base_pos, d.face)
		made += 1


## 목표 지정 (난이도 축 C). 지정 안 된 공룡을 눌러도 벌은 없다 — 손만 흔든다.
func _pick_targets(species: Array) -> void:
	target_ids.clear()
	if not bool(axes.get("targets_only", false)) or species.size() <= 2:
		return
	var e := effective_stage()
	# ★ 목표는 절반 아래로 안 내려간다. 찾을 것이 너무 줄면 "양이 많아서 오래 걸리는"
	#   가장 안전한 종류의 어려움까지 같이 사라진다.
	var half := int(ceil(float(species.size()) * 0.5))
	var n := maxi(half, species.size() - int((e - 24) / 8) - 1)
	if n >= species.size():
		return
	var pool: Array = species.duplicate()
	pool.shuffle()
	for i in n:
		target_ids.append(int(pool[i]))


## 한 방 안에서는 같은 종이 겹치지 않게, 한 판 동안은 골고루 나오게 뽑는다.
##
## 난이도 축 두 개가 여기 얹힌다:
##   D4 작은 종 편향 — 그림 면적이 종끼리 2배 넘게 차이나서, 작은 종이 찾기 어렵다.
##   도감 사냥    — 아직 못 만난 종을 우선 내보낸다 (큰 아이에게만).
func _next_species(avoid: Array) -> int:
	var bias := float(axes.get("small_bias", 0.0))
	# 도감에 없는 종을 먼저 (프로필이 켜져 있을 때만)
	if bool(Shell.tune("dino_dex_hunt", false)) and avoid.is_empty():
		var unmet := Shell.unmet_indices()
		if not unmet.is_empty():
			var pick := int(unmet[randi() % unmet.size()])
			_pool.erase(pick)
			return pick
	for attempt in 2:
		if _pool.is_empty():
			_pool = range(DinoSpecies.count())
			_pool.shuffle()
			if bias > 0.0:
				# 작은 종이 앞으로 오게 주머니를 부분적으로 정렬한다.
				var small := DinoSpecies.by_size_asc()
				var keep := int(round(float(_pool.size()) * bias))
				var head: Array = []
				for idx in small:
					if head.size() >= keep:
						break
					head.append(idx)
				for idx in head:
					_pool.erase(idx)
				_pool = head + _pool
		for i in _pool.size():
			if not avoid.has(_pool[i]):
				return int(_pool.pop_at(i))
		_pool.clear()
	return randi() % DinoSpecies.count()


## 타이틀/엔딩 배경용: 공룡들이 밖에 나와서 춤추는 방
func _build_showcase(idx: int, kinds: Array) -> void:
	var room: Dictionary = rooms[idx]
	_clear_world()
	_add_bg(room)
	_add_props(room["back"], -10)
	_add_props(room["front"], 20)
	var n := kinds.size()
	for i in n:
		var d := Dino.new()
		var x: float = 170.0 + (W - 340.0) * (float(i) / maxf(1.0, float(n) - 1.0))
		d.setup(int(kinds[i]), Vector2(x, 556.0), 1.0 if i % 2 == 0 else -1.0)
		d.found = true
		d.joy = 1.0
		d.z_index = 40
		world.add_child(d)
		dinos.append(d)


# ================================================================= 입력

func _unhandled_input(event: InputEvent) -> void:
	# F11 전체화면 / ESC 창모드 (어른용)
	if event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).keycode
		if key == KEY_F11:
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			return
		if key == KEY_ESCAPE:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			return
	if busy:
		return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 아기가 아무 데나 눌러도 시작/다시하기가 되도록
	if state == "title":
		_start_game(1)
	elif state == "play":
		_tap(get_global_mouse_position())


## 누른 곳에 걸리는 공룡을 고른다.
##
## ★ 판정 네모가 그림보다 크고(폭 +24px) 공룡끼리 84px 까지 붙을 수 있어서 자주 겹친다.
##   예전처럼 "위에서부터 첫 번째"를 집으면, 목표 지정 판에서 지정 안 된 공룡이
##   목표를 덮고 있을 때 아이가 목표를 눌러도 아무 일이 안 일어난다.
##   그래서 (1) 걸리는 것을 다 모으고 (2) 목표를 먼저 (3) 그 안에서 가장 가까운 것을 고른다.
func _pick_tapped(p: Vector2) -> Dino:
	var best: Dino = null
	var best_key := Vector2(9.0, 1e9)   # (목표 아님 = 1, 중심까지 거리)
	for d in dinos:
		if d.found or not d.hit_rect().has_point(p):
			continue
		var is_target := target_ids.is_empty() or target_ids.has(d.species)
		var key := Vector2(0.0 if is_target else 1.0,
				absf(d.base_pos.x - p.x) + absf(d.base_pos.y - 60.0 - p.y) * 0.5)
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = d
	return best


func _tap(p: Vector2) -> void:
	var hit := _pick_tapped(p)
	if hit != null:
		# 목표 지정 판에서 지정 안 된 공룡을 눌렀다 — 벌이 아니라 인사만 한다.
		if not target_ids.is_empty() and not target_ids.has(hit.species):
			hit.hint()
			sfx.play("tap", 0.8)
			return
		_on_found(hit)
		return
	for i in range(props.size() - 1, -1, -1):
		var pr: Prop = props[i]
		if pr.rect().has_point(p):
			pr.jiggle()
			misses_this_room += 1
			sfx.play("miss", randf_range(0.95, 1.1))
			fx.burst(p, 5, Color("ffffff"))
			return
	misses_this_room += 1
	sfx.play("miss", randf_range(0.9, 1.05))
	fx.burst(p, 4, Color("ffffff"))


func _on_found(d: Dino) -> void:
	d.celebrate()
	found += 1
	total_found += 1
	lifetime_found += 1
	idle = 0.0
	# ★ 도감. 예전에는 무엇을 모았는지 저장에 아예 없어서, 50종을 다 봤는지
	#   게임도 아이도 몰랐다. 이 한 줄이 "앱을 계속 켤 이유"의 토대다.
	var first := Shell.dex_meet(DinoSpecies.id_of(d.species))
	Shell.bump_today("dino")
	# 방을 다 깨야만 저장하던 버그도 여기서 같이 고쳐진다 —
	# 방 중간에 앱을 꺼도 찾은 공룡이 사라지지 않는다.
	_save_record()
	if first:
		fx.rain(40)
	hud_sub.text = "%d탄 · 공룡 %d마리" % [stage, total_found]
	row.found = found
	row.queue_redraw()
	sfx.play("find", 1.0 + 0.06 * float(found - 1))
	fx.burst(d.base_pos + Vector2(0, -100), 22, DinoSpecies.data(d.species)["col"])
	_show_card(d)
	if found >= _need_count():
		_room_clear()


## 이 방을 끝내려면 몇 마리를 찾아야 하는가.
## 목표 지정 판에서는 지정된 종만 세면 된다 — 나머지는 배경에 섞여 있는 이웃이다.
func _need_count() -> int:
	return target_ids.size() if not target_ids.is_empty() else dinos.size()


# ================================================================= 진행

func _room_clear() -> void:
	busy = true
	state = "clear"
	_update_skill()
	# ★ 기다림은 난이도 축이 아니다 — 올리지 않고 줄이기만 한다.
	#   2.9 -> 1.6 / 2.3 -> 1.4. 방 전환에서 5.85초를 쓰던 것을 3.6초로 줄인다.
	var mot := Shell.anim_scale()
	await get_tree().create_timer(1.6 * _slow * mot).timeout
	var milestone := stage % 10 == 0
	var rain := 150 if milestone else 70
	if Shell.reduce_motion:
		rain = rain / 2
	if milestone:
		sfx.play("hooray")
		fx.rain(rain)
		_show_banner("%d탄 돌파!" % stage)
	else:
		sfx.play("clear")
		fx.rain(rain)
		# ★ 칭찬은 사람이 아니라 사건을 말한다. "잘했어요"는 능력 귀인을 만들고
		#   그 귀인은 실패할 때 정확히 반대로 뒤집힌다.
		_show_banner("%s 다 찾았다!" % String(room["name"]))
	await get_tree().create_timer((2.0 if milestone else 1.4) * _slow * mot).timeout
	_hide_banner()
	stage += 1
	_save_record()
	# ★ 「섬 한 바퀴」로 들어왔으면 한 방만 하고 셸에 돌려준다.
	#   다음에 무엇이 나올지는 셸이 정한다 — 게임은 다른 게임을 몰라도 된다.
	if Shell.journey_active and not dev_mode:
		busy = true
		Shell.journey_advance()
		return
	# 방 하나가 개구리 문제 3개쯤의 놀이 단위다. 세션은 두 게임을 합쳐서 센다.
	Shell.add_session_units(Shell.DINO_ROOM_UNITS)
	if Shell.session_over_limit() and not dev_mode:
		await _fade(_go_home_from_clear)
		return
	await _fade(_build_room)


func _go_home_from_clear() -> void:
	# 상한에 닿았다 — 놀이를 끊지 않고 집으로 돌려보낸다.
	# 게임 안에서 끊으면 벌이지만 허브에서 닫히면 하루의 끝이다.
	Router.goto_hub()


## 적응형 조정. 방 하나가 끝날 때마다 딱 한 번.
##
## ★ 신호는 힌트 발동 횟수 하나뿐이다. 발견 시간(초시계)을 쓰면
##   (a) 화면에 안 보이는 타이머가 되고
##   (b) 아이가 자리를 비우면 난이도가 계속 바닥으로 흐르고
##   (c) 형이 대신 눌러 주면 아이 실력과 무관하게 올라간다.
## 내려갈 땐 한 방 만에, 올라갈 땐 두 방 연속. 중간은 데드존이라 아무 일도 없다.
func _update_skill() -> void:
	if cushion > 0:
		cushion -= 1
	var n := maxi(1, dinos.size())
	var hard := hints_this_room >= 2
	var easy := hints_this_room == 0 and misses_this_room <= n * 2
	if hard:
		skill = maxi(skill - 1, SKILL_MIN)
		ease_streak = 0
		cushion = 1           # 다음 한 방은 무조건 완충
	elif easy:
		ease_streak += 1
		if ease_streak >= 2:
			skill = mini(skill + 1, SKILL_MAX)
			ease_streak = 0
	else:
		ease_streak = 0


func _show_banner(text: String) -> void:
	banner_label.text = text
	banner.visible = true
	banner.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2(1.1, 1.1), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "scale", Vector2.ONE, 0.12)


func _hide_banner() -> void:
	banner.visible = false


func _fade(cb: Callable) -> void:
	busy = true
	var tw := create_tween()
	tw.tween_property(fade, "color", Color(1, 1, 1, 1), 0.30 * _slow)
	await tw.finished
	cb.call()
	var tw2 := create_tween()
	tw2.tween_property(fade, "color", Color(1, 1, 1, 0), 0.35 * _slow)
	await tw2.finished


# ================================================================= 매 프레임

func _process(delta: float) -> void:
	if state != "play" or busy:
		return
	idle += delta
	var wait := float(axes.get("hint_sec", 12.0))
	if idle > wait:
		idle = wait * 0.45
		hints_this_room += 1
		var any := false
		for d in dinos:
			if d.found:
				continue
			if not target_ids.is_empty() and not target_ids.has(d.species):
				continue
			d.hint()
			any = true
		if any:
			sfx.play("tap", 0.7)


# ============================================ 개발용: 화면 구성을 JSON으로 뽑기
# godot --headless -- --dump   (그래픽 없는 곳에서 배치 확인할 때만 사용)

## 자동으로 여러 탄을 이어서 돌려본다 (오류 확인용)
func _selftest() -> void:
	const LAST := 30
	var names: Array = []
	_slow = 0.10  # 연출을 짧게 — headless 는 프레임 제한이 없어 대기가 프레임을 많이 먹는다
	var t0 := Time.get_ticks_msec()
	_start_game(1)
	# 빗나간 탭 / 가구 탭 / 소리 끄기·켜기도 한 번씩
	await get_tree().process_frame
	_tap(Vector2(640, 200))
	if props.size() > 0:
		_tap(props[0].position + Vector2(0, -20))
	var guard := 0
	var last_seen := 0
	while stage <= LAST and Time.get_ticks_msec() - t0 < 180000:
		guard += 1
		await get_tree().process_frame
		if state == "play" and not busy:
			if stage != last_seen:
				last_seen = stage
				names.append("%d:%s(%d/%d)@%.1fs" % [stage, String(room["name"]),
						_need_count(), dinos.size(), (Time.get_ticks_msec() - t0) / 1000.0])
			var target: Dino = null
			for d in dinos:
				# 목표 지정 판에서는 지정된 종만 눌러야 찾아진다.
				# (이걸 안 보면 지정 안 된 공룡만 계속 눌러 영원히 안 끝난다.)
				if d.found:
					continue
				if not target_ids.is_empty() and not target_ids.has(d.species):
					continue
				target = d
				break
			if target == null:
				# 지정된 공룡을 다 찾았는데 방이 안 끝났다 — 있을 수 없지만 안전망.
				for d in dinos:
					if not d.found:
						target = d
						break
			if target == null:
				continue
			_tap(target.base_pos + Vector2(0, -70))
	print("자동 테스트: %d탄까지 진행, 공룡 %d마리, %.1f초\n  %s" % [last_seen, total_found, (Time.get_ticks_msec() - t0) / 1000.0, ", ".join(PackedStringArray(names))])
	if last_seen < LAST:
		printerr("자동 테스트 실패! %d탄에서 멈춤" % last_seen)
	sfx.stop_all()


## 손으로 꾸민 1~6탄: 숨을 자리마다 "얼마나 가려지는지" 확인 (28~74%가 적당)
func _check_spots() -> void:
	for r in rooms:
		var front: Array = r["front"]
		var spots: Array = r["spots"]
		for i in spots.size():
			var st: Dictionary = Rooms.spot_transform(front, spots[i])
			var cov := Rooms.coverage(st["pos"], front)
			var mark := "  " if cov >= Rooms.COV_HARD_LO and cov <= Rooms.COV_HARD_HI else "!!"
			print("%s %s spot%d(p%d,s%d) 가림 %d%%" % [mark, String(r["name"]), i, int(spots[i]["p"]), int(spots[i]["side"]), cov])


## 자동으로 만들어지는 7탄~ : 전부 제대로 된 방이 나오는지 무더기로 검사
##
## ★ 예전에는 "자리부족 0건"을 안전 증거로 삼았는데, 그건 동어반복이라
##   0 이외의 값이 나올 수 없었다 — stage_room 이 필요 마릿수를 자리 수에 맞춰
##   미리 깎기 때문이다. 그래서 **want(원한 마릿수) vs count(실제)** 를 같이 센다.
##   이게 벌어지는 것이 진짜 신호다.
func _check_stages(last := 200, t: Dictionary = {}) -> void:
	var short_rooms := 0
	var bad_cov := 0
	var min_spots := 99
	var counts := {}
	var cov_sum := 0
	var cov_n := 0
	var cov_lo := 100
	var cov_hi := 0
	var min_gap := 9999.0
	var rng := RandomNumberGenerator.new()
	for s in range(7, last + 1):
		for repeat in 3:  # 같은 탄도 매번 새로 만들어지므로 여러 번 본다
			rng.seed = hash(str(s) + "_" + str(repeat))
			var r := RoomGen.stage_room(s, rng, s, t)
			var need := int(r["count"])
			var want := int(r.get("want", need))
			var spots: Array = (r["spots"] as Array).slice(0, need)
			min_spots = mini(min_spots, (r["spots"] as Array).size())
			counts[need] = int(counts.get(need, 0)) + 1
			if need < want:
				short_rooms += 1
				if short_rooms <= 3:
					print("!! %d탄: 원한 %d마리 중 %d마리만" % [s, want, need])
			var xs: Array = []
			for sp in spots:
				var st: Dictionary = Rooms.spot_transform(r["front"], sp)
				var cov := Rooms.coverage(st["pos"], r["front"])
				cov_sum += cov
				cov_n += 1
				cov_lo = mini(cov_lo, cov)
				cov_hi = maxi(cov_hi, cov)
				if cov < Rooms.COV_HARD_LO or cov > Rooms.COV_HARD_HI:
					bad_cov += 1
					if bad_cov <= 3:
						print("!! %d탄: 가림 %d%% (한계 %d~%d)" % [s, cov, Rooms.COV_HARD_LO, Rooms.COV_HARD_HI])
				var x: float = (st["pos"] as Vector2).x
				for ox in xs:
					min_gap = minf(min_gap, absf(float(ox) - x))
				xs.append(x)
	# 판정 기준을 여기 한 곳에 둔다 — 숫자를 아는 코드가 정하고, verify.sh 는 이 줄만 본다.
	#   가림 한계 이탈은 0건이어야 한다 (화면 밖으로 나가거나 아이가 못 찾는 방).
	#   마릿수 부족은 1% 까지 봐준다 — 자리 간격(108px 이상)을 지키다 보면 아주 가끔
	#   6마리 대신 5마리가 나온다. 아이 눈에는 아무 차이가 없고, 간격을 줄이는 쪽이
	#   훨씬 나쁘다 (판정 네모가 겹쳐 목표를 눌러도 안 눌리는 사고가 난다).
	var rooms_n := (last - 6) * 3
	var short_pct := 100.0 * float(short_rooms) / float(maxi(1, rooms_n))
	var ok := bad_cov == 0 and short_pct <= 1.0
	print("%s 자동 생성 7~%d탄 (각 3회): 마릿수부족 %d건(%.1f%%), 가림한계이탈 %d건, 최소 자리수 %d, 공룡수 분포 %s"
		% ["  " if ok else "!!", last, short_rooms, short_pct, bad_cov, min_spots, str(counts)])
	print("   판정: %s" % ("정상" if ok else "이상 — 위 !! 줄을 보세요"))
	if cov_n > 0:
		print("   가림 평균 %.1f%% (최소 %d / 최대 %d), 공룡 최소 간격 %.0fpx"
			% [float(cov_sum) / float(cov_n), cov_lo, cov_hi, min_gap])


## 난이도 곡선이 정말 오르는지 표로 확인한다 (평평하면 지루하다는 뜻).
func _check_curve() -> void:
	var t := Shell.tuning()
	print("   유효탄별 난이도 (프로필: %s)" % String(Shell.profile()["age_band"]))
	print("   %5s %6s %6s %10s %8s %7s %7s" % ["E", "공룡", "가구", "가림밴드", "작은종", "미끼", "힌트초"])
	var rng := RandomNumberGenerator.new()
	for e in [1, 5, 10, 15, 20, 25, 30, 50, 100, 200]:
		var ax := RoomGen.axes(e, t)
		var b: Vector2i = ax["band"]
		# 실제로 나오는 가림% 평균도 같이 잰다
		var sum := 0
		var n := 0
		for rep in 12:
			rng.seed = hash("curve_%d_%d" % [e, rep])
			var r := RoomGen.stage_room(e, rng, e, t)
			for sp in (r["spots"] as Array).slice(0, int(r["count"])):
				var st: Dictionary = Rooms.spot_transform(r["front"], sp)
				sum += Rooms.coverage(st["pos"], r["front"])
				n += 1
		var avg := float(sum) / float(maxi(1, n))
		print("   %5d %6d %6d %10s %8.2f %7d %7.1f  실제 가림 %.1f%%"
			% [e, int(ax["dinos"]), int(ax["props"]), "%d~%d" % [b.x, b.y],
			   float(ax["small_bias"]), int(ax["decoys"]), float(ax["hint_sec"]), avg])


## 글자가 상자 밖으로 삐져나가지 않는지 폭을 재서 확인한다.
func _check_text() -> void:
	var f: Font = card_label.get_theme_font("font")
	var fs: int = card_label.get_theme_font_size("font_size")
	var widest := 0.0
	var widest_name := ""
	for i in DinoSpecies.count():
		var nm := DinoSpecies.full_name(i)
		var w: float = f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w > widest:
			widest = w
			widest_name = nm
	var room_for := card_label.size.x - 24.0
	var mark := "!!" if widest > room_for else "  "
	print("%s 카드 이름 최대폭 %.0fpx (%s) / 자리 %.0fpx" % [mark, widest, widest_name, room_for])

	var missing := PackedStringArray()
	for i in DinoSpecies.count():
		if DinoSpecies.texture(i) == null:
			missing.append(String(DinoSpecies.data(i)["id"]))
	# 첫 화면 버튼이 화면 밖으로 나가지 않는지
	best_stage = 123
	show_title()
	var bw: float = continue_btn.get_combined_minimum_size().x + 28.0
	for b in title_ui.get_children():
		if b is HBoxContainer:
			for c in (b as HBoxContainer).get_children():
				bw += (c as Control).get_combined_minimum_size().x
	print("%s 첫 화면 버튼 줄 폭 %.0fpx / 화면 %dpx" % ["!!" if bw > W - 80 else "  ", bw, int(W)])
	best_stage = 1

	if missing.size() > 0:
		print("!! 그림 없는 공룡 %d종 (손그림으로 대체 중): %s" % [missing.size(), ", ".join(missing)])
	else:
		print("   공룡 그림 %d종 모두 있음" % DinoSpecies.count())


## tests/dino_dump.gd 가 부른다. 게임 자신은 커맨드라인을 읽지 않는다.
func run_dump(with_boxes := false) -> void:
	_boxes = with_boxes
	await _dump()


func run_selftest() -> void:
	await _selftest()


var _boxes := false


func _dump() -> void:
	var dir := ProjectSettings.globalize_path("res://preview")
	DirAccess.make_dir_recursive_absolute(dir)
	_check_spots()
	_check_stages(200, Shell.tuning())
	_check_curve()
	_check_text()
	await get_tree().process_frame
	state = "play"
	# 손으로 꾸민 1~6탄
	for i in rooms.size():
		stage = i + 1
		_build_room()
		await get_tree().process_frame
		_dump_world(dir + "/%d_%s.json" % [i + 1, String(rooms[i]["name"])], true)
	# 자동으로 만들어지는 방 몇 개 (매번 달라지므로 맛보기)
	# 새 난이도 축이 처음 켜지는 지점을 그림으로 남긴다 (E=13/20/24/28/32).
	for s in [7, 13, 20, 24, 28, 34, 60]:
		stage = s
		_build_room()
		await get_tree().process_frame
		_dump_world(dir + "/s%03d_%s.json" % [s, String(room["name"])], true)
	show_title()
	await get_tree().process_frame
	_dump_world(dir + "/0_title.json", false)
	_dump_icon(dir + "/icon.json")
	stage = 1
	_build_room()
	await get_tree().process_frame
	_dump_card(dir + "/9_카드.json")


## 공룡을 찾았을 때 뜨는 카드 미리보기 (글자는 회색 막대로 자리만 표시)
func _dump_card(path: String) -> void:
	var rec = load("res://tools/dino/recorder.gd").new()
	_paint_world(rec)
	rec.set_node(Transform2D.IDENTITY)
	rec.draw_rect(Rect2(22, 16, W - 44, 88), Color(1, 1, 1, 0.8))
	DinoArt.blob(rec, DinoArt.rrect(Rect2(card.position, card.size), 44), Color(1, 1, 1, 0.95), Color("ffd166"), 8.0)
	var d: Dino = dinos[0]
	var tex := d.texture()
	if tex != null:
		var box := Rect2(card.position + card_img.position, card_img.size)
		var ts := Vector2(tex.get_width(), tex.get_height())
		var k: float = minf(box.size.x / ts.x, box.size.y / ts.y)
		var sz := ts * k
		rec.draw_texture_rect(tex, Rect2(box.position + (box.size - sz) * 0.5, sz))
	var f: Font = card_label.get_theme_font("font")
	var fs: int = card_label.get_theme_font_size("font_size")
	var tw: float = f.get_string_size(d.full_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	rec.draw_rect(Rect2(card.position + card_label.position + Vector2((card_label.size.x - tw) * 0.5, 8), Vector2(tw, fs)), Color(0.55, 0.5, 0.58, 0.55))
	rec.save(path)


## 안드로이드 런처 아이콘용 공룡 그림 (432x432 안전영역 안에)
func _dump_icon(path: String) -> void:
	var rec = load("res://tools/dino/recorder.gd").new()
	rec.set_node(Transform2D(0.0, Vector2(1.45, 1.45), 0.0, Vector2(238, 328)))
	DinoArt.draw_dino(rec, 0, DinoArt.palette(0), 1.0, 1.0, false)
	rec.save(path)


func _paint_world(rec) -> void:
	var kids := world.get_children()
	var zs: Array = []
	for k in kids:
		if not zs.has(k.z_index):
			zs.append(k.z_index)
	zs.sort()
	for z in zs:
		for k in kids:
			if k.z_index == z:
				rec.set_node(Transform2D(k.rotation, k.scale, 0.0, k.position))
				k._paint(rec)


func _dump_world(path: String, with_hud: bool) -> void:
	var rec = load("res://tools/dino/recorder.gd").new()
	_paint_world(rec)
	if with_hud:
		rec.set_node(Transform2D.IDENTITY)
		rec.draw_rect(Rect2(22, 16, W - 44, 88), Color(1, 1, 1, 0.8))
		if _boxes:
			for b in [home_btn]:
				rec.draw_rect((b as Button).get_rect(), Color("cfe8ff"))
			print("  HUD 위치: 카운터 %s  집으로 %s" % [row.get_rect(), home_btn.get_rect()])
		rec.set_node(Transform2D(0.0, Vector2.ONE, 0.0, row.position))
		row._paint(rec)
		if _boxes:
			rec.set_node(Transform2D.IDENTITY)
			for d in dinos:
				rec.draw_rect(d.hit_rect(), Color(1, 0, 0, 0.10))
	rec.save(path)
