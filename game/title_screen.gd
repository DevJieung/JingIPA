extends Node2D
class_name TitleScreen

## 시작 / 이어하기와 평생 기록. 만난 영웅 기록은 속성별 도감으로 열린다.

var main = null
var ui := Ui.new()
var collection := CollectionView.new()
var store := StoreView.new()
## The ladder's stages (zone "stages" opens it): only unlocked ones start (2026-10-19, LB2b).
var stage_select := StageSelectView.new()
## Hellbound's squad picker (D7, game/squad_view.gd): the "hell" zone opens it for DLC owners.
var squad := SquadView.new()
var t: float = 0.0
## D4 (2026-10-19): the title reads as one brand with the loading cover and the app icon. The
## soul-stone emblem crowns the metal wordmark (the loading lockup's crest), and the Soul Stone
## floats between the two guardians where the star rite's dome stood (the rite became the jewel
## box). Painted brand art: tools/brand/ (art/generated-assets.json).
const CREST := preload("res://art/ui/soul_emblem.png")
const STONE := preload("res://art/ui/soul_stone.png")
## The crest's box above the title line; the wordmark itself moves down by WORDMARK_DROP.
const CREST_HEIGHT := 90.0
const CREST_TOP := 6.0
const WORDMARK_DROP := 8.0
## The Soul Stone between the guardians (its centre and drawn height).
const STONE_AT := Vector2(640, 388)
const STONE_HEIGHT := 232.0
## The painted crest and stone are drawn far below their size (and the stone bobs by sub-pixels):
## they go through CanvasTextures that filter linearly with mipmaps, as the portraits do (core/art.gd),
## while the title canvas keeps the project's Nearest default for everything else.
static var _crest_smooth: CanvasTexture = null
static var _stone_smooth: CanvasTexture = null
## 시작을 두 번 눌러 판이 두 번 시작되지 않게.
var _started: bool = false
var _wordmark := Wordmark.new()


func _ready() -> void:
	# 글자 자체는 번들 글꼴로 유지하고 금속색·입체 테두리만 별도 캔버스에 그린다.
	add_child(_wordmark)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	queue_redraw()


func _input(e: InputEvent) -> void:
	# Under the boot loading cover nothing on the title may be pressed (F8): the cover
	# swallows input first, and this keeps it so even if an event slips past it.
	if main != null and main.get("interactive") == false:
		return
	# The sheets over the title, top first: they take every event while open.
	if store.input(e, ui):
		return
	if squad.input(e, ui):
		return
	if stage_select.input(e, ui):
		return
	if collection.input(e, ui):
		return
	if not (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT):
		return
	if main == null or _started:
		return
	action(ui.hit(e.position))


## One title button (a zone id). Returns whether it did anything.
func action(id: String) -> bool:
	if main == null or _started:
		return false
	match id:
		"collection":
			collection.opened = true
		"store:open":
			store.open()
		"stages":
			stage_select.open(main)
		"hell":
			# Hellbound belongs to the DLC: owners pick a squad, everyone else meets its shop sheet.
			if dlc():
				squad.open(main)
			else:
				store.open(Store.GUARDIAN)
		"resume":
			# 하다 만 판을 이어 한다. 되돌릴 수 없으면(옛 저장·깨진 저장) 조용히 새 판이다.
			_started = true
			if not main.resume_run():
				main.start_run(0, Save.stage_unlocked)
		"start":
			_started = true
			# ★ 새로 시작하면 하다 만 판은 사라진다. 그 전에 한 번 물어보고 싶어지겠지만,
			#   이어하기 단추가 바로 위에 있으므로 여기서 또 묻는 것은 성가시기만 하다.
			# 「시작」은 다음에 열린 스테이지다(Save.stage_unlocked).
			main.start_run(0, Save.stage_unlocked)
		_:
			return false
	Sfx.play("button")
	return true


## Whether the DLC (Store.GUARDIAN) is owned: Arena.dlc() once the run offers it (LA3).
func dlc() -> bool:
	return bool(Arena.call("dlc")) if Arena.has_method("dlc") else Store.owns(Store.GUARDIAN)


## Whether a sheet covers the title (Main.screen_modal_open, the menu button, the wordmark).
func overlay_open() -> bool:
	return collection.opened or store.opened or stage_select.opened or squad.opened


## Close the topmost sheet (the Android back button). False when none was open.
func close_overlay() -> bool:
	if store.opened:
		store.close()
	elif squad.opened:
		squad.close()
	elif stage_select.opened:
		stage_select.close()
	elif collection.opened:
		collection.close()
	else:
		return false
	return true


## The first record cell's data (O9, 2026-10-19), all from the ladder: the stage cleared last —
## label 「직전 클리어」 (arena.last_clear), value "STAGE n · <battlefield>" — or, before any clear,
## the stage to take on — label 「도전」 (arena.stage_next), value "STAGE n" (Save.stage_unlocked;
## the old ten-stage chain's best is no longer shown). `track_*` are the ten steps of that stage's
## chapter: `track_cleared` the chapter's stages actually cleared (the ladder opens in order, so
## every stage up to Save.stage_cleared), `track_reached` the next stage to take on when it lies
## in this chapter (past the end otherwise).
func first_record() -> Dictionary:
	var last: Dictionary = Save.last_clear
	var number := int(last.get("stage", 0))
	var record := {}
	if number > 0:
		var theme := Roster.theme_by_id(String(last.get("theme", "")))
		var field := I18n.t(String(theme.get("ko", "")))
		record = {"kind": "last_clear", "label": Arena.label("arena.last_clear"), "stage": number, "theme": theme,
			"name": field, "value": StageSelectView.stage_label(number) + ("" if field.is_empty() else " · " + field)}
	else:
		number = clampi(Save.stage_unlocked, 1, Balance.ARENA_LADDER)
		record = {"kind": "next", "label": Arena.label("arena.stage_next"), "stage": number,
			"value": StageSelectView.stage_label(number)}
	var chapter_start := (number - 1) / 10 * 10
	record.merge({"color": Look.CRYSTAL, "track_total": 10,
		"track_cleared": clampi(Save.stage_cleared - chapter_start, 0, 10),
		"track_reached": clampi(Save.stage_unlocked - chapter_start, 0, 11)})
	return record


## The stage a saved run would continue (the 「이어하기」 label), 1..Balance.ARENA_LADDER.
func continue_stage() -> int:
	return clampi(int(Save.cur_run.get("stage", 1)), 1, Balance.ARENA_LADDER)


## The 「이어하기」 button's words for the saved run: 「계속하기 · STAGE n」 — the stage is what tells
## a saved run apart, its clock restarts on every stage — or for a Hellbound run, whose endless
## waves have no stage, 「계속하기 · HELLBOUND · WAVE n」; a legacy wave run 「이어하기 — n탄」.
func resume_label() -> String:
	if Save.cur_run.get("mode") != "arena":
		return "이어하기 — %d탄" % Save.run_wave()
	var head := I18n.t("계속하기") + "  ·  "
	if Save.cur_run.get("hell", false) == true:
		var sim: Variant = Save.cur_run.get("sim", {})
		var wave := maxi(1, int((sim as Dictionary).get("wave_no", 1))) if sim is Dictionary else 1
		return head + Arena.label("arena.hell_tag") + "  ·  " + Arena.label("arena.wave_label") % wave
	return head + StageSelectView.stage_label(continue_stage())


func _draw() -> void:
	var cx := 640.0
	ui.begin()

	StellarBackdrop.draw(self, Look.SCREEN, Run.theme_for(1), t, true)
	# A night shade from the top keeps the wordmark off the busy field.
	_vgrad(Rect2(0, 0, 1280, 250), Color(Look.BG_DEEP, 0.55), Color(Look.BG_DEEP, 0.0))

	# The live-rig portrait renders sit on the same metal plinths as the roster.
	for side in [-1, 1]:
		var center := Vector2(640 + side * 422, 526)
		draw_set_transform(center, 0, Vector2(1, 0.24))
		draw_circle(Vector2.ZERO, 108, Color(Look.BG_DEEP, 0.75), true, -1, true)
		draw_arc(Vector2.ZERO, 103, 0, TAU, 64, Color(Look.CRYSTAL if side > 0 else Look.GOLD, 0.42), 3, true)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	Art.draw_unit_fit(self, Roster.unit_by_id("brasa"), Rect2(58, 232, 316, 324), Color.WHITE, 9)
	Art.draw_unit_fit(self, Roster.unit_by_id("thalassa"), Rect2(906, 232, 316, 324), Color.WHITE, 9)

	# The Soul Stone the guardians defend — the key art's stone, floating and breathing light.
	draw_soul_stone(self, STONE_AT + Vector2(0, sin(t * 1.7) * 5.0), STONE_HEIGHT, t)

	# 도감·상점·스테이지 창이 열렸을 때 제목 장식이 모달 위로 나오지 않게 한다.
	var bare := not overlay_open()
	_wordmark.visible = bare
	_wordmark.position = Vector2(0, WORDMARK_DROP)
	_wordmark.queue_redraw()
	if bare:
		var cw := CREST_HEIGHT * float(CREST.get_width()) / float(CREST.get_height())
		if _crest_smooth == null:
			_crest_smooth = _smooth(CREST)
		draw_texture_rect(_crest_smooth, Rect2(cx - cw * 0.5, CREST_TOP, cw, CREST_HEIGHT), false)

	_draw_records()
	_draw_actions(cx)

	Look.fill_round(self, Rect2(234, 765, 812, 30), 4, Color(Look.BG_DEEP, 0.85))
	Look.text_box(self, Rect2(244, 766, 792, 27), "균열 군단이 소울 스톤을 노린다. 보석상자에서 수호자를 골라 마을을 지켜라!", Look.TYPE_CAPTION, Look.CRYSTAL)
	# The shop is one quiet button in the utility row (the mirror of menu / language at
	# the top right), in the same secondary style: it never competes with "start".
	if _shop_entry():
		ui.glass_button(self, Rect2(24, 24, 150, 48), Arena.label("store.title"), "store:open", true, Look.STEEL, 20)
	collection.draw(self, ui)
	stage_select.draw(self, ui)
	squad.draw(self, ui)
	store.draw(self, ui, t)


## The three lifetime records: the stage cleared last (first_record), the best grade, the heroes met.
func _draw_records() -> void:
	var first := first_record()
	var records := [
		[first["label"], first["value"], first["color"]],
		["최고 등급", Look.star_label(Save.best_tier) if Save.best_tier >= 0 else "-", Look.GOLD],
		["만난 영웅", "%d / %d" % [Save.seen_count(), Roster.UNITS.size()], Look.GREEN],
	]
	for index in range(records.size()):
		var record: Array = records[index]
		var rect := Rect2(208 + index * 294, 536, 276, 88)
		Look.sheet(self, rect, record[2], Look.GLASS_FACE)
		if index > 0:
			Look.text_center(self, rect.position + Vector2(138, 22), record[0], 20, Look.INK_DIM)
		if index == 0:
			_draw_first_record(rect, first)
		elif index == 1 and Save.best_tier >= 0:
			Look.draw_rarity(self, rect.position + Vector2(90, 60), Save.best_tier, 8.0)
			Look.text_box(self, Rect2(rect.position.x + 150, rect.position.y + 43, 106, 36), record[1], 30, record[2])
		else:
			Look.text_center_fit(self, rect.position + Vector2(138, 60), record[1], 31, record[2], 238, 20)
		if index == 2:
			Look.text_right(self, rect.position + Vector2(254, 26), "›", 24, Look.GREEN)
			ui.zone(rect, "collection")


## The first cell. The stage cleared last takes two lines — 「STAGE n」 over the battlefield
## (its body mark and name) — so a long English field ('STAGE 100 · Mushroom Hollow') never
## shrinks below 18 px; before any clear it is the single best-reached value. Both sit on
## the chapter's ten-step track.
func _draw_first_record(rect: Rect2, first: Dictionary) -> void:
	var colour: Color = first.get("color", Look.CRYSTAL)
	var field := String(first.get("name", ""))
	var number := int(first.get("stage", 0))
	var track := Rect2(rect.position.x + 38, rect.position.y + 77, 200, 5)
	if String(first.get("kind", "")) == "last_clear" and number > 0 and not field.is_empty():
		Look.text_center(self, rect.position + Vector2(138, 17), String(first["label"]), 18, Look.INK_DIM)
		Look.text_center_fit(self, rect.position + Vector2(138, 39), StageSelectView.stage_label(number), 23, colour, 238, 18)
		var theme: Dictionary = first.get("theme", {})
		var body := String(theme.get("main_body", ""))
		var width := minf(Look.text_width(field, 19), 214.0)
		var at := rect.position + Vector2(138, 61)
		if body.is_empty():
			Look.text_center_fit(self, at, field, 19, Look.INK, 238, 18)
		else:
			Look.draw_body(self, at - Vector2(width * 0.5 + 12.0, 0), 8, body)
			Look.text_center_fit(self, at + Vector2(12, 0), field, 19, Look.INK, 214, 18)
	else:
		Look.text_center(self, rect.position + Vector2(138, 22), String(first["label"]), 20, Look.INK_DIM)
		Look.text_center_fit(self, rect.position + Vector2(138, 51), String(first["value"]), 29, colour, 238, 18)
	Look.draw_stage_track(self, track, int(first["track_reached"]), int(first["track_total"]), int(first["track_cleared"]))


## Start (or continue) in the middle, flanked by the stage select and Hellbound.
## ★ 하다 만 판이 있으면 **이어하기가 위**에 온다 — 앱을 껐다 켠 사람이 제일 먼저 누르고 싶은 단추.
func _draw_actions(cx: float) -> void:
	var main_rect: Rect2
	if Save.has_run():
		var continue_label := resume_label()
		main_rect = Rect2(cx - 170.0, 642.0, 340.0, 58.0)
		# 「계속하기」 on top, where it resumes underneath (STAGE n, or HELLBOUND · WAVE n): the long
		# Hellbound line would shrink below 18 px on one line of this button.
		var parts := continue_label.split("  ·  ", false, 1)
		if parts.size() == 2:
			ui.button(self, main_rect, "", "resume", true, Look.CRYSTAL, 34)
			var dy := 2.0 if ui.pressed == "resume" else 0.0
			var inner := main_rect.size.x - 28.0
			# Fitted by width only (a text box would also fit the line height and drop below 18 px).
			Look.text_center_fit(self, Vector2(main_rect.get_center().x, main_rect.position.y + 18.0 + dy), parts[0], 25, Look.INK, inner, 22)
			Look.text_center_fit(self, Vector2(main_rect.get_center().x, main_rect.position.y + 41.0 + dy),
				parts[1].replace("  ·  ", " · "), 20, Look.CRYSTAL_INK, inner, 18)
		else:
			ui.button(self, main_rect, continue_label, "resume", true, Look.CRYSTAL, 34)
		ui.button(self, Rect2(cx - 120.0, 710.0, 240.0, 44.0), "새로 시작", "start", true, Look.PANEL_EDGE, 26)
	else:
		main_rect = Rect2(cx - 150.0, 654.0, 300.0, 70.0)
		ui.button(self, main_rect, "시작", "start", true, Look.GOLD, 38)
		# The stage 「시작」 opens: a tab on the button's top edge.
		_stage_tab(Vector2(cx, main_rect.position.y), StageSelectView.stage_label(maxi(1, Save.stage_unlocked)))
	var h := 54.0
	var w := 200.0
	var y := main_rect.get_center().y - h * 0.5
	_side_button(Rect2(main_rect.position.x - 24.0 - w, y, w, h), Arena.label("arena.stages"), "stages", "stages")
	_side_button(Rect2(main_rect.end.x + 24.0, y, w, h), "Hellbound", "hell", "hell")


## A small gold-rimmed tab naming the stage the start button opens.
func _stage_tab(top_center: Vector2, label: String) -> void:
	var font := Look.font(17)
	var tw := font.get_string_size(I18n.t(label), HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	var r := Rect2(top_center.x - tw * 0.5 - 14.0, top_center.y - 13.0, tw + 28.0, 24.0)
	Look.outline_round(self, r, 12, Look.GOLD, 1.5)
	Look.fill_round(self, r, 12, Look.BG_DEEP)
	Look.text_center(self, r.get_center(), label, 17, Look.IVORY)


## The stage select and Hellbound: glass buttons with their own glyph. Hellbound burns in its
## ember when the DLC is owned; otherwise it stays steel with a padlock (a tap shows the shop).
func _side_button(r: Rect2, label: String, id: String, glyph: String) -> void:
	var hell := glyph == "hell"
	var owned := not hell or dlc()
	var accent := (StoreView.HELL_EMBER if owned else Look.STEEL) if hell else Look.GOLD
	ui.glass_button(self, r, "", id, true, accent, 21)
	var down := ui.pressed == id
	var at := Vector2(r.position.x + 32.0, r.get_center().y + (1.0 if down else 0.0))
	if hell:
		StoreView.draw_fact_glyph(self, at + Vector2(0, -1), "hell", StoreView.HELL_EMBER if owned else Look.STEEL_DIM, 1.15)
	else:
		_ladder_glyph(at, Look.GOLD)
	Look.text_box(self, Rect2(r.position.x + 52.0, r.position.y + 3.0, r.size.x - 62.0, r.size.y - 6.0), label, 21,
		Look.INK if owned else Look.INK_DIM)
	if not owned:
		_padlock(Vector2(r.end.x - 14.0, r.position.y + 2.0), Look.STEEL)


## Three stepping stones rising to a flag: the ladder of stages.
func _ladder_glyph(at: Vector2, color: Color) -> void:
	for i in range(3):
		var p := at + Vector2(-12.0 + float(i) * 9.0, 10.0 - float(i) * 7.5)
		Look.draw_diamond(self, p, 4.8, Color(color, 0.55 + 0.2 * float(i)))
	var pole := at + Vector2(12.0, -4.0)
	draw_line(pole + Vector2(0, 4), pole + Vector2(0, -14), color, 2.2, true)
	draw_colored_polygon(PackedVector2Array([pole + Vector2(1, -14), pole + Vector2(11, -10), pole + Vector2(1, -6)]), Look.CRYSTAL)


## A padlock badge (the DLC is not owned yet).
func _padlock(at: Vector2, color: Color) -> void:
	draw_circle(at, 11.0, Look.BG_DEEP, true, -1, true)
	draw_arc(at + Vector2(0, -2.5), 3.6, PI, TAU, 12, color, 1.8, true)
	Look.fill_round(self, Rect2(at + Vector2(-5.0, -1.5), Vector2(10.0, 8.0)), 1.5, color)


## The Soul Stone: a cyan pool of light, slow rays, sparks circling it, then the painted stone.
## Static so the stage select (and the menu, later) can reuse the same object.
static func draw_soul_stone(ci: CanvasItem, at: Vector2, height: float, time: float) -> void:
	var breath := 0.5 + 0.5 * sin(time * 2.2)
	# Light it throws on the ground under it (the stone floats a hand above the field).
	var floor_at := at + Vector2(0, height * 0.58)
	ci.draw_set_transform(floor_at, 0.0, Vector2(1.0, 0.24))
	for k in range(4):
		ci.draw_circle(Vector2.ZERO, height * (0.52 - 0.11 * float(k)), Color(Look.CRYSTAL, (0.05 + 0.03 * float(k)) * (0.8 + 0.2 * breath)), true, -1, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var pool := height * 0.80
	var core := Color(Look.CRYSTAL, 0.26 + 0.12 * breath)
	var clear := Color(Look.CRYSTAL, 0.0)
	for i in range(48):
		ci.draw_polygon(PackedVector2Array([at, at + Vector2.from_angle(TAU * float(i) / 48.0) * pool,
			at + Vector2.from_angle(TAU * float(i + 1) / 48.0) * pool]), PackedColorArray([core, clear, clear]))
	# Slow rays behind the stone.
	for i in range(8):
		var ang := time * 0.12 + TAU * float(i) / 8.0
		var len := height * (0.62 + 0.10 * sin(time * 0.9 + float(i)))
		var half := 0.07
		ci.draw_polygon(PackedVector2Array([at, at + Vector2.from_angle(ang - half) * len, at + Vector2.from_angle(ang + half) * len]),
			PackedColorArray([Color(Look.CRYSTAL_INK, 0.10 + 0.05 * breath), Color(Look.CRYSTAL, 0.0), Color(Look.CRYSTAL, 0.0)]))
	var w := height * float(STONE.get_width()) / float(STONE.get_height())
	# Sparks on a tilted orbit: the far half under the stone, the near half over it.
	var sparks := []
	for i in range(7):
		var a := time * 0.55 + TAU * float(i) / 7.0
		sparks.append([sin(a), at + Vector2(cos(a) * w * 0.95, sin(a) * height * 0.10 + height * 0.18)])
	for s in sparks:
		if float(s[0]) < 0.0:
			_spark(ci, s[1], 0.6 + 0.4 * (1.0 + float(s[0])), 0.45)
	if _stone_smooth == null:
		_stone_smooth = _smooth(STONE)
	ci.draw_texture_rect(_stone_smooth, Rect2(at - Vector2(w, height) * 0.5, Vector2(w, height)), false)
	for s in sparks:
		if float(s[0]) >= 0.0:
			_spark(ci, s[1], 1.0 + 0.3 * float(s[0]), 0.9)


static func _smooth(tex: Texture2D) -> CanvasTexture:
	var smooth := CanvasTexture.new()
	smooth.diffuse_texture = tex
	smooth.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return smooth


static func _spark(ci: CanvasItem, p: Vector2, size: float, alpha: float) -> void:
	ci.draw_circle(p, 7.0 * size, Color(Look.STARLIGHT, 0.16 * alpha), true, -1, true)
	ci.draw_colored_polygon(Look.star_points(p, 5.5 * size, 0.32), Color(Look.STARLIGHT, alpha))


func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]),
		PackedColorArray([top, top, bottom, bottom]))


## Whether the title shows the shop button. Only builds with a shop behind them have it.
## On the phone shops it is always there: "restore purchases" lives on that sheet and
## must stay findable (App Store). On Steam it steps aside once every product is owned
## (a paid copy owns them from the start): there is nothing to sell, and Steam needs no
## restore. A test build keeps it while test purchases can still be reset.
func _shop_entry() -> bool:
	if not Store.has_shop():
		return false
	if Store.shop_name() != "steam" or store.opened or (Store.test_build() and not Save.iap_sandbox.is_empty()):
		return true
	for product in Store.PRODUCTS:
		if not Store.owns(String(product["id"])):
			return true
	return false


## 배경의 색은 건드리지 않는 별도 워드아트 캔버스: 실제 글리프 위 금색 램프와 청동 입체면.
class Wordmark extends Node2D:
	const METAL_SHADER := preload("res://art/ui/title_wordmark.gdshader")

	func _ready() -> void:
		var metal := ShaderMaterial.new()
		metal.shader = METAL_SHADER
		material = metal

	func _diamond(center: Vector2, radius: Vector2, color: Color) -> void:
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, -radius.y), center + Vector2(radius.x, 0),
			center + Vector2(0, radius.y), center - Vector2(radius.x, 0)]), color)

	func _draw() -> void:
		var dark := Color("#101b20")
		var bronze := Color("#715436")
		var edge := Look.GOLD
		var light := Color("#fff0c7")
		var center := Vector2(640, 144)
		var title := I18n.t("스텔라 디펜스")
		var size := 84 if I18n.locale == "ko" else 76
		var font := Look.font(size)
		var width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Look._baseline(font, center - Vector2(width * 0.5, 0), size)

		# The crest above the title is the painted soul-stone emblem, drawn by the title itself
		# (TitleScreen._draw: CREST) — under this shader its colours would turn to metal.

		# 그림자 → 청동 측면 → 얇은 금 테두리 → 밝은 안쪽 베벨 → 금속 전면.
		draw_string_outline(font, at + Vector2(0, 8), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 13, Color(dark, 0.8))
		for depth in range(4, 0, -1):
			draw_string_outline(font, at + Vector2(0, depth), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, bronze)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 7, dark)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, edge)
		draw_string_outline(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 2, dark)
		draw_string(font, at + Vector2(0, 2), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, bronze)
		draw_string(font, at + Vector2(0, -1), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, light)
		draw_string(font, at, title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)
		Look._audit_raw(self, title, center - Vector2(width * 0.5, font.get_height(size) * 0.5), size)

		# 얇은 양쪽 장식은 글자보다 뒤로 물러나고, 부제는 두 언어의 브랜드를 함께 보여 준다.
		var subtitle := "STELLAR DEFENSE" if I18n.locale == "ko" else "스텔라 디펜스"
		var sub_size := 23
		var sub_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size).x
		var subtitle_pos := Vector2(640 - sub_width * 0.5, 212)
		var subtitle_at := Look._baseline(font, subtitle_pos, sub_size)
		draw_string_outline(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, 5, dark)
		draw_string(font, subtitle_at, subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, sub_size, light)
		for direction in [-1, 1]:
			var start: float = 640 + direction * (sub_width * 0.5 + 24)
			var end: float = 640 + direction * (width * 0.5 + 24)
			draw_line(Vector2(start, 213), Vector2(end, 213), dark, 5)
			draw_line(Vector2(start, 211), Vector2(end, 211), edge, 2)
			_diamond(Vector2(end, 211), Vector2(5, 5), edge)
			var side := Vector2(640 + direction * (width * 0.5 + 38), 145)
			_diamond(side, Vector2(7, 12), dark)
			_diamond(side, Vector2(4, 8), edge)
