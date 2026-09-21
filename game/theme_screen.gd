extends Node2D
class_name ThemeScreen

## 테마가 바뀔 때 등장 몬스터와 각자의 속성, 등장 비율을 보여 준다.
## 플레이어가 터치할 때까지 머문다.

## 넘길 수 있게 되기까지의 시간. **0 으로 두지 마라** — 앞 화면(타이틀·전과 판)에서
## 손을 떼는 그 탭이 이 판까지 흘러들어 와서, 뜨자마자 사라진다.
const TAP_AFTER := 0.35

var main = null
var ui := Ui.new()
var fx := Fx.new()
var t: float = 0.0
var _leaving: bool = false

var theme: Dictionary = {}
var block: int = 0
var pool: Array = []
var boss: Dictionary = {}
var preview: Dictionary = {}
var _monster_sources: Dictionary = {}


func _ready() -> void:
	theme = Run.theme_for(Run.wave + 1)
	block = Balance.theme_block(Run.wave + 1)
	preview = Run.theme_preview(Run.wave + 1)
	pool.clear()
	for row in preview.get("rows", []):
		pool.append_array(row["monsters"])
	boss = Run.boss_for(Balance.BOSS_EVERY * (block + 1))
	Sfx.play("theme")
	fx.ring(Vector2(640, 300), Look.GOLD, 40.0, 520.0, 0.9, 6.0)
	set_process(true)


func _process(dt: float) -> void:
	t += dt
	fx.update(dt)
	# ★ 시간으로 넘기지 않는다. 나가는 길은 _input() 의 탭 하나뿐이다.
	queue_redraw()


func _input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		if t > TAP_AFTER:
			_leave()


func _leave() -> void:
	if main == null or _leaving:
		return
	_leaving = true
	main.go(main.go_draw)


func _draw() -> void:
	ui.begin()
	Scenery.draw_backdrop(self, theme, Look.SCREEN, t)
	Scenery.draw_weather(self, theme, Look.SCREEN, t, 80)
	draw_rect(Look.SCREEN, Color(Look.BG_DEEP, 0.24))
	fx.draw_back(self)
	var progress := 1.0 - pow(1.0 - clampf(t / 0.5, 0, 1), 3)
	Look.text_center_out(self, Vector2(640, lerpf(76, 104, progress)), String(theme.get("ko", "")), 58, Look.INK, Look.BG_DEEP, 4)
	Look.text_center_out(self, Vector2(640, 158), "%d~%d탄" % [int(preview.get("start_wave", 1)), int(preview.get("end_wave", 10))], 24, Look.GOLD)
	Look.material_panel(self, Rect2(64, 198, 1152, 454), Color("#142a30"), Look.PANEL_EDGE)
	Look.text_left(self, Vector2(90, 228), "등장 속성 · 일반 몬스터", 23, Look.INK_DIM)
	var rows: Array = preview.get("rows", [])
	var width := 222.0
	for i in range(rows.size()):
		_draw_body_column(rows[i], 640 - rows.size() * width * 0.5 + i * width, width - 8)
	var bosses: Array = preview.get("bosses", [])
	for i in range(bosses.size()):
		var entry: Dictionary = bosses[i]
		var monster: Dictionary = entry["monster"]
		var box := Rect2(340, 674, 600, 66)
		Look.fill_round(self, box, 4, Color("#15282d"))
		_draw_monster_art(monster, Rect2(353, 680, 60, 54))
		Look.text_left(self, Vector2(430, 694), "보스 · %d탄" % int(entry["wave"]), 18, Look.GOLD)
		Look.draw_body(self, Vector2(442, 722), 11, String(monster["body"]))
		Look.text_box(self, Rect2(464, 706, 456, 32), String(monster["ko"]), 23, Look.INK, HORIZONTAL_ALIGNMENT_LEFT)
	if t > TAP_AFTER:
		Look.text_center_out(self, Vector2(640, 772), "화면을 터치하면 시작", 22, Look.INK)
	fx.draw(self)


func _draw_body_column(row: Dictionary, x: float, width: float) -> void:
	var body := String(row["body"])
	Look.fill_round(self, Rect2(x, 257, width, 372), 4, Color("#102229"))
	Look.draw_body(self, Vector2(x + 25, 283), 14, body)
	Look.text_left(self, Vector2(x + 48, 282), Balance.body_ko(body), 22, Look.INK)
	Look.text_right(self, Vector2(x + width - 14, 282), "%d%%" % int(row["percent"]), 25, Look.GOLD)
	var monsters: Array = row["monsters"]
	for i in range(monsters.size()):
		var y := 317.0 + i * 77.0
		_draw_monster_art(monsters[i], Rect2(x + 6, y + 7, 54, 55))
		Look.wrap_text(self, String(monsters[i]["ko"]), Rect2(x + 66, y + 9, width - 72, 57), 20, Look.INK, true)


func _draw_monster_art(monster: Dictionary, box: Rect2) -> void:
	var path := String(monster.get("art", ""))
	var texture := Art.tex(path)
	if texture == null:
		Look.draw_body(self, box.get_center(), 18, String(monster.get("body", "")))
		return
	if not _monster_sources.has(path):
		_monster_sources[path] = Rect2(texture.get_image().get_used_rect())
	var source: Rect2 = _monster_sources[path]
	draw_texture_rect_region(texture, Art.fit_rect(source.size, box), source)
