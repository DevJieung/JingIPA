extends RefCounted
class_name Scenery

## 테마 배경. **그림 파일 없이 코드로 그린다.**
##
## 사용자가 정한 것: 「테마별 배경 좀 바뀌게」. 예전에는 투기장 그림 한 장에 테마 색을
## 곱하기만 해서(지금은 없앤 battle_screen._tint), 쉰 곳이 전부 「색만 다른 같은 곳」이었다.
##
## ★ 왜 그림을 안 뽑는가: 테마가 쉰 개이고 한 곳에 배경·바닥 두 장이면 백 장이다.
##   이 머신의 GPU 로 두 시간이고, 테마 표를 한 줄 고칠 때마다 다시 두 시간이다.
##   대신 **몸 다섯 가지의 결**을 코드로 그린다 — 물은 수평선과 물결, 불은 화산 실루엣과
##   올라가는 불티, 나무는 우거진 윤곽과 떨어지는 잎, 바위는 각진 봉우리와 먼지,
##   얼음은 눈 덮인 산과 내리는 눈. 같은 몸 안에서도 테마의 색(bg·floor)이 다르므로
##   쉰 곳이 저마다 다르게 보인다.
## ★ 진짜 그림이 생기면(`art_bg`) 그쪽이 먼저다. 나중에 몇 곳만 뽑아도 코드는 그대로다.
##   (`python3 tools/gen_art.py --kind theme --only 화산`)
## ★ **띠(밴딩)로 그린다.** 매끈한 그라디언트는 도트 화면에서 저 혼자 매끈해 보인다.
##   스물넉 줄로 끊어 칠하면 그것 자체가 도트의 결이 된다.

const BANDS := 24


## 그 테마의 하늘 색 두 개 [위, 아래]. 테마의 bg 색을 밑동으로 삼고 몸에 따라 결을 준다.
static func sky(theme: Dictionary) -> Array:
	var base := Color(String(theme.get("bg", "#141422")))
	var body := String(theme.get("main_body", "rock"))
	# 위는 어둡고 아래는 밝다(지평선 쪽에 빛이 남는다). 몸마다 그 빛의 색이 다르다.
	var glow := Color(0.5, 0.5, 0.6)
	match body:
		"aqua":
			glow = Color(0.22, 0.52, 0.72)
		"flame":
			glow = Color(0.78, 0.32, 0.12)
		"wood":
			glow = Color(0.34, 0.56, 0.26)
		"rock":
			glow = Color(0.62, 0.50, 0.32)
		"frost":
			glow = Color(0.56, 0.72, 0.88)
	# ★ 아래쪽(지평선 쪽)을 넉넉히 밝게 잡는다. 0.45 로 두었더니 테마 색이 원래 어두워서
	#   (그곳의 색이니까) 하늘도 능선도 통째로 진흙빛 한 덩이가 됐다 — 사진에서 능선이
	#   있는지조차 안 보였다. 실루엣은 **밝은 하늘 위에서만** 실루엣으로 읽힌다.
	return [base.darkened(0.22), base.lerp(glow, 0.62)]


## 지평선의 높이(칸 안의 비율).
static func horizon(theme: Dictionary) -> float:
	match String(theme.get("main_body", "rock")):
		"aqua":
			return 0.52
		"flame":
			return 0.58
		"wood":
			return 0.50
		"frost":
			return 0.55
	return 0.56


## 테마 id 로 정해지는 씨앗. **같은 곳은 언제 와도 같은 모양이어야 한다** —
## 매번 굴리면 산의 능선이 프레임마다 춤춘다.
static func seed_of(theme: Dictionary) -> float:
	var s := String(theme.get("id", "x"))
	var acc := 0.0
	for i in range(s.length()):
		acc += float(s.unicode_at(i)) * float(i + 3)
	return fmod(acc, 1000.0)


## 씨앗 하나에서 0~1 사이 값 하나. 난수 객체를 만들지 않으려고 손으로 짠다 —
## 배경 한 장에 수백 번 부르는 자리라 객체를 만들면 그것만으로 프레임이 떨어진다.
static func rnd(seed_value: float, i: float) -> float:
	var v: float = sin(seed_value * 0.017 + i * 12.9898) * 43758.5453
	return v - floor(v)


## 배경 한 장. rect 를 통째로 채운다.
static func draw_backdrop(ci: CanvasItem, theme: Dictionary, rect: Rect2,
		t: float) -> void:
	StellarBackdrop.draw(ci, rect, theme, t)


static func _stars(ci: CanvasItem, rect: Rect2, hz: float, sd: float,
		body: String) -> void:
	var col := Color(1, 1, 1, 0.30)
	var n := 40
	match body:
		"flame":
			col = Color(1.0, 0.62, 0.22, 0.35)
		"wood":
			col = Color(0.72, 1.0, 0.62, 0.22)
		"aqua":
			col = Color(0.62, 0.88, 1.0, 0.24)
			n = 24
		"rock":
			col = Color(1.0, 0.92, 0.74, 0.18)
			n = 20
	for i in range(n):
		var x: float = rect.position.x + rnd(sd, float(i) * 1.7) * rect.size.x
		var y: float = rect.position.y + rnd(sd, float(i) * 3.1 + 5.0) * (hz - rect.position.y)
		var s: float = 2.0 + rnd(sd, float(i) * 7.3) * 2.0
		ci.draw_rect(Rect2(floor(x), floor(y), s, s), col)


## 먼 능선. 몸마다 실루엣이 다르다 — 이 한 줄이 「어디인가」를 말한다.
static func _ridge(ci: CanvasItem, rect: Rect2, hz: float, sd: float, body: String,
		tone: Color) -> void:
	# 먼 능선은 하늘에 살짝 잠기고(0.55), 가까운 능선은 더 짙다(0.74).
	var far := tone.darkened(0.55)
	var near := tone.darkened(0.74)
	match body:
		"aqua":
			# 물 — 능선 대신 **수평선과 물결 줄** 몇 개.
			ci.draw_rect(Rect2(rect.position.x, floor(hz) - 3.0, rect.size.x, 3.0),
					tone.lightened(0.25))
			for i in range(7):
				var y: float = hz + 10.0 + float(i) * 13.0
				if y > rect.position.y + rect.size.y:
					break
				var w: float = rect.size.x * (0.3 + rnd(sd, float(i) * 2.3) * 0.5)
				var x: float = rect.position.x + rnd(sd, float(i) * 5.1) * (rect.size.x - w)
				ci.draw_rect(Rect2(floor(x), floor(y), w, 3.0),
						Color(1, 1, 1, 0.10 - 0.01 * float(i)))
		"wood":
			# 나무 — 둥글게 뭉친 우듬지 여럿.
			for layer in range(2):
				var c: Color = far if layer == 0 else near
				var yb: float = hz + float(layer) * 26.0
				var n := 14 + layer * 4
				for i in range(n):
					var x2: float = rect.position.x + (float(i) + 0.5) / float(n) * rect.size.x
					var r: float = 34.0 + rnd(sd, float(i + layer * 40) * 1.9) * 42.0
					ci.draw_circle(Vector2(floor(x2), floor(yb - r * 0.35)), r, c)
					ci.draw_rect(Rect2(floor(x2 - r * 0.10), floor(yb - r * 0.4),
							r * 0.20, r * 0.6), c)
		_:
			# 불·바위·얼음 — 각진 봉우리. 얼음만 꼭대기에 흰 눈을 얹는다.
			for layer in range(2):
				var c2: Color = far if layer == 0 else near
				var yb2: float = hz + 6.0 + float(layer) * 30.0
				var n2 := 6 + layer * 3
				var pts := PackedVector2Array()
				pts.append(Vector2(rect.position.x, rect.position.y + rect.size.y))
				for i in range(n2 + 1):
					var x3: float = rect.position.x + float(i) / float(n2) * rect.size.x
					var h: float = (48.0 + rnd(sd, float(i + layer * 30) * 3.7) * 96.0) \
							* (1.0 - 0.35 * float(layer))
					pts.append(Vector2(floor(x3), floor(yb2 - h)))
				pts.append(Vector2(rect.position.x + rect.size.x,
						rect.position.y + rect.size.y))
				ci.draw_colored_polygon(pts, c2)
				if body == "frost" and layer == 0:
					for i in range(n2 + 1):
						var p: Vector2 = pts[i + 1]
						ci.draw_colored_polygon(PackedVector2Array([
							p, p + Vector2(11.0, 18.0), p + Vector2(-11.0, 18.0)]),
							Color(0.88, 0.94, 1.0, 0.85))
				if body == "flame" and layer == 0:
					# 화산 꼭대기의 붉은 빛.
					for i in range(n2 + 1):
						var p2: Vector2 = pts[i + 1]
						ci.draw_circle(p2, 7.0, Color(1.0, 0.42, 0.10, 0.55))


## 지평선 아래 — 땅의 결. 물이면 반짝임, 바위면 자갈, 얼음이면 눈밭.
static func _ground(ci: CanvasItem, rect: Rect2, hz: float, sd: float, body: String,
		tone: Color, t: float) -> void:
	var y0: float = hz + 30.0
	var h: float = rect.position.y + rect.size.y - y0
	if h <= 0.0:
		return
	match body:
		"rock", "flame":
			for i in range(70):
				var x: float = rect.position.x + rnd(sd, float(i) * 1.3) * rect.size.x
				var y: float = y0 + rnd(sd, float(i) * 2.9 + 11.0) * h
				var s: float = 3.0 + rnd(sd, float(i) * 4.1) * 5.0
				ci.draw_rect(Rect2(floor(x), floor(y), s, s * 0.6),
						tone.darkened(0.5) if i % 2 == 0 else tone.lightened(0.06))
		"frost":
			for i in range(40):
				var x2: float = rect.position.x + rnd(sd, float(i) * 1.9) * rect.size.x
				var y2: float = y0 + rnd(sd, float(i) * 3.3 + 7.0) * h
				var w: float = 20.0 + rnd(sd, float(i) * 5.7) * 60.0
				ci.draw_rect(Rect2(floor(x2), floor(y2), w, 4.0), Color(1, 1, 1, 0.10))
		"aqua":
			for i in range(26):
				var x3: float = rect.position.x + rnd(sd, float(i) * 2.7) * rect.size.x
				var y3: float = y0 + rnd(sd, float(i) * 4.3 + 3.0) * h
				var w2: float = 16.0 + rnd(sd, float(i) * 6.1) * 40.0
				var a: float = 0.06 + 0.05 * sin(t * 1.4 + float(i))
				ci.draw_rect(Rect2(floor(x3), floor(y3), w2, 3.0), Color(1, 1, 1, a))
		_:
			for i in range(30):
				var x4: float = rect.position.x + rnd(sd, float(i) * 3.1) * rect.size.x
				var y4: float = y0 + rnd(sd, float(i) * 2.1 + 13.0) * h
				ci.draw_rect(Rect2(floor(x4), floor(y4), 5.0, 3.0), tone.darkened(0.45))


## 날씨 — 눈·비·불티·잎·먼지. **상태를 안 들고 있다**: 자리를 시간과 번호로 바로 셈한다.
##
## ★ 왜 파티클 배열을 안 쓰는가: 배경 날씨는 전투 내내 백 개가 떠 있어야 하는데,
##   그것을 Fx 에 넣으면 이펙트 배열이 늘 백 개로 차 있어서 실제 타격 이펙트가
##   묻힌다. 시간으로 바로 셈하면 배열이 아예 없고 프레임도 안 먹는다.
static func draw_weather(ci: CanvasItem, theme: Dictionary, rect: Rect2, t: float,
		n: int = 70) -> void:
	if theme.is_empty():
		return
	var body := String(theme.get("main_body", "rock"))
	var sd := seed_of(theme)
	match body:
		"frost":
			for i in range(n):
				var sp: float = 26.0 + rnd(sd, float(i) * 1.1) * 40.0
				var x: float = rect.position.x + rnd(sd, float(i) * 2.3) * rect.size.x \
						+ sin(t * 0.7 + float(i)) * 14.0
				var y: float = rect.position.y + fposmod(rnd(sd, float(i) * 3.7)
						* rect.size.y + t * sp, rect.size.y)
				var s: float = 2.0 + rnd(sd, float(i) * 5.3) * 3.0
				ci.draw_rect(Rect2(floor(x), floor(y), s, s), Color(1, 1, 1, 0.55))
		"flame":
			for i in range(n):
				var sp2: float = 40.0 + rnd(sd, float(i) * 1.7) * 60.0
				var x2: float = rect.position.x + rnd(sd, float(i) * 2.9) * rect.size.x \
						+ sin(t * 1.6 + float(i) * 2.0) * 10.0
				var y2: float = rect.position.y + rect.size.y - fposmod(
						rnd(sd, float(i) * 4.1) * rect.size.y + t * sp2, rect.size.y)
				var s2: float = 2.0 + rnd(sd, float(i) * 6.7) * 3.0
				ci.draw_rect(Rect2(floor(x2), floor(y2), s2, s2),
						Color(1.0, 0.55 + 0.3 * rnd(sd, float(i)), 0.18, 0.7))
		"aqua":
			for i in range(n):
				var sp3: float = 240.0 + rnd(sd, float(i) * 1.3) * 160.0
				var x3: float = rect.position.x + rnd(sd, float(i) * 2.1) * rect.size.x
				var y3: float = rect.position.y + fposmod(rnd(sd, float(i) * 3.3)
						* rect.size.y + t * sp3, rect.size.y)
				ci.draw_rect(Rect2(floor(x3), floor(y3), 2.0, 11.0),
						Color(0.66, 0.86, 1.0, 0.30))
		"wood":
			for i in range(n / 2):
				var sp4: float = 22.0 + rnd(sd, float(i) * 1.9) * 26.0
				var x4: float = rect.position.x + rnd(sd, float(i) * 2.7) * rect.size.x \
						+ sin(t * 0.9 + float(i) * 1.3) * 26.0
				var y4: float = rect.position.y + fposmod(rnd(sd, float(i) * 4.7)
						* rect.size.y + t * sp4, rect.size.y)
				ci.draw_rect(Rect2(floor(x4), floor(y4), 5.0, 3.0),
						Color(0.62, 0.88, 0.40, 0.45))
		_:
			for i in range(n / 2):
				var sp5: float = 14.0 + rnd(sd, float(i) * 1.5) * 22.0
				var x5: float = rect.position.x + fposmod(rnd(sd, float(i) * 2.5)
						* rect.size.x + t * sp5, rect.size.x)
				var y5: float = rect.position.y + rnd(sd, float(i) * 3.9) * rect.size.y
				ci.draw_rect(Rect2(floor(x5), floor(y5), 3.0, 2.0),
						Color(0.85, 0.78, 0.62, 0.22))


## Named terrain landmarks live outside the shared combat lanes and hero posts.
## Every one of the 50 maps has a motif tied to its actual Roster theme id.
const MAP_MOTIFS := {
	"calm_lake": "lake", "reed_marsh": "reeds", "aqueduct_ruin": "aqueduct", "falls_gorge": "falls", "tidal_flats": "tidal", "glacier_lake": "ice_lake", "sunken_fleet": "ship", "geyser_mud": "geyser", "deep_trench": "trench", "maelstrom_sea": "whirlpool",
	"kiln_yard": "kiln", "burn_field": "field", "forge_canyon": "forge", "burnt_forest": "burnt", "sulfur_springs": "sulfur", "ash_city": "ruin", "lava_river": "lava", "obsidian_flats": "obsidian", "volcano_crater": "crater", "ash_blizzard": "ash",
	"spring_grove": "flowers", "mushroom_hollow": "mushroom", "bamboo_grove": "bamboo", "vine_ruins": "vine", "misty_cedar": "cedar", "thornbrake": "thorn", "moss_bog": "moss", "frost_pines": "pine", "rotroot_hollow": "root_cave", "worldtree_roots": "worldroot",
	"gravel_hills": "gravel", "stone_terraces": "terrace", "quarry_pit": "quarry", "red_canyon": "canyon", "broken_wall": "wall", "crystal_cavern": "crystal", "desert_mesa": "mesa", "iron_mine": "mine", "peak_cliffs": "cliff", "rift_chasm": "rift",
	"first_snow_hills": "snow", "frozen_pond": "pond", "snowed_village": "village", "frost_gorge": "gorge", "drift_ice_sea": "ice_floe", "icicle_cave": "icicle", "blizzard_plateau": "blizzard", "glacier_crevasse": "crevasse", "ice_spire_field": "spire", "polar_night": "aurora"
}
static var _map_places: Dictionary = {}


static func map_landmark_positions(theme: Dictionary) -> Array:
	var id := String(theme.get("id", ""))
	if _map_places.has(id):
		return _map_places[id]
	var result: Array = []
	var seed_value := seed_of(theme)
	for index in range(170):
		var point := Vector2(40 + rnd(seed_value, index * 2.1) * 746, 157 + rnd(seed_value, index * 3.7 + 9) * 540).snapped(Vector2(4, 4))
		if point.distance_to(Balance.ARENA_CENTER) < Balance.ALTAR_R + 42:
			continue
		var clear := true
		for post in Balance.POST_POINTS:
			if point.distance_to(post - Vector2(0, 24)) < 43:
				clear = false
		for route in range(2):
			var points := Balance.route_points(route)
			for segment in range(points.size() - 1):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, points[segment], points[segment + 1])) < Balance.ROAD_WIDTH * 0.5 + 17:
					clear = false
		for other in result:
			if point.distance_to(other) < 63:
				clear = false
		if clear:
			result.append(point)
		if result.size() >= 7:
			break
	_map_places[id] = result
	return result


static func draw_map_detail(ci: CanvasItem, theme: Dictionary, rect: Rect2, time: float = 0) -> void:
	var body := String(theme.get("main_body", "rock"))
	var motif := String(MAP_MOTIFS.get(String(theme.get("id", "")), "gravel"))
	var tones := {"aqua": Color("#24556a"), "flame": Color("#633323"), "wood": Color("#2e4e31"), "rock": Color("#64533b"), "frost": Color("#638394")}
	var base: Color = tones.get(body, Color("#435347"))
	ci.draw_rect(rect, Color(base, 0.37))
	var seed_value := seed_of(theme)
	_draw_map_environment(ci, motif, base, seed_value, time)
	# Quiet patches frame the winding road; decoration never changes walkability.
	for index in range(36):
		var at := Vector2(rect.position.x + rnd(seed_value, index * 2.4) * (rect.size.x - 32), rect.position.y + rnd(seed_value, index * 6.3) * (rect.size.y - 20)).snapped(Vector2(4, 4))
		var size := Vector2(12 + rnd(seed_value, index + 22) * 25, 4 + rnd(seed_value, index + 31) * 12).snapped(Vector2(4, 4))
		ci.draw_rect(Rect2(at, size), Color(base.lightened(0.25), 0.24))
	for at in map_landmark_positions(theme):
		_draw_landmark(ci, at, motif, base, time)


static func _pool(ci: CanvasItem, at: Vector2, tone: Color, frozen: bool = false) -> void:
	var rim := Color("#31444a") if not frozen else Color("#afcdd1")
	var points := PackedVector2Array([at + Vector2(-30,-9), at + Vector2(-17,-22), at + Vector2(17,-18), at + Vector2(33,0), at + Vector2(21,15), at + Vector2(-22,18), at + Vector2(-33,5)])
	ci.draw_colored_polygon(points, rim)
	for i in range(points.size()):
		points[i] = at + (points[i] - at) * 0.80
	ci.draw_colored_polygon(points, tone)
	for index in range(3):
		ci.draw_line(at + Vector2(-15 + index * 4, -8 + index * 9), at + Vector2(16, -8 + index * 9), Color("#b9dfdf") if frozen else Color(tone.lightened(0.44), 0.72), 2)
	if frozen:
		ci.draw_polyline(PackedVector2Array([at + Vector2(-12,-11), at + Vector2(2,-1), at + Vector2(-6,8), at + Vector2(12,12)]), Color("#f1f7ed"), 2)


static func _rock_prop(ci: CanvasItem, at: Vector2, tone: Color, tall: bool = false) -> void:
	var height := 49.0 if tall else 25.0
	var points := PackedVector2Array([at + Vector2(-23,7), at + Vector2(-18,-height * 0.68), at + Vector2(-2,-height), at + Vector2(16,-height * 0.79), at + Vector2(24,6), at + Vector2(4,17)])
	ci.draw_colored_polygon(points, tone.darkened(0.45))
	ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-17,4), at + Vector2(-12,-height * 0.65), at + Vector2(-2,-height + 5), at + Vector2(13,-height * 0.7), at + Vector2(15,4)]), tone)
	ci.draw_line(at + Vector2(-10,-height * 0.5), at + Vector2(8,-height * 0.5), tone.lightened(0.30), 3)


static func _tree_prop(ci: CanvasItem, at: Vector2, tone: Color, pine: bool = false) -> void:
	ci.draw_rect(Rect2(at + Vector2(-5,-23), Vector2(10,35)), Color("#655035"))
	if pine:
		for row in range(3):
			var y := -56 + row * 13
			var width := 12 + row * 6
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(0,y), at + Vector2(width,y + 27), at + Vector2(-width,y + 27)]), tone.lightened(0.1 * row))
	else:
		for index in range(3):
			var x := (index - 1) * 11
			Look.px_panel(ci, Rect2(at + Vector2(x - 14,-48 - (8 if index == 1 else 0)), Vector2(28,31)), tone, tone.darkened(0.35), 0.13)


static func _wall_prop(ci: CanvasItem, at: Vector2, tone: Color, arches: bool = false) -> void:
	for column in range(3):
		var pos := at + Vector2(-30 + column * 20, -31)
		Look.px_panel(ci, Rect2(pos, Vector2(19,39 if column != 1 else 31)), tone, tone.darkened(0.4), 0.15)
		ci.draw_line(pos + Vector2(0,12), pos + Vector2(18,12), tone.darkened(0.28), 2)
		ci.draw_line(pos + Vector2(0,25), pos + Vector2(18,25), tone.darkened(0.28), 2)
	if arches:
		ci.draw_rect(Rect2(at + Vector2(-22,-13), Vector2(12,24)), Color("#142930"))
		ci.draw_rect(Rect2(at + Vector2(10,-13), Vector2(12,24)), Color("#142930"))
		ci.draw_rect(Rect2(at + Vector2(-32,-36), Vector2(65,8)), tone.lightened(0.2))


static func _draw_landmark(ci: CanvasItem, at: Vector2, motif: String, base: Color, time: float) -> void:
	ci.draw_rect(Rect2(at + Vector2(-31,8), Vector2(62,10)), Color(0,0,0,0.23))
	match motif:
		"lake", "tidal", "ice_lake", "pond", "ice_floe", "sulfur", "moss":
			var frozen := motif in ["ice_lake", "pond", "ice_floe"]
			_pool(ci, at, Color("#609baf") if frozen else (Color("#8c8137") if motif == "sulfur" else Color("#286a7b")), frozen)
			if motif == "ice_floe":
				_rock_prop(ci, at + Vector2(7,-6), Color("#d0e0dc"))
			if motif == "moss":
				_tree_prop(ci, at + Vector2(-14,2), Color("#52653a"))
		"reeds":
			_pool(ci, at, Color("#335447"))
			for index in range(7):
				var point := at + Vector2(-24 + index * 8, 8)
				ci.draw_line(point, point + Vector2(3,-24 - index % 3 * 5), Color("#9aab60"), 3)
				ci.draw_rect(Rect2(point + Vector2(1,-30 - index % 3 * 5), Vector2(5,12)), Color("#8d673d"))
		"aqueduct", "wall", "vine", "ruin":
			_wall_prop(ci, at, Color("#87938b") if motif != "ruin" else Color("#786d68"), motif == "aqueduct")
			if motif == "vine":
				ci.draw_polyline(PackedVector2Array([at + Vector2(-25,-29), at + Vector2(-13,-9), at + Vector2(6,-28), at + Vector2(17,5)]), Color("#729553"), 5)
		"falls", "geyser":
			_pool(ci, at + Vector2(0,5), Color("#397e92"))
			if motif == "falls":
				_rock_prop(ci, at - Vector2(0,18), Color("#64766f"), true)
			for index in range(3):
				ci.draw_line(at + Vector2(-7 + index * 6,-45 + sin(time + index) * 3), at + Vector2(-5 + index * 6,5), Color("#9cd8db"), 4)
		"ship":
			_pool(ci, at, Color("#286176"))
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-29,-13), at + Vector2(28,-10), at + Vector2(18,12), at + Vector2(-21,8)]), Color("#987048"))
			ci.draw_line(at + Vector2(-6,5), at + Vector2(8,-41), Color("#cf9c68"), 4)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(8,-37), at + Vector2(27,-16), at + Vector2(4,-20)]), Color("#b4b6a2"))
		"trench", "rift", "crevasse", "gorge":
			var points := PackedVector2Array([at + Vector2(-28,-9), at + Vector2(-8,-1), at + Vector2(2,-14), at + Vector2(9,4), at + Vector2(30,9)])
			ci.draw_polyline(points, Color("#8a9b97") if motif in ["crevasse","gorge"] else base.lightened(0.25), 14)
			ci.draw_polyline(points, Color("#101d27"), 8)
		"whirlpool":
			_pool(ci, at, Color("#28597a"))
			for index in range(3):
				ci.draw_arc(at, 7 + index * 6, time * 0.6 + index, time * 0.6 + index + PI * 1.65, 20, Color("#8bd2de"), 2)
		"kiln", "forge":
			_wall_prop(ci, at, Color("#956146"))
			Look.px_panel(ci, Rect2(at + Vector2(-15,-22), Vector2(30,29)), Color("#391e18"), Color("#b78349"))
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-11,4), at + Vector2(-5,-14), at + Vector2(0,-7), at + Vector2(5,-21), at + Vector2(12,4)]), Color("#f4a43c"))
			if motif == "forge":
				ci.draw_rect(Rect2(at + Vector2(-31,0), Vector2(17,8)), Color("#8a9e9f"))
				ci.draw_rect(Rect2(at + Vector2(-27,7), Vector2(10,10)), Color("#526976"))
		"field", "terrace":
			for index in range(4):
				var y := -22 + index * 10
				ci.draw_line(at + Vector2(-30,y), at + Vector2(29,y), Color("#96784c") if motif == "terrace" else Color("#8b492b"), 4)
				if motif == "terrace":
					for plant in range(4):
						ci.draw_rect(Rect2(at + Vector2(-22 + plant * 14,y-4), Vector2(6,4)), Color("#7e9a50"))
		"burnt", "root_cave", "worldroot":
			for index in range(3):
				var x := -20 + index * 20
				ci.draw_polyline(PackedVector2Array([at + Vector2(x-10,8), at + Vector2(x,-7), at + Vector2(x-3,-35), at + Vector2(x+5,-45)]), Color("#72614b") if motif != "burnt" else Color("#60493c"), 7)
			if motif == "root_cave":
				ci.draw_circle(at - Vector2(0,4), 13, Color("#151d1a"))
			if motif == "worldroot":
				ci.draw_circle(at - Vector2(0,30), 4, Look.CRYSTAL)
		"lava", "crater", "ash":
			_pool(ci, at, Color("#a04b26"))
			ci.draw_arc(at, 18, time, time + PI * 1.7, 16, Color("#ffc464"), 4)
			if motif != "lava":
				_rock_prop(ci, at + Vector2(-19,-8), Color("#6c4a40"), true)
			if motif == "ash":
				ci.draw_line(at + Vector2(-28,-18), at + Vector2(4,-40), Color("#aaa49a"), 4)
		"bamboo":
			for index in range(5):
				var x := -23 + index * 11
				ci.draw_line(at + Vector2(x,12), at + Vector2(x+3,-46 + index%2*8), Color("#719852"), 5)
				for y in [-30,-13,3]:
					ci.draw_line(at + Vector2(x-3,y), at + Vector2(x+5,y), Color("#bac083"), 2)
		"mushroom":
			for index in range(3):
				var point := at + Vector2(-19+index*19,-index%2*13)
				ci.draw_rect(Rect2(point + Vector2(-4,-8),Vector2(8,17)),Color("#baac8b"))
				ci.draw_colored_polygon(PackedVector2Array([point+Vector2(-16,-9),point+Vector2(-10,-23),point+Vector2(6,-26),point+Vector2(17,-9)]),Color("#a96a71") if index%2 else Color("#877bb1"))
				ci.draw_rect(Rect2(point+Vector2(-3,-20),Vector2(5,5)),Color("#dfd0a7"))
		"flowers", "cedar", "pine", "thorn":
			_tree_prop(ci, at, Color("#6c9259") if motif == "flowers" else Color("#456b60"), motif in ["cedar","pine"])
			if motif == "flowers":
				for index in range(5):
					ci.draw_rect(Rect2(at + Vector2(-24+index*11,-27-index%2*16),Vector2(5,5)),Color("#dab186"))
			if motif == "pine":
				ci.draw_line(at+Vector2(-16,-31),at+Vector2(16,-31),Color("#c5d9d0"),4)
			if motif == "thorn":
				ci.draw_polyline(PackedVector2Array([at+Vector2(-24,4),at+Vector2(-10,-16),at+Vector2(1,5),at+Vector2(13,-9),at+Vector2(25,7)]),Color("#aaa574"),3)
		"crystal", "spire", "icicle":
			for index in range(3):
				Look.draw_crystal(ci, at + Vector2(-18 + index*18,-index%2*17), 11 + index%2*5, true, 0.15)
		"mine":
			_rock_prop(ci, at, Color("#79746b"), true)
			ci.draw_rect(Rect2(at + Vector2(-15,-20),Vector2(30,29)),Color("#121c21"))
			ci.draw_rect(Rect2(at + Vector2(-20,-25),Vector2(40,6)),Color("#af8356"))
			for x in [-17,17]:
				ci.draw_rect(Rect2(at+Vector2(x-3,-21),Vector2(6,31)),Color("#99754f"))
			ci.draw_line(at+Vector2(-13,16),at+Vector2(-6,-1),Color("#c0bbb0"),3)
			ci.draw_line(at+Vector2(13,16),at+Vector2(6,-1),Color("#c0bbb0"),3)
		"village":
			Look.px_panel(ci,Rect2(at+Vector2(-23,-24),Vector2(46,37)),Color("#899082"),Color("#4a5b66"))
			ci.draw_colored_polygon(PackedVector2Array([at+Vector2(-29,-24),at+Vector2(0,-49),at+Vector2(29,-24)]),Color("#c7d4cd"))
			ci.draw_rect(Rect2(at+Vector2(-6,-5),Vector2(12,18)),Color("#536775"))
			ci.draw_rect(Rect2(at+Vector2(11,-15),Vector2(7,8)),Color("#e6bd79"))
		"aurora":
			_rock_prop(ci,at,Color("#a5bbc4"))
			for index in range(3):
				ci.draw_line(at+Vector2(-28,-42+index*8),at+Vector2(27,-24+index*8),Color("#78b5a7",0.6-index*0.1),5)
		_:
			var tone := Color("#805345") if motif == "canyon" else (Color("#536173") if motif == "obsidian" else base.lightened(0.15))
			if motif in ["snow","blizzard","cliff"]:
				tone = Color("#a9bfc1")
			_rock_prop(ci, at, tone, motif in ["mesa","cliff","quarry"])
			if motif in ["snow","blizzard"]:
				ci.draw_line(at+Vector2(-16,-13),at+Vector2(11,-16),Color("#e1ebe3"),6)


## Large terrain clusters make a named place recognizable at mobile size.
## Roads are painted afterwards, so waterways read as bridged crossings.
static func _terrain_patch(ci: CanvasItem, center: Vector2, size: Vector2, color: Color, seed_value: float) -> void:
	var points := PackedVector2Array()
	for index in range(16):
		var angle := index * TAU / 16.0
		var radius := 0.80 + rnd(seed_value, index * 5.1) * 0.2
		points.append((center + Vector2.from_angle(angle) * size * radius).snapped(Vector2(8,8)))
	ci.draw_colored_polygon(points, color)


static func _draw_map_environment(ci: CanvasItem, motif: String, base: Color, seed_value: float, time: float) -> void:
	var centers := [Vector2(242,474), Vector2(592,360)]
	var water := Color("#24677b")
	var stone := Color("#8d8270")
	for index in range(centers.size()):
		var at: Vector2 = centers[index]
		var zone_seed := seed_value + index * 157
		match motif:
			"lake", "tidal", "ice_lake", "pond", "ice_floe", "ship", "reeds", "moss", "sulfur", "geyser", "whirlpool":
				var tone := water
				if motif in ["ice_lake","pond"]:
					tone = Color("#74afb9")
				elif motif == "tidal":
					tone = Color("#ad9b6e")
				elif motif in ["reeds","moss"]:
					tone = Color("#477459")
				elif motif == "sulfur":
					tone = Color("#9e9950")
				elif motif == "geyser":
					tone = Color("#83735b")
				_terrain_patch(ci,at,Vector2(146,89),tone.darkened(0.26),zone_seed)
				_terrain_patch(ci,at-Vector2(4,7),Vector2(131,72),tone,zone_seed)
				for row in range(5):
					var y := -49 + row * 21
					ci.draw_line(at+Vector2(-83,y),at+Vector2(70,y),Color(tone.lightened(0.35),0.5),4)
				if motif in ["ice_lake","pond","ice_floe"]:
					for chip in range(4):
						var offset := Vector2(-72 + chip*45, -33 + chip%2*46)
						_terrain_patch(ci,at+offset,Vector2(31,18),Color("#c9e0d9"),chip*56)
				if motif in ["reeds","moss"]:
					for reed in range(16):
						var point := at + Vector2(-118 + rnd(zone_seed,reed)*220,-65 + rnd(zone_seed,reed+31)*118)
						ci.draw_line(point,point-Vector2(3,14+reed%3*6),Color("#a4b76b"),3)
				if motif in ["sulfur","geyser"]:
					for puff in range(5):
						var point := at + Vector2(-75+puff*32,-25-puff%2*28)
						ci.draw_rect(Rect2(point,Vector2(24,7)),Color("#ece3bd",0.3+sin(time+puff)*0.06))
				if motif == "whirlpool":
					for band in range(4):
						ci.draw_arc(at,20+band*18,index+band*0.6,index+band*0.6+PI*1.5,24,Color("#78c6d2",0.8),4)
				if motif == "ship":
					for plank in range(5):
						ci.draw_line(at+Vector2(-92,-30+plank*14),at+Vector2(54,plank*14-47),Color("#ac885a"),8)
			"falls", "lava":
				var tone := Color("#d37830") if motif == "lava" else Color("#4ca8b6")
				var points := PackedVector2Array([at+Vector2(-102,-84),at+Vector2(-47,-35),at+Vector2(23,-12),at+Vector2(47,43),at+Vector2(101,75)])
				ci.draw_polyline(points,tone.darkened(0.4),76,false)
				ci.draw_polyline(points,tone,58,false)
				ci.draw_polyline(points,Color("#ffc668") if motif == "lava" else Color("#b9e6df"),5,false)
			"crater", "ash":
				_terrain_patch(ci,at,Vector2(138,93),Color("#786256") if motif == "ash" else Color("#704c38"),zone_seed)
				_terrain_patch(ci,at,Vector2(95,61),Color("#d18b43") if motif == "crater" else Color("#aa9581"),zone_seed)
				_terrain_patch(ci,at-Vector2(6,0),Vector2(56,38),Color("#9b4b2a"),zone_seed)
			"trench", "rift", "crevasse", "gorge":
				var points := PackedVector2Array([at+Vector2(-107,-58),at+Vector2(-65,-10),at+Vector2(-28,-23),at+Vector2(1,26),at+Vector2(37,12),at+Vector2(101,63)])
				var rim := Color("#b4d5d9") if motif in ["crevasse","gorge"] else (Color("#b37845") if motif == "rift" else Color("#38658a"))
				ci.draw_polyline(points,rim,55,false)
				ci.draw_polyline(points,Color("#132735") if motif != "rift" else Color("#392b25"),39,false)
			"aqueduct", "wall", "vine", "ruin", "village":
				var tone := Color("#739883") if motif == "vine" else (Color("#a8b3b3") if motif == "village" else Color("#8f9389"))
				for cluster in range(3):
					var point := at+Vector2(-100+cluster*80,-54+cluster%2*72)
					Look.px_panel(ci,Rect2(point,Vector2(70,62)),tone.darkened(0.40),tone,0.17)
					for row in range(3):
						ci.draw_line(point+Vector2(0,row*20+7),point+Vector2(70,row*20+7),tone.darkened(0.13),3)
					ci.draw_rect(Rect2(point+Vector2(20,15),Vector2(22,31)),Color("#34494b"))
					if motif == "village":
						ci.draw_colored_polygon(PackedVector2Array([point-Vector2(9,0),point+Vector2(35,-27),point+Vector2(80,0)]),Color("#dce5d9"))
				if motif == "vine":
					ci.draw_polyline(PackedVector2Array([at+Vector2(-102,-55),at+Vector2(-39,17),at+Vector2(44,-41),at+Vector2(95,34)]),Color("#83a659"),10,false)
			"field", "terrace", "quarry", "mine", "kiln", "forge":
				var tone := Color("#a89361") if motif == "terrace" else (Color("#997954") if motif in ["field","kiln"] else Color("#7d7f7e"))
				_terrain_patch(ci,at,Vector2(145,94),tone.darkened(0.38),zone_seed)
				for row in range(5):
					ci.draw_line(at+Vector2(-112,-64+row*27),at+Vector2(114,-64+row*27),tone,7,false)
					if motif == "terrace":
						for plant in range(7):
							ci.draw_rect(Rect2(at+Vector2(-105+plant*33,-73+row*27),Vector2(11,7)),Color("#95b363"))
				if motif == "mine":
					for side in [-1,1]:
						ci.draw_line(at+Vector2(side*45,-83),at+Vector2(side*45,83),Color("#b8a77f"),5,false)
				if motif in ["kiln","forge"]:
					for cluster in range(3):
						var point := at+Vector2(-74+cluster*76,-31+cluster%2*52)
						ci.draw_rect(Rect2(point,Vector2(32,14)),Color("#d8a363"))
			"flowers", "mushroom", "bamboo", "cedar", "pine", "thorn", "burnt":
				var tone := Color("#8aa568") if motif == "flowers" else (Color("#746a8b") if motif == "mushroom" else Color("#6b7d68"))
				if motif == "burnt":
					tone=Color("#726154")
				if motif == "thorn":
					tone=Color("#8c8a50")
				_terrain_patch(ci,at,Vector2(144,96),tone.darkened(0.34),zone_seed)
				for group in range(9):
					var point := at+Vector2(-104+group%3*90,-70+group/3*66)
					if motif == "bamboo":
						for stem in range(3):
							ci.draw_line(point+Vector2(stem*12,22),point+Vector2(stem*12,-26),Color("#92b15f"),5,false)
							ci.draw_line(point+Vector2(stem*12-3,-3),point+Vector2(stem*12+5,-3),Color("#c5ce86"),3,false)
					elif motif == "mushroom":
						ci.draw_rect(Rect2(point-Vector2(5,-1),Vector2(10,18)),Color("#bbb4a1"))
						_terrain_patch(ci,point-Vector2(0,5),Vector2(30,17),Color("#b596b8"),group)
					elif motif in ["cedar","pine"]:
						_tree_prop(ci,point,Color("#6f9985") if motif == "cedar" else Color("#7eaaa4"),true)
					elif motif in ["burnt","thorn"]:
						ci.draw_polyline(PackedVector2Array([point+Vector2(-16,12),point-Vector2(1,12),point+Vector2(17,11)]),tone.lightened(0.26),6,false)
					else:
						for petal in range(3):
							ci.draw_rect(Rect2(point+Vector2(-12+petal*13,-petal%2*12),Vector2(9,8)),Color("#d5b28b"))
				if motif in ["pine","cedar"]:
					for row in range(3):
						ci.draw_rect(Rect2(at+Vector2(-114,-59+row*50),Vector2(228,7)),Color("#bfd2ca",0.35 if motif == "cedar" else 0.65))
			"worldroot", "root_cave":
				_terrain_patch(ci,at,Vector2(145,96),Color("#34472d"),zone_seed)
				for branch in range(4):
					var y := -53+branch*32
					var points := PackedVector2Array([at+Vector2(-129,y+29),at+Vector2(-61,y-14),at+Vector2(17,y+12),at+Vector2(110,y-21)])
					ci.draw_polyline(points,Color("#9d8052") if motif == "worldroot" else Color("#78643e"),12,false)
				if motif == "root_cave":
					_terrain_patch(ci,at,Vector2(56,41),Color("#141e21"),zone_seed)
				else:
					for light in range(5):
						ci.draw_rect(Rect2(at+Vector2(-90+light*44,-light%2*36),Vector2(7,7)),Color("#a2d4ac"))
			"snow", "blizzard", "icicle", "spire", "aurora":
				var tone := Color("#b6d2d1") if motif != "aurora" else Color("#487b87")
				_terrain_patch(ci,at,Vector2(148,94),tone.darkened(0.2),zone_seed)
				for cluster in range(7):
					var point := at+Vector2(-113+cluster*35,-57+cluster%3*42)
					if motif in ["icicle","spire"]:
						ci.draw_colored_polygon(PackedVector2Array([point-Vector2(0,35+cluster%2*26),point+Vector2(20,13),point-Vector2(18,-13)]),Color("#d9e9e2"))
					else:
						ci.draw_rect(Rect2(point,Vector2(57,11)),Color("#d6e2d9",0.58))
				if motif == "aurora":
					for band in range(4):
						ci.draw_polyline(PackedVector2Array([at+Vector2(-119,-54+band*21),at+Vector2(-31,-26+band*21),at+Vector2(51,-55+band*21),at+Vector2(128,-32+band*21)]),Color("#94b69a") if band%2 else Color("#9b98ba"),10,false)
			_:
				var tone := stone
				if motif in ["canyon","mesa"]:
					tone = Color("#bd7951") if motif == "canyon" else Color("#c4ab70")
				elif motif == "crystal":
					tone = Color("#8c83a8")
				elif motif == "obsidian":
					tone = Color("#6c637a")
				elif motif == "cliff":
					tone = Color("#8d9fac")
				_terrain_patch(ci,at,Vector2(145,94),tone.darkened(0.35),zone_seed)
				for cluster in range(5):
					var point := at+Vector2(-101+cluster*46,-41+cluster%2*67)
					_rock_prop(ci,point,tone,motif in ["mesa","cliff","crystal"])
				if motif == "crystal":
					for vein in range(3):
						ci.draw_line(at+Vector2(-102,-42+vein*44),at+Vector2(111,-23+vein*44),Color("#bcb2e3"),5,false)
